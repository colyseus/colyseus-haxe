// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
// 

package schema.backwardsforwards;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class StateV2 extends Schema {
	@:type("string")
	public var str: String = "";

	@:type("map", PlayerV2)
	public var map: MapSchema<PlayerV2> = new MapSchema<PlayerV2>();

	@:type("number")
	public var countdown: Dynamic = 0;

}
