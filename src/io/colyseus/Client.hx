package io.colyseus;

import io.colyseus.Room.IRoom;
import io.colyseus.Room.RoomFossilDelta;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

interface RoomAvailable {
    public var roomId: String;
    public var clients: Int;
    public var maxClients: Int;
    public var metadata: Dynamic;
}

class DummyState {}

@:keep
class Client {
    public var id: String = "";
    public var endpoint: String;

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onClose():Void {}
    public dynamic function onError(e: String):Void {}

    private var connection: Connection;

    private var rooms: Map<String, IRoom> = new Map();
    private var connectingRooms: Map<Int, IRoom> = new Map();
    private var requestId: UInt = 0;
    private var previousCode: Int = 0;

    private var roomsAvailableRequests: Map<Int, Array<RoomAvailable> -> Void> = new Map();

    public function new (url: String) {
        this.endpoint = url;

        // getItem('colyseusid', (colyseusid) => this.connect(colyseusid));
        this.connect(this.id);
    }

    @:generic
    public function join<T>(roomName: String, ?options: Map<String, Dynamic>, ?cls: Class<T>): Room<T> {
        if (options == null) {
            options = new Map<String, Dynamic>();
        }

        options.set("requestId", ++this.requestId);

        var room: Room<T> = new Room<T>(roomName, options, cls);

        // remove references on leaving
        room.onLeave.nextTime().handle(function () {
			room.dispose();
            this.rooms.remove(room.id);
            this.connectingRooms.remove(options.get("requestId"));
        });

        this.connectingRooms.set(options.get("requestId"), room);

        this.connection.send([Protocol.JOIN_REQUEST, roomName, options]);

        return room;
    }

    @:generic
    public function rejoin<T>(roomName: String, sessionId: String, cls: Class<T>): Room<T> {
        return this.join(roomName, [ "sessionId" => sessionId ], cls);
    }

    /* TODO: remove this on 1.0.0 */
    public function joinFossilDelta(roomName: String, ?options: Map<String, Dynamic>) {
        if (options == null) {
            options = new Map();
        }
        options.set("requestId", ++this.requestId);

        var room = new RoomFossilDelta(roomName, options);

        // remove references on leaving
        room.onLeave.nextTime().handle(function () {
			room.dispose();
            this.rooms.remove(room.id);
            this.connectingRooms.remove(options.get("requestId"));
        });

        this.connectingRooms.set(options.get("requestId"), room);
        this.connection.send([Protocol.JOIN_REQUEST, roomName, options]);

        return room;
    }

    /* TODO: remove this on 1.0.0 */
    public function rejoinFossilDelta(roomName: String, sessionId: String) {
        return this.joinFossilDelta(roomName, [ "sessionId" => sessionId ]);
    }

    public function getAvailableRooms(roomName: String, callback: Array<RoomAvailable>->?String -> Void) {
        // reject this promise after 10 seconds.
        var requestId = ++this.requestId;

        function removeRequest() {
            return this.roomsAvailableRequests.remove(requestId);
        };

        var rejectionTimeout = haxe.Timer.delay(function() {
            removeRequest();
            callback([], 'timeout');
        }, 10000);

        // send the request to the server.
        this.connection.send([Protocol.ROOM_LIST, requestId, roomName]);

        this.roomsAvailableRequests.set(requestId, function(roomsAvailable) {
            removeRequest();
            rejectionTimeout.stop();
            callback(roomsAvailable);
        });
    }

    public function close() {
        this.connection.close();
    }

    private function connect(colyseusid: String) {
        this.id = colyseusid;

        this.connection = this.createConnection();

        this.connection.onMessage = function (data) {
            this.onMessageCallback(data);
        }

        this.connection.onClose = function () {
            this.onClose();
        };

        this.connection.onError = function (e) {
            this.onError(e);
        };

        // check for id on cookie
        this.connection.onOpen = function () {
            if (this.id != "") {
                this.onOpen();
            }
        };
    }

    private function createConnection(path: String = '', ?options: Map<String, Dynamic>) {
        if (options == null) {
            options = new Map();
        }
        // append colyseusid to connection string.
        var params: Array<String> = ["colyseusid=" + this.id];

        for (name in options.keys()) {
            params.push(name + "=" + options[name]);
        }

        return new Connection(this.endpoint + "/" + path + "?" + params.join('&'));
    }

    /**
     * @override
     */
    private function onMessageCallback(data: Bytes) {
        if (this.previousCode == 0) {
            var code: Int = data.get(0);

            if (code == Protocol.USER_ID) {
                this.id = data.getString(2, data.get(1));

                this.onOpen();

            } else if (code == Protocol.JOIN_REQUEST) {
                var requestId: Int = data.get(1);
                var room = this.connectingRooms.get(requestId);

                if (room == null) {
                    trace('colyseus.js: client left room before receiving session id.');
                    return;
                }

                room.id = data.getString(3, data.get(2));
                this.rooms.set(room.id, room);

                var processPath = "";
                var nextIndex = 3 + room.id.length;
                if (data.length > nextIndex) {
                    processPath = data.getString(nextIndex + 1, data.get(nextIndex)) + "/";
                }

                room.connect(this.createConnection(processPath + room.id, room.options));
                this.connectingRooms.remove(requestId);

            } else if (code == Protocol.JOIN_ERROR) {
                var err = data.getString(2, data.get(1));
                trace('colyseus.js: server error:' + err);

                // general error
                this.onError(err);

            } else if (code == Protocol.ROOM_LIST) {
                this.previousCode = code;
            }

        } else {
            if (this.previousCode == Protocol.ROOM_LIST) {
                var message: Dynamic = MsgPack.decode(data);
                var requestId: Int = message[0];

                if (this.roomsAvailableRequests.exists(requestId)) {
                    var callback = this.roomsAvailableRequests.get(requestId);
                    callback(cast message[1]);

                } else {
                    trace('receiving ROOM_LIST after timeout:' + message[2]);
                }

            }
            this.previousCode = 0;
        }

    }

}
