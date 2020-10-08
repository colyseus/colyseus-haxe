// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
// 

package schema.mapschemaint8;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class MapSchemaInt8 extends Schema {
	@:type("string")
	public var status: String = "";

	@:type("map", "int8")
	public var mapOfInt8: MapSchema<Int> = new MapSchema<Int>();

}
