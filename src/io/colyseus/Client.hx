package io.colyseus;

import haxe.Constraints.Function;

using io.colyseus.events.EventHandler;
using io.colyseus.error.MatchMakeError;

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
    public function joinOrCreate<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        this.createMatchMakeRequest('joinOrCreate', roomName, options, stateClass, callback);
    }

    @:generic
    public function create<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        this.createMatchMakeRequest('create', roomName, options, stateClass, callback);
    }

    @:generic
    public function join<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        this.createMatchMakeRequest('join', roomName, options, stateClass, callback);
    }

    @:generic
    public function joinById<T>(roomId: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        this.createMatchMakeRequest('joinById', roomId, options, stateClass, callback);
    }

    @:generic
    public function reconnect<T>(roomId: String, sessionId: String, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        this.createMatchMakeRequest('joinById', roomId, [ "sessionId" => sessionId ], stateClass, callback);
    }

    public function getAvailableRooms(roomName: String, callback: (MatchMakeError, Array<RoomAvailable>)->Void) {
        this.request("GET", "/matchmake/" + roomName, null, callback);
    }

    @:generic
    public function consumeSeatReservation<T>(response: Dynamic, stateClass: Class<T>, callback: (MatchMakeError, Room<T>)->Void) {
        var room: Room<T> = new Room<T>(response.room.name, stateClass);

        room.id = response.room.roomId;
        room.sessionId = response.sessionId;

        var onError = function(code: Int, message: String) {
            callback(new MatchMakeError(code, message), null);
        };
        var onJoin = function() {
            room.onError -= onError;
            callback(null, room);
        };

        room.onError += onError;
        room.onJoin += onJoin;

        room.connect(this.createConnection(response.room.processId + "/" + room.id, ["sessionId" => room.sessionId]));
    }

    @:generic
    private function createMatchMakeRequest<T>(
        method: String,
        roomName: String,
        options: Map<String, Dynamic>,
        stateClass: Class<T>,
        callback: (MatchMakeError, Room<T>)->Void
    ) {
        if (this.auth.hasToken()) {
            options.set("token", this.auth.token);
        }

        this.request("POST", "/matchmake/" + method + "/" + roomName, haxe.Json.stringify(options), function(err, response) {
            if (err != null) {
                return callback(err, null);

            } else {
                this.consumeSeatReservation(response, stateClass, callback);
            }
        });
    }

    private function createConnection(path: String = '', options: Map<String, Dynamic>) {
        // append colyseusid to connection string.
        var params: Array<String> = [];

        for (name in options.keys()) {
            params.push(name + "=" + options[name]);
        }

        return new Connection(this.endpoint + "/" + path + "?" + params.join('&'));
    }

    private function request(method: String, segments: String, body: String, callback: (MatchMakeError,Dynamic)->Void) {
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
                var code = cast response.code;
                var message = cast response.error;
                callback(new MatchMakeError(code, message), null);

            } else {
                callback(null, response);
            }
        };

        req.onError = function(err) {
            callback(new MatchMakeError(0, err), null);
        };

        req.request(method == "POST");
    }

}
