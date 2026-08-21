using io.colyseus.events.EventHandler;

import io.colyseus.events.EventHandler;

/**
 * `EventHandler` — add/remove, `once`, and the mid-dispatch mutation hazard.
 *
 * `once` is the canonical "wait for the first X" idiom in the JS SDK
 * (`room.onStateChange.once(...)`); without it every consumer hand-rolls a
 * `fired` boolean. It only works if `dispatch` tolerates the list changing
 * underneath it, which is what most of this case is really guarding.
 */
class EventHandlerTestCase extends haxe.unit.TestCase {

	public function testOnceFiresOnlyOnTheNextDispatch() {
		var e = new EventHandler<Void->Void>();
		var calls = 0;
		e.once(() -> calls++);

		e.dispatch();
		assertEquals(1, calls);
		e.dispatch();
		assertEquals(1, calls);
	}

	public function testOnceCarriesArguments() {
		var one = new EventHandler<Int->Void>();
		var seen = -1;
		one.once((code) -> seen = code);
		one.dispatch(4);
		one.dispatch(9);
		assertEquals(4, seen);

		var two = new EventHandler<Int->String->Void>();
		var got = "";
		two.once((code, message) -> got = code + ":" + message);
		two.dispatch(1, "a");
		two.dispatch(2, "b");
		assertEquals("1:a", got);
	}

	/**
	 * The hazard `once` sits on: dispatch used to walk the live array, so a
	 * handler removing itself shifted the next one into the slot the
	 * index-based iterator had already passed — and that listener was skipped.
	 */
	public function testAHandlerRemovingItselfDoesNotSkipTheNextOne() {
		var e = new EventHandler<Void->Void>();
		var order: Array<String> = [];
		var first: Void->Void = null;
		first = function() { e -= first; order.push("first"); };
		e += first;
		e += () -> order.push("second");
		e += () -> order.push("third");

		e.dispatch();
		assertEquals("first,second,third", order.join(","));

		// ...and `first` really is gone
		order = [];
		e.dispatch();
		assertEquals("second,third", order.join(","));
	}

	/** Several `once` listeners on one handler all fire, then all clear. */
	public function testSeveralOnceListenersAllFireOnce() {
		var e = new EventHandler<Void->Void>();
		var order: Array<String> = [];
		e.once(() -> order.push("a"));
		e.once(() -> order.push("b"));
		e += () -> order.push("persistent");

		e.dispatch();
		assertEquals("a,b,persistent", order.join(","));

		order = [];
		e.dispatch();
		assertEquals("persistent", order.join(","));
	}

	/** once() unsubscribes BEFORE calling, so a throwing listener is still spent. */
	public function testOnceIsSpentEvenIfTheListenerThrows() {
		var e = new EventHandler<Void->Void>();
		var calls = 0;
		e.once(() -> { calls++; throw "boom"; });

		try { e.dispatch(); } catch (_: Dynamic) {}
		assertEquals(1, calls);
		e.dispatch();
		assertEquals(1, calls);
	}
}
