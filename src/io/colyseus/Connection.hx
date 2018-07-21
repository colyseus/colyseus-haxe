package io.colyseus;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

import haxe.net.WebSocket;
import haxe.net.WebSocket.ReadyState;


class Connection {
    public var reconnectionEnabled: Bool = false;

    private var ws: WebSocket;
    private var _enqueuedCalls: Array<Dynamic> = [];

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onMessage(bytes: Bytes):Void {}
    public dynamic function onClose():Void {}
    public dynamic function onError(message: String):Void {}

    public function new (url: String) {
        this.ws = WebSocket.create(url);

        this.ws.onopen = function() {
            this.onOpen();

            for (i in 0...this._enqueuedCalls.length) {
                var enqueuedCall = this._enqueuedCalls[i];
                Reflect.callMethod(this, Reflect.field(this, enqueuedCall[0]), [enqueuedCall[1]]);
            }

            // reset enqueued calls
            this._enqueuedCalls = [];
        }

        this.ws.onmessageBytes = function(bytes) {
            this.onMessage(bytes);
        }

        this.ws.onclose = function() {
            this.onClose();
        }

        this.ws.onerror = function(message) {
            this.onError(message);
        }
    }

    public function send(data: Dynamic) {
        if (this.ws.readyState == ReadyState.Open) {
            return this.ws.sendBytes( MsgPack.encode(data) );

        } else {
            // WebSocket not connected.
            // Enqueue data to be sent when readyState == OPEN
            this._enqueuedCalls.push(['send', data]);
        }
    }

    public function close () {
        this.ws.close();
    }

}
