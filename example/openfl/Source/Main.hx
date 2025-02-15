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

		this.client.joinOrCreate("state_handler", [], State, function(err, room) {
            if (err != null) {
                trace("ERROR! " + err);
                return;
            }

			trace("joinOrCreate, roomId: " + room.roomId);

            this.room = room;

            this.room.state.players.onAdd((player, key) -> {
                trace("PLAYER ADDED AT: ", key);

                var cat = Assets.getMovieClip("library:NyanCatAnimation");
                this.cats.set(key, cat);
                cat.x = player.x;
                cat.y = player.y;
                addChild(cat);

				player.onChange((changes) -> {
					this.cats.get(key).x = player.x;
					this.cats.get(key).y = player.y;
				});
            });

            this.room.state.players.onRemove((player, key) -> {
                trace("PLAYER REMOVED AT: ", key);
                removeChild(this.cats.get(key));
            });

            this.room.onStateChange += (state) -> {
            };

            this.room.onMessage(0, (message) -> {
                trace("onMessage: 0 => " + message);
            });

            this.room.onMessage("type", (message) -> {
                trace("onMessage: 'type' => " + message);
            });

            this.room.onError += (code: Int, message: String) -> {
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
