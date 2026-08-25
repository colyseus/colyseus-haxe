// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 5.0.11
// 

package schema.resyncfixtures;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class ResyncTransientState extends Schema {
	@:type("map", Unit)
	public var units: MapSchema<Unit> = new MapSchema<Unit>();

	@:type("map", "number")
	public var locals: MapSchema<Dynamic> = new MapSchema<Dynamic>();

}
