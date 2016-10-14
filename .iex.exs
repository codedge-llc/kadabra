alias Kadabra.{Connection, Http2}
{:ok, pid} = Kadabra.open('http2.golang.org', :https)
#Kadabra.get(pid, "/")
#{:ok, pid} = Kadabra.open('cloudflare.com', :https)
