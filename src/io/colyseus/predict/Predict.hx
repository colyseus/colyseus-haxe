package io.colyseus.predict;

import io.colyseus.Room;
import io.colyseus.RoomClock;
import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.predict.Reconciler;
import io.colyseus.predict.PredictedEventChannel;
import io.colyseus.predict.PredictedSpawns;
import io.colyseus.predict.SimReconciler.SimReconcilerOptions;

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
	/** Output-smoothing time constant, in milliseconds. 0 = off (snap / raw
	    projection / exact interpolation). Roughly the extra display lag the
	    smoothing adds: a steady mover trails its target by ≈ speed × smoothMs;
	    corrections fade ~63% per smoothMs, ~95% by 3×. Damped uses it as the
	    chase rate toward the latest value, extrapolate as its
	    predict-then-smooth blend, and lerp as an optional DISPLAY-ONLY output
	    spring on the interpolated result. Null = the mode default: 50 on
	    damped/extrapolate, 0 on lerp (spring off — exact interpolation). */
	@:optional var smoothMs: Null<Float>;
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
	/** Predict-then-smooth time constant (ms) — see
	    `PredictFieldOptions.smoothMs`. Default 50. 0 = raw projection. */
	@:optional var smoothMs: Null<Float>;
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
	/** Null = unset — the mode default resolves at the read site. */
	public var smoothMs: Null<Float>;
	public var maxExtrapolate: Float;
	public var tickInterval: Float;
	public var snap: Float;
	public var angle: Bool;
	public var v1: Float = 0;
	public var auxV: Float = 0;
	public var auxT: Float = 0;
	/** Previous frame's RAW lerp output — the target slope for the output spring's FOH step. */
	public var lerpPrev: Float = 0;
	public var ringT: Array<Float>;
	public var ringV: Array<Float>;
	public var ringHead: Int = 0;
	public var ringCount: Int = 0;
	public var detach: Void -> Void;
	/** mode "bound" only: the controller owning this field, and its pose key. */
	public var ctrl: RollbackController;
	public var poseKey: String;
	/** mode "bound" only: the passive slot displaced here, restored on dispose. */
	public var stash: Slot;
	public function new() {}
}

private class SimState {
	public var instance: Dynamic;
	public var scratch: Dynamic;
	public var fields: Array<String>;
	public var step: (Dynamic, Float, Float) -> Void;
	public var smoothMs: Float;
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
	/** smoothMs fallback for damped/extrapolate (lerp's spring defaults 0). */
	private static inline var DEFAULT_SMOOTH_MS = 50.0;

	private var callbacks: PredictCallbacks;
	private var clock: RoomClock;
	private var renderTime: Float = 0;
	// refId -> field -> slot
	private var slotsByRef: Map<Int, Map<String, Slot>> = new Map();
	private var simsByRef: Map<Int, SimState> = new Map();
	private var driven: Array<Dynamic> = [];
	// Every attachAll* detacher, so dispose can unhook what the caller never held.
	private var attachments: Array<Void -> Void> = [];

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
	/**
	 * The one-liner every caller wants: a Predict over a room's callbacks and
	 * clock — the same two collaborators every time, and no decision the caller
	 * is better placed to make.
	 *
	 * Uses the IMMEDIATE callbacks flavour (`new SchemaCallbacks(decoder)`)
	 * rather than `Callbacks.get(room)`. The latter defers onto Heaps' MainLoop,
	 * which never drains on a headless sys target — prediction would then see no
	 * callbacks at all, and silently, since nothing errors. Prediction is driven
	 * from the caller's own `tick`, so deferring buys it nothing anyway.
	 */
	public static function get<T>(room: Room<T>): Predict {
		var serializer: SchemaSerializer<T> = cast room.serializer;
		return create(new SchemaCallbacks<T>(serializer.decoder), room.clock);
	}

	public static function create(callbacks: Dynamic, clock: RoomClock): Predict {
		return new Predict({
			listen: (instance, field, handler, immediate) -> {
				var off: Dynamic = callbacks.listen(instance, field,
					(value: Dynamic, _previous: Dynamic) -> handler(value), immediate);
				return () -> { off(); };
			},
			// neko Dynamic dispatch needs EXACT argument counts — pass every
			// optional parameter explicitly
			onAdd: (collection, handler) -> {
				var off: Dynamic = callbacks.onAdd(collection,
					(value: Dynamic, key: Dynamic) -> handler(value, key), null, null);
				return () -> { off(); };
			},
			onRemove: (collection, handler) -> {
				var off: Dynamic = callbacks.onRemove(collection,
					(value: Dynamic, key: Dynamic) -> handler(value, key), null);
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

	/**
	 * Track one numeric field for smoothing. Returns an untrack function.
	 * Internal primitive under `attach` — PORTING.md strips track/untrack/
	 * trackStepped from the published surface.
	 */
	@:noCompletion
	private function track(instance: Dynamic, field: String, ?options: PredictFieldOptions): Void -> Void {
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
		slot.smoothMs = (options != null) ? options.smoothMs : null;
		slot.maxExtrapolate = (options != null && options.maxExtrapolate != null) ? options.maxExtrapolate : 200;
		slot.tickInterval = (options != null && options.tickInterval != null) ? options.tickInterval : 0;
		slot.snap = (options != null && options.snap != null) ? options.snap : 0;
		slot.angle = (options != null && options.angle != null) ? options.angle : false;
		var initial = toNumber(Reflect.getProperty(instance, field));
		slot.v1 = initial;
		slot.auxV = initial;
		slot.lerpPrev = initial;
		slot.auxT = RoomClock.getNow();
		slot.ringT = [for (_ in 0...RING_CAP) 0.0];
		slot.ringV = [for (_ in 0...RING_CAP) 0.0];
		perRef.set(field, slot);

		slot.detach = this.callbacks.listen(instance, field,
			(current: Dynamic) -> this.onSample(slot, toNumber(current)), true);
		return () -> this.untrack(instance, field);
	}

	/** Dead-reckon fields of an instance with a step SHARED with the server. */
	@:noCompletion
	private function trackStepped(instance: Dynamic, options: ReckonOptions): Void -> Void {
		var refId: Int = (instance : Schema).__refId;
		var schema: Schema = cast instance;
		var scratch: Dynamic = Type.createInstance(Type.getClass(instance), []);
		var copyFields: Array<String> = [];
		var i = 0;
		while (schema._indexes.exists(i)) {
			var t = schema._types.get(i);
			// Every primitive, strings included: the scratch is documented as a
			// FULL copy of the entity so the shared step can read descriptors it
			// never attached (a bot's `kind`). Dropping strings makes step
			// functions that branch on one silently take the default branch — and
			// an attach-all reckon gives the caller no live instance to fall back on.
			if (t != "ref" && t != "array" && t != "map") {
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
		sim.smoothMs = (options.smoothMs != null) ? options.smoothMs : DEFAULT_SMOOTH_MS;
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
	 * Attach prediction to ONE instance from a declarative config. Returns a
	 * detacher.
	 *
	 * Two shapes, mirroring the reference:
	 *
	 * ```haxe
	 * // per-field smoothing; each field picks its own mode
	 * predict.attach(boss, { x: "lerp", yaw: { mode: "damped", angle: true } });
	 *
	 * // dead reckoning, one step shared with the server across `fields`
	 * predict.attach(bot, { mode: "reckon", fields: ["x", "y"], step: patrol });
	 * ```
	 *
	 * `Dynamic` because the config is a union the type system can't spell here:
	 * a per-field map whose values are either a mode string or a full
	 * `PredictFieldOptions`, or the reckon shape.
	 *
	 * Fields the instance's schema doesn't declare are DROPPED, not an error:
	 * one config can cover a heterogeneous collection, and a field that isn't
	 * there would otherwise subscribe to nothing (or read garbage from the
	 * reckon scratch).
	 */
	public function attach(instance: Dynamic, config: Dynamic): Void -> Void {
		if (Reflect.field(config, "mode") == "reckon") {
			return this.trackStepped(instance, config);
		}
		var offs: Array<Void -> Void> = [];
		for (field in Reflect.fields(config)) {
			if (Reflect.getProperty(instance, field) == null) { continue; }
			var spec: Dynamic = Reflect.field(config, field);
			var opts: PredictFieldOptions =
				Std.isOfType(spec, String) ? { mode: cast spec } : cast spec;
			offs.push(this.track(instance, field, opts));
		}
		return () -> { for (off in offs) off(); };
	}

	/**
	 * Attach prediction to every child of a root-level collection: wires
	 * onAdd -> attach(child, config) and onRemove -> detach. Same config shapes
	 * as `attach`, reckon included — there is no separate reckon flavour.
	 */
	public function attachAll(collection: String, config: Dynamic): Void -> Void {
		return this.attachEach(collection, (child) -> { this.attach(child, config); });
	}

	/** Shared add/remove wiring behind the attach-all path. */
	private function attachEach(collection: String, attach: Dynamic -> Void): Void -> Void {
		var tracked: Array<Dynamic> = [];
		var addOff = this.callbacks.onAdd(collection, (child, _key) -> {
			attach(child);
			tracked.push(child);
		});
		var removeOff = this.callbacks.onRemove(collection, (child, _key) -> {
			tracked.remove(child);
			this.detach(child);
		});
		var off = () -> {
			if (addOff != null) { addOff(); }
			if (removeOff != null) { removeOff(); }
			for (child in tracked) { this.detach(child); }
			tracked = [];
		};
		this.attachments.push(off);
		return off;
	}

	/**
	 * Release everything this Predict registered: tracked fields, reckon sims,
	 * attachAll wiring, and every driven child.
	 *
	 * This matters more than it looks. Callbacks live on the ROOM, so a Predict
	 * that outlives its owner keeps firing handlers into freed state — attach and
	 * detach are not symmetric unless someone closes the loop, and the attachAll
	 * detachers are held here, not by the caller. This is that loop; call it when
	 * the screen using this goes away.
	 */
	public function dispose(): Void {
		for (off in this.attachments) { off(); }
		this.attachments = [];
		for (perRef in this.slotsByRef) {
			for (slot in perRef) { if (slot.detach != null) { slot.detach(); } }
		}
		this.slotsByRef = new Map();
		this.simsByRef = new Map();
		for (child in this.driven) {
			var d: Dynamic = child;
			d.dispose();
		}
		this.driven = [];
		this.fixedStepMs = null;
	}

	// --- Factories --------------------------------------------------------

	/** Spawn a driven `Reconciler` (clock injected, fixed step adopted). */
	public function reconciler(instance: Schema, opts: ReconcilerOptions): Reconciler {
		if (opts.clock == null) { opts.clock = this.clock; }
		this.bindRenderDelay(opts.input);
		var recon = new Reconciler(instance, opts);
		this.adoptFixedStep(recon.stepMs);
		this.installBoundOverlay(recon);
		this.driven.push(recon);
		return recon;
	}

	/**
	 * Route `value(instance, field)` at every field a controller predicts, so ONE
	 * read idiom covers the whole render layer: passively-smoothed remotes and
	 * controller-owned entities alike, with the caller never naming a pose key.
	 *
	 * Any passive slot already on that field is STASHED, not dropped — its
	 * listener keeps sampling, and dispose() puts it back.
	 */
	private function installBoundOverlay(ctrl: RollbackController): Void {
		var regs = ctrl.boundRegistrations();
		if (regs.length == 0) { return; }
		var touched: Array<{ perRef: Map<String, Slot>, field: String }> = [];
		for (reg in regs) {
			if (reg.source == null) { continue; }
			var refId = (reg.source : Schema).__refId;
			var perRef = this.slotsByRef.get(refId);
			if (perRef == null) {
				perRef = new Map();
				this.slotsByRef.set(refId, perRef);
			}
			for (k in 0...reg.fields.length) {
				var field = reg.fields[k];
				var stash = perRef.get(field);
				if (stash != null && stash.mode == "bound") {
					trace('colyseus.predict: "$field" is already bound to a controller — '
						+ "the newer registration wins.");
					stash = stash.stash;
				}
				var slot = new Slot();
				slot.field = field;
				slot.instance = reg.source;
				slot.mode = "bound";
				slot.ctrl = ctrl;
				slot.poseKey = reg.poseKeys[k];
				slot.stash = stash;
				perRef.set(field, slot);
				touched.push({ perRef: perRef, field: field });
			}
		}
		ctrl.onDisposed(() -> {
			for (t in touched) {
				var slot = t.perRef.get(t.field);
				if (slot != null && slot.mode == "bound") {
					if (slot.stash != null) { t.perRef.set(t.field, slot.stash); }
					else { t.perRef.remove(t.field); }
				}
			}
		});
	}

	/**
	 * Tell the input handle how far in the past this client draws, taken from
	 * the lerp delay already attached here.
	 *
	 * Worth doing automatically because the failure is silent and expensive: a
	 * lag-compensating server rewinds to `serverNow - (renderDelay + rtt/2)`, so
	 * leaving renderDelay at zero makes every rewound read land one full
	 * render-delay early, and shots miss by exactly that much with nothing in the
	 * logs to say so. An explicit `renderDelay` on `room.input()` still wins.
	 */
	private function bindRenderDelay(input: Dynamic): Void {
		if (input == null || input.renderDelay() > 0) { return; }
		for (perRef in this.slotsByRef) {
			for (slot in perRef) {
				if (slot.mode == "lerp" && slot.delay > 0) {
					input.setRenderDelay(slot.delay);
					return;
				}
			}
		}
	}

	/**
	 * Spawn a driven `SimReconciler` — the composite face, for a world of parts
	 * rather than one entity's fields.
	 */
	public function sim<W, I>(opts: SimReconcilerOptions<W, I>): SimReconciler<W, I> {
		if (opts.clock == null) { opts.clock = this.clock; }
		this.bindRenderDelay(opts.input);
		var recon = new SimReconciler<W, I>(opts);
		this.adoptFixedStep(recon.stepMs);
		this.installBoundOverlay(recon);
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
	 *
	 * With `fields`, the store also owns the collection's MOTION (no separate
	 * `attachAll` needed): confirmed entities are dead-reckoned with the same
	 * `step` that advances pending locals, and `store.value(entry, field)` is
	 * one read path across the whole life of the entity.
	 */
	public function spawns(collection: String, opts: SpawnsOptions): PredictedSpawns {
		var store = new PredictedSpawns(opts, this.clock);

		// Reckon wiring (`fields` + `step`): every confirmed entity gets a
		// reckon attach whose horizon is snapshot age PLUS the entry's measured
		// input lead — 0 for a foreign entity (server-present, same as an
		// attachAll reckon), the exact per-spawn uplink for an owned one (see
		// spawnTime). An owned projectile thus keeps flying the shooter's
		// timeline through the handoff.
		var reckon = (opts != null && opts.fields != null && opts.step != null);
		// keyed by refId, like simsByRef — Dynamic is not a valid Map key here
		var untrack: Map<Int, Void -> Void> = reckon ? new Map() : null;
		var clock = this.clock;
		var step = reckon ? opts.step : null;

		var addOff = this.callbacks.onAdd(collection, (server, _key) -> {
			store.handleAdd(server);
			if (!reckon || untrack.exists((server : Schema).__refId)) { return; } // decoder re-fire
			// AFTER handleAdd: the lead is only measured once the entry collapses.
			var entry = store.entryFor(server);
			var lead = (entry != null) ? entry.leadMs : 0.0;
			var off = this.trackStepped(server, {
				fields: opts.fields,
				step: (scratch, dt, _elapsed) -> step(scratch, dt),
				// 0, not the reckon default 50: a deterministic constant-step
				// projectile rebases exactly, so smoothing only adds lag.
				smoothMs: (opts.smoothMs != null) ? opts.smoothMs : 0,
				substep: opts.substep,
			});
			this.bindForward(server, () -> {
				if (clock == null) { return Math.max(0, lead); }
				var stamp = clock.lastServerTime();
				var age = (stamp > 0) ? Math.max(0, clock.serverNow() - stamp) : 0;
				return Math.max(0, age + lead);
			});
			untrack.set((server : Schema).__refId, off);
		});

		var removeOff = this.callbacks.onRemove(collection, (server, _key) -> {
			if (untrack != null) {
				var refId = (server : Schema).__refId;
				var off = untrack.get(refId);
				if (off != null) { off(); }
				untrack.remove(refId);
			}
			store.handleRemove(server);
		});

		if (reckon) {
			// route store.value() confirmed reads through the reckon slots
			store.bindReader((server, field) -> this.value(server, field));
		}

		store.onDisposedInternal = () -> {
			if (addOff != null) { addOff(); }
			if (removeOff != null) { removeOff(); }
			if (untrack != null) {
				for (off in untrack) { off(); }
				untrack.clear();
			}
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
	 *
	 * `now` is a monotonic ms reading; omit it to read the SDK clock, which is
	 * what the JS reference does with its `performance.now()` default. Omitting
	 * it keeps the caller off a platform clock of its own.
	 */
	public function tick(?now: Float): Int {
		if (now == null) { now = RoomClock.getNow(); }
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
			slot.lerpPrev = current;   // lerp's output spring pops too
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
			// Controller-owned: a reconciler claimed this field, so the pose comes
			// from its rollback rather than a smoothing curve over the server stream.
			case "bound": slot.ctrl.value(slot.poseKey);
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
			var tau: Float = (slot.smoothMs != null) ? slot.smoothMs : DEFAULT_SMOOTH_MS;
			var k = (tau > 0) ? 1 - Math.exp(-dtFrame / tau) : 1;   // 0 = snap
			slot.auxV += (slot.v1 - slot.auxV) * k;
		}
		return slot.auxV;
	}

	private function computeLerp(slot: Slot): Float {
		var raw = this.computeLerpRaw(slot);
		var tau: Float = (slot.smoothMs != null) ? slot.smoothMs : 0;   // lerp's output spring defaults OFF
		var now = this.renderTime;
		if (tau <= 0) {
			// Spring off (the default) — pin the state to the raw output so a
			// runtime smoothMs enable starts from here instead of gliding in
			// from wherever the spring last rested.
			slot.auxV = raw;
			slot.lerpPrev = raw;
			slot.auxT = now;
			return raw;
		}
		var dt = now - slot.auxT;
		if (dt <= 0) { return slot.auxV; }   // same-frame re-read
		// Exact first-order-hold step for a linearly-varying target (τ = smoothMs):
		//   y(dt) = u1 − s·τ + (y0 − u0 + s·τ)·e^(−dt/τ),  s = (u1 − u0)/dt
		// Frame-rate independent: a steady mover renders with a constant s·τ
		// trail at any fps (a per-frame EMA's trail varies with frame rate).
		var u0 = slot.lerpPrev;
		var y0 = slot.auxV;
		var kdt = dt / tau;
		var trail = (raw - u0) / kdt;
		var y = raw - trail + (y0 - u0 + trail) * Math.exp(-kdt);
		slot.auxV = y;
		slot.lerpPrev = raw;
		slot.auxT = now;
		return y;
	}

	/** The undamped interpolant — `computeLerp` minus the output spring. */
	private function computeLerpRaw(slot: Slot): Float {
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
		var tau: Float = (slot.smoothMs != null) ? slot.smoothMs : DEFAULT_SMOOTH_MS;
		if (tau <= 0) {
			slot.auxV = raw;
			return raw;
		}
		var dtFrame = now - lastT;
		if (dtFrame > 0) {
			var k = 1 - Math.exp(-dtFrame / tau);
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
		if (first || sim.smoothMs <= 0) {
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
			var decay = Math.exp(-dtMs / sim.smoothMs);
			for (k in 0...n) {
				sim.offset[k] *= decay;
				sim.smoothed[k] = sim.out[k] + sim.offset[k];
			}
		} else {
			// no clock — plain EMA chase
			var dtMs = Math.max(0, Math.min(now - sim.lastApplyTime, 100));
			var k2 = 1 - Math.exp(-dtMs / sim.smoothMs);
			for (k in 0...n) {
				sim.smoothed[k] += (sim.out[k] - sim.smoothed[k]) * k2;
			}
		}
		for (k in 0...n) { sim.outPrev[k] = sim.out[k]; }
		sim.lastBaseT = baseT;
		sim.lastApplyTime = now;
	}
}
