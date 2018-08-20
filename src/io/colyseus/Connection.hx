package io.colyseus;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

import haxe.net.WebSocket;
import haxe.net.WebSocket.ReadyState;

class Connection {
    public var reconnectionEnabled: Bool = false;

    private var ws: WebSocket;
    private var _enqueuedSend: Array<Dynamic> = [];

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onMessage(bytes: Bytes):Void {}
    public dynamic function onClose():Void {}
    public dynamic function onError(message: String):Void {}

    public function new (url: String) {
        this.ws = WebSocket.create(url);
        this.ws.onopen = function() {
            trace("WS OPEN!!!!");
            this.onOpen();

            trace("enqueued calls: " + this._enqueuedSend.length);

            for (i in 0...this._enqueuedSend.length) {
                this.send(this._enqueuedSend[i]);
            }

            // reset enqueued calls
            this._enqueuedSend = [];
        }

        this.ws.onmessageBytes = function(bytes) {
            trace("BYTES:" + Std.string(bytes));
            this.onMessage(bytes);
        }

        this.ws.onclose = function() {
            trace("WS CLOSE!!!!");
            this.onClose();
        }

        this.ws.onerror = function(message) {
            trace("WS ERROR!!!!");
            this.onError(message);
        }

        #if sys
        Runner.thread(function() {
            trace("WebSocket thread started for " + url);
            while (true) {
                this.ws.process();
            }
        });
        #end
    }

    public function send(data: Dynamic) {
        trace("Connection.send, Type.typeof => " + Type.typeof(data));

        if (this.ws.readyState == ReadyState.Open) {
            trace("SEND BYTES! => " + Std.string(MsgPack.encode(data)));
            return this.ws.sendBytes( MsgPack.encode(data) );

        } else {
            trace("ENQUEUE send! => " + Std.string(MsgPack.encode(data)));
            // WebSocket not connected.
            // Enqueue data to be sent when readyState == OPEN
            this._enqueuedSend.push(data);
        }
    }

    public function close () {
        this.ws.close();
    }

}
