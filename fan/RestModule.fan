using web
using webmod
using haystack
using hx

**
** RestModule
** Main module for Haystack REST API
**
const class RestModule : HxModule
{
  new make()
  {
    this.service = HaystackRestService()
  }

  ** Module name
  override const Str name := "rest"

  ** Module version
  override const Version version := Version("1.0")

  ** Start module
  override Void onStart()
  {
    log.info("RestModule started")
    
    // Register web routes
    web := context.rt.web
    web.route(`/api/haystack/**`, service)
  }

  ** Stop module
  override Void onStop()
  {
    log.info("RestModule stopped")
  }

  private const HaystackRestService service
}
