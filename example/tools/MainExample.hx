package tools;

import io.colyseus.Room;
import io.colyseus.Client;
import io.colyseus.serializer.schema.Callbacks;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;
import io.colyseus.tools.*;
import tink.state.*;

using tink.CoreApi;

// Item schema
// NOTE: even though schema generator will create Dynamic types sometimes, it is your responsibility to change it to concrete types manually as it will help macro to generate correct binding.
@:keep
class Item extends Schema {
	@:type("string")
	public var name:String;

	@:type("number")
	public var value:Float;
}

// Player schema
@:keep
class Player extends Schema {
	@:type("number")
	public var x:Int = 0;

	@:type("number")
	public var y:Int = 0;

	@:type("boolean")
	public var isBot:Bool;

	@:type("boolean")
	public var disconnected:Bool;

	@:type("array", Item)
	public var items:ArraySchema<Item> = new ArraySchema<Item>();
}

// MyRoomState schema
@:keep
class MyRoomState extends Schema {
	@:type("map", Player)
	public var players:MapSchema<Player> = new MapSchema<Player>();

	@:type("ref", Player)
	public var host:Player = new Player();

	@:type("string")
	public var currentTurn:String;
}

@:build(io.colyseus.tools.ObservableSchemaMacro.build(MyRoomState))
class MyRoomObservable {
	private static var link:CallbackLink;
	public function listen(room:Room<MyRoomState>) link = SchemaListenMacro.listenRef(Callbacks.get(room), room.state);
	public function dispose() link.cancel();
}

class MainExample {
	static function main() {
		var observables:MyRoomObservable = new MyRoomObservable();
		var client:Client = new Client("ws://localhost:2567");

		client.joinOrCreate("my_room", [], MyRoomState, function(err, room) {
			if (err != null) {
				trace("[MyRoom] error: " + err);
				return;
			}

			trace("[MyRoom] roomId: " + room.roomId);
			observables.listen(room);

			// ... game logic does something with schema items on server side ...
			// and this autorun observable will trigger on every change it is subscribed to - players and their properties:

			Observable.autorun(() -> for (player in observables.players) {
				trace('Player x=${player.x.value} y=${player.y.value} isBot=${player.isBot.value}');
				trace('  items: ${player.items.toArray()}');
			});

			// or just bind to individual field:
			observables.currentTurn.observe().bind(x -> trace('Current turn: $x'));

			// tink.state.State has many uses and handy methods, see full doc here: https://github.com/haxetink/tink_state
		});
	}
}
