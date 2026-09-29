package schema.splitmodules;

import io.colyseus.serializer.schema.Schema;

class SplitRow extends Schema {
	@:type("number")
	public var value:Int;
}
