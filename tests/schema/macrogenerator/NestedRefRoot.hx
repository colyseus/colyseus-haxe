package schema.macrogenerator;

import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.MapSchema;

class NestedRefRoot extends Schema {
	@:type("map", NestedRefItem) public var items:MapSchema<NestedRefItem> = new MapSchema();
}

class NestedRefItem extends Schema {
	@:type("ref", NestedRefLeaf) public var leaf:NestedRefLeaf = new NestedRefLeaf();
}

class NestedRefLeaf extends Schema {
	@:type("number") public var value:Int;
}
