package io.colyseus;

import tink.url.Query.QueryStringBuilder;
import haxe.io.Bytes;
import org.msgpack.MsgPack;
import haxe.net.WebSocket;
import haxe.net.WebSocket.ReadyState;
import tink.Url;
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

typedef ReconnectOptions = {
	?reconnectionToken:String,
	?skipHandshake:Bool
};

/**
 * On native targets the socket is read on a thread of its own, but every
 * event it produces (open, message, close, error) is replayed on the thread
 * that created the connection, through that thread's event loop — so room and
 * schema callbacks run on your game thread, exactly as on JS. Engines that
 * progress the main thread's event loop each frame (Heaps, Lime, anything
 * running `haxe.EntryPoint`) need nothing else. An open socket also keeps
 * that loop alive, so a headless program can simply return from `main()`.
 * A host that drives its own loop calls `sys.thread.Thread.current().events.progress()`.
 */
@:keep
class Connection {
	public var reconnectionEnabled:Bool = false;

	public var _isOpen(get, never):Bool;

	@:getter(isOpen)
	function get__isOpen():Bool {
		return (this.ws != null && this.ws.readyState == ReadyState.Open);
	}

	private var ws:WebSocket;
	private var parsedUrl:Url;

	/** Where this connection's events run: the thread that created it, reconnects included. */
	public final owner = new OwnerLoop();

	// callbacks
	public dynamic function onOpen():Void {}

	public dynamic function onMessage(bytes:Bytes):Void {}

	public dynamic function onClose(data:Dynamic):Void {}

	public dynamic function onError(message:String):Void {}

	public function new(url:String) {
		this.parsedUrl = Url.parse(url);
		this.createWebSocket(url);
	}

	private function createWebSocket(url:String) {
		this.ws = WebSocket.create(url);
		this.ws.onopen = function() {
			owner.run(() -> this.onOpen());
		}

		this.ws.onmessageBytes = function(bytes) {
			owner.run(() -> this.onMessage(bytes));
		}

		this.ws.onclose = function(?e:Dynamic) {
			owner.run(() -> {
				if (this.forceCloseCode != null) {
					e = { code: this.forceCloseCode };
					this.forceCloseCode = null;
				}
				this.onClose(e);
			});
		}

		this.ws.onerror = function(message) {
			owner.run(() -> this.onError(message));
		}

		#if sys
		var ws = this.ws;
		owner.hold(); // an open socket keeps the owner's event loop running
		Thread.create(function() {
			while (true) {
				ws.process();

				if (ws.readyState == ReadyState.Closed) {
					break;
				}

				Sys.sleep(.01);
			}
			owner.release(() -> {});
		});
		#end
	}

	public function reconnect(?options:ReconnectOptions) {
        var redirectUrl = Url.make({
            hosts: [this.parsedUrl.host],
            scheme: this.parsedUrl.scheme,
            hash: this.parsedUrl.hash,
            path: this.parsedUrl.path,
            query: this.parsedUrl.query.with([
				"reconnectionToken" => options.reconnectionToken,
				"skipHandshake" => (options.skipHandshake != null && options.skipHandshake == true) ? "1" : "0",
            ]),
        });

		// Create a new WebSocket connection
		this.createWebSocket(redirectUrl.toString());
	}

	/**
	 * Dynamic for the same reason `onMessage` is: it is the OUTBOUND seam. A
	 * decorator (a latency simulator, a recorder) captures this and reassigns it,
	 * which puts it in front of the socket rather than beside it.
	 */
	public dynamic function send(data:Bytes) {
		return this.ws.sendBytes(data);
	}

	/**
	 * The ws lib cannot send a close code, so a LOCAL close would reach
	 * onClose without one and the room would read it as a plain leave. A drop
	 * test needs its own kill classified as reconnectable: stash the code and
	 * report it from the onclose dispatch (mirrors the Lua SDK's
	 * `_force_close_code`).
	 */
	public var forceCloseCode: Null<Int> = null;

	public function close(?code: Int) {
		this.forceCloseCode = code;
		this.ws.close();
	}
}
