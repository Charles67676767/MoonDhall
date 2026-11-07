let pair = \(a : Type) -> \(left : a) -> \(right : a) -> [ left, right ]
let Port = Natural
let ports = pair Port 8080 9090
let names = pair Text "api" "admin"
let total = List/fold Natural ports Natural
  (\(port : Natural) -> \(sum : Natural) -> port + sum) 0
in { ports = ports
   , names = names
   , count = List/length Port ports
   , first = List/head Port ports
   , indexed = List/indexed Text names
   , total = total
   }
