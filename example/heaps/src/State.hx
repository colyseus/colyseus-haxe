// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.1
// 


import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class State extends Schema {
	@:type("map", "string")
	public var testMap: MapSchema<String> = new MapSchema<String>();

	@:type("array", "number")
	public var testArray: ArraySchema<Dynamic> = new ArraySchema<Dynamic>();

}
