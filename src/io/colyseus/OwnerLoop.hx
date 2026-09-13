package io.colyseus;

/**
 * Where native room events are delivered: the event loop of the thread that
 * captured it (the thread that joined). Off threaded targets, and for a thread
 * without an event loop (a raw worker), every call just runs inline.
 */
class OwnerLoop {
	#if (target.threaded && !cppia && haxe_ver >= 4.2)
	final loop:Null<sys.thread.EventLoop>;
	#end

	/** Captures the calling thread's event loop. */
	public function new() {
		#if (target.threaded && !cppia && haxe_ver >= 4.2)
		loop = try sys.thread.Thread.current().events catch (_:Dynamic) null;
		#end
	}

	/** Whether calls are replayed on an event loop — so a `haxe.Timer` runs there too. */
	public var active(get, never):Bool;

	function get_active():Bool {
		#if (target.threaded && !cppia && haxe_ver >= 4.2)
		return loop != null;
		#else
		return false;
		#end
	}

	/** Run `fn` on the owner thread. */
	public function run(fn:Void->Void):Void {
		#if (target.threaded && !cppia && haxe_ver >= 4.2)
		if (loop != null) {
			loop.run(fn);
			return;
		}
		#end
		fn();
	}

	/** Keep the owner's event loop running until the matching `release`. */
	public function hold():Void {
		#if (target.threaded && !cppia && haxe_ver >= 4.2)
		if (loop != null) loop.promise();
		#end
	}

	/** End one `hold`, running `fn` on the owner thread. */
	public function release(fn:Void->Void):Void {
		#if (target.threaded && !cppia && haxe_ver >= 4.2)
		if (loop != null) {
			loop.runPromised(fn);
			return;
		}
		#end
		fn();
	}
}
