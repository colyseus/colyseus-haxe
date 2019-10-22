// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 0.4.61
// 

package schema.mapschematypes;
import io.colyseus.serializer.schema.Schema;

class MapSchemaTypes extends Schema {
	@:type("map", IAmAChild)
	public var mapOfSchemas: MapSchema<IAmAChild> = new MapSchema<IAmAChild>();

	@:type("map", "number")
	public var mapOfNumbers: MapSchema<Dynamic> = new MapSchema<Dynamic>();

	@:type("map", "string")
	public var mapOfStrings: MapSchema<String> = new MapSchema<String>();

	@:type("map", "int32")
	public var mapOfInt32: MapSchema<Int> = new MapSchema<Int>();

}
