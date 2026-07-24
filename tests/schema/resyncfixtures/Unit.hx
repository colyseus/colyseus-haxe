// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 5.0.11
// 

package schema.resyncfixtures;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class Unit extends Schema {
	@:type("string")
	public var name: String = "";

	@:type("number")
	public var hp: Dynamic = 0;

	@:type("array", Gem)
	public var gems: ArraySchema<Gem> = new ArraySchema<Gem>();

}
