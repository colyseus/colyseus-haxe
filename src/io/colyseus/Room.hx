package io.colyseus;

import haxe.net.WebSocket.ReadyState;
import haxe.io.BytesOutput;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.Serializer;
import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.NoneSerializer;
import io.colyseus.serializer.FossilDeltaSerializer;

import io.colyseus.serializer.schema.Schema.It;
import io.colyseus.serializer.schema.Schema.SPEC;

using io.colyseus.events.EventHandler;

import haxe.io.Bytes;
import haxe.ds.Map;
import org.msgpack.MsgPack;

class Room<T> {
    public var roomId: String;
    public var sessionId: String;
    public var reconnectionToken: String;

    public var name: String;

    // callbacks
    public var onJoin = new EventHandler<Void->Void>();
    public var onStateChange = new EventHandler<Dynamic->Void>();
    public var onError = new EventHandler<Int->String->Void>();
    public var onLeave = new EventHandler<Void->Void>();
    private var onMessageHandlers = new Map<String, Dynamic->Void>();

    public var connection: Connection;

    public var serializerId: String = null;
    private var serializer: Serializer = null;

    private var tmpStateClass: Class<T>;

    public function new (name: String, ?cls: Class<T>) {
        this.roomId = null;
        this.name = name;
        this.tmpStateClass = cls;
    }

    public function connect(connection: Connection, room: Room<T>, ?devModeCloseCallback) {
        if (room == null) {
            room = this;
        }
        room.connection = connection;
        room.connection.reconnectionEnabled = false;

        room.connection.onMessage = function (bytes) {
            room.onMessageCallback(bytes);
        }

        room.connection.onClose = function () {
            if (devModeCloseCallback == null) {
                room.teardown();
                room.onLeave.dispatch();
            } else {
                devModeCloseCallback();
            }
        }

        room.connection.onError = function (e) {
            room.onError.dispatch(0, e);
            return false;
        };

        return room.connection.state() == ReadyState.Open;
    }

    public function leave(consented: Bool = true) {
        if (this.connection != null) {
            if (consented) {
				var bytes = new BytesOutput();
				bytes.writeByte(Protocol.LEAVE_ROOM);
                this.connection.send(bytes.getBytes());

            } else {
                this.connection.close();
            }

        } else {
            this.onLeave.dispatch();
        }
    }

    public function send(type: Dynamic, ?message: Dynamic) {
        var bytesToSend = new BytesOutput();
        bytesToSend.writeByte(Protocol.ROOM_DATA);

        if (Std.isOfType(type, String)) {
            var encodedType = Bytes.ofString(type);
            bytesToSend.writeByte(encodedType.length | 0xa0);
            bytesToSend.writeBytes(encodedType, 0, encodedType.length);

        } else {
            bytesToSend.writeByte(type);
        }

        if (message != null) {
            var encodedMessage = MsgPack.encode(message);
            bytesToSend.writeBytes(encodedMessage, 0, encodedMessage.length);
        }

        this.connection.send(bytesToSend.getBytes());
    }

    public function sendBytes(type: Dynamic, ?bytes: Dynamic) {
        var bytesToSend = new BytesOutput();
        bytesToSend.writeByte(Protocol.ROOM_DATA_BYTES);

        if (Std.isOfType(type, String)) {
            var encodedType = Bytes.ofString(type);
            bytesToSend.writeByte(encodedType.length | 0xa0);
            bytesToSend.writeBytes(encodedType, 0, encodedType.length);

        } else {
            bytesToSend.writeByte(type);
        }

        bytesToSend.writeBytes(bytes, 0, bytes.length);

        this.connection.send(bytesToSend.getBytes());
    }

    public function onMessage(type: Dynamic, callback: Dynamic->Void) {
        this.onMessageHandlers[this.getMessageHandlerKey(type)] = callback;
        return this;
    }

    public var state (get, null): T;
    function get_state () : T {
        return this.serializer.getState();
    }

    // TODO: deprecate .id
    public var id (get, null): String;
    function get_id () : String { return this.roomId; }

    public function teardown() {
        if (this.serializer != null) {
            this.serializer.teardown();
        }

        // this.onJoin.removeAll();
        // this.onStateChange.removeAll();
        // this.onMessage.removeAll();
        // this.onError.removeAll();
        // this.onLeave.removeAll();
    }

    private function onMessageCallback(data: Bytes) {
        var code = data.get(0);
        var it:It = {offset: 1};

        if (code == Protocol.JOIN_ROOM) {
            var reconnectionToken = data.getString(it.offset + 1, data.get(it.offset));
            it.offset += reconnectionToken.length + 1;

            this.serializerId = data.getString(it.offset + 1, data.get(it.offset));
            it.offset += this.serializerId.length + 1;

            if (this.serializerId == "schema") {
                this.serializer = new SchemaSerializer<T>(tmpStateClass);

            } else if (this.serializerId == "fossil-delta") {
                this.serializer = new FossilDeltaSerializer();

            } else {
                this.serializer = new NoneSerializer();
            }

            if (data.length > it.offset) {
                this.serializer.handshake(data, it.offset);
            }

            // store local reconnection token
			this.reconnectionToken = this.roomId + ":" + reconnectionToken;

            this.onJoin.dispatch();

            // acknowledge JOIN_ROOM
            var bytes = new BytesOutput();
            bytes.writeByte(Protocol.JOIN_ROOM);
            this.connection.send(bytes.getBytes());

        } else if (code == Protocol.ERROR) {
            var errorCode: Int = Schema.decoder.number(data, it);
            var message = Schema.decoder.string(data, it);
            trace("Room error: code => " + errorCode + ", message => " + message);
            this.onError.dispatch(errorCode, message);

        } else if (code == Protocol.LEAVE_ROOM) {
            this.leave();

        } else if (code == Protocol.ROOM_STATE) {
            this.setState(data.sub(it.offset, data.length - 1));

        } else if (code == Protocol.ROOM_STATE_PATCH) {
            this.patch(data.sub(it.offset, data.length - 1));

        } else if (code == Protocol.ROOM_DATA) {
            var type = (SPEC.stringCheck(data, it))
                ? Schema.decoder.string(data, it)
                : Schema.decoder.number(data, it);

            var message = (data.length > it.offset)
                ? MsgPack.decode(data.sub(it.offset, data.length - it.offset))
                : null;

            this.dispatchMessage(type, message);

        } else if (code == Protocol.ROOM_DATA_BYTES) {
            var type = (SPEC.stringCheck(data, it))
                ? Schema.decoder.string(data, it)
                : Schema.decoder.number(data, it);

            this.dispatchMessage(type, data.sub(it.offset, data.length - it.offset));
        }
    }

    private function setState(encodedState: Bytes) {
        this.serializer.setState(encodedState);
        this.onStateChange.dispatch(this.serializer.getState());
    }

    private function patch(binaryPatch: Bytes) {
        this.serializer.patch(binaryPatch);
        this.onStateChange.dispatch(this.serializer.getState());
    }

    private function dispatchMessage(type: Dynamic, message: Dynamic) {
        var messageType = this.getMessageHandlerKey(type);

        if (this.onMessageHandlers.get(messageType) != null) {
            this.onMessageHandlers.get(messageType)(message);

        // } else if (this.onMessageHandlers['*'] != null) {
        //     this.onMessageHandlers.get(messageType)(type, message);

        } else {
            trace("onMessage not registered for type " + type);
        }

    }

    private function getMessageHandlerKey(type: Dynamic): String {
        if (Std.isOfType(type, String)) {
            return type;

        } else if (Std.isOfType(type, Int)) {
            return "i" + type;

        } else {
            return "$" + Type.getClassName(Type.getClass(type));
        }
    }

}
