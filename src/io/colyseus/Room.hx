package io.colyseus;

import io.colyseus.serializer.Serializer;
import io.colyseus.serializer.FossilDeltaSerializer;
import io.colyseus.serializer.SchemaSerializer;

import haxe.io.Bytes;

import org.msgpack.MsgPack;

/**
 * TODO: import typedef's from `io.colyseus.serializer`?
 */
#if haxe4
typedef Listener = {
    callback: DataChange->Void,
    rules: Array<Null<EReg>>,
    rawRules: Array<String>
}
typedef DataChange = { path: Dynamic, operation: String, value: Dynamic, ?rawPath: Array<String> }
#else
typedef DataChange = { path: Dynamic, operation: String, value: Dynamic, ?rawPath: Array<String> }
typedef Listener = { callback: DataChange->Void, rules: List<EReg>, rawRules: Array<String> }
#end

interface IRoom {
    public var id: String;
    public var options: Dynamic;

    public dynamic function onJoin(): Void;
    public dynamic function onStateChange(newState: Dynamic): Void;
    public dynamic function onMessage(data: Dynamic): Void;
    public dynamic function onError(message: String): Void;
    public dynamic function onLeave(): Void;

    public function connect(connection: Connection): Void;
}

class Room<T> implements IRoom {
    public var id: String;
    public var sessionId: String;

    public var name: String;
    public var options: Dynamic;

    // callbacks
    public dynamic function onJoin(): Void {}
    public dynamic function onStateChange(newState: Dynamic): Void {}
    public dynamic function onMessage(data: Dynamic): Void {}
    public dynamic function onError(message: String): Void {}
    public dynamic function onLeave(): Void {}

    public var connection: Connection;

    public var serializerId: String = null;
    private var serializer: Serializer;

    private var previousCode: Int = 0;
    private var tmpStateClass: Class<T>;

    public function new (name: String, options: Dynamic = null, ?cls: Class<T>) {
        this.id = null;
        this.name = name;
        this.options = options;
        this.tmpStateClass = cls;
    }

    public function connect(connection: Connection) {
        this.connection = connection;
        this.connection.reconnectionEnabled = false;

        this.connection.onMessage = function (bytes) {
            this.onMessageCallback(bytes);
        }

        this.connection.onClose = function () {
            this.teardown();
            this.onLeave();
        }

        this.connection.onError = function (e) {
            trace("Possible causes: room's onAuth() failed or maxClients has been reached.");
            this.onError(e);
        };
    }

    public function leave(consented: Bool = true) {
        this.teardown();

        if (this.connection != null) {
            if (consented) {
                this.connection.send([ Protocol.LEAVE_ROOM ]);

            } else {
                this.connection.close();
            }

        } else {
            this.onLeave();
        }
    }

    public function send(data: Dynamic) {
        if (this.connection != null) {
            this.connection.send([ Protocol.ROOM_DATA, this.id, data ]);
        }
    }

    public var state (get, null): T;
    function get_state () {
        return this.serializer.getState();
    }

    public function teardown() {
        this.serializer.teardown();
        // this.onJoin.removeAll();
        // this.onStateChange.removeAll();
        // this.onMessage.removeAll();
        // this.onError.removeAll();
        // this.onLeave.removeAll();
    }

    private function onMessageCallback(data: Bytes) {
        if (this.previousCode == 0) {
            var code = data.get(0);

            if (code == Protocol.JOIN_ROOM) {
                var offset: Int = 1;

                this.sessionId = data.getString(offset + 1, data.get(offset));
                offset += this.sessionId.length + 1;

                this.serializerId = data.getString(offset + 1, data.get(offset));
                offset += this.serializerId.length + 1;

                if (this.serializerId == "schema") {
                    this.serializer = new SchemaSerializer<T>(tmpStateClass);
                } else {
                    throw "use joinFossilDelta() if you're using Fossil Delta serializer.";
                }

                if (data.length > offset) {
                    this.serializer.handshake(data, offset);
                }

                this.onJoin();

            } else if (code == Protocol.JOIN_ERROR) {
                var err = data.getString(2, data.get(1));
                trace("Error: " + err);
                this.onError(err);

            } else if (code == Protocol.LEAVE_ROOM) {
                this.leave();

            } else {
                this.previousCode = code;
            }

        } else {
            if (this.previousCode == Protocol.ROOM_STATE) {
                this.setState(data);

            } else if (this.previousCode == Protocol.ROOM_STATE_PATCH) {
                this.patch(data);

            } else if (this.previousCode == Protocol.ROOM_DATA) {
                this.onMessage(MsgPack.decode(data));
            }

            this.previousCode = 0;
        }
    }

    public function setState(encodedState: Bytes) {
        this.serializer.setState(encodedState);
        this.onStateChange(this.serializer.getState());
    }

    private function patch(binaryPatch: Bytes) {
        this.serializer.patch(binaryPatch);
        this.onStateChange(this.serializer.getState());
    }
}

/** TODO: remove me on 1.0.0 **/
class RoomFossilDelta implements IRoom {
    public var id: String;
    public var sessionId: String;

    public var name: String;
    public var options: Dynamic;

    // callbacks
    public dynamic function onJoin(): Void {}
    public dynamic function onStateChange(newState: Dynamic): Void {}
    public dynamic function onMessage(data: Dynamic): Void {}
    public dynamic function onError(message: String): Void {}
    public dynamic function onLeave(): Void {}

    public var connection: Connection;

    public var serializerId: String = null;
    private var serializer: FossilDeltaSerializer;

    private var previousCode: Int = 0;

    public function new (name: String, options: Dynamic = null) {
        this.id = null;
        this.name = name;
        this.options = options;

        // TODO: remove default serializer. it should arrive only after JOIN_ROOM.
        this.serializer = new FossilDeltaSerializer();
    }

    public function connect(connection: Connection) {
        this.connection = connection;
        this.connection.reconnectionEnabled = false;

        this.connection.onMessage = function (bytes) {
            this.onMessageCallback(bytes);
        }

        this.connection.onClose = function () {
            this.teardown();
            this.onLeave();
        }

        this.connection.onError = function (e) {
            trace("Possible causes: room's onAuth() failed or maxClients has been reached.");
            this.onError(e);
        };
    }

    public function leave(consented: Bool = true) {
        this.teardown();

        if (this.connection != null) {
            if (consented) {
                this.connection.send([ Protocol.LEAVE_ROOM ]);

            } else {
                this.connection.close();
            }

        } else {
            this.onLeave();
        }
    }

    public function send(data: Dynamic) {
        if (this.connection != null) {
            this.connection.send([ Protocol.ROOM_DATA, this.id, data ]);
        }
    }

    public var state (get, null): Dynamic;
    function get_state () {
        return this.serializer.getState();
    }

    public function teardown() {
        this.serializer.teardown();
        // this.onJoin.removeAll();
        // this.onStateChange.removeAll();
        // this.onMessage.removeAll();
        // this.onError.removeAll();
        // this.onLeave.removeAll();
    }

    // fossil-delta serializer
    public function listen (segments: Dynamic, ?callback: DataChange->Void, ?immediate: Bool): Listener {
        if (this.serializerId == "schema") {
            trace("'" + this.serializerId + "' serializer doesn't support .listen() method.");
            return null;
        }

        if (this.serializerId == null) {
            trace("DEPRECATION WARNING: room.Listen() should be called after room.OnJoin has been called");
        }

        return cast(this.serializer, FossilDeltaSerializer).state.listen(segments, callback, immediate);
    }
    public function removeListener (listener: Listener) {
        return cast(this.serializer, FossilDeltaSerializer).state.removeListener(listener);
    }

    private function onMessageCallback(data: Bytes) {
        if (this.previousCode == 0) {
            var code = data.get(0);

            if (code == Protocol.JOIN_ROOM) {
                var offset: Int = 1;

                this.sessionId = data.getString(offset + 1, data.get(offset));
                offset += this.sessionId.length + 1;

                this.serializerId = data.getString(2, data.get(1));
                offset += this.serializerId.length + 1;

                // if (this.serializerId == "schema") {
                //     this.serializer = new SchemaSerializer<T>();
                // }

                if (data.length > offset) {
                    this.serializer.handshake(data, offset);
                }

                this.onJoin();

            } else if (code == Protocol.JOIN_ERROR) {
                var err = data.getString(2, data.get(1));
                trace("Error: " + err);
                this.onError(err);

            } else if (code == Protocol.LEAVE_ROOM) {
                this.leave();

            } else {
                this.previousCode = code;
            }

        } else {
            if (this.previousCode == Protocol.ROOM_STATE) {
                this.setState(data);

            } else if (this.previousCode == Protocol.ROOM_STATE_PATCH) {
                this.patch(data);

            } else if (this.previousCode == Protocol.ROOM_DATA) {
                this.onMessage(MsgPack.decode(data));
            }

            this.previousCode = 0;
        }
    }

    public function setState(encodedState: Bytes) {
        this.serializer.setState(encodedState);
        this.onStateChange(this.serializer.getState());
    }

    private function patch(binaryPatch: Bytes) {
        this.serializer.patch(binaryPatch);
        this.onStateChange(this.serializer.getState());
    }
}