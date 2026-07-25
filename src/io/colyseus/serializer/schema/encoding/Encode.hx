package io.colyseus.serializer.schema.encoding;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

/**
 * Encode counterpart of `Decode` for the wire primitives the room layer
 * emits (byte order matches `Decode`: little-endian). Port of
 * @colyseus/schema `src/encoding/encode.ts` — the schema "number" codec and
 * the fixed-width primitives the input layer needs.
 */
class Encode {
	// f32 round-trip scratch for the number codec's precision check
	private static var _f32scratch: Bytes = Bytes.alloc(4);

	private static inline var MAX_SAFE_INTEGER: Float = 9007199254740991.0;

	/**
	 * The schema "number" codec for non-negative integers (msgpack-style):
	 * positive fixint < 0x80, then uint8 / uint16 / uint32 prefixes.
	 * Kept for callers that KNOW the value is a non-negative int (request
	 * framing); `number()` is the full dynamic codec.
	 */
	public static function uint(out: BytesOutput, value: UInt) {
		if (value < 0x80) {
			out.writeByte(value);

		} else if (value < 0x100) {
			out.writeByte(0xcc);
			out.writeByte(value);

		} else if (value < 0x10000) {
			out.writeByte(0xcd);
			out.writeByte(value & 0xFF);
			out.writeByte((value >> 8) & 0xFF);

		} else {
			out.writeByte(0xce);
			out.writeByte(value & 0xFF);
			out.writeByte((value >> 8) & 0xFF);
			out.writeByte((value >> 16) & 0xFF);
			out.writeByte((value >>> 24) & 0xFF);
		}
	}

	/**
	 * The schema dynamic "number" codec (msgpack-style, both signs + floats).
	 * NaN encodes as 0; ±Infinity as ±MAX_SAFE_INTEGER; fractional values as
	 * float32 when the f32 round-trip stays within 1e-4, else float64.
	 */
	public static function number(out: BytesOutput, value: Float) {
		if (Math.isNaN(value)) {
			number(out, 0);
			return;
		}
		if (!Math.isFinite(value)) {
			number(out, value > 0 ? MAX_SAFE_INTEGER : -MAX_SAFE_INTEGER);
			return;
		}

		// JS `value !== (value|0)`: fractional OR outside int32 range → float branch
		var isInt32 = (value == Math.ffloor(value)) && value >= -2147483648.0 && value <= 2147483647.0;
		if (!isInt32) {
			if (Math.abs(value) <= 3.4028235e+38) {
				_f32scratch.setFloat(0, value);
				var asF32 = _f32scratch.getFloat(0);
				// precision check — 1e-4 acceptable loss (mirrors the reference)
				if (Math.abs(Math.abs(asF32) - Math.abs(value)) < 1e-4) {
					out.writeByte(0xca);
					float32(out, value);
					return;
				}
			}
			out.writeByte(0xcb);
			float64(out, value);
			return;
		}

		var v: Int = Std.int(value);
		if (v >= 0) {
			if (v < 0x80) {
				out.writeByte(v);
			} else if (v < 0x100) {
				out.writeByte(0xcc);
				out.writeByte(v);
			} else if (v < 0x10000) {
				out.writeByte(0xcd);
				uint16(out, v);
			} else {
				out.writeByte(0xce);
				uint32(out, v);
			}
		} else {
			if (v >= -0x20) {
				out.writeByte(0xe0 | (v + 0x20));
			} else if (v >= -0x80) {
				out.writeByte(0xd0);
				int8(out, v);
			} else if (v >= -0x8000) {
				out.writeByte(0xd1);
				int16(out, v);
			} else {
				out.writeByte(0xd2);
				int32(out, v);
			}
		}
	}

	public static inline function int8(out: BytesOutput, value: Int) {
		out.writeByte(value & 0xFF);
	}

	public static inline function uint8(out: BytesOutput, value: Int) {
		out.writeByte(value & 0xFF);
	}

	public static inline function int16(out: BytesOutput, value: Int) {
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
	}

	public static inline function uint16(out: BytesOutput, value: Int) {
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
	}

	public static inline function int32(out: BytesOutput, value: Int) {
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
		out.writeByte((value >> 16) & 0xFF);
		out.writeByte((value >>> 24) & 0xFF);
	}

	public static inline function uint32(out: BytesOutput, value: Float) {
		// carried as Float — uint32 values exceed Int32 on static targets
		var low16 = Std.int(value % 65536);
		var high16 = Std.int(value / 65536) & 0xFFFF;
		out.writeByte(low16 & 0xFF);
		out.writeByte((low16 >> 8) & 0xFF);
		out.writeByte(high16 & 0xFF);
		out.writeByte((high16 >> 8) & 0xFF);
	}

	public static function int64(out: BytesOutput, value: Float) {
		var high = Math.ffloor(value / 4294967296.0);
		var low = value - high * 4294967296.0;
		uint32(out, low);
		uint32(out, (high < 0) ? high + 4294967296.0 : high);
	}

	public static function uint64(out: BytesOutput, value: Float) {
		var high = Math.ffloor(value / 4294967296.0);
		var low = value - high * 4294967296.0;
		uint32(out, low);
		uint32(out, high);
	}

	public static function float32(out: BytesOutput, value: Float) {
		_f32scratch.setFloat(0, value);
		out.writeByte(_f32scratch.get(0));
		out.writeByte(_f32scratch.get(1));
		out.writeByte(_f32scratch.get(2));
		out.writeByte(_f32scratch.get(3));
	}

	public static function float64(out: BytesOutput, value: Float) {
		var b = Bytes.alloc(8);
		b.setDouble(0, value);
		out.writeBytes(b, 0, 8);
	}

	public static inline function boolean(out: BytesOutput, value: Bool) {
		out.writeByte(value ? 1 : 0);
	}

	/** fixstr / str8 / str16 / str32 with utf8 payload. `null` encodes as empty. */
	public static function string(out: BytesOutput, value: String) {
		if (value == null) { value = ""; }
		var utf8 = Bytes.ofString(value, haxe.io.Encoding.UTF8);
		var length = utf8.length;

		if (length < 0x20) {
			out.writeByte(length | 0xa0);
		} else if (length < 0x100) {
			out.writeByte(0xd9);
			out.writeByte(length);
		} else if (length < 0x10000) {
			out.writeByte(0xda);
			uint16(out, length);
		} else {
			out.writeByte(0xdb);
			uint32(out, length);
		}
		out.writeBytes(utf8, 0, length);
	}
}
