package io.colyseus;

import haxe.Constraints.Function;

using io.colyseus.events.EventHandler;

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
    public var endpoint: String;

    /**
     * @colyseus/social is not fully implemented in the Haxe client
     */
    private var auth: Auth;

    public function new (endpoint: String) {
        this.endpoint = endpoint;
        this.auth = new Auth(this.endpoint);
    }

    @:generic
    public function joinOrCreate<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (String, Room<T>)->Void) {
        this.createMatchMakeRequest('joinOrCreate', roomName, options, stateClass, callback);
    }

    @:generic
    public function create<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (String, Room<T>)->Void) {
        this.createMatchMakeRequest('create', roomName, options, stateClass, callback);
    }

    @:generic
    public function join<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (String, Room<T>)->Void) {
        this.createMatchMakeRequest('join', roomName, options, stateClass, callback);
    }

    @:generic
    public function joinById<T>(roomId: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (String, Room<T>)->Void) {
        this.createMatchMakeRequest('joinById', roomId, options, stateClass, callback);
    }

    @:generic
    public function reconnect<T>(roomId: String, sessionId: String, stateClass: Class<T>, callback: (String, Room<T>)->Void) {
        this.createMatchMakeRequest('joinById', roomId, [ "sessionId" => sessionId ], stateClass, callback);
    }

    public function getAvailableRooms(roomName: String, callback: (String, Array<RoomAvailable>)->Void) {
        this.request("GET", "/matchmake/" + roomName, null, callback);
    }

    @:generic
    private function createMatchMakeRequest<T>(
        method: String,
        roomName: String,
        options: Map<String, Dynamic>,
        stateClass: Class<T>,
        callback: (String, Room<T>)->Void
    ) {
        this.request("POST", "/matchmake/" + method + "/" + roomName, haxe.Json.stringify(options), function(err, response) {
            if (err != null) { return callback(err, null); }

            var room: Room<T> = new Room<T>(roomName, stateClass);
            room.id = response.room.roomId;
            room.sessionId = response.sessionId;

            var onError = function(message) {
                callback(message, null);
            };
            var onJoin = function() {
                room.onError -= onError;
                callback(null, room);
            };

            room.onError += onError;
            room.onJoin += onJoin;

            room.connect(this.createConnection(response.room.processId + "/" + room.id, ["sessionId" => room.sessionId]));
        });
    }

    private function createConnection(path: String = '', options: Map<String, Dynamic>) {
        // append colyseusid to connection string.
        var params: Array<String> = [];

        if (this.auth.hasToken()) {
            params.push("token=" + this.auth.token);
        }

        for (name in options.keys()) {
            params.push(name + "=" + options[name]);
        }

        return new Connection(this.endpoint + "/" + path + "?" + params.join('&'));
    }

    private function request(method: String, segments: String, body: String, callback: (String,Dynamic)->Void) {
        var req = new haxe.Http("http" + this.endpoint.substring(2) + segments);

        if (body != null) {
            req.setPostData(body);
            req.setHeader("Content-Type", "application/json");
        }

        req.setHeader("Accept", "application/json");

        var responseStatus: Int;
        req.onStatus = function(status) {
            responseStatus = status;
        };

        req.onData = function(json) {
            var response = haxe.Json.parse(json);

            if (response.error) {
                callback(cast response.error, null);

            } else {
                callback(null, response);
            }
        };

        req.onError = function(err) {
            callback(err, null);
        };

        req.request(method == "POST");
    }

}
