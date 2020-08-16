//
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
//
// GENERATED USING @colyseus/schema 0.4.61
//

package schema.backwardsforwards;
import io.colyseus.serializer.schema.*;

class StateV1 extends Schema {
	@:type("string")
	public var str: String = "";

	@:type("map", PlayerV1)
	public var map: MapSchema<PlayerV1> = new MapSchema<PlayerV1>();

}
