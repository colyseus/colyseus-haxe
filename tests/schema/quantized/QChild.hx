//
// Hand-written fixture (not codegen'd) — exercises the @:type options-object
// macro support. Mirrors schema-5.0 test-external/generate-quantized-fixtures.ts
//
package schema.quantized;
import io.colyseus.serializer.schema.Schema;

class QChild extends Schema {
	@:type("number")
	public var v: Dynamic = 0;
}
