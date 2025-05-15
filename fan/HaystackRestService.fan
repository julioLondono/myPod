using web
using webmod
using haystack
using folio
using hx
using hxFolio
using concurrent

**
** HaystackRestService
** Implements Project Haystack REST API endpoints
**
const class HaystackRestService : WebMod
{
  ** Active watch subscriptions
  private const ConcurrentMap watches := ConcurrentMap()
  
  ** Watch poll timeout in milliseconds
  private const Duration watchTimeout := 1min
  new make()
  {
    this.context = HxContext.cur
    this.folio = context.rt.db.folio
  }

  override Void onService()
  {
    // CORS headers for web client
    res.headers["Access-Control-Allow-Origin"] = "*"
    res.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    res.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    
    // Handle OPTIONS request for CORS preflight
    if (req.method == "OPTIONS")
    {
      res.statusCode = 200
      res.headers["Content-Length"] = "0"
      return
    }

    try
    {
      // Route requests
      switch (req.modRel.path.first)
      {
        case "about":     onAbout
        case "ops":       onOps
        case "read":      onRead
        case "nav":       onNav
        case "watchSub":  onWatchSub
        case "watchUnsub": onWatchUnsub
        case "watchPoll": onWatchPoll
        case "pointWrite": onPointWrite
        default:          onErr("Unknown route: ${req.modRel.path.first}")
      }
    }
    catch (Err e)
    {
      onErr(e.toStr)
    }
  }

  ** Get API information and server metadata
  private Void onAbout()
  {
    dict := Etc.makeDict([
      "haystackVersion": Version("3.0"),
      "serverName":      "HaystackRestPod",
      "serverTime":      DateTime.now,
      "serverBootTime": context.bootTime,
      "productName":    "Haxall",
      "productUri":     "https://haxall.io/",
      "moduleName":     "mypod"
    ])
    
    sendGrid([dict])
  }

  ** List available operations
  private Void onOps()
  {
    ops := [
      Etc.makeDict(["name": "about", "summary": "Get API information"]),
      Etc.makeDict(["name": "ops", "summary": "List available operations"]),
      Etc.makeDict(["name": "read", "summary": "Read records by filter or ids"]),
      Etc.makeDict(["name": "nav", "summary": "Navigate record hierarchy"]),
      Etc.makeDict(["name": "watchSub", "summary": "Subscribe to watch"]),
      Etc.makeDict(["name": "watchUnsub", "summary": "Unsubscribe from watch"]),
      Etc.makeDict(["name": "watchPoll", "summary": "Poll watch for changes"]),
      Etc.makeDict(["name": "pointWrite", "summary": "Write to point"])
    ]
    sendGrid(ops)
  }

  ** Read records by filter or ids
  private Void onRead()
  {
    // Check content type
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    // Parse request
    grid := readZincGrid
    if (grid == null) return

    try
    {
      // Handle read by filter
      filter := grid.first?.get("filter") as Str
      if (filter != null)
      {
        // Parse filter string into AST
        ast := HaystackFilter.parse(filter)
        
        // Query Folio database
        results := folio.readAll(ast)
        
        // Send results
        sendGrid(results)
        return
      }

      // Handle read by ids
      ids := grid.first?.get("ids") as Ref[]
      if (ids != null)
      {
        // Query records by IDs
        results := Ref:Dict[:]
        ids.each |id| { results[id] = folio.read(id) }
        
        // Send results
        sendGrid(results.vals)
        return
      }

      onErr("Invalid read request - must specify 'filter' or 'ids'")
    }
    catch (Err e)
    {
      log.err("Read error", e)
      onErr("Read failed: ${e.msg}")
    }
  }

  ** Navigate record hierarchy
  private Void onNav()
  {
    // Check content type
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    try
    {
      // Parse request
      grid := readZincGrid
      if (grid == null) return

      // Get navId from request
      navId := grid.first?.get("navId") as Str
      if (navId == null)
      {
        // Return root nav nodes
        results := [
          Etc.makeDict([
            "id": "points",
            "dis": "Points",
            "icon": "point",
            "hasChildren": true
          ]),
          Etc.makeDict([
            "id": "equips",
            "dis": "Equipment",
            "icon": "equip",
            "hasChildren": true
          ])
        ]
        sendGrid(results)
        return
      }

      // Handle specific navigation paths
      switch (navId)
      {
        case "points":
          filter := HaystackFilter.parse("point")
          results := folio.readAll(filter)
          sendGrid(results)
          
        case "equips":
          filter := HaystackFilter.parse("equip")
          results := folio.readAll(filter)
          sendGrid(results)
          
        default:
          // Try to read specific item
          try
          {
            ref := Ref(navId)
            dict := folio.read(ref)
            sendGrid([dict])
          }
          catch (Err e)
          {
            onErr("Invalid navId: ${navId}")
          }
      }
    }
    catch (Err e)
    {
      log.err("Nav error", e)
      onErr("Navigation failed: ${e.msg}")
    }
  }

  ** Subscribe to watch
  private Void onWatchSub()
  {
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    try
    {
      // Parse request
      grid := readZincGrid
      if (grid == null) return

      // Get watch parameters
      watchId := grid.first?.get("watchId") as Str
      if (watchId == null)
      {
        onErr("Missing watchId")
        return
      }

      // Create watch if it doesn't exist
      if (!watches.containsKey(watchId))
      {
        watch := Watch
        {
          it.id = watchId
          it.lastPoll = DateTime.now
          it.changes = Ref:Dict[:]
        }
        watches[watchId] = watch
      }

      // Add points to watch
      ids := grid.first?.get("ids") as Ref[]
      if (ids != null)
      {
        watch := watches[watchId] as Watch
        ids.each |id|
        {
          if (!watch.changes.containsKey(id))
          {
            try
            {
              dict := folio.read(id)
              watch.changes[id] = dict
            }
            catch (Err e)
            {
              log.err("Watch read error: ${id}", e)
            }
          }
        }
      }

      // Return success
      sendGrid([Etc.makeDict(["watchId": watchId])])
    }
    catch (Err e)
    {
      log.err("Watch sub error", e)
      onErr("Watch subscription failed: ${e.msg}")
    }
  }

  ** Unsubscribe from watch
  private Void onWatchUnsub()
  {
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    try
    {
      // Parse request
      grid := readZincGrid
      if (grid == null) return

      // Get watch ID
      watchId := grid.first?.get("watchId") as Str
      if (watchId == null)
      {
        onErr("Missing watchId")
        return
      }

      // Remove watch
      watches.remove(watchId)

      // Return success
      sendGrid([Etc.makeDict(["watchId": watchId])])
    }
    catch (Err e)
    {
      log.err("Watch unsub error", e)
      onErr("Watch unsubscription failed: ${e.msg}")
    }
  }

  ** Poll watch for changes
  private Void onWatchPoll()
  {
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    try
    {
      // Parse request
      grid := readZincGrid
      if (grid == null) return

      // Get watch ID
      watchId := grid.first?.get("watchId") as Str
      if (watchId == null)
      {
        onErr("Missing watchId")
        return
      }

      // Get watch
      watch := watches[watchId] as Watch
      if (watch == null)
      {
        onErr("Invalid watchId")
        return
      }

      // Update watched points
      changes := Dict[,]
      watch.changes.each |dict, id|
      {
        try
        {
          newDict := folio.read(id)
          if (dict != newDict)
          {
            changes.add(newDict)
            watch.changes[id] = newDict
          }
        }
        catch (Err e)
        {
          log.err("Watch poll read error: ${id}", e)
        }
      }

      // Update last poll time
      watch.lastPoll = DateTime.now

      // Return changes
      sendGrid(changes)
    }
    catch (Err e)
    {
      log.err("Watch poll error", e)
      onErr("Watch poll failed: ${e.msg}")
    }
  }

  ** Write to point
  private Void onPointWrite()
  {
    if (req.method != "POST")
    {
      res.statusCode = 405
      onErr("Method not allowed")
      return
    }

    try
    {
      // Parse request
      grid := readZincGrid
      if (grid == null) return

      // Get point ID and value
      dict := grid.first
      if (dict == null)
      {
        onErr("Missing write data")
        return
      }

      id := dict.get("id") as Ref
      if (id == null)
      {
        onErr("Missing point id")
        return
      }

      val := dict.get("val")
      if (val == null)
      {
        onErr("Missing write value")
        return
      }

      // Write to point
      point := folio.read(id)
      if (!point.has("writable"))
      {
        onErr("Point not writable")
        return
      }

      // Perform write operation
      folio.commit(Diff.makeAdd(id, ["curVal":val, "writeVal":val]))

      // Return updated point
      sendGrid([folio.read(id)])
    }
    catch (Err e)
    {
      log.err("Point write error", e)
      onErr("Point write failed: ${e.msg}")
    }
  }

  ** Send error response
  private Void onErr(Str msg)
  {
    res.statusCode = 500
    sendJson(["err": msg])
  }

  ** Send ZINC grid response
  private Void sendGrid(Dict[] recs)
  {
    res.headers["Content-Type"] = "text/zinc; charset=utf-8"
    out := res.out
    grid := Etc.makeListGrid(null, recs)
    writer := ZincWriter(out)
    writer.writeGrid(grid)
    out.flush
  }

  ** Send JSON response
  private Void sendJson(Str:Obj map)
  {
    res.headers["Content-Type"] = "application/json; charset=utf-8"
    out := res.out
    out.writeJson(map)
    out.flush
  }

  ** Read ZINC formatted grid from request
  private Grid? readZincGrid()
  {
    try
    {
      // Verify content type
      contentType := req.headers["Content-Type"] ?: ""
      if (!contentType.contains("text/zinc"))
      {
        res.statusCode = 415
        onErr("Unsupported content type, expected text/zinc")
        return null
      }

      // Read and parse ZINC
      return ZincReader(req.in).readGrid
    }
    catch (Err e)
    {
      log.err("ZINC parse error", e)
      res.statusCode = 400
      onErr("Invalid ZINC format: ${e.msg}")
      return null
    }
  }

  ** Watch class for tracking subscriptions
  private const class Watch
  {
    const Str id
    DateTime lastPoll
    const Ref:Dict changes
  }

  private const HxContext context
  private const Folio folio
}
