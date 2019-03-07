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

    private static var isRunnerInitialized: Bool = false;

    public function new (url: String) {
        this.ws = WebSocket.create(url);
        this.ws.onopen = function() {
            this.onOpen();

            for (i in 0...this._enqueuedSend.length) {
                this.send(this._enqueuedSend[i]);
            }

            // reset enqueued calls
            this._enqueuedSend = [];
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

#if sys
        if (!Connection.isRunnerInitialized) {
            Runner.init();
        }

        Runner.thread(function() {
            // TODO: check when to kill this thread!
            while (true) {
                this.ws.process();

                if (this.ws.readyState == ReadyState.Closed) {
                    trace("WebSocket connection has been closed, stopping the thread!");
                    break;
                }

                Sys.sleep(.01);
            }
        });
#end
    }

    public function send(data: Dynamic) {
        if (this.ws.readyState == ReadyState.Open) {
            return this.ws.sendBytes( MsgPack.encode(data) );

        } else {
            // WebSocket not connected.
            // Enqueue data to be sent when readyState == OPEN
            this._enqueuedSend.push(data);
        }
    }

    public function close () {
        this.ws.close();
    }

}
