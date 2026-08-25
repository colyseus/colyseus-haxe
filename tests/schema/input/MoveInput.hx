//
// Hand-written fixture matching colyseus-0.18
// PORTING/generate-input-fixtures.cts (MoveInput) — field order is the wire
// contract.
//
package schema.input;
import io.colyseus.serializer.schema.Schema;

class MoveInput extends Schema {
	@:type("number")
	public var vx: Dynamic = 0;

	@:type("number")
	public var vy: Dynamic = 0;

	@:type("boolean")
	public var jump: Bool = false;

	@:type("uint8")
	public var action: UInt = 0;
}
