let defaults = ./defaults.dhall
let banner = ./banner.txt as Text
let Environment = < Development | Production >
let environment = Environment.Production
let debug = merge { Development = True, Production = False } environment
let service = \(name : Text) -> \(port : Natural) ->
  { host = defaults.host
  , port = port
  , labels = defaults.labels # [ name ]
  , description = "service: ${name}"
  }
in { services.api = service "api" 8080
   , services.admin = service "admin" 9090
   , debug = debug
   , banner = banner
   }
