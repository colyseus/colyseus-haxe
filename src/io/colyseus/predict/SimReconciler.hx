package io.colyseus.predict;

import io.colyseus.predict.RollbackController.BoundRegistration;
import io.colyseus.predict.RollbackController.RollbackOptions;
import io.colyseus.predict.RollbackController.StepContext;
import io.colyseus.serializer.schema.Schema;

/**
 * Options for `SimReconciler`.
 */
typedef SimReconcilerOptions<W, I> = {
	> RollbackOptions,

	/**
	 * Your world handle — an object whose fields reach the simulated state.
	 * Fields holding a DECODED schema instance (`{ paddle: player, puck:
	 * state.puck }`) are auto-bound: replaced IN PLACE by mirrors that the
	 * controller seeds, re-adopts on every ack, and poses as
	 * `"<field>.<schemaField>"`. Every other field is opaque and untouched.
	 *
	 * Set once and passed to every callback, never swapped — so the object you
	 * hand in IS the one your step mutates, and reading `world.paddle` after
	 * construction gives you the mirror.
	 *
	 * A typed class is recommended over an anonymous structure: the step then
	 * reads `w.paddle.x` as a real field access. On a sys target, Dynamic field
	 * access silently yields null for anything that turns out to be a property,
	 * which is a failure mode worth designing out rather than debugging.
	 */
	var world: W;

	/**
	 * Deterministic input-application step, SHARED with the server. Apply
	 * `command` to `world` and advance it by `ctx.dt`. Parameter order matches
	 * `Reconciler`'s `step(ctx, state, command)` — world ≈ state.
	 */
	var step: (ctx: StepContext, world: W, command: I) -> Void;

	/**
	 * Adopt the server's truth into the world's OPAQUE fields. Called on every
	 * ack, BEFORE the unacked inputs replay on top and AFTER the bound fields'
	 * auto-adopt, so it may derive from just-adopted mirrors.
	 *
	 * Optional when bound fields cover the world; REQUIRED when nothing is
	 * bound, since there would be no restore point at all.
	 */
	@:optional var adopt: (world: W) -> Void;
};

/** A bound field: its source, the mirror that replaced it, and its poses. */
private class Bound {
	/** World field this entry came from — the prefix of its pose keys. */
	public var name: String;
	public var source: Schema;
	public var mirror: Schema;
	public var fields: Array<String> = [];

	public function new(name: String, source: Schema, mirror: Schema) {
		this.name = name;
		this.source = source;
		this.mirror = mirror;
	}
}

/**
 * SimReconciler — the COMPOSITE face of the same rollback engine that drives
 * `Reconciler` (port of predict/simReconciler.ts).
 *
 * Where the flat reconciler predicts ONE entity's scalar fields, this predicts a
 * WORLD of parts and reads back a pose keyed `"<field>.<schemaField>"`.
 *
 * The engine — catch-up, reconcile, error rebase, snap, drift, memos, epoch
 * follow — is inherited verbatim; only the state hooks differ. Notably
 * `truthMatchesAt` stays false: a composite sim has no wire-precision
 * short-circuit and always adopts, so the reference expects a little float noise
 * in the correction rather than an exact zero.
 *
 * Bound fields register into `predict.value()`, so the render layer reads them
 * the same way it reads any other entity — `predict.value(state.puck, "x")` —
 * and the "field.schemaField" pose key stays an internal detail.
 *
 * NOT ported (see PORTING.md): the custom `pose`/`interpolate` overlays that
 * give OPAQUE parts render smoothing. Those have no decoded instance to key on,
 * so `value(poseKey)` remains the only way to read them.
 */
class SimReconciler<W, I> extends RollbackController {
	/**
	 * The world the step mutates — the same object you passed in, with bound
	 * fields already replaced by their mirrors.
	 */
	public var world(default, null): W;

	private var stepFn: (StepContext, W, I) -> Void;
	private var adoptFn: (W) -> Void;
	private var bound: Array<Bound> = [];
	private var poseKeyList: Array<String> = [];
	private var poseOf: Map<String, { bound: Bound, field: String }> = new Map();

	public function new(opts: SimReconcilerOptions<W, I>) {
		super(opts);

		this.stepFn = opts.step;
		if (this.stepFn == null) { throw "SimReconciler: step required"; }
		this.world = opts.world;
		if (this.world == null) { throw "SimReconciler: world required"; }
		this.adoptFn = opts.adopt;

		// Reflect only at construction: the step never pays for it.
		var names = Reflect.fields(this.world);
		names.sort(Reflect.compare);
		for (name in names) {
			var value: Dynamic = Reflect.getProperty(this.world, name);
			if (!Std.isOfType(value, Schema)) { continue; }   // opaque
			bindField(name, cast value);
		}

		// Without a bound field there is nothing to restore from, so an adopt
		// callback is the only possible restore point.
		if (bound.length == 0 && adoptFn == null) {
			throw "SimReconciler: no field of the world holds a decoded schema instance, "
				+ "so `adopt` is required — otherwise a replay has no state to roll back to.";
		}
		poseKeyList.sort(Reflect.compare);
	}

	function bindField(name: String, source: Schema): Void {
		// Same as the flat face: the predicted state is a same-class schema
		// mirror, so a step writes `w.paddle.vy = …` against a real instance.
		var mirror: Schema = Type.createInstance(Type.getClass(source), []);
		var b = new Bound(name, source, mirror);

		var i = 0;
		while (source._indexes.exists(i)) {
			var field = source._indexes.get(i);
			if (isScalarType(source._types.get(i))) {
				var value: Dynamic = Reflect.getProperty(source, field);
				Reflect.setProperty(mirror, field, value);
				b.fields.push(field);

				var key = name + "." + field;
				poseOf.set(key, { bound: b, field: field });
				if (isNumeric(value)) {
					poseKeyList.push(key);
					this.prev.set(key, cast(value, Float));
					this.error.set(key, 0);
				}
			}
			i++;
		}

		if (b.fields.length == 0) {
			throw 'SimReconciler: bound field \'$name\' has no scalar schema fields.';
		}

		// In place, exactly like the JS reference: the caller's own object now
		// points at the mirror, so `world.paddle` is what the step mutates.
		Reflect.setProperty(this.world, name, mirror);
		bound.push(b);
	}

	static function isScalarType(fieldType: Dynamic): Bool {
		if (!Std.isOfType(fieldType, String)) { return false; }
		var t: String = cast fieldType;
		return t != "ref" && t != "array" && t != "map" && t != "string";
	}

	static inline function isNumeric(v: Dynamic): Bool {
		return Std.isOfType(v, Float) || Std.isOfType(v, Int);
	}

	function readPose(key: String): Float {
		var slot = poseOf.get(key);
		if (slot == null) { return Math.NaN; }
		var v: Dynamic = Reflect.getProperty(slot.bound.mirror, slot.field);
		return isNumeric(v) ? cast(v, Float) : Math.NaN;
	}

	/**
	 * Rendered pose for `"<field>.<schemaField>"`: the predicted value
	 * interpolated between the two latest steps plus the decaying correction
	 * offset. NaN for an unknown key.
	 */
	public override function value(poseKey: String): Float {
		var current = readPose(poseKey);
		if (Math.isNaN(current)) { return Math.NaN; }
		var smoothed = current + this.getError(poseKey);
		var p = this.prev.get(poseKey);
		if (p == null) { p = smoothed; }
		return p + (smoothed - p) * this.renderAlpha();
	}

	/** Every pose key this world exposes — useful when one reads NaN. */
	public function poseKeys(): Array<String> {
		return poseKeyList;
	}

	/**
	 * Composite face: each bound field keeps its ORIGINAL decoded instance as the
	 * source (not the mirror that replaced it), so `predict.value(state.puck,
	 * "x")` resolves without the caller ever naming "puck.x".
	 */
	public override function boundRegistrations(): Array<BoundRegistration> {
		var out: Array<BoundRegistration> = [];
		for (b in bound) {
			var fields = [], keys = [];
			for (f in b.fields) {
				var key = b.name + "." + f;
				if (poseOf.exists(key) && isNumeric(Reflect.getProperty(b.mirror, f))) {
					fields.push(f);
					keys.push(key);
				}
			}
			if (fields.length > 0) {
				out.push({ source: b.source, fields: fields, poseKeys: keys });
			}
		}
		return out;
	}

	// --- RollbackController hooks -----------------------------------------

	private override function smoothedFields(): Array<String> {
		return poseKeyList;
	}

	private override function readCurrent(field: String): Float {
		return readPose(field);
	}

	private override function applyStep(command: Dynamic) {
		stepFn(this.stepCtx, this.world, cast command);
	}

	private override function snapshotPrev() {
		for (key in poseKeyList) {
			this.prev.set(key, readPose(key) + this.getError(key));
		}
	}

	/**
	 * Pull every mirror back from its source, then let the app restore the
	 * opaque fields. Bound fields are unconditional: unlike the flat face there
	 * is no per-field wire-precision comparison to skip on.
	 */
	private override function adoptTruth() {
		for (b in bound) {
			for (f in b.fields) {
				Reflect.setProperty(b.mirror, f, Reflect.getProperty(b.source, f));
			}
		}
		if (adoptFn != null) { adoptFn(this.world); }
	}

	private override function reseedState() {
		adoptTruth();
		for (key in poseKeyList) {
			this.prev.set(key, readPose(key));
			this.error.set(key, 0);
		}
	}
}
