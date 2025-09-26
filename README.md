# Kadabra

> HTTP/2 client for Elixir. Written to manage HTTP/2 connections for [pigeon](https://github.com/codedge-llc/pigeon).

[![CI](https://github.com/codedge-llc/kadabra/actions/workflows/ci.yml/badge.svg)](https://github.com/codedge-llc/kadabra/actions/workflows/ci.yml)
[![Version](https://img.shields.io/hexpm/v/kadabra.svg)](https://hex.pm/packages/kadabra)
[![Total Downloads](https://img.shields.io/hexpm/dt/kadabra.svg)](https://hex.pm/packages/kadabra)
[![License](https://img.shields.io/hexpm/l/kadabra.svg)](https://github.com/codedge-llc/kadabra/blob/master/LICENSE)
[![Last Updated](https://img.shields.io/github/last-commit/codedge-llc/kadabra.svg)](https://github.com/codedge-llc/kadabra/commits/master)
[![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/kadabra/)

## Installation

_Requires Elixir 1.6/OTP 19.2 or later._

Add kadabra to your `mix.exs`:

```elixir
def deps do
  [
    {:kadabra, "~> 0.6.1"}
  ]
end
```

## Usage

```elixir
{:ok, pid} = Kadabra.open("https://http2.codedge.dev")
Kadabra.get(pid, "/")
receive do
  {:end_stream, %Kadabra.Stream.Response{} = stream} ->
  IO.inspect stream
after 5_000 ->
  IO.puts "Connection timed out."
end

%Kadabra.Stream.Response{
  body: "<html>\\n<body>\\n<h1>Go + HTTP/2</h1>\\n\\n<p>Welcome to..."
  headers: [
    {":status", "200"},
    {"content-type", "text/html; charset=utf-8"},
    {"content-length", "1708"},
    {"date", "Sun, 16 Oct 2016 21:20:47 GMT"}
  ],
  id: 1,
  status: 200
}
```

## Making Requests Manually

```elixir
{:ok, pid} = Kadabra.open("https://http2.codedge.dev")

path = "/ECHO" # Route echoes PUT body in uppercase
body = "sample echo request"
headers = [
  {":method", "PUT"},
  {":path", path},
]

Kadabra.request(pid, headers, body)

receive do
  {:end_stream, %Kadabra.Stream.Response{} = stream} ->
  IO.inspect stream
after 5_000 ->
  IO.puts "Connection timed out."
end

%Kadabra.Stream.Response{
  body: "SAMPLE ECHO REQUEST",
  headers: [
    {":status", "200"},
    {"content-type", "text/plain; charset=utf-8"},
    {"date", "Sun, 16 Oct 2016 21:28:15 GMT"}
  ],
  id: 1,
  status: 200
}
```

## Contributing

### Testing

Unit tests can be run with `mix test` or `mix coveralls.html`.

### Formatting

This project uses Elixir's `mix format` and [Prettier](https://prettier.io) for formatting.
Add hooks in your editor of choice to run it after a save. Be sure it respects this project's
`.formatter.exs`.

### Commits

Git commit subjects use the [Karma style](http://karma-runner.github.io/5.0/dev/git-commit-msg.html).

## License

Copyright (c) 2016-2024 Codedge LLC (https://www.codedge.io/)

This library is MIT licensed. See the [LICENSE](https://github.com/codedge-llc/kadabra/blob/master/LICENSE) for details.
