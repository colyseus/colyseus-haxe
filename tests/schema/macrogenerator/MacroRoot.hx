package schema.macrogenerator;

import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;
import tink.json.Serialized;

typedef MacroPayload = {n:Int};

class MacroRoot extends Schema {
	@:type("number") public var tick:Int;
	@:type("ref", MacroChild) public var child:MacroChild = new MacroChild();
	@:type("map", MacroItem) public var items:MapSchema<MacroItem> = new MapSchema();
	@:type("array", MacroItem) public var list:ArraySchema<MacroItem> = new ArraySchema();
	@:type("map", "boolean") public var flags:MapSchema<Bool> = new MapSchema();
	@:type("array", "string") public var names:ArraySchema<String> = new ArraySchema();
	@:type("string") public var label:String;
	@:type("string") public var payload:Serialized<MacroPayload>;
}

class MacroChild extends Schema {
	@:type("number") public var value:Int;
	@:type("boolean") public var active:Bool;
	@:type("map", MacroItem) public var rows:MapSchema<MacroItem> = new MapSchema();
}

class MacroItem extends Schema {
	@:type("number") public var value:Int;
	@:type("string") public var name:String;
}
