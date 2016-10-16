# Kadabra

HTTP/2 client for Elixir

Written to manage HTTP/2 connections for [pigeon](https://github.com/codedge-llc/pigeon). Very much a work in progress.

## Usage
```elixir
{:ok, pid} = Kadabra.open('http2.golang.org', :https)
Kadabra.get(pid, "/")
receive do
  {:end_stream, %Kadabra.Stream{} = stream} ->
  IO.inspect stream
after 5_000 ->
  IO.puts "Connection timed out."
end

%Kadabra.Stream{
  body: "<html>\n<body>\n<h1>Go + HTTP/2</h1>\n\n<p>Welcome to <a href=\"https://golang.org/\">the Go language</a>'s <a\nhref=\"https://http2.github.io/\">HTTP/2</a> demo & interop server.</p>\n\n<p>Congratulations, <b>you're using HTTP/2 right now</b>.</p>\n\n<p>This server exists for others in the HTTP/2 community to test their HTTP/2 client implementations and point out flaws in our server.</p>\n\n<p>\nThe code is at <a href=\"https://golang.org/x/net/http2\">golang.org/x/net/http2</a> and\nis used transparently by the Go standard library from Go 1.6 and later.\n</p>\n\n<p>Contact info: <i>bradfitz@golang.org</i>, or <a\nhref=\"https://golang.org/s/http2bug\">file a bug</a>.</p>\n\n<h2>Handlers for testing</h2>\n<ul>\n  <li>GET <a href=\"/reqinfo\">/reqinfo</a> to dump the request + headers received</li>\n  <li>GET <a href=\"/clockstream\">/clockstream</a> streams the current time every second</li>\n  <li>GET <a href=\"/gophertiles\">/gophertiles</a> to see a page with a bunch of images</li>\n  <li>GET <a href=\"/file/gopher.png\">/file/gopher.png</a> for a small file (does If-Modified-Since, Content-Range, etc)</li>\n  <li>GET <a href=\"/file/go.src.tar.gz\">/file/go.src.tar.gz</a> for a larger file (~10 MB)</li>\n  <li>GET <a href=\"/redirect\">/redirect</a>to redirect back to / (this page)</li>\n  <li>GET <a href=\"/goroutines\">/goroutines</a> to see all active goroutines in this server</li>\n  <li>GET <a href=\"/.well-known/h2interop/state\">/.well-known/h2interop/state</a> for the HTTP/2 server state</li>\n  <li>PUT something to <a href=\"/crc32\">/crc32</a> to get a count of number of bytes and its CRC-32</li>\n  <li>PUT something to <a href=\"/ECHO\">/ECHO</a> and it will be streamed back to you capitalized</li>\n</ul>\n\n</body></html>",
  headers: [{":status", "200"}, {"content-type", "text/html; charset=utf-8"}, {"content-length", "1708"}, {"date", "Sun, 16 Oct 2016 21:20:47 GMT"}],
  id: 1
}
```

## Making Requests Manually
```elixir
{:ok, pid} = Kadabra.open('http2.golang.org', :https)

path = "/ECHO" # Route echoes PUT body in uppercase
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

%Kadabra.Stream{
  body: "SAMPLE ECHO REQUEST",
  headers: [{":status", "200"}, {"content-type", "text/plain; charset=utf-8"}, {"date", "Sun, 16 Oct 2016 21:28:15 GMT"}],
  id: 1
}
```
