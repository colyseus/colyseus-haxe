//
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
//
// GENERATED USING @colyseus/schema 0.4.61
//

package schema.mapschemaint8;
import io.colyseus.serializer.schema.*;

class MapSchemaInt8 extends Schema {
	@:type("string")
	public var status: String = "";

	@:type("map", "int8")
	public var mapOfInt8: MapSchema<Int> = new MapSchema<Int>();

}
