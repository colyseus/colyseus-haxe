package io.colyseus.serializer.schema;

import haxe.io.Bytes;
import haxe.io.BytesOutput;
import io.colyseus.serializer.schema.encoding.Encode;

/**
 * Bound single-struct encoder for client→server input packets. Port of
 * @colyseus/schema `src/input/InputEncoder.ts` (flat primitive fields only).
 *
 * Delta tracking differs from the JS reference by design: the reference uses
 * setter-populated ChangeTrees; this port diffs the instance against the
 * last-sent snapshot. Benign divergence: re-assigning an identical value
 * emits nothing (the JS reference would re-emit the field) — the server
 * decodes to the same state either way.
 *
 * - `"reliable"` mode: one delta per `encode()` — only changed fields, empty
 *   when nothing changed. Bytes decode through the standard schema Decoder.
 * - `"unreliable"` mode: ring of the last `historySize` deltas, one packet:
 *   `[baseSeq][len][slot]…` oldest→newest; slot i has seq baseSeq+i. A
 *   no-change tick still pushes an empty carry-forward slot.
 */
class InputEncoder {
	// A field op packs as `operation | index`, so index 63 would emit 255 — the
	// byte a decoder reads as SWITCH_TO_STRUCTURE. The server rejects the 64th
	// field where the schema is defined; mirror it here, since this encoder
	// assembles the op byte itself.
	static inline var MAX_FIELDS: Int = 63;

	public var instance(default, null): Schema;
	public var mode(default, null): String;
	public var historySize(default, null): Int;

	/**
	 * Framework input seq of the most recent tick (unreliable mode):
	 * monotonic, ++ per `encode()`, kept across `reset()`. `0` in reliable
	 * mode (inputs are sequenced implicitly by message count).
	 */
	public var seq(default, null): Int = 0;

	// field indexes in wire order, resolved once at construction
	private var _fieldIndexes: Array<Int>;

	// last-sent snapshot per field index, seeded from construction defaults
	// (matching the JS reference: only explicit assignments are dirty).
	// null → snapshot mode: next encode emits every populated field (reset()).
	private var _baseline: Map<Int, Dynamic> = null;

	// unreliable ring (oldest→newest via head/count arithmetic)
	private var _slots: Array<Bytes>;
	private var _slotHead: Int = 0;
	private var _slotCount: Int = 0;

	public function new(instance: Schema, ?mode: String, ?historySize: Int) {
		this.instance = instance;
		this.mode = (mode != null) ? mode : "reliable";
		this.historySize = (this.mode == "unreliable")
			? ((historySize != null && historySize > 1) ? historySize : 3)
			: 1;

		this._fieldIndexes = [];
		for (index in instance._indexes.keys()) {
			if (index >= MAX_FIELDS) {
				throw "InputEncoder: field '" + instance._indexes.get(index) + "' is at index " + index +
					"; a Schema may only have " + MAX_FIELDS + " fields.";
			}

			var fieldType = instance._types.get(index);
			if (fieldType == "ref" || fieldType == "array" || fieldType == "map") {
				throw "InputEncoder: non-primitive field '" + instance._indexes.get(index) + "' is not supported.";
			}
			this._fieldIndexes.push(index);
		}
		this._fieldIndexes.sort((a, b) -> a - b);

		if (this.mode == "unreliable") {
			this._slots = [];
		}

		// diff against construction defaults from the start — an unassigned
		// field is not dirty (the JS ChangeTree behaves the same way)
		this._baseline = new Map();
		for (index in this._fieldIndexes) {
			this._baseline.set(index, instance.getByIndex(index));
		}
	}

	/** Encode the bound instance's delta (see class doc for the shape per mode). */
	public function encode(): Bytes {
		var body = this.produceDelta();
		return (this.mode == "reliable") ? body : this.pushAndEmitRing(body);
	}

	/**
	 * Reset: drops the ring and the diff baseline, so the next `encode()`
	 * emits a fresh full snapshot. `seq` is kept (monotonic across reset so a
	 * reconnect that reuses the server buffer doesn't replay seen seqs).
	 */
	public function reset() {
		this._baseline = null;
		this._slotHead = 0;
		this._slotCount = 0;
	}

	/**
	 * Copy the bound instance's field values into `target` (same-type
	 * instance) in place — for snapshotting the just-sent input into a
	 * replay ring slot.
	 */
	public function copyInto(target: Schema) {
		for (index in this._fieldIndexes) {
			target.setByIndex(index, this.instance.getByIndex(index));
		}
	}

	// ── delta producer ──────────────────────────────────────────────────

	private function produceDelta(): Bytes {
		var out = new BytesOutput();
		var snapshot = (this._baseline == null); // post-reset
		if (snapshot) { this._baseline = new Map(); }

		for (index in this._fieldIndexes) {
			var current: Dynamic = this.instance.getByIndex(index);
			var changed = snapshot
				? (current != null)                       // snapshot: every populated field
				: (current != this._baseline.get(index)); // delta: diff vs last sent
			if (!changed) { continue; }

			out.writeByte(0x80 | index); // ADD|fieldIndex — the schema field op
			this.encodeValue(out, this.instance._types.get(index), index, current);
			this._baseline.set(index, current);
		}
		return out.getBytes();
	}

	private function encodeValue(out: BytesOutput, fieldType: String, index: Int, value: Dynamic) {
		switch (fieldType) {
			case "number": Encode.number(out, value);
			case "string": Encode.string(out, value);
			case "boolean": Encode.boolean(out, value == true);
			case "int8": Encode.int8(out, value);
			case "uint8": Encode.uint8(out, value);
			case "int16": Encode.int16(out, value);
			case "uint16": Encode.uint16(out, value);
			case "int32": Encode.int32(out, value);
			case "uint32": Encode.uint32(out, value);
			case "int64": Encode.int64(out, value);
			case "uint64": Encode.uint64(out, value);
			case "float32": Encode.float32(out, value);
			case "float64": Encode.float64(out, value);
			case "quantized":
				var desc = Quantize.descriptor(this.instance._childTypes.get(index));
				var q = Quantize.quantize(desc, value);
				if (desc.bits == 8) { Encode.uint8(out, Std.int(q)); }
				else if (desc.bits == 16) { Encode.uint16(out, Std.int(q)); }
				else { Encode.uint32(out, q); }
			default:
				throw "InputEncoder: unsupported field type '" + fieldType + "'";
		}
	}

	// ── unreliable ring ─────────────────────────────────────────────────

	private function pushAndEmitRing(body: Bytes): Bytes {
		// push EVERY tick (even empty) so ring seqs stay consecutive: the
		// packet carries one base seq; the decoder derives slot seqs by position
		this.seq++;
		if (this._slots.length < this.historySize) {
			this._slots.push(body);
			this._slotCount = this._slots.length;
			this._slotHead = this._slotCount % this.historySize;
		} else {
			this._slots[this._slotHead] = body;
			this._slotHead = (this._slotHead + 1) % this.historySize;
			if (this._slotCount < this.historySize) { this._slotCount++; }
		}

		// [baseSeq][len][slot]… oldest→newest
		var out = new BytesOutput();
		var baseSeq = this.seq - this._slotCount + 1;
		Encode.number(out, baseSeq);
		var oldest = (this._slotHead - this._slotCount + this.historySize) % this.historySize;
		for (i in 0...this._slotCount) {
			var slot = this._slots[(oldest + i) % this.historySize];
			Encode.number(out, slot.length);
			out.writeBytes(slot, 0, slot.length);
		}
		return out.getBytes();
	}
}
