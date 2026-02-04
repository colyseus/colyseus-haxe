package io.colyseus;

import haxe.Timer;
import haxe.io.Bytes;
import haxe.io.BytesOutput;

using io.colyseus.events.EventHandler;
using io.colyseus.error.HttpException;

import tink.Url;

interface RoomAvailable {
    public var roomId: String;
    public var clients: Int;
    public var maxClients: Int;
    public var metadata: Dynamic;
}

typedef LatencyOptions = {
    /** "ws" for WebSocket (default: "ws") */
    ?protocol: String,
    /** Number of pings to send (default: 1). Returns the average latency when > 1. */
    ?pingCount: Int
}

class EndpointSettings {
	public var hostname:String;
	public var port:Int;
	public var useSSL:Bool;
    public var pathname:String;

    public function new (hostname: String, port: Int, useSSL: Bool, ?pathname: String) {
        this.hostname = hostname;
        this.port = port;
        this.useSSL = useSSL;
        this.pathname = pathname != null ? pathname : "";
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
            var pathname = url.path != null ? url.path : "";

            this.settings = new EndpointSettings(url.host.name, port, useSSL, pathname);

        } else {
            this.settings = new EndpointSettings(endpointOrHostname, port, useSSL);
        }

        this.http = new HTTP(this);
        this.auth = new Auth(this.http);
    }

    @:generic
    public function joinOrCreate<T:Dynamic>(
        roomName:String,
        options:Map<String, Dynamic>,
        stateClass:Class<T> = null,
        callback:(HttpException, Room<T>) -> Void
    ) {
        this.createMatchMakeRequest('joinOrCreate', roomName, options, stateClass, callback);
    }

    @:generic
    public function create<T>(
        roomName:String,
        options:Map<String, Dynamic>,
        stateClass:Class<T>,
        callback:(HttpException, Room<T>) -> Void
    ) {
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
    public function consumeSeatReservation<T:Dynamic>(
        response:Dynamic,
        stateClass:Class<T> = null,
        callback:(HttpException, Room<T>) -> Void
    ) {

        // Prevents crashing upon .room being null. Can be caused if the server itself encounters an error making a room.
        if (response.error != null)
		{
			callback(new HttpException(response.code, response.error), null);
			return;
		}

        var room: Room<T> = new Room<T>(response.name, stateClass);

        room.roomId = response.roomId;
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

        room.connect(this.createConnection(response, options));
    }

    @:generic
    private function createMatchMakeRequest<T:Dynamic>(
        method: String,
        roomName: String,
        options: Map<String, Dynamic>,
        stateClass: Class<T> = null,
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

    /**
     * Select the endpoint with the lowest latency.
     * @param endpoints Array of endpoints to select from.
     * @param latencyOptions Latency measurement options (protocol, pingCount).
     * @param callback Callback with the client with the lowest latency.
     */
    public static function selectByLatency(
        endpoints: Array<String>,
        ?latencyOptions: LatencyOptions,
        callback: (HttpException, Client) -> Void
    ) {
        var clients = endpoints.map(function(endpoint) return new Client(endpoint));
        var latencies: Array<{index: Int, latency: Float}> = [];
        var errors: Array<HttpException> = [];
        var completed = 0;
        var total = clients.length;

        for (i in 0...clients.length) {
            var index = i;
            clients[index].getLatency(latencyOptions, function(err, latency) {
                completed++;

                if (err != null) {
                    errors.push(err);
                } else {
                    var settings = clients[index].settings;
                    trace('Endpoint Latency: ${latency}ms - ${settings.hostname}:${settings.port}${settings.pathname}');
                    latencies.push({index: index, latency: latency});
                }

                // All requests completed
                if (completed >= total) {
                    if (latencies.length == 0) {
                        callback(new HttpException(0, "All endpoints failed to respond"), null);
                    } else {
                        // Sort by latency and return the client with lowest latency
                        latencies.sort(function(a, b) return Std.int(a.latency - b.latency));
                        callback(null, clients[latencies[0].index]);
                    }
                }
            });
        }
    }

    /**
     * Create a new connection with the server, and measure the latency.
     * @param options Latency measurement options (protocol, pingCount).
     * @param callback Callback with the measured latency in milliseconds.
     */
    public function getLatency(?options: LatencyOptions, callback: (HttpException, Float) -> Void) {
        var protocol = options != null && options.protocol != null ? options.protocol : "ws";
        var pingCount = options != null && options.pingCount != null ? options.pingCount : 1;

        var latencies: Array<Float> = [];
        var pingStart: Float = 0;

        var wsEndpoint = this.http.buildHttpEndpoint("", "ws");
        var conn = new Connection(wsEndpoint);

        conn.onOpen = function() {
            pingStart = Timer.stamp() * 1000; // Convert to milliseconds
            var bytes = new BytesOutput();
            bytes.writeByte(Protocol.PING);
            conn.send(bytes.getBytes());
        };

        conn.onMessage = function(_: Bytes) {
            latencies.push(Timer.stamp() * 1000 - pingStart);

            if (latencies.length < pingCount) {
                // Send another ping
                pingStart = Timer.stamp() * 1000;

                var bytes = new BytesOutput();
                bytes.writeByte(Protocol.PING);
                conn.send(bytes.getBytes());
            } else {
                // Done, calculate average and close
                conn.close();
                var sum: Float = 0;
                for (l in latencies) {
                    sum += l;
                }
                var average = sum / latencies.length;
                callback(null, average);
            }
        };

        conn.onError = function(message: String) {
            callback(new HttpException(1006, 'Failed to get latency: ${message}'), 0);
        };
    }

}
