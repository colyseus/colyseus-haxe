import io.colyseus.Client;
import io.colyseus.Room;

class Main extends hxd.App {
  private var client = new Client("ws://localhost:2567");
  private var room: Room<State>;

	override function init() {
    this.client.joinOrCreate("test", [], State, function(err, room) {
      if (err != null) {
        trace(err);
        return;
      }

			// this triggers only when map or array are created with `new`
			// when new value appended it is also triggered but traces just empty array
			room.state.onChange = function(v) trace('Root.onChange', v);

			// following callbacks are never triggered
			room.state.testMap.onChange = function(v, k) trace('Map.onChange', v, 'key', k);
			room.state.testMap.onAdd = function(v, k) trace('Map.onAdd', v, 'key', k);
      room.state.testMap.onRemove = function(v, k) trace('Map.onRemove', v, 'key', k);

			room.state.testArray.onChange = function(v, k) trace('Array.onChange', v, 'key', k);
			room.state.testArray.onAdd = function(v, k) trace('Array.onAdd', v, 'key', k);
			room.state.testArray.onRemove = function(v, k) trace('Array.onRemove', v, 'key', k);

      this.room = room;
    });

    var tf = new h2d.Text(hxd.res.DefaultFont.get(), s2d);
		tf.text = "Hello World !";
	}

	static function main() {
		new Main();
	}

}
