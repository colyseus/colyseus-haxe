package io.colyseus.serializer.schema.encoding;

import haxe.io.BytesOutput;

/**
 * Encode counterpart of `Decode` for the wire primitives the room layer
 * emits (byte order matches `Decode`: little-endian). Kept minimal on
 * purpose — it grows as client→server features (input encoding, etc.)
 * are ported.
 */
class Encode {
	/**
	 * The schema "number" codec for non-negative integers (msgpack-style):
	 * positive fixint < 0x80, then uint8 / uint16 / uint32 prefixes.
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
}
