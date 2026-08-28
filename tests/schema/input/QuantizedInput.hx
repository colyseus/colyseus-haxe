//
// Hand-written fixture, same convention as MoveInput — field order is the wire
// contract. Shaped after demos/fps `MoveInput`: a wrapping `t.angle()` yaw, a
// clamped `t.quantized()` pitch, and one plain field.
//
package schema.input;
import io.colyseus.serializer.schema.Schema;

class QuantizedInput extends Schema {
	@:type("quantized", {min: 0, max: 6.283185307179586, bits: 16, mode: 1})
	public var yaw: Float = 0;

	@:type("quantized", {min: -1.5, max: 1.5, bits: 16, mode: 0})
	public var pitch: Float = 0;

	@:type("uint8")
	public var slot: UInt = 0;
}
