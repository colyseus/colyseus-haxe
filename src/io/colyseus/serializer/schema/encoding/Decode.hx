package io.colyseus.serializer.schema.encoding;

import io.colyseus.serializer.schema.Schema.It;
import haxe.io.Bytes;

class Decode {

	public static function decodePrimitiveType(type:String, bytes:Bytes, it:It):Dynamic {
        switch (type) {
            case "string":
                return string(bytes, it);
			case "number":
				return number(bytes, it);
			case "boolean":
				return boolean(bytes, it);
			case "int8":
				return int8(bytes, it);
			case "uint8":
				return uint8(bytes, it);
			case "int16":
				return int16(bytes, it);
			case "uint16":
				return uint16(bytes, it);
			case "int32":
				return int32(bytes, it);
			case "uint32":
				return uint32(bytes, it);
			case "int64":
				return int64(bytes, it);
			case "uint64":
				return uint64(bytes, it);
			case "float32":
				return float32(bytes, it);
			case "float64":
				return float64(bytes, it);
			default:
				throw "can't decode: " + type;
		}
	}

	public static function string(bytes:Bytes, it:It) {
		var prefix = bytes.get(it.offset++);
		var length:Int = 0;

		if (prefix < 0xc0) {
			// fixstr
			length = prefix & 0x1f;
		} else if (prefix == 0xd9) {
			length = uint8(bytes, it);
		} else if (prefix == 0xda) {
			length = uint16(bytes, it);
		} else if (prefix == 0xdb) {
			length = uint32(bytes, it);
		}

		var value = bytes.getString(it.offset, length);
		it.offset += length;

		return value;
	}

	public static function number(bytes:Bytes, it:It):Dynamic {
		var prefix = bytes.get(it.offset++);

		if (prefix < 0x80) {
			// positive fixint
			return prefix;
		} else if (prefix == 0xca) {
			// float 32
			return float32(bytes, it);
		} else if (prefix == 0xcb) {
			// float 64
			return float64(bytes, it);
		} else if (prefix == 0xcc) {
			// uint 8
			return uint8(bytes, it);
		} else if (prefix == 0xcd) {
			// uint 16
			return uint16(bytes, it);
		} else if (prefix == 0xce) {
			// uint 32
			return uint32(bytes, it);
		} else if (prefix == 0xcf) {
			// uint 64
			return uint64(bytes, it);
		} else if (prefix == 0xd0) {
			// int 8
			return int8(bytes, it);
		} else if (prefix == 0xd1) {
			// int 16
			return int16(bytes, it);
		} else if (prefix == 0xd2) {
			// int 32
			return int32(bytes, it);
		} else if (prefix == 0xd3) {
			// int 64
			return int64(bytes, it);
		} else if (prefix > 0xdf) {
			// negative fixint
			return (0xff - prefix + 1) * -1;
		}

		return 0;
	}

	public static function boolean(bytes:Bytes, it:It) {
		return uint8(bytes, it) > 0;
	}

	public static function int8(bytes:Bytes, it:It) {
		return (uint8(bytes, it) : Int) << 24 >> 24;
	}

	public static function uint8(bytes:Bytes, it:It):UInt {
		return bytes.get(it.offset++);
	}

	public static function int16(bytes:Bytes, it:It) {
		return (uint16(bytes, it) : Int) << 16 >> 16;
	}

	public static function uint16(bytes:Bytes, it:It):UInt {
		return bytes.get(it.offset++) | bytes.get(it.offset++) << 8;
	}

	public static function int32(bytes:Bytes, it:It) {
		var value = bytes.getInt32(it.offset);
		it.offset += 4;
		return value;
	}

	public static function uint32(bytes:Bytes, it:It):UInt {
		return int32(bytes, it);
	}

	public static function int64(bytes:Bytes, it:It) {
		var value = bytes.getInt64(it.offset);
		it.offset += 8;
		return value;
	}

	public static function uint64(bytes:Bytes, it:It) {
		var low = uint32(bytes, it);
		var high = uint32(bytes, it) * Math.pow(2, 32);
		return haxe.Int64.make(cast high, cast low);
	}

	public static function float32(bytes:Bytes, it:It) {
		var value = bytes.getFloat(it.offset);
		it.offset += 4;
		return value;
	}

	public static function float64(bytes:Bytes, it:It) {
		var value = bytes.getDouble(it.offset);
		it.offset += 8;
		return value;
	}

}
