import io.colyseus.RoomClock;
import io.colyseus.predict.Predict;
import io.colyseus.predict.Predict.PredictCallbacks;

import schema.predict.PassiveEnt;

/** Listener stub — tests push samples directly, no decoder bytes. */
private class FakeCallbacks {
	public var listeners: Map<String, Dynamic -> Void> = new Map();
	public function new() {}

	public function face(): PredictCallbacks {
		return {
			listen: (instance, field, handler, immediate) -> {
				this.listeners.set(field, handler);
				if (immediate) { handler(Reflect.getProperty(instance, field)); }
				return () -> { this.listeners.remove(field); };
			},
			onAdd: (_collection, _handler) -> () -> {},
			onRemove: (_collection, _handler) -> () -> {},
		};
	}

	public function push(field: String, value: Float) {
		this.listeners.get(field)(value);
	}
}

/**
 * Lerp + `smoothMs` — the display-only output spring on the lerp result
 * (mirror of the JS SDK's predict-lerp-smoothing.test.ts). Default 0 (off):
 * the output stays the raw interpolant, bit-identical to a spring-less lerp.
 * Armed, it keeps rendered velocity continuous, trailing the raw output by
 * speed × smoothMs during motion — frame-rate independently (exact
 * first-order-hold step).
 *
 * The reference's fields-array / constructor-defaults spellings don't exist
 * on this port; the per-field map is the one config surface, so those cases
 * collapse into the trail test. The setDefaults mode-flip case maps to
 * "damped with smoothMs unset uses its own 50 default".
 */
class PredictLerpSmoothingTestCase extends haxe.unit.TestCase {

	private var savedNow: Void -> Float;
	private var now: Float = 0;

	override public function setup() {
		this.savedNow = RoomClock.getNow;
		this.now = 0;
		RoomClock.getNow = () -> this.now;
	}

	override public function tearDown() {
		RoomClock.getNow = this.savedNow;
	}

	private function assertClose(expected: Float, actual: Float, ?epsilon: Float, ?pos: haxe.PosInfos) {
		if (epsilon == null) { epsilon = 1e-9; }
		assertTrue(Math.abs(expected - actual) <= epsilon, pos);
	}

	private function makeEnt(x0: Float = 10): PassiveEnt {
		var ent = new PassiveEnt();
		ent.a = x0;
		return ent;
	}

	public function testSmoothMsOmittedIsBitIdenticalToExplicitZero() {
		// The GOTCHA this guards: 50 is the damped/extrapolate default —
		// lerp must NOT silently spring with it.
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());
		var cb0 = new FakeCallbacks();
		var p0 = new Predict(cb0.face(), new RoomClock());
		p.attach(ent, { a: "lerp" });
		p0.attach(ent, { a: { mode: "lerp", smoothMs: 0 } });

		this.now = 1050; cb.push("a", 20); cb0.push("a", 20);
		this.now = 1130; p.tick(this.now); p0.tick(this.now);   // target 1030 -> u = 0.6
		var v = p.value(ent, "a");
		assertClose(16, v, 1e-12);
		assertEquals(p0.value(ent, "a"), v);

		this.now = 1145; cb.push("a", 35); cb0.push("a", 35);
		this.now = 1170; p.tick(this.now); p0.tick(this.now);
		assertEquals(p0.value(ent, "a"), p.value(ent, "a"));
	}

	public function testSmoothMsTrailsTheRawOutputDuringMotion() {
		this.now = 1000;
		var entRaw = makeEnt();
		var cbRaw = new FakeCallbacks();
		var raw = new Predict(cbRaw.face(), new RoomClock());
		var entSm = makeEnt();
		var cbSm = new FakeCallbacks();
		var sm = new Predict(cbSm.face(), new RoomClock());
		raw.attach(entRaw, { a: "lerp" });
		sm.attach(entSm, { a: { mode: "lerp", smoothMs: 30 } });

		this.now = 1050;
		while (this.now <= 1400) {
			var x = 10 + (this.now - 1000) / 5;
			cbRaw.push("a", x);
			cbSm.push("a", x);
			this.now += 50;
		}
		this.now = 1000;
		while (this.now <= 1400) {
			raw.tick(this.now); sm.tick(this.now);
			raw.value(entRaw, "a"); sm.value(entSm, "a");
			this.now += 10;
		}
		this.now -= 10;
		var vRaw = raw.value(entRaw, "a");
		var vSm = sm.value(entSm, "a");
		assertTrue(vRaw > 10);          // raw is moving
		assertTrue(vSm < vRaw);         // spring trails the raw output
		assertTrue(vSm > vRaw - 15);    // by a bounded distance, not stuck
	}

	public function testSteadyMoverTrailsBySpeedTimesSmoothMsAtAnyFrameRate() {
		// 200 u/s stream, smoothMs 25 -> trail = 200 x 0.025 = 5 u. The exact
		// first-order-hold step makes it hold at ANY tick cadence.
		var run = (tickMs: Float) -> {
			this.now = 1000;
			var ent = makeEnt();
			var cb = new FakeCallbacks();
			var p = new Predict(cb.face(), new RoomClock());
			p.attach(ent, { a: { mode: "lerp", smoothMs: 25 } });
			var v: Float = 10;
			this.now = 1000 + tickMs;
			while (this.now <= 2500) {
				if (this.now % 50 == 0) { cb.push("a", 10 + (this.now - 1000) / 5); }
				p.tick(this.now);
				v = p.value(ent, "a");
				this.now += tickMs;
			}
			var rawAt2500 = 10 + (2500 - 100 - 1000) / 5;   // target = now - delay(100)
			return rawAt2500 - v;
		};

		assertClose(5, run(10), 1e-6);   // trail = speed x smoothMs
		assertClose(5, run(25), 1e-6);   // same trail at a coarser tick
	}

	public function testSnapTeleportPopsTheSpring() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());
		p.attach(ent, { a: { mode: "lerp", snap: 4, smoothMs: 30 } });

		this.now = 1050; cb.push("a", 10.2);      // establish cadence
		this.now = 3000; cb.push("a", 60);        // teleport
		this.now = 3060; p.tick(this.now);
		assertClose(60, p.value(ent, "a"), 1e-9); // spring state popped with the ring
	}

	public function testDampedUnsetSmoothMsKeepsItsOwnDefault() {
		// Lerp's 0 default must not leak into damped: unset smoothMs on a
		// damped field chases with the 50ms default, not frozen at 0.
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());
		p.attach(ent, { a: "damped" });

		this.now = 1050; cb.push("a", 60);
		this.now = 1110; p.tick(this.now);
		var v = p.value(ent, "a");
		assertTrue(v > 10);   // damped is chasing — smoothMs 50 intact
		assertTrue(v < 60);   // still mid-glide
	}

	public function testDampedExplicitZeroSnapsToTheLatestValue() {
		// The old rate-form k=0 froze the output — 0 now means snap.
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());
		p.attach(ent, { a: { mode: "damped", smoothMs: 0 } });

		this.now = 1050; cb.push("a", 60);
		this.now = 1110; p.tick(this.now);
		assertEquals(60.0, p.value(ent, "a"));
	}

	public function testSameFrameReReadsReturnTheSameValue() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());
		p.attach(ent, { a: { mode: "lerp", smoothMs: 30 } });

		this.now = 1050; cb.push("a", 20);
		this.now = 1130; p.tick(this.now);
		var v1 = p.value(ent, "a");
		assertEquals(v1, p.value(ent, "a"));   // spring advances once per frame
	}
}
