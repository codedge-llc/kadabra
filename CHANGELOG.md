# Changelog

## Unreleased

**Fixed**

- Fix crashes due to missing error handling

## v0.6.0

**Security**

- Verify CA certificates with `:certifi` (~> 2.5) by default. This is considered a breaking change
  for anyone using Kadabra for anything other than [Pigeon](https://github.com/codedge-llc/pigeon).

## v0.5.0

**Changed**

- Minimum Elixir version bumped to 1.6.

**Fixed**

- Removed Elixir 1.11 compile warnings.

## v0.4.5

- Removed some compile warnings.

## v0.4.4

- Fixed ArithmeticError when calculating how many streams to request
  on infinite stream sets.

## v0.4.3

- Fixed supervisor crash report during normal connection shutdown.
- Removed `GenStage` dependency.
- GOAWAY error logger messages now disabled by default.
  Re-enable with `config :kadabra, debug_log?: true`.

## v0.4.2

- Fixed `{:closed, pid}` task race condition during connection cleanup.
- Everything is supervised under `Kadabra.Application` again, instead of
  handling supervision yourself.

## v0.4.1

- Send exactly number of allowed bytes on initial connection WINDOW_UPDATE.
- Default settings use maximum values for MAX_FRAME_SIZE and INITIAL_WINDOW_SIZE.
- Incoming PING and WINDOW_UPDATE frames are now validated, closing the
  connection if an error is encountered.
- Fixed: can no longer accidentally send 0-size WINDOW_UPDATE frames.
- Fixed: don't send WINDOW_UPDATE frames larger than remote server's available
  connection flow window.

## v0.4.0

- Support for `http` URIs.
- Requests are now buffered with GenStage.
- Added `Kadabra.head/2` and `Kadabra.delete/2`.
- `Kadabra.open/3` replaced with `Kadabra.open/2`.
  - Scheme, host and port are now automatically parsed from the URI string.
    See the README for examples.
  - Socket options passed as `:tcp`/`:ssl`, respectively.
- Removed `:reconnect` functionality.

## v0.3.8

- Fixed: Streams properly killed if hpack table crashes.
- Removed unused `Scribe` dependency.

## v0.3.7

- Fixed: `noproc` crash caused by race condition on recv GOAWAY.

## v0.3.6

- Fixed: ES flag properly set on certain HEADERS frames.

## v0.3.5

- Fixed: Memory leak on connection crashes.
- New supervision structure. `Kadabra.open/2` now returns a supervisor pid,
  but the API for making requests remains unchanged.

## v0.3.4

- Fixed: Connections properly respect settings updates.

## v0.3.3

- Fixed: Hpack memory leak on connection close.

## v0.3.2

- Fixed: Connection settings defaults are now actually default.

## v0.3.1

- Fixed: Sending payloads larger than the stream window.

## v0.3.0

- Minimum requirements are now Elixir 1.4/OTP 19.
- Performance improvements for individual streams.
- Fixed: multiple connections now supported per host.
- Request responses now return with new `%Stream.Response{}` struct.
- Push promises can be intercepted with `{:push_promise, %Stream.Response{}}`
  messages.

## v0.2.2

- `Connection` now respects `max_concurrent_streams`.
- Fixed: proper WINDOW_UPDATE responses on received DATA frames.

## v0.2.1

- Fixed: calling `Kadabra.open/3` with `reconnect: false` to disable
  automatic reconnect on socket close.
