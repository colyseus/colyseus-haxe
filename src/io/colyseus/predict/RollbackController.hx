package io.colyseus.predict;

import io.colyseus.InputHandle;
import io.colyseus.RoomClock;

/**
 * Minimal shape `StepContext.predict` emits into — implemented by
 * `PredictedEventChannel`.
 */
interface PredictSink {
	function predictFromSim(seq: Int, payload: Dynamic, acked: Void -> Int): Void;
}

/**
 * One controller-owned instance and the pose keys its numeric fields map to.
 * `fields[i]` is read back as `poseKeys[i]` — the two differ only on the
 * composite face, where a key is "<worldKey>.<field>".
 */
typedef BoundRegistration = {
	var source: Dynamic;
	var fields: Array<String>;
	var poseKeys: Array<String>;
};

/**
 * Per-step context handed to a reconciler's step (port of
 * `predict/rollback.ts` StepContext). One fixed dt drives both sides of the
 * rollback. The instance is REUSED across steps.
 */
class StepContext {
	/** Fixed step in SECONDS (1/tickRate). */
	public var dt: Float;
	/** Fixed step in MILLISECONDS. */
	public var dtMs: Float;
	/** The input's seq — the index of the step being simulated. */
	public var tick: Int = 0;
	/** Physics sub-steps per fixed step (>= 1). */
	public var subSteps: Int = 1;
	public var subDt: Float;
	public var subDtMs: Float;
	/**
	 * True while re-simulating an already-applied input during rollback —
	 * one-shot presentation must branch on this.
	 */
	public var isReplay: Bool = false;
	/**
	 * The input's reckon instant (server-clock ms): the per-seq lag-comp
	 * stamp when present (replay-deterministic), else the live serverNow().
	 */
	public var reckonTime: Float = 0;
	public var lagCompActive: Bool = false;

	@:allow(io.colyseus.predict.RollbackController)
	private var owner: RollbackController;

	@:allow(io.colyseus.predict.RollbackController)
	private function new() {}

	/**
	 * Memoize a VALUE on the rollback timeline that replay can't re-derive:
	 * computed ONCE on the live step for this seq, frozen, and returned
	 * WITHOUT re-running on every replay. Returns null when the live step
	 * memoized nothing. `memo(compute)` uses the shared key-less slot;
	 * `memo(key, compute)` disambiguates multiple memos per step.
	 */
	public function memo(keyOrCompute: Dynamic, ?compute: Void -> Dynamic): Dynamic {
		var key: String = "";
		if (compute == null) {
			compute = keyOrCompute;
		} else {
			key = keyOrCompute;
		}
		return this.owner.memoRun(key, this.isReplay, this.tick, compute);
	}

	/**
	 * Declare an optimistic discrete EVENT the timeline just produced into an
	 * event channel — fires only on the LIVE step (silently skipped on every
	 * rollback replay).
	 */
	public function predict(sink: PredictSink, payload: Dynamic) {
		if (!this.isReplay) {
			sink.predictFromSim(this.tick, payload, this.owner.ackWatermark);
		}
	}
}

/** Options shared by every rollback controller. */
typedef RollbackOptions = {
	var input: InputHandle<Dynamic>;
	/** Resolves reckonTime's unstamped fallback (serverNow). */
	@:optional var clock: RoomClock;
	/** Error-decay time constant (ms); 0 = hard snap; null = the server's
	    correction cadence (one patch interval) else 50. */
	@:optional var smoothMs: Null<Float>;
	/** Teleport threshold — corrections beyond it POP. 0 = off. */
	@:optional var snap: Null<Float>;
	@:optional var stepMs: Null<Float>;
	@:optional var stepSeconds: Null<Float>;
	@:optional var subSteps: Null<Int>;
	@:optional var onReconcile: Int -> Void;
	/** Divergence-warning tolerance; null = off. */
	@:optional var warnOnDivergence: Null<Float>;
}

/**
 * Shared rollback engine (port of the JS SDK's `predict/rollback.ts`) — a
 * pure OBSERVER of an input handle: you mutate + send through the handle;
 * the controller steps each send eagerly, polls the server ack in `tick()`
 * and rewinds-to-truth + replays on new acks, absorbing mispredictions into
 * per-field visual offsets that decay.
 *
 * Subclass hooks: `smoothedFields`, `readCurrent`, `adoptTruth`,
 * `applyStep`, `snapshotPrev`, `reseedState`, `truthMatchesAt` (default
 * false), `refreshRender` (no-op), `markDirty` (no-op).
 */
class RollbackController {
	/**
	 * Rendered pose for one key. Overridden by both faces — `Reconciler` keys by
	 * schema field, `SimReconciler` by "<worldKey>.<field>". Declared here so the
	 * bound overlay can read a pose without knowing which face it holds.
	 */
	public function value(key: String): Float { return Math.NaN; }

	/**
	 * What `Predict.value(instance, field)` needs to reach this controller's
	 * poses: the ORIGINAL decoded instance per bound entry (not the mirror), its
	 * numeric fields, and the pose key each maps to. Empty when nothing is bound.
	 */
	public function boundRegistrations(): Array<BoundRegistration> { return []; }

	/** Per-numeric-field correction injected by the most recent reconcile. */
	public var lastCorrection(default, null): Map<String, Float> = new Map();
	/** Max |lastCorrection| across fields. */
	public var lastCorrectionMag(default, null): Float = 0;
	/** Increments once per reconcile. */
	public var reconcileSeq(default, null): Int = 0;
	/** Rolling reconcile drift. */
	public var drift(default, null): Drift = new Drift();
	/** Set by `dispose()`. */
	public var dead(default, null): Bool = false;
	/** The fixed simulation step (ms) this controller predicts at. */
	public var stepMs(default, null): Float;
	/** Number of unacknowledged inputs currently buffered. */
	public var pendingCount(get, never): Int;
	function get_pendingCount() return this.input.pendingCount;

	private var error: Map<String, Float> = new Map();
	private var prev: Map<String, Float> = new Map();
	private var renderedBefore: Map<String, Float> = new Map();

	private var lastTick: Float = -1;
	private var lastAcked: Int;
	private var lastEpoch: Int;
	private var replayFrom: Int = 0;
	private var predictedSeq: Int;
	private var catching: Bool = false;
	private var unsubscribeSend: Void -> Void;
	private var renderAcc: Float = 0;

	private var stepCtx: StepContext;
	@:allow(io.colyseus.predict.StepContext)
	private var ackWatermark: Void -> Int;
	// per-seq memo store: seq -> (key -> value)
	private var memos: Map<Int, Map<String, Dynamic>> = new Map();

	private var smoothMs: Float;
	private var snapThreshold: Float;
	private var input: InputHandle<Dynamic>;
	private var onReconcileHook: Int -> Void;
	private var warnTolerance: Null<Float>;
	private var clock: RoomClock;

	private var disposedHooks: Array<Void -> Void> = [];

	private function new(opts: RollbackOptions) {
		if (opts.input == null) { throw "RollbackController: input handle required"; }
		this.input = opts.input;
		this.clock = opts.clock;
		this.smoothMs = (opts.smoothMs != null)
			? opts.smoothMs
			: ((this.input.patchRate != null && this.input.patchRate > 0) ? this.input.patchRate : 50);
		this.snapThreshold = (opts.snap != null) ? opts.snap : 0;

		var stepMs: Null<Float> = (opts.stepMs != null) ? opts.stepMs : this.input.stepMs;
		if (stepMs == null && opts.stepSeconds != null) { stepMs = opts.stepSeconds * 1000; }
		if (stepMs == null) {
			throw "reconciler: fixed simulation step is unknown. The server room must call "
				+ "setFixedTimestep() (or setTimestep()), or pass stepMs/stepSeconds explicitly — "
				+ "a wrong dt silently diverges rollback-replay.";
		}
		this.stepMs = stepMs;

		var dt: Float = (opts.stepSeconds != null) ? opts.stepSeconds
			: ((this.input.stepSeconds != null) ? this.input.stepSeconds : stepMs / 1000);
		var subSteps: Int = (opts.subSteps != null) ? opts.subSteps : this.input.subSteps;
		if (subSteps < 1) { subSteps = 1; }

		this.stepCtx = new StepContext();
		this.stepCtx.dt = dt;
		this.stepCtx.dtMs = stepMs;
		this.stepCtx.subSteps = subSteps;
		this.stepCtx.subDt = dt / subSteps;
		this.stepCtx.subDtMs = stepMs / subSteps;
		this.stepCtx.owner = this;

		this.onReconcileHook = opts.onReconcile;
		this.warnTolerance = opts.warnOnDivergence;
		this.ackWatermark = () -> this.input.lastProcessed;
		this.lastAcked = this.input.lastProcessed;
		this.lastEpoch = this.input.epoch;
		this.predictedSeq = this.input.sentCount; // pre-existing sends are NOT predicted
		this.unsubscribeSend = this.input.onSend((_seq) -> this.catchUp());
	}

	@:allow(io.colyseus.predict.StepContext)
	private function memoRun(key: String, isReplay: Bool, tick: Int, compute: Void -> Dynamic): Dynamic {
		if (isReplay) {
			var slot = this.memos.get(tick);
			return (slot != null) ? slot.get(key) : null;
		}
		var value = compute();
		if (value != null) {
			var slot = this.memos.get(tick);
			if (slot == null) {
				slot = new Map();
				this.memos.set(tick, slot);
			}
			slot.set(key, value);
		}
		return value;
	}

	/**
	 * Advance one render frame: follow the handle's epoch (self-reset), poll
	 * the server ack (reconcile), decay the correction offsets. Live inputs
	 * are stepped eagerly via the handle's onSend hook.
	 */
	public function tick(now: Float) {
		var dt = (this.lastTick < 0) ? 0 : now - this.lastTick;
		this.lastTick = now;
		if (dt > 0 && this.stepMs > 0) { this.renderAcc += dt; }

		var epoch = this.input.epoch;
		if (epoch != this.lastEpoch) {
			this.lastEpoch = epoch;
			this.reset();
		}

		var acked = this.input.lastProcessed;
		if (acked > this.lastAcked) {
			this.lastAcked = acked;
			this.reconcile(acked);
		}
		this.markDirty();

		if (dt <= 0) { return; }
		var k = (this.smoothMs <= 0) ? 1 : 1 - Math.exp(-dt / this.smoothMs);
		for (f in this.smoothedFields()) {
			this.error.set(f, this.getError(f) * (1 - k));
		}
	}

	/** Interpolation factor between the last two fixed steps (0..1). */
	private function renderAlpha(): Float {
		if (this.stepMs <= 0) { return 1; }
		var a = this.renderAcc / this.stepMs;
		return (a < 0) ? 0 : ((a > 1) ? 1 : a);
	}

	private function catchUp() {
		var sent = this.input.sentCount;
		if (this.predictedSeq >= sent || this.catching) { return; }
		this.catching = true;
		this.stepCtx.isReplay = false;
		for (seq in (this.predictedSeq + 1)...(sent + 1)) {
			var inp = this.input.at(seq);
			if (inp != null) {
				this.snapshotPrev();
				this.runStep(seq, inp);
				this.refreshRender();
				// consume one step of render time per live step
				this.renderAcc -= this.stepMs;
				if (this.renderAcc < 0) { this.renderAcc = 0; }
				else if (this.renderAcc >= this.stepMs) { this.renderAcc %= this.stepMs; }
			}
			this.predictedSeq = seq;
		}
		this.catching = false;
	}

	private function runStep(seq: Int, command: Dynamic) {
		this.stepCtx.tick = seq;
		var raw = this.input.reckonTimeAt(seq);
		this.stepCtx.lagCompActive = raw > 0;
		this.stepCtx.reckonTime = (raw > 0) ? raw : ((this.clock != null) ? this.clock.serverNow() : 0);
		this.applyStep(command);
	}

	private function reconcile(acked: Int) {
		var fields = this.smoothedFields();

		if (this.truthMatchesAt(acked)) {
			// wire-precision match: keep own full-precision state, zero telemetry
			for (f in fields) { this.lastCorrection.set(f, 0); }
			this.lastCorrectionMag = 0;
			this.drift.update(0);
			this.reconcileSeq++;
			this.memoPrune(acked);
			if (this.onReconcileHook != null) { this.onReconcileHook(acked); }
			return;
		}

		for (f in fields) {
			this.renderedBefore.set(f, this.readCurrent(f) + this.getError(f));
		}

		this.adoptTruth();

		var from = (acked > this.replayFrom) ? acked : this.replayFrom;
		this.stepCtx.isReplay = true;
		this.catching = true;
		for (seq in (from + 1)...(this.input.sentCount + 1)) {
			var inp = this.input.at(seq);
			if (inp != null) { this.runStep(seq, inp); }
		}
		this.catching = false;
		this.stepCtx.isReplay = false;
		this.refreshRender();
		this.predictedSeq = this.input.sentCount;

		// error rebase: what the player SAW minus the corrected result
		var hard = this.smoothMs <= 0;
		var mag: Float = 0;
		for (f in fields) {
			var correction = this.renderedBefore.get(f) - this.readCurrent(f);
			this.error.set(f, hard ? 0 : correction);
			var a = (correction < 0) ? -correction : correction;
			if (a > mag) { mag = a; }
			this.lastCorrection.set(f, correction);
		}

		// teleport-scale corrections POP all-or-nothing instead of gliding
		var popped = this.snapThreshold > 0 && mag > this.snapThreshold;
		if (popped) {
			for (f in fields) {
				this.error.set(f, 0);
				this.prev.set(f, this.readCurrent(f));
			}
		}
		this.reconcileSeq++;
		this.lastCorrectionMag = mag;
		if (!popped) {
			this.drift.update(mag);
			if (this.warnTolerance != null && this.drift.classify(this.warnTolerance) == "diverging") {
				trace("colyseus.predict: reconcile corrections are trending (ema "
					+ this.drift.ema + ") — client/server step likely diverged");
			}
		}

		this.memoPrune(acked);
		if (this.onReconcileHook != null) { this.onReconcileHook(acked); }
	}

	private function memoPrune(acked: Int) {
		var stale: Array<Int> = [];
		for (seq in this.memos.keys()) { if (seq <= acked) { stale.push(seq); } }
		for (seq in stale) { this.memos.remove(seq); }
	}

	private function getError(field: String): Float {
		var e = this.error.get(field);
		return (e != null) ? e : 0;
	}

	/**
	 * Re-seed local state from the authoritative instance(s): clears the
	 * offsets, memos, and the in-flight window. The controller self-resets on
	 * the handle's epoch (reconnect).
	 */
	public function reset() {
		this.reseedState();
		this.drift.reset();
		this.replayFrom = this.input.sentCount;
		this.predictedSeq = this.input.sentCount;
		this.lastAcked = this.input.lastProcessed;
		this.renderAcc = 0;
		this.memos = new Map();
		this.markDirty();
	}

	public function onDisposed(hook: Void -> Void) {
		this.disposedHooks.push(hook);
	}

	public function dispose() {
		this.dead = true;
		this.unsubscribeSend();
		var hooks = this.disposedHooks;
		this.disposedHooks = [];
		for (hook in hooks) { hook(); }
	}

	// --- Subclass hooks ---------------------------------------------------

	private function smoothedFields(): Array<String> { throw "not implemented"; }
	private function readCurrent(field: String): Float { throw "not implemented"; }
	private function adoptTruth() { throw "not implemented"; }
	private function applyStep(command: Dynamic) { throw "not implemented"; }
	private function snapshotPrev() { throw "not implemented"; }
	private function reseedState() { throw "not implemented"; }
	private function truthMatchesAt(_acked: Int): Bool { return false; }
	private function refreshRender() {}
	private function markDirty() {}
}
