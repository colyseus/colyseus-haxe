<div align="center">
  <a href="https://github.com/gamestdio/colyseus">
    <img src="https://github.com/gamestdio/colyseus/blob/master/media/header.png?raw=true" />
  </a>
  <br>
  <br>
  <a href="https://npmjs.com/package/colyseus">
    <img src="https://img.shields.io/npm/dm/colyseus.svg?style=for-the-badge">
  </a>
  <a href="https://patreon.com/endel" title="Donate to this project using Patreon">
    <img src="https://img.shields.io/badge/patreon-donate-yellow.svg?style=for-the-badge" alt="Patreon donate button" />
  </a>
  <a href="http://discuss.colyseus.io" title="Discuss on Forum">
    <img src="https://img.shields.io/badge/discuss-on%20forum-brightgreen.svg?style=for-the-badge&colorB=b400ff" alt="Discussion forum" />
  </a>
  <a href="https://discord.gg/RY8rRS7">
    <img src="https://img.shields.io/discord/525739117951320081.svg?style=for-the-badge">
  </a>
  <h3>
     Multiplayer Game Client for <a href="https://haxe.org/">Haxe</a> <br /><a href="http://colyseus.io/docs/">View documentation</a>
  <h3>
</div>

## Example

The [`example`](example/NyanCat) project can be compiled to `html5`, `neko`,
`cpp`, `ios`, etc.

It uses the `state_handler` room from the [colyseus-examples](https://github.com/gamestdio/colyseus-examples) project, which you
can find [here](https://github.com/gamestdio/colyseus-examples/blob/master/rooms/02-state-handler.ts).

**Compiling it to `html5` ([live demo](http://gamestd.io/colyseus-hx/))**

```
lime build project.xml html5
```

## Usage

### Connecting to server:

```haxe
import io.colyseus.Client;
import io.colyseus.Room;

var client = new Client('ws://localhost:2657');
```

### Joining to a room:

```haxe
var room = client.join("room_name");
room.onJoin = function() {
    trace(client.id + " joined " + room.name);
}
```

### Listening to room state change:

Listening to entities being added/removed from the room:

```haxe
room.listen("entities/:id", function (change) {
    trace("new entity " +  change.path.id + " => " + change.value);
});
```

Listening to entity attributes being added/replaced/removed:

```haxe
room.listen("entities/:id/:attribute", function (change) {
    trace("entity " + change.path.id + " changed attribute " + change.path.attribute + " to " + change.value);
});
```

### Other room events

Room state has been updated:

```haxe
room.onStateChange = function(state) {
  // full new state avaialble on 'state' variable
}
```

Message broadcasted from server or directly to this client:

```haxe
room.onMessage = function (message) {
  trace(client.id + " received on " + room.name + ": " + message);
}
```

Server error occurred:

```haxe
room.onError = function() {
  trace(client.id + " couldn't join " + room.name);
}
```

The client left the room:

```haxe
room.onLeave = function() {
  trace(client.id + " left " + room.name);
}
```

## `ios` target caveats

You may need to manually apply this patch in order to compile for iOS: [HaxeFoundation/hxcpp@5f63d23](https://github.com/HaxeFoundation/hxcpp/commit/5f63d23768988ba2a4d4488843afab70d279a593)

> More info:
> http://community.openfl.org/t/solved-system-not-available-on-ios-with-xcode-9-0/9683?source_topic_id=10046


## License

MIT
