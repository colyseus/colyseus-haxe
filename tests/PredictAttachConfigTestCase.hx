import io.colyseus.RoomClock;
import io.colyseus.predict.Predict;
import io.colyseus.predict.Predict.PredictCallbacks;
import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.serializer.schema.Decoder;
import io.colyseus.serializer.schema.Schema;

import schema.predict.PassiveEnt;
import schema.predict.ReckonBall;

/**
 * Listener stub keyed by (refId, field) — the smoothing test's fake is keyed by
 * field alone, which cannot tell two children of a collection apart. onAdd /
 * onRemove actually fire here, so attachAll is exercised.
 */
private class FakeCallbacks {
	public var listeners: Map<String, Dynamic -> Void> = new Map();
	private var adds: Map<String, Array<(Dynamic, Dynamic) -> Void>> = new Map();
	private var removes: Map<String, Array<(Dynamic, Dynamic) -> Void>> = new Map();

	public function new() {}

	public function face(): PredictCallbacks {
		return {
			listen: (instance, field, handler, immediate) -> {
				var key = slotKey(instance, field);
				this.listeners.set(key, handler);
				if (immediate) { handler(Reflect.getProperty(instance, field)); }
				return () -> { this.listeners.remove(key); };
			},
			onAdd: (parent, collection, handler) -> register(this.adds, parent, collection, handler),
			onRemove: (parent, collection, handler) -> register(this.removes, parent, collection, handler),
		};
	}

	/** Is this Predict subscribed to the field? Zero here is the item-03 tell. */
	public function tracks(instance: Dynamic, field: String): Bool {
		return this.listeners.exists(slotKey(instance, field));
	}

	public function push(instance: Dynamic, field: String, value: Float) {
		this.listeners.get(slotKey(instance, field))(value);
	}

	public function emitAdd(parent: Dynamic, collection: String, child: Dynamic) {
		emit(this.adds, parent, collection, child);
	}

	public function emitRemove(parent: Dynamic, collection: String, child: Dynamic) {
		emit(this.removes, parent, collection, child);
	}

	private static function slotKey(instance: Dynamic, field: String): String {
		return Std.string((instance : Schema).__refId) + "|" + field;
	}

	private static function collectionKey(parent: Dynamic, collection: String): String {
		return ((parent == null) ? "root" : Std.string((parent : Schema).__refId)) + "|" + collection;
	}

	private static function register(into: Map<String, Array<(Dynamic, Dynamic) -> Void>>,
			parent: Dynamic, collection: String, handler: (Dynamic, Dynamic) -> Void): Void -> Void {
		var key = collectionKey(parent, collection);
		var list = into.get(key);
		if (list == null) { list = []; into.set(key, list); }
		list.push(handler);
		return () -> { list.remove(handler); };
	}

	private static function emit(from: Map<String, Array<(Dynamic, Dynamic) -> Void>>,
			parent: Dynamic, collection: String, child: Dynamic) {
		var list = from.get(collectionKey(parent, collection));
		if (list == null) { return; }
		for (handler in list.copy()) { handler(child, Std.string((child : Schema).__refId)); }
	}
}

/**
 * The attach CONFIG surface: which shape means what, and what a config that
 * matches nothing does.
 *
 * The bug these guard (TODO 03): `attach` discriminated the union on
 * `mode == "reckon"`, so every other group config — including the one the JS
 * docs spell, `{ mode: "lerp", fields: ["x","y"], snap: 4 }` — fell into the
 * per-field loop, where `mode`/`fields`/`snap` were looked up as schema fields,
 * missed, and were skipped. It attached NOTHING, and said nothing: `value()`
 * falls back to the raw synced field, so the failure renders as a plausible
 * number. The discriminator is `fields` being an ARRAY, as in the reference.
 */
class PredictAttachConfigTestCase extends haxe.unit.TestCase {

	private var savedNow: Void -> Float;
	private var savedTrace: Dynamic;
	private var traced: Array<String> = [];
	private var now: Float = 0;
	private var nextRefId: Int = 1;

	override public function setup() {
		this.savedNow = RoomClock.getNow;
		this.now = 0;
		RoomClock.getNow = () -> this.now;
		this.nextRefId = 1;
		this.traced = [];
		this.savedTrace = haxe.Log.trace;
		haxe.Log.trace = (value: Dynamic, ?_infos: haxe.PosInfos) -> {
			this.traced.push(Std.string(value));
		};
	}

	override public function tearDown() {
		RoomClock.getNow = this.savedNow;
		haxe.Log.trace = this.savedTrace;
	}

	private function assertClose(expected: Float, actual: Float, ?epsilon: Float, ?pos: haxe.PosInfos) {
		if (epsilon == null) { epsilon = 1e-9; }
		assertTrue(Math.abs(expected - actual) <= epsilon, pos);
	}

	/** Hand-built schemas all share __refId 0; the slot maps key on it. */
	private function makeEnt(a: Float = 10, b: Float = 10): PassiveEnt {
		var ent = new PassiveEnt();
		ent.a = a;
		ent.b = b;
		ent.__refId = this.nextRefId++;
		return ent;
	}

	private function getBytes(arr: Array<Int>): haxe.io.Bytes {
		var bytes = haxe.io.Bytes.alloc(arr.length);
		for (i in 0...arr.length) { bytes.set(i, arr[i]); }
		return bytes;
	}

	private function tracedEmptyAttach(): Bool {
		for (line in this.traced) {
			if (line.indexOf("attach matched no fields") > -1) { return true; }
		}
		return false;
	}

	// --- The group shape ---------------------------------------------------

	/**
	 * The item's bug, end to end: the JS-docs spelling must subscribe and smooth.
	 * Same fixture as the lerp tests — samples 10@1000 and 20@1050, read at 1130
	 * with delay 100 lands the render target at 1030, 60% of the way across.
	 */
	public function testGroupShapeAttachesAndInterpolates() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { mode: "lerp", fields: ["a", "b"], snap: 40 });

		assertTrue(cb.tracks(ent, "a"));
		assertTrue(cb.tracks(ent, "b"));

		this.now = 1050; cb.push(ent, "a", 20);
		this.now = 1130; p.tick(this.now);
		// ...and NOT the raw synced field, which is the silent-failure signature:
		// a dead attach still renders a plausible number through value()'s fallback
		assertClose(10, ent.a);
		assertClose(16, p.value(ent, "a"), 1e-12);
	}

	/** Group options reach every field's slot, not just the field list. */
	public function testGroupSnapCutsInsteadOfGliding() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { mode: "lerp", fields: ["a"], snap: 4 });

		// a 10-unit jump is past the 4-unit teleport threshold: cut, don't glide
		this.now = 1050; cb.push(ent, "a", 20);
		this.now = 1130; p.tick(this.now);
		assertClose(20, p.value(ent, "a"), 1e-12);
	}

	/** `angle` is a group option in the reference too: it lands on every field. */
	public function testGroupAngleReachesEveryField() {
		this.now = 1000;
		var ent = makeEnt();
		ent.yaw = 3;

		var groupCb = new FakeCallbacks();
		var group = new Predict(groupCb.face(), new RoomClock());
		group.attach(ent, { mode: "lerp", fields: ["yaw"], angle: true });

		var perFieldCb = new FakeCallbacks();
		var perField = new Predict(perFieldCb.face(), new RoomClock());
		perField.attach(ent, { yaw: { mode: "lerp", angle: true } });

		// -3 is the short way round from 3, across the ±π seam
		this.now = 1050; groupCb.push(ent, "yaw", -3); perFieldCb.push(ent, "yaw", -3);
		this.now = 1130; group.tick(this.now); perField.tick(this.now);
		assertEquals(perField.value(ent, "yaw"), group.value(ent, "yaw"));
		// unwrapped, the read stays past the seam rather than gliding back through 0
		assertTrue(group.value(ent, "yaw") > 3);
	}

	/**
	 * `delay` on a group is a Haxe superset — the reference only takes it
	 * per-field or from the Predict's defaults.
	 */
	public function testGroupDelayIsHonoured() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { mode: "lerp", fields: ["a"], delay: 50 });

		this.now = 1050; cb.push(ent, "a", 20);
		// render target 1080 is past the newest sample, so lerp clamps to it;
		// the default delay of 100 would have landed mid-interpolation at 16
		this.now = 1130; p.tick(this.now);
		assertClose(20, p.value(ent, "a"), 1e-12);
	}

	/** Omitted `mode` takes the Predict's, which itself defaults to lerp. */
	public function testGroupModeOmittedUsesPredictDefault() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { fields: ["a"] });
		assertEquals("lerp", p.mode);

		this.now = 1050; cb.push(ent, "a", 20);
		this.now = 1130; p.tick(this.now);
		assertClose(16, p.value(ent, "a"), 1e-12);
	}

	/** ...and follows the Predict's default when that is something else. */
	public function testGroupModeOmittedFollowsConfiguredDefault() {
		this.now = 1000;
		var ent = makeEnt();

		var groupCb = new FakeCallbacks();
		var group = new Predict(groupCb.face(), new RoomClock(), { mode: "damped" });
		group.attach(ent, { fields: ["a"] });

		var perFieldCb = new FakeCallbacks();
		var perField = new Predict(perFieldCb.face(), new RoomClock());
		perField.attach(ent, { a: "damped" });

		assertEquals("damped", group.mode);

		this.now = 1050; groupCb.push(ent, "a", 20); perFieldCb.push(ent, "a", 20);
		this.now = 1130; group.tick(this.now); perField.tick(this.now);
		assertEquals(perField.value(ent, "a"), group.value(ent, "a"));
	}

	/** Only "reckon" allocates sim state — a lerp group is slots and nothing else. */
	public function testSmoothingGroupAllocatesNoSimState() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { mode: "lerp", fields: ["a", "b"] });
		assertFalse(@:privateAccess p.simsByRef.keys().hasNext());
	}

	// --- Reckon ------------------------------------------------------------

	/**
	 * Reckon without a step used to be accepted, then throw `Invalid call` from
	 * tick() — a stack away from the call that was actually wrong.
	 */
	public function testReckonGroupWithoutStepThrowsAtAttach() {
		var state = new ReckonBall();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<ReckonBall> = new SchemaCallbacks<ReckonBall>(decoder);
		var p = Predict.create(callbacks, new RoomClock());

		var message = "";
		try {
			p.attach(decoder.state, { mode: "reckon", fields: ["x"] });
		} catch (e: Dynamic) {
			message = Std.string(e);
		}
		assertTrue(message.indexOf("reckon mode requires a 'step' function") > -1);
	}

	/**
	 * A reckon group inherits step/substep/smoothMs from the Predict, so
	 * `Predict.get(room, { mode: "reckon", step })` + `{ fields: [...] }` is a
	 * complete attach. Trajectory is the fixture from PredictTestCase.
	 */
	public function testReckonGroupInheritsDefaultsFromPredict() {
		var state = new ReckonBall();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<ReckonBall> = new SchemaCallbacks<ReckonBall>(decoder);
		var clock = new RoomClock();
		var p = Predict.create(callbacks, clock, {
			mode: "reckon",
			step: (s, dt, _elapsed) -> { s.x += s.vx * dt; },
			smoothMs: 0,   // raw projection
			substep: 10,
		});
		var ball = decoder.state;

		p.attach(ball, { fields: ["x"] });
		assertTrue(@:privateAccess p.simsByRef.keys().hasNext());

		this.now = 1000;
		clock.sample(1000, -1);
		decoder.decode(getBytes([128, 100, 129, 50]));

		var traj = [[1000.0, 100.0], [1050.0, 102.5], [1100.0, 105.0], [1200.0, 110.0]];
		for (pair in traj) {
			this.now = pair[0];
			p.tick(this.now);
			assertClose(pair[1], p.value(ball, "x"));
		}
	}

	// --- The per-field map -------------------------------------------------

	/** Regression: the shape that always worked still does. */
	public function testPerFieldMapStillAttaches() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { a: "lerp", b: { mode: "damped", angle: true } });
		assertTrue(cb.tracks(ent, "a"));
		assertTrue(cb.tracks(ent, "b"));
		assertFalse(tracedEmptyAttach());
	}

	/**
	 * A field holding null at attach time is still DECLARED, so it attaches.
	 * The guard used to read the live value, which dropped it.
	 */
	public function testNullValuedFieldStillAttaches() {
		this.now = 1000;
		var ent = makeEnt();
		ent.a = null;
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { a: "lerp", b: "lerp" });
		assertTrue(cb.tracks(ent, "a"));
		assertTrue(cb.tracks(ent, "b"));
	}

	// --- Fields the schema doesn't declare ---------------------------------

	/** Dropping SOME fields is legitimate — one config over mixed children. */
	public function testUndeclaredFieldsAreDroppedQuietly() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { a: "lerp", nope: "lerp" });
		assertTrue(cb.tracks(ent, "a"));
		assertFalse(cb.tracks(ent, "nope"));
		assertFalse(tracedEmptyAttach());

		var ent2 = makeEnt();
		var p2 = new Predict(cb.face(), new RoomClock());
		p2.attach(ent2, { mode: "lerp", fields: ["a", "nope"] });
		assertTrue(cb.tracks(ent2, "a"));
		assertFalse(cb.tracks(ent2, "nope"));
	}

	/** Matching zero fields never is. Silence there is what made this expensive. */
	public function testAttachMatchingNothingIsLoud() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { nonsense: "lerp" });
		assertFalse(cb.tracks(ent, "nonsense"));
		assertTrue(tracedEmptyAttach());
	}

	/** One warning per class + config, not one per child of the collection. */
	public function testEmptyAttachWarnsOncePerShape() {
		this.now = 1000;
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(makeEnt(), { nonsense: "lerp" });
		p.attach(makeEnt(), { nonsense: "lerp" });
		var count = 0;
		for (line in this.traced) {
			if (line.indexOf("attach matched no fields") > -1) { count++; }
		}
		assertEquals(1, count);
	}

	// --- attachAll ---------------------------------------------------------

	public function testAttachAllAppliesGroupConfigToEveryChild() {
		this.now = 1000;
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		var off = p.attachAll("players", { mode: "lerp", fields: ["a", "b"] });

		var one = makeEnt();
		var two = makeEnt();
		cb.emitAdd(null, "players", one);
		cb.emitAdd(null, "players", two);

		assertTrue(cb.tracks(one, "a"));
		assertTrue(cb.tracks(one, "b"));
		assertTrue(cb.tracks(two, "a"));

		cb.emitRemove(null, "players", two);
		assertFalse(cb.tracks(two, "a"));
		assertTrue(cb.tracks(one, "a"));

		off();
		assertFalse(cb.tracks(one, "a"));
	}

	/** The (parent, key, config) form reaches a collection off the root state. */
	public function testAttachAllOnANestedCollection() {
		this.now = 1000;
		var parent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attachAll(parent, "items", { a: "lerp" });

		var child = makeEnt();
		cb.emitAdd(parent, "items", child);
		assertTrue(cb.tracks(child, "a"));

		// the root-level wiring is a different subscription entirely
		var stray = makeEnt();
		cb.emitAdd(null, "items", stray);
		assertFalse(cb.tracks(stray, "a"));
	}

	// --- Defaults ----------------------------------------------------------

	/**
	 * An attach snapshots its options, so a later setDefaults leaves it alone —
	 * the reference allocates a per-group profile for the same reason.
	 */
	public function testSetDefaultsDoesNotRetroAffectAttachedSlots() {
		this.now = 1000;
		var ent = makeEnt();
		var cb = new FakeCallbacks();
		var p = new Predict(cb.face(), new RoomClock());

		p.attach(ent, { fields: ["a"] });           // lerp, delay 100
		p.setDefaults({ mode: "raw", delay: 0 });
		assertEquals("raw", p.mode);

		this.now = 1050; cb.push(ent, "a", 20);
		this.now = 1130; p.tick(this.now);
		assertClose(16, p.value(ent, "a"), 1e-12);   // still the lerp it attached with

		// a NEW attach picks the changed defaults up
		var later = makeEnt();
		p.attach(later, { fields: ["a"] });
		this.now = 1150; cb.push(later, "a", 99);
		p.tick(this.now);
		assertClose(99, p.value(later, "a"));
	}
}
