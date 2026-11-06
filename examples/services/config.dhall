let service = \(port : Natural) ->
  { host = "127.0.0.1", port = port, enabled = True }

in { api = service 8080, admin = service 9090 }
