package io.colyseus.tools;

import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;
import io.colyseus.tools.*;
import tink.state.*;
import tink.json.Serialized;

using tink.CoreApi;

// Player schema
@:keep
class PlayerSchema extends Schema {
	@:type("string")
	public var name:String;

	@:type("number")
	public var score:Int;

	@:type("string")
	public var avatar:Serialized<PlayerAvatar>;

	@:type("array", "number")
	public var turns:ArraySchema<Int> = new ArraySchema();

	@:type("map", "number")
	public var inventory:MapSchema<Int> = new MapSchema<Int>();
}

// Game schema
@:keep
class GameSchema extends Schema {
	@:type("array", PlayerSchema)
	public var players:ArraySchema<PlayerSchema> = new ArraySchema<PlayerSchema>();

	@:type("boolean")
	public var isFinished:Bool;
}

typedef PlayerAvatar = {
	final url_large:String;
	final url_small:String;
}

@:build(io.colyseus.tools.ObservableSchemaMacro.build(GameSchema))
class GameObservable {
	private static var link:CallbackLink;
	public function listen(room:Room<GameSchema>) link = SchemaListenMacro.listenRef(Callbacks.get(room), room.state);
	public function dispose() link.cancel();
}

class MainExample {
	static function main() {
		var observables:GameObservable = new GameObservable();
		var client:Client = new Client("ws://localhost:2567");

		client.joinOrCreate("my_room", [], GameSchema, function(err, room) {
			if (err != null) {
				trace("[MyRoom] error: " + err);
				return;
			}

			trace("[MyRoom] roomId: " + room.roomId);
			observables.listen(room);

			// ... game logic does something with schema items on server side ...
			// and this autorun observable will trigger on every change it is subscribed to - players and their properties:

			Observable.autorun(() -> for (item in observables.players) {
				trace('Player ${item.name} (${item.avatar.value.url_large})');
				trace('  scores ${item.score.value}');
				trace('  turns ${item.turns.toArray()}');
				trace('  inventory ${item.inventory.toMap()}');
			});

			// or just bind to individual field:
			observables.isFinished.observe().bind(x -> if (x) trace("Game is finished!"));

			// tink.state.State has many uses and handy methods, see full doc here: https://github.com/haxetink/tink_state
		});
	}
}