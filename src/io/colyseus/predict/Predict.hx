package io.colyseus.predict;

import io.colyseus.RoomClock;
import io.colyseus.predict.Reconciler;
import io.colyseus.predict.PredictedEventChannel;
import io.colyseus.predict.PredictedSpawns;

import io.colyseus.serializer.schema.Schema;

/** Driven-child face for event channels / spawn stores. */
interface DrivenChild {
	var dead(default, null): Bool;
	function tick(now: Float): Void;
	function prune(): Void;
}

/**
 * The callbacks face `Predict` consumes — engine-level, string-keyed.
 * `Predict.create` adapts the SDK's `SchemaCallbacks<T>`.
 */
typedef PredictCallbacks = {
	var listen: (instance: Dynamic, field: String, handler: Dynamic -> Void, immediate: Bool) -> (Void -> Void);
	var onAdd: (collection: String, handler: (value: Dynamic, key: Dynamic) -> Void) -> (Void -> Void);
	var onRemove: (collection: String, handler: (value: Dynamic, key: Dynamic) -> Void) -> (Void -> Void);
}

/** Per-field smoothing options (defaults mirror the JS reference). */
typedef PredictFieldOptions = {
	/** "lerp" | "extrapolate" | "damped" | "reckon" | "raw" (default "lerp"). */
	@:optional var mode: String;
	/** Lerp render-time lag (ms); default 100. */
	@:optional var delay: Null<Float>;
	/** Damped/extrapolate spring (1/s); default 15. 0 on extrapolate = raw projection. */
	@:optional var damping: Null<Float>;
	/** Extrapolate overshoot cap (ms); default 200. */
	@:optional var maxExtrapolate: Null<Float>;
	/** Arrival-grid snap (ms); 0 off. */
	@:optional var tickInterval: Null<Float>;
	/** Value-space teleport threshold; 0 off. */
	@:optional var snap: Null<Float>;
	/** Radian angle — unwrap samples over the shortest arc. */
	@:optional var angle: Null<Bool>;
}

/** Options for a reckon attach. */
typedef ReckonOptions = {
	var fields: Array<String>;
	/** The pure step function, SHARED with the server: mutate the scratch in
	    place by dt seconds; elapsedMs is the absolute server-time at the end
	    of the substep. */
	var step: (scratch: Dynamic, dtSeconds: Float, elapsedMs: Float) -> Void;
	/** Offset-decay smoothing (1/s); default 20. 0 = raw projection. */
	@:optional var smoothing: Null<Float>;
	/** Substep length (ms); default 16. */
	@:optional var substep: Null<Float>;
	/** Rebase discontinuities beyond this pop. 0 off. */
	@:optional var snap: Null<Float>;
}

private class Slot {
	public var field: String;
	public var instance: Dynamic;
	public var mode: String;
	public var delay: Float;
	public var damping: Float;
	public var maxExtrapolate: Float;
	public var tickInterval: Float;
	public var snap: Float;
	public var angle: Bool;
	public var v1: Float = 0;
	public var auxV: Float = 0;
	public var auxT: Float = 0;
	public var ringT: Array<Float>;
	public var ringV: Array<Float>;
	public var ringHead: Int = 0;
	public var ringCount: Int = 0;
	public var detach: Void -> Void;
	public function new() {}
}

private class SimState {
	public var instance: Dynamic;
	public var scratch: Dynamic;
	public var fields: Array<String>;
	public var step: (Dynamic, Float, Float) -> Void;
	public var smoothing: Float;
	public var substep: Float;
	public var snap: Float;
	public var smoothed: Array<Float>;
	public var out: Array<Float>;
	public var valueOut: Array<Float>;
	public var offset: Array<Float>;
	public var outPrev: Array<Float>;
	public var frameVel: Array<Float>;
	public var lastBaseT: Float = Math.NaN;
	public var lastApplyTime: Float = Math.NEGATIVE_INFINITY;
	public var copyFields: Array<String>;
	/** Per-entity forward horizon override (spawns lead). Null = snapshot age. */
	public var forwardMs: Void -> Float;
	public function new() {}
}

/**
 * Predict — passive smoothing of the server stream for entities you DON'T
 * control (port of the JS SDK's `predict/Predictor.ts`: passive engine +
 * orchestration). One read idiom: `value(instance, field)` — with raw
 * instance fallback when untracked. Reconciler factories inject the room
 * clock and adopt the fixed step for `tick()`'s send budget.
 */
class Predict {
	private static inline var RING_CAP = 16;
	private static inline var GAP_RESUME_MULT = 3.0;
	private static inline var GAP_RESUME_PATCH_MULT = 1.5;
	private static inline var GAP_RESUME_MAX_MS = 250.0;
	private static inline var MAX_STEPS_PER_FRAME = 5;

	private var callbacks: PredictCallbacks;
	private var clock: RoomClock;
	private var renderTime: Float = 0;
	// refId -> field -> slot
	private var slotsByRef: Map<Int, Map<String, Slot>> = new Map();
	private var simsByRef: Map<Int, SimState> = new Map();
	private var driven: Array<Dynamic> = [];

	// room-wide fixed-step accumulator (send budget)
	private var fixedStepMs: Null<Float> = null;
	private var stepAcc: Float = 0;
	private var lastFrameNow: Float = -1;

	/**
	 * Adapt the SDK's `SchemaCallbacks<T>` (from `Callbacks.get(room)`).
	 * Typed `Dynamic` because `@:generic` erases the parametric relationship
	 * of the specialized callbacks class — every specialization has the same
	 * Dynamic-typed listen/onAdd/onRemove surface consumed here.
	 */
	public static function create(callbacks: Dynamic, clock: RoomClock): Predict {
		return new Predict({
			listen: (instance, field, handler, immediate) -> {
				var off: Dynamic = callbacks.listen(instance, field,
					(value: Dynamic, _previous: Dynamic) -> handler(value), immediate);
				return () -> { off(); };
			},
			onAdd: (collection, handler) -> {
				var off: Dynamic = callbacks.onAdd(collection,
					(value: Dynamic, key: Dynamic) -> handler(value, key));
				return () -> { off(); };
			},
			onRemove: (collection, handler) -> {
				var off: Dynamic = callbacks.onRemove(collection,
					(value: Dynamic, key: Dynamic) -> handler(value, key));
				return () -> { off(); };
			},
		}, clock);
	}

	public function new(callbacks: PredictCallbacks, clock: RoomClock) {
		this.callbacks = callbacks;
		this.clock = clock;
	}

	private static function toNumber(value: Dynamic): Float {
		if (value == null) { return 0; }
		if (Std.isOfType(value, Bool)) { return cast(value, Bool) ? 1 : 0; }
		if (Std.isOfType(value, Float)) { return cast value; }
		return 0;
	}

	// --- Attach -----------------------------------------------------------

	/** Track one numeric field for smoothing. Returns an untrack function. */
	public function track(instance: Dynamic, field: String, ?options: PredictFieldOptions): Void -> Void {
		var refId: Int = (instance : Schema).__refId;
		var perRef = this.slotsByRef.get(refId);
		if (perRef == null) {
			perRef = new Map();
			this.slotsByRef.set(refId, perRef);
		}
		// idempotent per field
		var existing = perRef.get(field);
		if (existing != null) {
			if (existing.detach != null) { existing.detach(); }
			perRef.remove(field);
		}

		var slot = new Slot();
		slot.field = field;
		slot.instance = instance;
		slot.mode = (options != null && options.mode != null) ? options.mode : "lerp";
		slot.delay = (options != null && options.delay != null) ? options.delay : 100;
		slot.damping = (options != null && options.damping != null) ? options.damping : 15;
		slot.maxExtrapolate = (options != null && options.maxExtrapolate != null) ? options.maxExtrapolate : 200;
		slot.tickInterval = (options != null && options.tickInterval != null) ? options.tickInterval : 0;
		slot.snap = (options != null && options.snap != null) ? options.snap : 0;
		slot.angle = (options != null && options.angle != null) ? options.angle : false;
		var initial = toNumber(Reflect.getProperty(instance, field));
		slot.v1 = initial;
		slot.auxV = initial;
		slot.ringT = [for (_ in 0...RING_CAP) 0.0];
		slot.ringV = [for (_ in 0...RING_CAP) 0.0];
		perRef.set(field, slot);

		slot.detach = this.callbacks.listen(instance, field,
			(current: Dynamic) -> this.onSample(slot, toNumber(current)), true);
		return () -> this.untrack(instance, field);
	}

	/** Dead-reckon fields of an instance with a step SHARED with the server. */
	public function trackReckon(instance: Dynamic, options: ReckonOptions): Void -> Void {
		var refId: Int = (instance : Schema).__refId;
		var schema: Schema = cast instance;
		var scratch: Dynamic = Type.createInstance(Type.getClass(instance), []);
		var copyFields: Array<String> = [];
		var i = 0;
		while (schema._indexes.exists(i)) {
			var t = schema._types.get(i);
			if (t != "ref" && t != "array" && t != "map" && t != "string") {
				copyFields.push(schema._indexes.get(i));
			}
			i++;
		}
		var n = options.fields.length;
		var sim = new SimState();
		sim.instance = instance;
		sim.scratch = scratch;
		sim.fields = options.fields;
		sim.step = options.step;
		sim.smoothing = (options.smoothing != null) ? options.smoothing : 20;
		sim.substep = (options.substep != null && options.substep > 0) ? options.substep : 16;
		sim.snap = (options.snap != null) ? options.snap : 0;
		sim.smoothed = [for (k in 0...n) toNumber(Reflect.getProperty(instance, options.fields[k]))];
		sim.out = [for (_ in 0...n) 0.0];
		sim.valueOut = [for (_ in 0...n) 0.0];
		sim.offset = [for (_ in 0...n) 0.0];
		sim.outPrev = [for (_ in 0...n) 0.0];
		sim.frameVel = [for (_ in 0...n) 0.0];
		sim.copyFields = copyFields;
		this.simsByRef.set(refId, sim);

		// each reckoned field gets a RECKON slot (sample mirror + fallback)
		var offs: Array<Void -> Void> = [];
		for (f in options.fields) {
			offs.push(this.track(instance, f, { mode: "reckon" }));
		}
		return () -> {
			for (off in offs) { off(); }
			this.simsByRef.remove(refId);
		};
	}

	/** Per-instance forward-horizon override (the spawns store's lead reckon). */
	@:allow(io.colyseus.predict)
	private function bindForward(instance: Dynamic, forwardMs: Void -> Float) {
		var sim = this.simsByRef.get((instance : Schema).__refId);
		if (sim != null) { sim.forwardMs = forwardMs; }
	}

	public function untrack(instance: Dynamic, field: String) {
		var refId: Int = (instance : Schema).__refId;
		var perRef = this.slotsByRef.get(refId);
		if (perRef == null) { return; }
		var slot = perRef.get(field);
		if (slot != null) {
			if (slot.detach != null) { slot.detach(); }
			perRef.remove(field);
			if (!perRef.keys().hasNext()) { this.slotsByRef.remove(refId); }
		}
	}

	/** Stop tracking every field (and any reckon sim) of an instance. */
	public function detach(instance: Dynamic) {
		var refId: Int = (instance : Schema).__refId;
		var perRef = this.slotsByRef.get(refId);
		if (perRef != null) {
			for (slot in perRef) {
				if (slot.detach != null) { slot.detach(); }
			}
			this.slotsByRef.remove(refId);
		}
		this.simsByRef.remove(refId);
	}

	/**
	 * Attach prediction to every child of a root-level collection: wires
	 * onAdd -> track(fields) and onRemove -> detach. Returns a detacher.
	 */
	public function attachAll(collection: String, fields: Array<String>, ?options: PredictFieldOptions): Void -> Void {
		var tracked: Array<Dynamic> = [];
		var addOff = this.callbacks.onAdd(collection, (child, _key) -> {
			for (f in fields) { this.track(child, f, options); }
			tracked.push(child);
		});
		var removeOff = this.callbacks.onRemove(collection, (child, _key) -> {
			tracked.remove(child);
			this.detach(child);
		});
		return () -> {
			if (addOff != null) { addOff(); }
			if (removeOff != null) { removeOff(); }
			for (child in tracked) { this.detach(child); }
			tracked = [];
		};
	}

	// --- Factories --------------------------------------------------------

	/** Spawn a driven `Reconciler` (clock injected, fixed step adopted). */
	public function makeReconciler(instance: Schema, opts: ReconcilerOptions): Reconciler {
		if (opts.clock == null) { opts.clock = this.clock; }
		var recon = new Reconciler(instance, opts);
		this.adoptFixedStep(recon.stepMs);
		this.driven.push(recon);
		return recon;
	}

	/** Spawn a driven `PredictedEventChannel`. */
	public function defineEvent(opts: EventChannelOptions): PredictedEventChannel {
		var channel = new PredictedEventChannel(opts, this.clock);
		this.driven.push(channel);
		return channel;
	}

	/**
	 * Spawn a driven `PredictedSpawns` store wired to a root-level
	 * collection's add/remove stream.
	 */
	public function spawns(collection: String, opts: SpawnsOptions): PredictedSpawns {
		var store = new PredictedSpawns(opts, this.clock);
		var addOff = this.callbacks.onAdd(collection, (server, _key) -> store.handleAdd(server));
		var removeOff = this.callbacks.onRemove(collection, (server, _key) -> store.handleRemove(server));
		store.onDisposedInternal = () -> {
			if (addOff != null) { addOff(); }
			if (removeOff != null) { removeOff(); }
		};
		this.driven.push(store);
		return store;
	}

	private function adoptFixedStep(stepMs: Float) {
		if (this.fixedStepMs == null) {
			this.fixedStepMs = stepMs;
			this.stepAcc = 0;
			this.lastFrameNow = -1;
			return;
		}
		if (Math.abs(this.fixedStepMs - stepMs) > 1e-6) {
			trace("colyseus.predict: a reconciler's fixed step (" + stepMs + "ms) differs from "
				+ "this Predict's (" + this.fixedStepMs + "ms). tick() paces one rate; "
				+ "use a separate Predict per rate.");
		}
	}

	// --- Per-frame driver -------------------------------------------------

	/**
	 * Call once per render frame. Returns the SEND BUDGET: how many fixed
	 * input steps are due — send exactly that many inputs, then read render
	 * values. 0 until a reconciler advertises the step.
	 */
	public function tick(now: Float): Int {
		this.renderTime = now;

		var steps = 0;
		if (this.fixedStepMs != null && this.fixedStepMs > 0) {
			var dt = (this.lastFrameNow < 0) ? 0 : now - this.lastFrameNow;
			this.stepAcc += dt;
			steps = Math.floor(this.stepAcc / this.fixedStepMs);
			if (steps > MAX_STEPS_PER_FRAME) {
				// hitch: drop the backlog instead of bursting
				this.stepAcc = 0;
				steps = MAX_STEPS_PER_FRAME;
			} else {
				this.stepAcc -= steps * this.fixedStepMs;
			}
		}
		this.lastFrameNow = now;

		// drive children; compact the dead
		var i = this.driven.length - 1;
		while (i >= 0) {
			var child: Dynamic = this.driven[i];
			if (Std.isOfType(child, RollbackController)) {
				var ctrl: RollbackController = cast child;
				if (ctrl.dead) { this.driven.splice(i, 1); }
				else { ctrl.tick(now); }
			} else {
				var dc: DrivenChild = cast child;
				if (dc.dead) { this.driven.splice(i, 1); }
				else {
					dc.tick(now);
					dc.prune();
				}
			}
			i--;
		}
		return steps;
	}

	// --- Sample pipeline --------------------------------------------------

	private function onSample(slot: Slot, current: Float) {
		var now = (this.clock != null && this.clock.lastServerTime() > 0)
			? this.clock.lastServerTime()  // server-stamped, jitter-free
			: RoomClock.getNow();

		if (slot.angle) {
			// unwrap onto the previous sample over the shortest arc
			var previous = slot.v1;
			current = previous + Math.atan2(Math.sin(current - previous), Math.cos(current - previous));
		}

		var head = slot.ringHead;
		var count = slot.ringCount;

		// value-space teleport: clear history, pop (don't glide)
		if (slot.snap > 0 && count > 0 && Math.abs(current - slot.v1) > slot.snap) {
			head = 0;
			count = 0;
			slot.auxV = current;
		}

		var lastT1 = (count == 0)
			? Math.NEGATIVE_INFINITY
			: slot.ringT[(head == 0) ? RING_CAP - 1 : head - 1];

		// arrival-grid snap
		var snapT = now;
		if (slot.tickInterval > 0 && count > 0) {
			var elapsed = now - lastT1;
			var ticks = (elapsed > 0) ? Math.max(1, Math.ffloor(elapsed / slot.tickInterval + 0.5)) : 1;
			snapT = lastT1 + ticks * slot.tickInterval;
			var cap = now + slot.tickInterval;
			if (snapT > cap) { snapT = cap; }
		}

		slot.v1 = current;

		// idle-resume gap collapse: inject a synthetic held sample so lerp
		// resumes from "just before" instead of gliding across the idle gap
		if (count >= 2) {
			var h1 = (head == 0) ? RING_CAP - 1 : head - 1;
			var h2 = (h1 == 0) ? RING_CAP - 1 : h1 - 1;
			var lastInterval = lastT1 - slot.ringT[h2];
			var patchMs: Float = (this.clock != null) ? this.clock.patchInterval() : 0;
			var span = (patchMs > 0) ? patchMs : lastInterval;
			var trigger = (patchMs > 0) ? GAP_RESUME_PATCH_MULT * patchMs : GAP_RESUME_MULT * lastInterval;
			if (span > 0 && snapT - lastT1 > trigger) {
				var resumeSpan = (span < GAP_RESUME_MAX_MS) ? span : GAP_RESUME_MAX_MS;
				slot.ringT[head] = snapT - resumeSpan;
				slot.ringV[head] = slot.ringV[h1];
				head = (head + 1 >= RING_CAP) ? 0 : head + 1;
				if (count < RING_CAP) { count++; }
			}
		}

		slot.ringT[head] = snapT;
		slot.ringV[head] = current;
		slot.ringHead = (head + 1 >= RING_CAP) ? 0 : head + 1;
		slot.ringCount = (count < RING_CAP) ? count + 1 : count;
	}

	// --- Reads ------------------------------------------------------------

	/** Smoothed/predicted RENDER value with raw instance fallback. */
	public function value(instance: Dynamic, field: String): Float {
		var perRef = this.slotsByRef.get((instance : Schema).__refId);
		var slot = (perRef != null) ? perRef.get(field) : null;
		if (slot == null) { return toNumber(Reflect.getProperty(instance, field)); }
		return switch (slot.mode) {
			case "lerp": this.computeLerp(slot);
			case "damped": this.computeDamped(slot);
			case "extrapolate": this.computeExtrapolate(slot);
			case "reckon": this.computeReckon(slot);
			default: slot.v1; // raw
		}
	}

	/**
	 * RAW reckoned value at an arbitrary server-time instant (no smoothing
	 * offset) — for game logic / lag-comp hit tests. Reckons forward from the
	 * latest snapshot; the past clamps to it.
	 */
	public function valueAt(instance: Dynamic, field: String, time: Float): Float {
		var perRef = this.slotsByRef.get((instance : Schema).__refId);
		var slot = (perRef != null) ? perRef.get(field) : null;
		if (slot == null || slot.mode != "reckon") {
			return this.value(instance, field);
		}
		var sim = this.simsByRef.get((instance : Schema).__refId);
		if (sim != null) {
			var pos = sim.fields.indexOf(field);
			if (pos >= 0) {
				var baseT: Float = (this.clock != null) ? this.clock.lastServerTime() : Math.NaN;
				var forward = Math.isNaN(baseT) ? 0 : Math.max(0, time - baseT);
				this.advance(sim, forward, sim.valueOut, time);
				return sim.valueOut[pos];
			}
		}
		return slot.v1;
	}

	// --- Mode computers ---------------------------------------------------

	private function computeDamped(slot: Slot): Float {
		var now = this.renderTime;
		var dtFrame = now - slot.auxT;
		slot.auxT = now;
		if (dtFrame > 0) {
			var k = 1 - Math.exp(-slot.damping * dtFrame / 1000);
			slot.auxV += (slot.v1 - slot.auxV) * k;
		}
		return slot.auxV;
	}

	private function computeLerp(slot: Slot): Float {
		var count = slot.ringCount;
		if (count == 0) { return slot.v1; }
		var head = slot.ringHead;
		var start = (head - count + RING_CAP) % RING_CAP;
		var newest = (start + count - 1) % RING_CAP;
		if (count == 1) { return slot.ringV[newest]; }

		var target = (this.clock != null && this.clock.lastServerTime() > 0)
			? this.clock.serverNow() - slot.delay - this.clock.smoothedRtt() / 2
			: this.renderTime - slot.delay;

		// hold at the ends — NEVER extrapolate
		if (target <= slot.ringT[start]) { return slot.ringV[start]; }
		if (target >= slot.ringT[newest]) { return slot.ringV[newest]; }

		// walk back to the bracketing pair
		var k = count - 2;
		var phys = (start + k) % RING_CAP;
		while (k > 0) {
			if (slot.ringT[phys] <= target) { break; }
			k--;
			phys = (phys == 0) ? RING_CAP - 1 : phys - 1;
		}
		var b = (phys + 1 >= RING_CAP) ? 0 : phys + 1;
		var tA = slot.ringT[phys];
		var tB = slot.ringT[b];
		var span = tB - tA;
		if (span <= 0) { return slot.ringV[b]; }
		var u = (target - tA) / span;
		return slot.ringV[phys] + (slot.ringV[b] - slot.ringV[phys]) * u;
	}

	private function computeExtrapolate(slot: Slot): Float {
		var count = slot.ringCount;
		if (count == 0) { return slot.v1; }
		var head = slot.ringHead;
		var start = (head - count + RING_CAP) % RING_CAP;
		var newest = (start + count - 1) % RING_CAP;
		var newestT = slot.ringT[newest];
		var newestV = slot.ringV[newest];
		var now = this.renderTime;

		var raw: Float;
		if (count == 1) {
			raw = newestV;
		} else {
			// 2-step lookback flattens single-sample noise
			var steps = (count >= 3) ? 2 : 1;
			var lb = (start + count - 1 - steps + RING_CAP) % RING_CAP;
			var dt = newestT - slot.ringT[lb];
			if (dt <= 0) {
				raw = newestV;
			} else {
				var slope = (newestV - slot.ringV[lb]) / dt;
				var ahead = now - newestT;
				if (ahead < 0) { ahead = 0; }
				else if (ahead > slot.maxExtrapolate) { ahead = slot.maxExtrapolate; }
				raw = newestV + slope * ahead;
			}
		}

		var lastT = slot.auxT;
		slot.auxT = now;
		if (slot.damping <= 0) {
			slot.auxV = raw;
			return raw;
		}
		var dtFrame = now - lastT;
		if (dtFrame > 0) {
			var k = 1 - Math.exp(-slot.damping * dtFrame / 1000);
			slot.auxV += (raw - slot.auxV) * k;
		}
		return slot.auxV;
	}

	private function computeReckon(slot: Slot): Float {
		var sim = this.simsByRef.get((slot.instance : Schema).__refId);
		if (sim != null) {
			var pos = sim.fields.indexOf(slot.field);
			if (pos >= 0) {
				this.applySimulation(sim);
				return sim.smoothed[pos];
			}
		}
		return slot.v1;
	}

	/** Forward-sim the scratch instance from the latest snapshot by forwardMs. */
	private function advance(sim: SimState, forwardMs: Float, output: Array<Float>, endElapsed: Float) {
		for (f in sim.copyFields) {
			Reflect.setProperty(sim.scratch, f, Reflect.getProperty(sim.instance, f));
		}
		var remaining = forwardMs;
		var elapsed = endElapsed - forwardMs;
		while (remaining > 0) {
			var stepMs = (remaining < sim.substep) ? remaining : sim.substep;
			elapsed += stepMs;
			sim.step(sim.scratch, stepMs / 1000, elapsed);
			remaining -= stepMs;
		}
		for (k in 0...sim.fields.length) {
			output[k] = toNumber(Reflect.getProperty(sim.scratch, sim.fields[k]));
		}
	}

	/** Once per frame per instance: advance + offset-decay smoothing. */
	private function applySimulation(sim: SimState) {
		var now = this.renderTime;
		if (sim.lastApplyTime == now) { return; }

		var n = sim.fields.length;
		var baseT: Float = (this.clock != null) ? this.clock.lastServerTime() : Math.NaN;
		var present: Float = (this.clock != null) ? this.clock.serverNow() : 0;
		var forward: Float;
		if (sim.forwardMs != null) {
			forward = sim.forwardMs();
		} else if (!Math.isNaN(baseT) && baseT > 0) {
			forward = Math.max(0, present - baseT);
		} else {
			forward = 0;
		}
		this.advance(sim, forward, sim.out, present);

		var first = sim.lastApplyTime == Math.NEGATIVE_INFINITY;
		if (first || sim.smoothing <= 0) {
			for (k in 0...n) {
				sim.offset[k] = 0;
				sim.smoothed[k] = sim.out[k];
			}
		} else if (!Math.isNaN(baseT)) {
			var dtMs = Math.max(0, Math.min(now - sim.lastApplyTime, 100));
			if (baseT != sim.lastBaseT && !Math.isNaN(sim.lastBaseT)) {
				// rebase: subtract EXPECTED motion so steady travel doesn't read as error
				for (k in 0...n) {
					var d = sim.smoothed[k] + sim.frameVel[k] * dtMs - sim.out[k];
					sim.offset[k] = (sim.snap > 0 && Math.abs(d) > sim.snap) ? 0 : d;
				}
			} else if (dtMs > 0) {
				for (k in 0...n) {
					sim.frameVel[k] = (sim.out[k] - sim.outPrev[k]) / dtMs;
				}
			}
			var decay = Math.exp(-sim.smoothing * dtMs / 1000);
			for (k in 0...n) {
				sim.offset[k] *= decay;
				sim.smoothed[k] = sim.out[k] + sim.offset[k];
			}
		} else {
			// no clock — plain EMA chase
			var dtMs = Math.max(0, Math.min(now - sim.lastApplyTime, 100));
			var k2 = 1 - Math.exp(-sim.smoothing * dtMs / 1000);
			for (k in 0...n) {
				sim.smoothed[k] += (sim.out[k] - sim.smoothed[k]) * k2;
			}
		}
		for (k in 0...n) { sim.outPrev[k] = sim.out[k]; }
		sim.lastBaseT = baseT;
		sim.lastApplyTime = now;
	}
}
