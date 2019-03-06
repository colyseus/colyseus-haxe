package;

import openfl.Assets;
import openfl.ui.Keyboard;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;

import io.colyseus.Client;
import io.colyseus.Room;

class Main extends Sprite {

	private var client: Client;
	private var room: Room;

	private var cats: Map<String, Sprite> = new Map();

	public function new () {
		super ();

		this.client = new Client("ws://0.0.0.0:2567");
		// this.client = new Client("ws://colyseus-examples.herokuapp.com");
		this.room = this.client.join("state_handler");

		// list available rooms for connection
        haxe.Timer.delay(function() {
			this.client.getAvailableRooms("state_handler", function(rooms, ?err) {
				if (err != null) trace("ERROR! " + err);
				for (room in rooms) {
					trace("RoomAvailable:");
					trace("roomId: " + room.roomId);
					trace("clients: " + room.clients);
					trace("maxClients: " + room.maxClients);
					trace("metadata: " + room.metadata);
				}
			});
        }, 3000);

		/**
		 * Client callbacks
		 */
		this.client.onOpen = function() {
			trace("CLIENT OPEN, id => " + this.client.id);
		};

		this.client.onClose = function () {
			trace("CLIENT CLOSE");
		};

		this.client.onError = function (message){
			trace("CLIENT ERROR: " + message);
		};

		/**
		 * Room callbacks
		 */
		this.room.onJoin = function() {
			trace("JOINED ROOM");
		};

		this.room.onStateChange = function (state) {
			trace("STATE CHANGE: " + Std.string(state));
		};

		this.room.onMessage = function (message) {
			trace("ROOM MESSAGE: " + Std.string(message));
		};

		this.room.onError = function (message) {
			trace("ROOM ERROR: " + message);
		};

		this.room.onLeave = function () {
			trace("ROOM LEAVE");
		}

		this.room.listen("players/:id", function(change) {
			if (change.operation == "add") {
				var cat = Assets.getMovieClip ("library:NyanCatAnimation");
				this.cats[change.path.id] = cat;
				cat.x = change.value.x;
				cat.y = change.value.y;
				addChild (cat);

			} else if (change.operation == "remove") {
				removeChild(this.cats[change.path.id]);
			}
		}, true);

		this.room.listen("players/:id/:axis", function(change) {
			if (this.cats.get(change.path.id) == null) {
				trace("CAT DONT EXIST: " + change.path.id);
				return;
			}

			if (change.path.axis == "x") {
				this.cats[change.path.id].x = change.value;

			} else if (change.path.axis == "y") {
				this.cats[change.path.id].y = change.value;
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
			this.room.send({ y: -1 });

		} else if (evt.keyCode == Keyboard.DOWN) {
			this.room.send({ y: 1 });

		} else if (evt.keyCode == Keyboard.LEFT) {
			this.room.send({ x: -1 });

		} else if (evt.keyCode == Keyboard.RIGHT) {
			this.room.send({ x: 1 });
		}
	}

	private function onKeyUp(evt:KeyboardEvent):Void {
	}

}