package;

import openfl.Assets;
import openfl.ui.Keyboard;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;

import io.colyseus.Client;
import io.colyseus.Room;
import io.colyseus.serializer.schema.Callbacks;

class Main extends Sprite {
	private var client:Client;
	private var room:Room<MyRoomState>;

	private var cats:Map<String, Sprite> = new Map();

	public function new() {
		super();

		// this.client = new Client("ws://192.168.0.5:2567");
		this.client = new Client("ws://localhost:2567");

        this.joinRoom();
        this.lobbyRoom();
        this.queueRoom();

		stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
		stage.addEventListener(KeyboardEvent.KEY_UP, onKeyUp);

		stage.addEventListener(Event.ENTER_FRAME, onUpdate);
	}

    private function joinRoom():Void {
		this.client.joinOrCreate("my_room", [], MyRoomState, function(err, room) {
            if (err != null) {
                trace("[MyRoom] error: " + err);
                return;
            }

			trace("[MyRoom] roomId: " + room.roomId);

            this.room = room;

            var callbacks = Callbacks.get(this.room);

            callbacks.onAdd("players", (player, key) -> {
                trace("PLAYER ADDED AT: ", key);

                var cat = Assets.getMovieClip("library:NyanCatAnimation");
                this.cats.set(key, cat);
                cat.scaleX = 0.3;
                cat.scaleY = 0.3;
                cat.x = player.x;
                cat.y = player.y;
                addChild(cat);

				callbacks.onChange(player, () -> {
				});

                callbacks.listen(player, "x", (value, previousValue) -> {
                    trace("PLAYER X CHANGED: " + value + " => " + previousValue);
					this.cats.get(key).x = player.x;
                });

                callbacks.listen(player, "y", (value, previousValue) -> {
                    trace("PLAYER Y CHANGED: " + value + " => " + previousValue);
					this.cats.get(key).y = player.y;
                });

                callbacks.listen(player, "disconnected", (value, previousValue) -> {
                    // flag disconnecting players with alpha 0.5
                    this.cats.get(key).alpha = (value) ? 0.5 : 1;
                });

                callbacks.onAdd(player, "items", (item, key) -> {
                    trace("ITEM ADDED AT: " + key + " => " + item);
                });

                callbacks.onRemove(player, "items", (item, key) -> {
                    trace("ITEM REMOVED AT: " + key + " => " + item);
                });
            });

            callbacks.onRemove("players", (player, key) -> {
                trace("PLAYER REMOVED AT: ", key);
                removeChild(this.cats.get(key));
                this.cats.remove(key);
            });

            callbacks.listen("currentTurn", (turn, previousValue) -> {
                trace("CURRENT TURN: " + turn);
            });

            this.room.onStateChange += (state) -> {
            };

            this.room.onMessage("weather", (message) -> {
                trace("[MyRoom] weather => " + message.weather);
            });

            this.room.onError += (code: Int, message: String) -> {
                trace("[MyRoom] error: " + code + " => " + message);
            };

            var pingTimer = new haxe.Timer(2000); // 2 seconds delay
            pingTimer.run = () -> {
                this.room.ping((latency: Float) -> {
                    trace("[MyRoom] ping: " + latency + "ms");
                });
            };

            this.room.onLeave += (code: Int) -> {
                trace("[MyRoom] leave, code: " + code);
                pingTimer.stop();
            };

        });
    }

    private function lobbyRoom():Void {
		this.client.joinOrCreate("lobby", [], function(err, room: Room<Dynamic>) {
            if (err != null) {
                trace("[Lobby] error: " + err);
                return;
            }

			trace("[Lobby] roomId: " + room.roomId);

            room.onMessage("rooms", (rooms: Dynamic) -> {
                trace("[Lobby] rooms: " + rooms);
            });

            room.onMessage("+", (message: Dynamic) -> {
                trace("[Lobby] room added: " + message[0] + " => ");
                trace(message[1]);
            });

            room.onMessage("-", (roomId: String) -> {
                trace("[Lobby] room removed: " + roomId);
            });

            room.onLeave += (code: Int) -> {
                trace("[Lobby] leave, code: " + code);
            };

        });
    }

    private function queueRoom():Void {
		this.client.joinOrCreate("queue", [], function(err, room: Room<Dynamic>) {
            if (err != null) {
                trace("[Queue] error: " + err);
                return;
            }

			trace("[Queue] roomId: " + room.roomId);

            room.onMessage("clients", (clients: Int) -> {
                trace("[Queue] clients: " + clients);
            });

            room.onMessage("seat", (seat: Dynamic) -> {
                trace("[Queue] seat: " + seat);

                // confirm the seat consumption, so the server can close the queue room
                room.send("confirm");

                this.client.consumeSeatReservation(seat, MyRoomState, function(err, newRoom: Room<MyRoomState>) {
                    if (err != null) {
                        trace("[Queue consumeSeatReservation] error: " + err);
                        return;
                    }

                    trace("[Queue consumeSeatReservation] seat consumed: " + room.roomId);

                    newRoom.onLeave += (code: Int) -> {
                        trace("[Queue consumeSeatReservation] newRoom leave, code: " + code);
                    };

                    // for demonstration, we .leave() here, but in a real application you would use the newRoom for the next steps
                    newRoom.leave();
                });

            });

            room.onLeave += (code: Int) -> {
                trace("[Queue] leave, code: " + code);
            };

        });
    }

	private function onUpdate(e:Event):Void {
		// Your update function...
	}

	private function onKeyDown(evt:KeyboardEvent):Void {
        if (this.room == null) return;

        var move = {
			x: this.cats.get(this.room.sessionId).x,
			y: this.cats.get(this.room.sessionId).y,
        };

		if (evt.keyCode == Keyboard.UP) {
			move.y -= 5;

		} else if (evt.keyCode == Keyboard.DOWN) {
			move.y += 5;

		} else if (evt.keyCode == Keyboard.LEFT) {
			move.x -= 5;

		} else if (evt.keyCode == Keyboard.RIGHT) {
			move.x += 5;
		}

		this.room.send("move", move);
	}

	private function onKeyUp(evt:KeyboardEvent):Void {}
}
