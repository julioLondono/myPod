using build

class Build : BuildPod
{
  new make()
  {
    podName = "mypod"
    summary = "Haystack REST API Pod"
    version = Version("1.0")
    
    // Dependencies
    depends = [
      "sys 1.0+",
      "concurrent 1.0+",  // For async operations
      "web 1.0+",        // For REST API
      "webmod 1.0+",     // Web modules
      "auth 1.0+",       // Authentication
      "crypto 1.0+",     // Security
      "folio 1.0+",      // Database
      "haystack 1.0+",   // Core Haystack
      "axon 1.0+",       // Axon programming language
      "hx 1.0+",         // Haxall core
      "hxFolio 1.0+",    // Haxall Folio integration
      "hxd 1.0+"         // Haxall daemon
    ]
    
    // Source and resource directories
    srcDirs = [`fan/`]
    resDirs = [`locale/`, `res/`]  // Add res/ for web resources
    
    // Index source files
    index = ["ph.rest": "REST API"]
    
    // Metadata
    meta = [
      "org.name":     "HxPod",
      "org.uri":      "https://hxpod.org",
      "proj.name":    "HaystackRestPod",
      "proj.uri":     "https://hxpod.org/mypod",
      "license.name": "MIT",
      "vcs.name":     "Git",
      "ph.service":   "true"  // Mark as Haystack service
    ]
  }
}
