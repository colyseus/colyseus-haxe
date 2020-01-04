package io.colyseus;

import io.colyseus.serializer.Serializer;
import io.colyseus.serializer.SchemaSerializer;

using io.colyseus.events.EventHandler;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

class Room<T> {
    public var id: String;
    public var sessionId: String;

    public var name: String;

    // callbacks
    public var onJoin = new EventHandler<Void->Void>();
    public var onStateChange = new EventHandler<Dynamic->Void>();
    public var onMessage = new EventHandler<Dynamic->Void>();
    public var onError = new EventHandler<String->Void>();
    public var onLeave = new EventHandler<Void->Void>();

    public var connection: Connection;

    public var serializerId: String = null;
    private var serializer: Serializer;

    private var tmpStateClass: Class<T>;

    public function new (name: String, ?cls: Class<T>) {
        this.id = null;
        this.name = name;
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
            this.onLeave.dispatch();
        }

        this.connection.onError = function (e) {
            this.onError.dispatch(e);
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
            this.onLeave.dispatch();
        }
    }

    public function send(data: Dynamic) {
        if (this.connection != null) {
            this.connection.send([ Protocol.ROOM_DATA, data ]);
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
        var code = data.get(0);

        if (code == Protocol.JOIN_ROOM) {
            var offset: Int = 1;

            this.serializerId = data.getString(offset + 1, data.get(offset));
            offset += this.serializerId.length + 1;

            if (this.serializerId == "schema") {
                this.serializer = new SchemaSerializer<T>(tmpStateClass);
            } else {
                throw "FossilDelta serializer has been deprecated! Use SchemaSerializer instead.";
            }

            if (data.length > offset) {
                this.serializer.handshake(data, offset);
            }

            this.onJoin.dispatch();

            // acknowledge JOIN_ROOM
            this.connection.send([ Protocol.JOIN_ROOM ]);

        } else if (code == Protocol.JOIN_ERROR) {
            var err = data.getString(2, data.get(1));
            trace("Error: " + err);
            this.onError.dispatch(err);

        } else if (code == Protocol.LEAVE_ROOM) {
            this.leave();

        } else if (code == Protocol.ROOM_STATE) {
			this.setState(data.sub(1, data.length - 1));

        } else if (code == Protocol.ROOM_STATE_PATCH) {
            this.patch(data.sub(1, data.length - 1));

        } else if (code == Protocol.ROOM_DATA) {
            this.onMessage.dispatch(MsgPack.decode(data.sub(1, data.length - 1)));
        }
    }

    public function setState(encodedState: Bytes) {
        this.serializer.setState(encodedState);
        this.onStateChange.dispatch(this.serializer.getState());
    }

    private function patch(binaryPatch: Bytes) {
        this.serializer.patch(binaryPatch);
        this.onStateChange.dispatch(this.serializer.getState());
    }
}
