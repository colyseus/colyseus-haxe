package;

import openfl.Assets;
import openfl.ui.Keyboard;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;

import io.colyseus.Client;
import io.colyseus.Room;

class Main extends Sprite {
	private var client:Client;
	private var room:Room<State>;

	private var cats:Map<String, Sprite> = new Map();

	public function new() {
		super();

		// this.client = new Client("ws://192.168.0.5:2567");
		this.client = new Client("ws://localhost:2567");
		// this.client = new Client("wss://colyseus-examples.herokuapp.com");

		// list available rooms for connection
		haxe.Timer.delay(function() {
			this.client.getAvailableRooms("state_handler", function(err, rooms) {
				if (err != null) {
					trace("ERROR! " + err);
                    return;
                }

				for (room in rooms) {
					trace("RoomAvailable:");
					trace("roomId: " + room.roomId);
					trace("clients: " + room.clients);
					trace("maxClients: " + room.maxClients);
					trace("metadata: " + room.metadata);
				}
			});
		}, 3000);

		this.client.joinOrCreate("state_handler", [], State, function(err, room) {
            if (err != null) {
                trace("ERROR! " + err);
                return;
            }

            this.room = room;
            this.room.state.players.onAdd = function(player, key) {
                trace("PLAYER ADDED AT: ", key);
                var cat = Assets.getMovieClip("library:NyanCatAnimation");
                this.cats[key] = cat;
                cat.x = player.x;
                cat.y = player.y;
                addChild(cat);
            }

            this.room.state.players.onChange = function(player, key) {
                trace("PLAYER CHANGED AT: ", key);
                this.cats[key].x = player.x;
                this.cats[key].y = player.y;
            }

            this.room.state.players.onRemove = function(player, key) {
                trace("PLAYER REMOVED AT: ", key);
                removeChild(this.cats[key]);
            }

            this.room.onStateChange += function(state) {
                trace("STATE CHANGE: " + Std.string(state));
            };

            this.room.onMessage(0, function(message) {
                trace("onMessage: 0 => " + message);
            });

            this.room.onMessage("type", function(message) {
                trace("onMessage: 'type' => " + message);
            });

            this.room.onError += function(code: Int, message: String) {
                trace("ROOM ERROR: " + code + " => " + message);
            };

            this.room.onLeave += function() {
                trace("ROOM LEAVE");
            }
        });

		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);

		stage.addEventListener(Event.ENTER_FRAME, onUpdate);
	}

	private function onUpdate(e:Event):Void {
		// Your update function...
	}

	private function onKeyDown(evt:KeyboardEvent):Void {
		if (evt.keyCode == Keyboard.UP) {
			this.room.send("move", {y: -1});
		} else if (evt.keyCode == Keyboard.DOWN) {
			this.room.send("move", {y: 1});
		} else if (evt.keyCode == Keyboard.LEFT) {
			this.room.send("move", {x: -1});
		} else if (evt.keyCode == Keyboard.RIGHT) {
			this.room.send("move", {x: 1});
		}
	}

	private function onKeyUp(evt:KeyboardEvent):Void {}
}
