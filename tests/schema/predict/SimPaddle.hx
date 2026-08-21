//
// Hand-written fixture for the SimReconciler world tests — a part with BOTH
// numeric fields (posed, error-corrected) and a string field (mirrored
// verbatim, never posed). Field order is the wire contract.
//
package schema.predict;
import io.colyseus.serializer.schema.Schema;

class SimPaddle extends Schema {
	@:type("number")
	public var x: Dynamic = 0;

	@:type("number")
	public var y: Dynamic = 0;

	@:type("string")
	public var team: String = "";
}
