//
// Hand-written fixture for the SimReconciler world tests — an all-numeric
// part. Field order is the wire contract.
//
package schema.predict;
import io.colyseus.serializer.schema.Schema;

class SimPuck extends Schema {
	@:type("number")
	public var x: Dynamic = 0;

	@:type("number")
	public var y: Dynamic = 0;

	@:type("number")
	public var vx: Dynamic = 0;

	@:type("number")
	public var vy: Dynamic = 0;
}
