package io.colyseus;
import io.colyseus.state_listener.StateContainer;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import org.msgpack.MsgPack;

import io.gamestd.FossilDelta;

class Room extends StateContainer {
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
    private var _previousState: Bytes;

    public function new (name: String, options: Dynamic = null) {
        super({});

        this.id = null;
        this.name = name;

        this.options = options;
    }

    public function connect(connection: Connection) {
        this.connection = connection;
        this.connection.reconnectionEnabled = false;

        this.connection.onMessage = function (bytes) {
            this.onMessageCallback(bytes);
        }

        this.connection.onClose = function () {
            this.removeAllListeners();
            this.onLeave();
        }

        this.connection.onError = function (e) {
            trace("Possible causes: room's onAuth() failed or maxClients has been reached.");
            this.onError(e);
        };
    }

    public function leave() {
        this.removeAllListeners();

        if (this.connection != null) {
            this.connection.close();

        } else {
            this.onLeave();
        }
    }

    public function send(data: Dynamic) {
        if (this.connection != null) {
            this.connection.send([ Protocol.ROOM_DATA, this.id, data ]);
        }
    }

    public override function removeAllListeners() {
        super.removeAllListeners();
        // this.onJoin.removeAll();
        // this.onStateChange.removeAll();
        // this.onMessage.removeAll();
        // this.onError.removeAll();
        // this.onLeave.removeAll();
    }

    private function onMessageCallback(data: Bytes) {
        var message: Dynamic = MsgPack.decode(data);
        var code = message[0];

        if (code == Protocol.JOIN_ROOM) {
            this.sessionId = cast message[1];
            this.onJoin();

        } else if (code == Protocol.JOIN_ERROR) {
            trace("Error: " + message[1]);
            this.onError(cast message[1]);

        } else if (code == Protocol.ROOM_STATE) {
            var state = message[1];
            var remoteCurrentTime = message[2];
            var remoteElapsedTime = message[3];

            this.setState(cast state, remoteCurrentTime, remoteElapsedTime);

        } else if (code == Protocol.ROOM_STATE_PATCH) {
            var bytes: Array<Int> = cast message[1];
            var buffer = new BytesBuffer();

            for (i in bytes) {
                buffer.addByte(i);
            }

            this.patch(buffer.getBytes());

        } else if (code == Protocol.ROOM_DATA) {
            this.onMessage(message[1]);

        } else if (code == Protocol.LEAVE_ROOM) {
            this.leave();
        }
    }

    public function setState( encodedState: Bytes, remoteCurrentTime: Int = 0, remoteElapsedTime: Int = 0) {
        this._previousState = encodedState;

        var state = MsgPack.decode(encodedState);
        this.set(state);

        this.onStateChange(state);
    }

    private function patch( binaryPatch: Bytes ) {
        // apply patch
        this._previousState = FossilDelta.Apply(this._previousState, binaryPatch);

        // trigger state callbacks
        this.set( MsgPack.decode( this._previousState ) );

        this.onStateChange(this.state);
    }

}


