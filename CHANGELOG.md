# Changelog

All notable changes to the Colyseus Haxe SDK are documented in this file.

## 0.18.6

- The callback of `join()`, `joinOrCreate()`, `create()`, `joinById()` and `reconnect()` no longer fires a second time, with an error and a `null` room, when the room reports an error after joining (e.g. its socket drops while a mobile app sleeps). Thanks @serjek! [#86](https://github.com/colyseus/colyseus-haxe/issues/86)

## 0.18.5

- `SchemaListenMacro.listenRef()` observables now fill in when `listen()` is called after the first state has arrived, stay in sync with a collection on the root schema after the first patch, and apply removals from an `ArraySchema` of schemas. Listeners no longer pile up with every root change, and cancelling the returned link now detaches all of them. Thanks @serjek! [#84](https://github.com/colyseus/colyseus-haxe/pull/84)
- A `ref` field on a schema held in a collection now works with `SchemaListenMacro`; it failed to compile or crashed on the first patch. Thanks @serjek! [#84](https://github.com/colyseus/colyseus-haxe/pull/84), [#85](https://github.com/colyseus/colyseus-haxe/pull/85)

## 0.18.4

- `ObservableSchemaMacro` / `SchemaListenMacro` now compile a schema collection nested inside another, a child schema declared in its parent's module or in one your observables class doesn't import, and a `MapSchema<Bool>`. Thanks @serjek! [#82](https://github.com/colyseus/colyseus-haxe/pull/82)
- An observable `MapSchema<Serialized<T>>` now holds parsed `T` values instead of raw JSON strings, as `ArraySchema<Serialized<T>>` already did.

## 0.18.3

- `callbacks.listen(instance, "field", cb)` now calls `cb` right away with the field's current value for primitive fields too, as the TypeScript SDK does; it only did so for schema-typed fields, so a value already set before you registered was never reported until it changed. Pass `false` as the last argument to opt out.
- **Breaking for native programs that wait in a blocking loop:** room and matchmaking callbacks now run on the thread that joined, through its event loop, like on JS — such a loop must call `sys.thread.Thread.current().events.progress()` or the join never completes. They used to fire on the socket's own thread, racing your game loop's reads of the same state, and failing outright for `haxe.Timer` ("Event loop is not available"). Engines that progress the main thread's event loop each frame (Heaps, Lime, anything using `haxe.EntryPoint`) need no change.
- A headless native program can now simply return from `main()` after joining: an open room keeps the program running. It used to exit before the join finished unless it ran its own loop.
- `Callbacks.get(room)` callbacks now fire right after each patch is decoded, instead of on a later turn of the main loop. `SchemaCallbacks.enableMainLoopProcessing()` and `disableMainLoopProcessing()` are gone: room callbacks already run on the thread that joined.
- `for (key => value in mapSchema)` now iterates in insertion order, like `for (value in mapSchema)` and JS's `Map`, and no longer copies every key on each loop on HashLink.

## 0.18.2

- `t.quantized()` fields on a range symmetric about zero (`min: -1, max: 1`) now decode an exact `0`. A released input axis or a resting velocity arrived as one quantum above zero, so a `== 0` check never fired and anything integrating the value drifted. Requires a server on @colyseus/schema 5.0.27 — the wire mapping for these fields changed.

## 0.18.1

- `t.quantized()` / `t.angle()` input fields now hold the value that goes on the wire once the input is sent, instead of the raw value you assigned. Prediction replayed from the un-snapped value, so every step mispredicted — it looked like a movement bug rather than a rounding one.
- The first input packet after connecting (or after `reset()`) now carries every field, not just the ones you changed. A field your input schema declares with a non-zero default never moved, so it was never sent, and the server kept its own zero for it.

## 0.18.0

Requires a Colyseus 0.18 server — the room protocol and the schema wire format both changed.

- Client-side prediction, via `Predict.get(room)`: a rollback reconciler that replays unacknowledged input against server state, `sim()` to drive several instances as one world, `spawns()` for entries that appear before the server confirms them, and `defineEvent()` for effects that must fire once even though the tick they happen on is replayed. Corrections are smoothed rather than snapped (`smoothMs`).
- Typed input, via `room.input({ type: MyInput })`. The returned `InputHandle<MyInput>` is typed, so `handle.data.dx` compiles; fields are delta-encoded, and `"unreliable"` mode resends a short ring of recent ticks so a dropped packet does not cost an input.
- `room.clock` reads server time (`serverNow()`, `lastServerTime()`, `smoothedRtt()`), which is what input stamping and prediction are timed against.
- Schema 5.0 wire format: the new reflection layout, `t.quantized()` fields (bounded floats sent as 8/16/32-bit integers), full-snapshot resync on rejoin, and the 5.0 `ArraySchema` semantics.
- `room.reconnection` now configures automatic reconnection — enable/disable, attempt cap, min/max delay, and a custom backoff curve (defaults to exponential).

## 0.17.13

- Fix matchmaking HTTP requests failing on native targets (cpp/iOS/Android) when the JSON body contains non-ASCII characters. The `Content-Length` header was set from `String.length` (character count), while tink_http writes the body as UTF-8 bytes — so multi-byte bodies were truncated by the server, causing "Unterminated string in JSON" 400 errors. The header is now computed from the UTF-8 byte length ([#79](https://github.com/colyseus/colyseus-haxe/issues/79)) — thanks @hansagames for the report and the fix!

## 0.17.12

- Fix `getLatency()` (and therefore `selectByLatency()`) hanging on unresponsive endpoints. The measurement only completed on a pong or `onError`, so a server that closed the socket cleanly without replying (only `onClose` fires) left the callback pending forever, and a blackholed/unreachable host stalled indefinitely. `getLatency()` now also fails on `onClose` and on a configurable `timeout` (milliseconds, default `1500`, also forwarded through `selectByLatency()`) and invokes its callback exactly once, so a single wedged endpoint can no longer stall the whole selection. Ports the JS SDK fix for [#941](https://github.com/colyseus/colyseus/issues/941) — thanks @TJEvans for reporting!
