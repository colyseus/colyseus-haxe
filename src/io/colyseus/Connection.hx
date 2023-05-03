package io.colyseus;

import haxe.io.Bytes;
import org.msgpack.MsgPack;

import haxe.net.WebSocket;
import haxe.net.WebSocket.ReadyState;

#if !haxe4
    #if neko
        import neko.vm.Thread;
    #elseif hl
        import hl.vm.Thread;
    #elseif cpp
        import cpp.vm.Thread;
    #end
#elseif sys
    import sys.thread.Thread;
#end

class Connection {
    public var reconnectionEnabled: Bool = false;

    private var ws: WebSocket;

    // callbacks
    public dynamic function onOpen():Void {}
    public dynamic function onMessage(bytes: Bytes):Void {}
    public dynamic function onClose(data: Dynamic):Void {}
    public dynamic function onError(message: String):Void {}

    private static var isRunnerInitialized: Bool = false;

    public function new (url: String) {
        this.ws = WebSocket.create(url);
        this.ws.onopen = function() {
            this.onOpen();
        }

        this.ws.onmessageBytes = function(bytes) {
            this.onMessage(bytes);
        }

        this.ws.onclose = function(?e:Dynamic) {
            this.onClose(e);
        }

        this.ws.onerror = function(message) {
            this.onError(message);
        }

        #if sys
        Thread.create(function() {
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

    public function send(data: Bytes) {
        return this.ws.sendBytes(data);
    }

    public function close () {
        this.ws.close();
    }
}
