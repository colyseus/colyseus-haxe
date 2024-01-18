import io.colyseus.Client;
import io.colyseus.Room;

class Main extends hxd.App {
  private var client = new Client("ws://localhost:2567");
  private var room: Room<State>;

	override function init() {
        // auth
        this.client.auth.onChange(function (user) {
            trace('auth.onChange', user);
        });

        this.client.auth.signInAnonymously(function(err, data) {
            trace("signInAnonymously => err: " + err + ", data: " + data);
        });

        // room
		this.client.joinOrCreate("my_room", [], State, function(err, room) {
			if (err != null) {
				trace(err);
				return;
			}

			// this triggers only when map or array are created with `new`
			// when new value appended it is also triggered but traces just empty array
			room.state.container.onChange(function(v) trace('Root.onChange', v));

			// following callbacks are never triggered
			room.state.container.testMap.onChange(function(v, k) trace('Map.onChange', v, 'key', k));
			room.state.container.testMap.onAdd(function(v, k) trace('Map.onAdd', v, 'key', k));
			room.state.container.testMap.onRemove(function(v, k) trace('Map.onRemove', v, 'key', k));

			room.state.container.testArray.onChange(function(v, k) trace('Array.onChange', v, 'key', k));
			room.state.container.testArray.onAdd(function(v, k) trace('Array.onAdd', v, 'key', k));
			room.state.container.testArray.onRemove(function(v, k) trace('Array.onRemove', v, 'key', k));

			this.room = room;
		});

		var tf = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		tf.text = "Hello World !";
	}

	static function main() {
		new Main();
	}

}
