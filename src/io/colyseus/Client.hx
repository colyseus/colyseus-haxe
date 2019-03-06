package io.colyseus;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

interface RoomAvailable {
    public var roomId: String;
    public var clients: Int;
    public var maxClients: Int;
    public var metadata: Dynamic;
}

@:keep
class Client {
    public var id: String = "";
    public var endpoint: String;

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onClose():Void {}
    public dynamic function onError(e: String):Void {}

    private var connection: Connection;

    private var rooms: Map<String, Room> = new Map();
    private var connectingRooms: Map<Int, Room> = new Map();
    private var requestId = 0;
    private var previousCode: Int = 0;

    private var roomsAvailableRequests: Map<Int, Array<RoomAvailable> -> Void> = new Map();

    public function new (url: String) {
        this.endpoint = url;
        trace("ENDPOINT => " + url);

        // getItem('colyseusid', (colyseusid) => this.connect(colyseusid));
        this.connect(this.id);
    }

    public function join(roomName: String, ?options: Map<String, Dynamic>): Room {
        if (options == null) {
            options = new Map();
        }

        options.set("requestId", ++this.requestId);

        var room = new Room(roomName, options);

        // remove references on leaving
        room.onLeave = function () {
            this.rooms.remove(room.id);
            this.connectingRooms.remove(options.get("requestId"));
        };

        this.connectingRooms.set(options.get("requestId"), room);

        this.connection.send([Protocol.JOIN_REQUEST, roomName, options]);

        return room;
    }

    public function rejoin(roomName: String, sessionId: String) {
        return this.join(roomName, [ "sessionId" => sessionId ]);
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
            trace("Connection onMessage!");
            this.onMessageCallback(data);
        }

        this.connection.onClose = function () {
            trace("Connection close!");
            this.onClose();
        };

        this.connection.onError = function (e) {
            trace("Connection error! " + e);
            this.onError(e);
        };

        // check for id on cookie
        this.connection.onOpen = function () {
            trace("Connection open!");
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
            trace("CODE => " + code);

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

                room.connect(this.createConnection(room.id, room.options));
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
