package schema.nestedmap;

import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.MapSchema;

class NestedMap extends Schema {
	@:type("ref", NestedChild)
	public var child:NestedChild = new NestedChild();
}

class NestedChild extends Schema {
	@:type("map", NestedRow)
	public var rows:MapSchema<NestedRow> = new MapSchema();
}

class NestedRow extends Schema {
	@:type("number")
	public var value:Int;
}
