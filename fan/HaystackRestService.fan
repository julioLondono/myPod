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
    // TODO: Implement navigation
    sendGrid([,])
  }

  ** Subscribe to watch
  private Void onWatchSub()
  {
    // TODO: Implement watch subscription
    sendGrid([,])
  }

  ** Unsubscribe from watch
  private Void onWatchUnsub()
  {
    // TODO: Implement watch unsubscription
    sendGrid([,])
  }

  ** Poll watch for changes
  private Void onWatchPoll()
  {
    // TODO: Implement watch polling
    sendGrid([,])
  }

  ** Write to point
  private Void onPointWrite()
  {
    // TODO: Implement point write
    sendGrid([,])
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

  private const HxContext context
  private const Folio folio
}
