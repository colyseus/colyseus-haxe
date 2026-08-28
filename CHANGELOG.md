# Changelog

All notable changes to the Colyseus Haxe SDK are documented in this file.

## Unreleased

- `t.quantized()` / `t.angle()` input fields now hold the value that goes on the wire once the input is sent, instead of the raw value you assigned. Prediction replayed from the un-snapped value, so every step mispredicted — it looked like a movement bug rather than a rounding one.
- The first input packet after connecting (or after `reset()`) now carries every field, not just the ones you changed. A field your input schema declares with a non-zero default never moved, so it was never sent, and the server kept its own zero for it.

## 0.17.13

- Fix matchmaking HTTP requests failing on native targets (cpp/iOS/Android) when the JSON body contains non-ASCII characters. The `Content-Length` header was set from `String.length` (character count), while tink_http writes the body as UTF-8 bytes — so multi-byte bodies were truncated by the server, causing "Unterminated string in JSON" 400 errors. The header is now computed from the UTF-8 byte length ([#79](https://github.com/colyseus/colyseus-haxe/issues/79)) — thanks @hansagames for the report and the fix!

## 0.17.12

- Fix `getLatency()` (and therefore `selectByLatency()`) hanging on unresponsive endpoints. The measurement only completed on a pong or `onError`, so a server that closed the socket cleanly without replying (only `onClose` fires) left the callback pending forever, and a blackholed/unreachable host stalled indefinitely. `getLatency()` now also fails on `onClose` and on a configurable `timeout` (milliseconds, default `1500`, also forwarded through `selectByLatency()`) and invokes its callback exactly once, so a single wedged endpoint can no longer stall the whole selection. Ports the JS SDK fix for [#941](https://github.com/colyseus/colyseus/issues/941) — thanks @TJEvans for reporting!
