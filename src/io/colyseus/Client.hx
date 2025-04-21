package io.colyseus;

import haxe.Timer;

using io.colyseus.events.EventHandler;
using io.colyseus.error.HttpException;

import tink.Url;

interface RoomAvailable {
    public var roomId: String;
    public var clients: Int;
    public var maxClients: Int;
    public var metadata: Dynamic;
}

class EndpointSettings {
	public var hostname:String;
	public var port:Int;
	public var useSSL:Bool;

    public function new (hostname: String, port: Int, useSSL: Bool) {
        this.hostname = hostname;
        this.port = port;
        this.useSSL = useSSL;
    }
}

@:keep
class Client {
    public var settings: EndpointSettings;
    public var http: HTTP;
    public var auth: Auth;

    public function new (endpointOrHostname: String, ?port: Int, ?useSSL: Bool) {
        if (port == null && useSSL == null) {
            var url: Url = Url.parse(Std.string(endpointOrHostname));
            var useSSL = (url.scheme == "https" || url.scheme == "wss");
            var port = (url.host.port != null)
                ? url.host.port
                : (useSSL)
                    ? 443
                    : 80;

            this.settings = new EndpointSettings(url.host.name, port, useSSL);

        } else {
            this.settings =  new EndpointSettings(endpointOrHostname, port, useSSL);
        }

        this.http = new HTTP(this);
        this.auth = new Auth(this.http);
    }

    @:generic
    public function joinOrCreate<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {
        this.createMatchMakeRequest('joinOrCreate', roomName, options, stateClass, callback);
    }

    @:generic
    public function create<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {
        this.createMatchMakeRequest('create', roomName, options, stateClass, callback);
    }

    @:generic
    public function join<T>(roomName: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {
        this.createMatchMakeRequest('join', roomName, options, stateClass, callback);
    }

    @:generic
    public function joinById<T>(roomId: String, options: Map<String, Dynamic>, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {
        this.createMatchMakeRequest('joinById', roomId, options, stateClass, callback);
    }

    @:generic
    public function reconnect<T>(reconnectionToken: String, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {
        var roomIdAndReconnectionToken = reconnectionToken.split(":");
        this.createMatchMakeRequest('reconnect', roomIdAndReconnectionToken[0], [ "reconnectionToken" => roomIdAndReconnectionToken[1] ], stateClass, callback);
    }

    @:generic
    public function consumeSeatReservation<T>(response: Dynamic, stateClass: Class<T>, callback: (HttpException, Room<T>)->Void) {

        // Prevents crashing upon .room being null. Can be caused if the server itself encounters an error making a room.
        if (response.error != null)
		{
			callback(new HttpException(response.code, response.error), null);
			return;
		}

        var room: Room<T> = new Room<T>(response.room.name, stateClass);

        room.roomId = response.room.roomId;
        room.sessionId = response.sessionId;

        //
        // WORKAROUND: declare onError/onJoin first, so we can use its references to remove the listeners
        // FIXME: EventHandler must implement a .once() method to remove the listener after the first call
        //
        var onError:(Int, String) -> Void = null;
        var onJoin:() -> Void = null;

        onError = function(code: Int, message: String) {
            // TODO: this may not work on native targets + devMode
            room.onError -= onError;
            room.onJoin -= onJoin;
            callback(new HttpException(code, message), null);
        };

        onJoin = function() {
            // TODO: this may not work on native targets + devMode
            room.onError -= onError;
            room.onJoin -= onJoin;
            callback(null, room);
        };

        room.onError += onError;
        room.onJoin += onJoin;

        var options = ["sessionId" => room.sessionId];

        if (response.reconnectionToken != null) {
			options.set("reconnectionToken", response.reconnectionToken);
        }

        function reserveSeat() {
            function devModeCloseCallBack() {
                var retryCount = 0;
                var maxRetryCount = 8;

                function retryConnection () {
                    retryCount++;
                    reserveSeat();

                    room.connection.onError = function(e) {
                        if( retryCount <= maxRetryCount) {
                            trace("[Colyseus devMode]: retrying... (" + retryCount + " out of " + maxRetryCount + ")");
                            Timer.delay(retryConnection, 2000);
                        } else {
                            trace("[Colyseus devMode]: Failed to reconnect. Is your server running? Please check server logs.");
                        }
                    }

                    room.connection.onOpen = function () {
                        trace("[Colyseus devMode]: Successfully re-established connection with room " + room.roomId);
                    }
                }

                Timer.delay(retryConnection, 2000);
            }

            room.connect(this.createConnection(response.room, options), room, response.devMode? devModeCloseCallBack: null);
        }
        reserveSeat();
    }

    @:generic
    private function createMatchMakeRequest<T>(
        method: String,
        roomName: String,
        options: Map<String, Dynamic>,
        stateClass: Class<T>,
        callback: (HttpException, Room<T>)->Void
    ) {
        this.http.post("matchmake/" + method + "/" + roomName, { body: cast options, }, function(err, response) {
            if (err != null) {
                return callback(err, null);

            } else {
                if (method == "reconnect") {
                    response.reconnectionToken = options.get("reconnectionToken");
                }
                this.consumeSeatReservation(response, stateClass, callback);
            }
        });
    }

    private function createConnection(room: Dynamic, options: Map<String, Dynamic>) {
        // build query string
        var params: Array<String> = [];

        if (this.http.authToken != null) {
            options.set("_authToken", this.http.authToken);
        }

        for (name in options.keys()) {
            params.push(name + "=" + options[name]);
        }

        var endpoint = (this.settings.useSSL) ? "wss://" : "ws://";

		if (room.publicAddress != null) {
			endpoint += room.publicAddress;
		} else {
			endpoint += '${this.settings.hostname}${this.http.getEndpointPort()}';
		}

        return new Connection('${endpoint}/${room.processId}/${room.roomId}?${params.join('&')}');
    }

}
