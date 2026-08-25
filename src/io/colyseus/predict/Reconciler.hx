package io.colyseus.predict;

import io.colyseus.predict.RollbackController;
import io.colyseus.serializer.schema.Schema;

/** Options for `Reconciler`. */
typedef ReconcilerOptions = RollbackOptions & {
	/**
	 * Deterministic input-application step, SHARED with the server. Mutates
	 * `state` in place by applying `command` over `ctx.dt`.
	 */
	var step: (ctx: StepContext, state: Dynamic, command: Dynamic) -> Void;
	/**
	 * Fields to mirror from the server on reconcile. Null = every
	 * numeric/boolean field of the schema (declaration order).
	 */
	@:optional var fields: Array<String>;
}

/**
 * Server-reconciled rollback for a locally-controlled entity whose truth is
 * a flat scalar field list on ONE schema instance (port of the JS SDK's
 * `predict/reconciler.ts`). The predicted state is a same-class schema
 * MIRROR exposed as `state`; numeric fields get smooth error correction,
 * booleans copy verbatim.
 */
class Reconciler extends RollbackController {
	/**
	 * The TRUE predicted state — a same-class schema mirror. Read for game
	 * logic; mutations must be replay-reproducible.
	 */
	public var state(default, null): Schema;

	private var instance: Schema;
	private var step: (StepContext, Dynamic, Dynamic) -> Void;
	private var fields: Array<String> = [];
	private var numericFields: Array<String> = [];

	// wire-precision history ring
	private var wireRound: Array<Float -> Float> = [];
	private var history: Array<Float>;
	private var historySeq: Array<Int>;
	private var historySize: Int;
	private var historyOn: Bool;

	private static var _f32scratch = haxe.io.Bytes.alloc(4);

	/** Round to the nearest float32 — the value an IEEE 754 single would hold. */
	private static function fround(v: Float): Float {
		_f32scratch.setFloat(0, v);
		return _f32scratch.getFloat(0);
	}

	private static inline var MAX_SAFE_INTEGER = 9007199254740991.0;

	/**
	 * Mirror of the codec's dynamic "number" wire rule — what value would the
	 * wire deliver for this float64?
	 */
	private static function quantizeAutoNumber(v: Float): Float {
		if (Math.isNaN(v)) { return 0; }
		if (!Math.isFinite(v)) { return v > 0 ? MAX_SAFE_INTEGER : -MAX_SAFE_INTEGER; }
		var isInt32 = (v == Math.ffloor(v)) && v >= -2147483648.0 && v <= 2147483647.0;
		if (!isInt32 && Math.abs(v) <= 3.4028235e+38) {
			var f = fround(v);
			if (Math.abs(Math.abs(f) - Math.abs(v)) < 1e-4) { return f; }
		}
		return v;
	}

	// ref/array/map are object types; "quantized" holds the wire-exact float64
	// (identity quantizer). Strings can't error-correct, but they still belong
	// in the mirror — copied verbatim, kept out of `numericFields`, and they
	// disable the wire-precision reconcile skip via `scalarOnly` below.
	private static function isScalarType(fieldType: String): Bool {
		return switch (fieldType) {
			case "ref" | "array" | "map": false;
			default: true;
		}
	}

	private static function isNumeric(value: Dynamic): Bool {
		return Std.isOfType(value, Float);
	}

	private static function asScalar(value: Dynamic): Float {
		if (Std.isOfType(value, Bool)) { return cast(value, Bool) ? 1 : 0; }
		if (isNumeric(value)) { return cast value; }
		return Math.NaN;
	}

	private function wireQuantizerOf(field: String): Float -> Float {
		var declared: String = null;
		for (index => name in this.instance._indexes) {
			if (name == field) {
				declared = this.instance._types.get(index);
				break;
			}
		}
		return switch (declared) {
			case "float32": fround;
			case "number": quantizeAutoNumber;
			default: (v: Float) -> v;
		}
	}

	public function new(instance: Schema, opts: ReconcilerOptions) {
		super(opts);
		this.instance = instance;
		if (opts.step == null) { throw "Reconciler: step required"; }
		this.step = opts.step;

		var declared = opts.fields;
		if (declared == null) {
			declared = [];
			// walk metadata by dense index from 0 until gap (declaration order)
			var i = 0;
			while (instance._indexes.exists(i)) {
				if (isScalarType(instance._types.get(i))) {
					declared.push(instance._indexes.get(i));
				}
				i++;
			}
			if (declared.length == 0) {
				throw "Reconciler: no fields given and none derivable from the schema.";
			}
		}

		// the predicted state is a same-class schema MIRROR: step mutates a
		// real typed instance (state.vy = ...)
		var mirror: Schema = Type.createInstance(Type.getClass(instance), []);
		this.state = mirror;

		var scalarOnly = declared.length > 0;
		for (f in declared) {
			this.fields.push(f);
			var value: Dynamic = Reflect.getProperty(instance, f);
			Reflect.setProperty(mirror, f, value);
			if (isNumeric(value)) {
				this.numericFields.push(f);
				this.prev.set(f, cast value);
				this.error.set(f, 0);
			} else if (!Std.isOfType(value, Bool)) {
				scalarOnly = false;
			}
			this.wireRound.push(this.wireQuantizerOf(f));
		}
		this.historyOn = scalarOnly;
		this.historySize = (this.input.replayBufferSize > 0) ? this.input.replayBufferSize : 64;
		this.history = this.historyOn ? [for (_ in 0...this.historySize * this.fields.length) 0.0] : [];
		this.historySeq = this.historyOn ? [for (_ in 0...this.historySize) -1] : [];
	}

	/**
	 * Rendered value: the predicted state interpolated between the two latest
	 * steps plus the decaying correction offset. Numeric fields only; others
	 * return the current value.
	 */
	public override function value(field: String): Float {
		var current: Dynamic = Reflect.getProperty(this.state, field);
		if (!isNumeric(current)) { return asScalar(current); }
		var smoothed: Float = cast(current, Float) + this.getError(field);
		var p = this.prev.get(field);
		if (p == null) { p = smoothed; }
		return p + (smoothed - p) * this.renderAlpha();
	}

	/**
	 * Flat face: the pose key IS the field name, so the two lists match — kept
	 * separate to share one overlay path with the composite face.
	 */
	public override function boundRegistrations(): Array<BoundRegistration> {
		if (this.numericFields.length == 0) { return []; }
		return [{
			source: this.instance,
			fields: this.numericFields,
			poseKeys: this.numericFields,
		}];
	}

	// --- RollbackController hooks -----------------------------------------

	private override function smoothedFields(): Array<String> {
		return this.numericFields;
	}

	private override function readCurrent(field: String): Float {
		return cast Reflect.getProperty(this.state, field);
	}

	private override function applyStep(command: Dynamic) {
		this.step(this.stepCtx, this.state, command);
		if (this.historyOn) {
			var slot = this.stepCtx.tick % this.historySize;
			var base = slot * this.fields.length;
			for (i in 0...this.fields.length) {
				this.history[base + i] = asScalar(Reflect.getProperty(this.state, this.fields[i]));
			}
			this.historySeq[slot] = this.stepCtx.tick;
		}
	}

	private override function truthMatchesAt(acked: Int): Bool {
		if (!this.historyOn) { return false; }
		var slot = acked % this.historySize;
		if (this.historySeq[slot] != acked) { return false; }
		var base = slot * this.fields.length;
		for (i in 0...this.fields.length) {
			if (this.wireRound[i](this.history[base + i])
				!= asScalar(Reflect.getProperty(this.instance, this.fields[i]))) {
				return false;
			}
		}
		return true;
	}

	private override function snapshotPrev() {
		for (f in this.numericFields) {
			this.prev.set(f, cast(Reflect.getProperty(this.state, f), Float) + this.getError(f));
		}
	}

	private override function adoptTruth() {
		for (f in this.fields) {
			Reflect.setProperty(this.state, f, Reflect.getProperty(this.instance, f));
		}
	}

	private override function reseedState() {
		for (f in this.fields) {
			Reflect.setProperty(this.state, f, Reflect.getProperty(this.instance, f));
		}
		for (f in this.numericFields) {
			this.prev.set(f, cast Reflect.getProperty(this.state, f));
			this.error.set(f, 0);
		}
		for (s in 0...this.historySeq.length) { this.historySeq[s] = -1; }
	}
}
