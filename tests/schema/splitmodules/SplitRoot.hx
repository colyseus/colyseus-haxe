package schema.splitmodules;

import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.MapSchema;

class SplitRoot extends Schema {
	@:type("map", SplitRow)
	public var rows:MapSchema<SplitRow> = new MapSchema();

	@:type("map", "boolean")
	public var flags:MapSchema<Bool> = new MapSchema();
}
