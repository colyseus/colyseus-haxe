package io.colyseus.serializer.schema;

/**
 * `t.quantized()` codec — a bounded float encoded as a fixed-width unsigned
 * integer. Port of @colyseus/schema 5.0 `src/types/quantize.ts`; the math
 * must stay bit-identical to the reference:
 *
 * - rounding is explicit `ffloor(x + 0.5)` — NOT a language-default round
 *   (they disagree on the .5 case across languages)
 * - wrapping ranges are reduced in the FLOAT domain before the integer step
 * - the wrap top step folds via `%` on Floats (bits=32 would overflow
 *   32-bit integer math)
 * - NaN → q=0 (both modes); ±Inf → q=0 for wrap, natural clamp for clamp
 * - all math in Float (IEEE float64); `q` is carried as Float because
 *   uint32 values exceed the signed Int range on static targets
 */
class Quantize {
	/** Precompute range/span for {min, max, bits (8|16|32), wrap}. */
	public static function resolve(min: Float, max: Float, bits: Int, wrap: Bool): Dynamic {
		var steps = Math.pow(2, bits);
		return {
			min: min,
			max: max,
			bits: bits,
			wrap: wrap,
			range: max - min,
			// wrapping spreads 2^bits steps across [min,max) (top ≡ bottom);
			// clamped maps the endpoints onto 0 and 2^bits-1 inclusive
			span: wrap ? steps : steps - 1,
		};
	}

	/**
	 * Resolve a `@:type("quantized", {...})` options object into a descriptor,
	 * caching the resolution on the object itself (the options live in the
	 * class's `_childTypes` table, shared by all instances).
	 */
	public static function descriptor(opts: Dynamic): Dynamic {
		if (opts.span == null) {
			var resolved = resolve(opts.min, opts.max, (opts.bits != null) ? opts.bits : 16, opts.mode == 1);
			opts.range = resolved.range;
			opts.span = resolved.span;
			opts.wrap = resolved.wrap;
		}
		return opts;
	}

	/** Float → unsigned wire integer (as Float — may exceed Int range). */
	public static function quantize(desc: Dynamic, value: Float): Float {
		var range: Float = desc.range;
		var span: Float = desc.span;

		if (desc.wrap == true) {
			// non-finite can't be range-reduced; pin to q=0 so both peers agree
			if (!Math.isFinite(value)) { return 0; }

			// float-domain range reduction → [0, range)
			var a = (value - desc.min) % range;
			if (a < 0) { a += range; }
			return Math.ffloor((a / range) * span + 0.5) % span;
		}

		if (Math.isNaN(value)) { return 0; } // NaN → min (±Inf clamps naturally)
		var v: Float = value;
		if (v < desc.min) { v = desc.min; } else if (v > desc.max) { v = desc.max; }
		return Math.ffloor(((v - desc.min) / range) * span + 0.5);
	}

	/** Unsigned wire integer → float. */
	public static function dequantize(desc: Dynamic, q: Float): Float {
		return desc.min + (q / desc.span) * desc.range;
	}

	/** Wire-exact round-trip — what a quantized field yields after assignment. */
	public static function snap(desc: Dynamic, value: Float): Float {
		return dequantize(desc, quantize(desc, value));
	}
}
