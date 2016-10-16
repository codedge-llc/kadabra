alias Kadabra.{Connection, Http2}
#{:ok, pid} = Kadabra.open('http2.golang.org', :https)
#Kadabra.get(pid, "/")
#receive do
#  {:end_stream, %Kadabra.Stream{} = stream} ->
#  IO.inspect stream
#after 5_000 ->
#  IO.puts "Connection timed out."
#end

{:ok, pid} = Kadabra.open('http2.golang.org', :https)

path = "/ECHO"
body = "sample echo request"
headers = [
  {":method", "PUT"},
  {":path", path},
]

Kadabra.request(pid, headers, body)

receive do
  {:end_stream, %Kadabra.Stream{} = stream} ->
  IO.inspect stream
after 5_000 ->
  IO.puts "Connection timed out."
end
