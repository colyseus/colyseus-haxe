// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 3.0.0-alpha.48
// 

package schema.callbacks;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class Player extends Schema {
	@:type("ref", Vec3)
	public var position: Vec3 = new Vec3();

	@:type("map", Item)
	public var items: MapSchema<Item> = new MapSchema<Item>();

}
