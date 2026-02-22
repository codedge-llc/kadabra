# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.2] - 2026-02-22

### Fixed

- SSL socket usage in OTP 28. ([#56](https://github.com/codedge-llc/kadabra/pull/56))
- Removed Elixir compile warnings. ([#58](https://github.com/codedge-llc/kadabra/pull/58))

## [0.6.1] - 2024-08-30

### Fixed

- Removed Elixir compile warnings.

## [0.6.0] - 2021-03-04

### Security

- Verify CA certificates with `:certifi` (~> 2.5) by default. This is considered a breaking change
for anyone using Kadabra for anything other than [Pigeon](https://github.com/codedge-llc/pigeon).

## [0.5.0] - 2021-01-10

### Changed

- Minimum Elixir version bumped to 1.6.

### Fixed

- Removed Elixir 1.11 compile warnings.

## [0.4.5] - 2020-04-08

- Removed some compile warnings.

## [0.4.4] - 2018-10-13

- Fixed ArithmeticError when calculating how many streams to request
on infinite stream sets.

## [0.4.3] - 2018-07-28

- Fixed supervisor crash report during normal connection shutdown.
- Removed `GenStage` dependency.
- GOAWAY error logger messages now disabled by default.
Re-enable with `config :kadabra, debug_log?: true`.

## [0.4.2] - 2018-05-25

- Fixed `{:closed, pid}` task race condition during connection cleanup.
- Everything is supervised under `Kadabra.Application` again, instead of
handling supervision yourself.

## [0.4.1] - 2018-05-10

- Send exactly number of allowed bytes on initial connection WINDOW_UPDATE.
- Default settings use maximum values for MAX_FRAME_SIZE and INITIAL_WINDOW_SIZE.
- Incoming PING and WINDOW_UPDATE frames are now validated, closing the
connection if an error is encountered.
- Fixed: can no longer accidentally send 0-size WINDOW_UPDATE frames.
- Fixed: don't send WINDOW_UPDATE frames larger than remote server's available
connection flow window.

## [0.4.0] - 2018-04-04

- Support for `http` URIs.
- Requests are now buffered with GenStage.
- Added `Kadabra.head/2` and `Kadabra.delete/2`.
- `Kadabra.open/3` replaced with `Kadabra.open/2`.
  - Scheme, host and port are now automatically parsed from the URI string.
  See the README for examples.
  - Socket options passed as `:tcp`/`:ssl`, respectively.
- Removed `:reconnect` functionality.

## [0.3.8] - 2018-02-25

- Fixed: Streams properly killed if hpack table crashes.
- Removed unused `Scribe` dependency.

## [0.3.7] - 2018-01-07

- Fixed: `noproc` crash caused by race condition on recv GOAWAY.

## [0.3.6] - 2017-12-18

- Fixed: ES flag properly set on certain HEADERS frames.

## [0.3.5] - 2017-12-04

- Fixed: Memory leak on connection crashes.
- New supervision structure. `Kadabra.open/2` now returns a supervisor pid,
but the API for making requests remains unchanged.

## [0.3.4] - 2017-10-31

- Fixed: Connections properly respect settings updates.

## [0.3.3] - 2017-10-23

- Fixed: Hpack memory leak on connection close.

## [0.3.2] - 2017-09-16

- Fixed: Connection settings defaults are now actually default.

## [0.3.1] - 2017-08-26

- Fixed: Sending payloads larger than the stream window.

## [0.3.0] - 2017-08-11

- Minimum requirements are now Elixir 1.4/OTP 19.
- Performance improvements for individual streams.
- Fixed: multiple connections now supported per host.
- Request responses now return with new `%Stream.Response{}` struct.
- Push promises can be intercepted with `{:push_promise, %Stream.Response{}}`
messages.

## [0.2.2] - 2017-08-03

- `Connection` now respects `max_concurrent_streams`.
- Fixed: proper WINDOW_UPDATE responses on received DATA frames.

## [0.2.1] - 2017-08-01

- Fixed: calling `Kadabra.open/3` with `reconnect: false` to disable
automatic reconnect on socket close.

