// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 5.0.11
// 

package schema.quantized;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class QState extends Schema {
	@:type("quantized", {min: 0, max: 6.283185307179586, bits: 16, mode: 1})
	public var yaw: Float = 0;

	@:type("quantized", {min: -1.5, max: 1.5, bits: 8, mode: 0})
	public var pitch: Float = 0;

	@:type("quantized", {min: 0, max: 1, bits: 32, mode: 0})
	public var precise: Float = 0;

	@:type("array", "number")
	public var nums: ArraySchema<Dynamic> = new ArraySchema<Dynamic>();

	@:type("map", "string")
	public var tags: MapSchema<String> = new MapSchema<String>();

	@:type("ref", QChild)
	public var child: QChild = new QChild();

	@:type("array", QChild)
	public var items: ArraySchema<QChild> = new ArraySchema<QChild>();

	@:type("string")
	public var label: String = "";

}
