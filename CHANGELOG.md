# Changelog

All notable changes to the Colyseus Haxe SDK are documented in this file.

## 0.17.12

- Fix `getLatency()` (and therefore `selectByLatency()`) hanging on unresponsive endpoints. The measurement only completed on a pong or `onError`, so a server that closed the socket cleanly without replying (only `onClose` fires) left the callback pending forever, and a blackholed/unreachable host stalled indefinitely. `getLatency()` now also fails on `onClose` and on a configurable `timeout` (milliseconds, default `1500`, also forwarded through `selectByLatency()`) and invokes its callback exactly once, so a single wedged endpoint can no longer stall the whole selection. Ports the JS SDK fix for [#941](https://github.com/colyseus/colyseus/issues/941) — thanks @TJEvans for reporting!
