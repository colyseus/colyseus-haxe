package;

import openfl.display.Sprite;
import openfl.Assets;

import io.colyseus.Client;
import io.colyseus.Room;

class Main extends Sprite {

	private var client: Client;
	private var room: Room;

	private var cats: Map<String, Sprite> = new Map();

	public function new () {
		super ();

		this.client = new Client("ws://localhost:2567");
		this.room = this.client.join("state_handler");

		this.client.onOpen = function() {
			trace("CLIENT OPEN, id => " + this.client.id);
		};

		this.client.onMessage = function(message) {
			trace("CLIENT MESSAGE: " + Std.string(message));
		};

		this.client.onClose = function () {
			trace("CLIENT CLOSE");
		};

		this.client.onError = function (message){
			trace("CLIENT ERROR: " + message);
		};

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
			var cat = Assets.getMovieClip ("library:NyanCatAnimation");
			this.cats[change.path.id] = cat;
			addChild (cat);
		});

	}

}