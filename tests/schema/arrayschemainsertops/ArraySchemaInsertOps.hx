// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 5.0.11
// 

package schema.arrayschemainsertops;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class ArraySchemaInsertOps extends Schema {
	@:type("array", "number")
	public var numbers: ArraySchema<Dynamic> = new ArraySchema<Dynamic>();

	@:type("array", Item)
	public var items: ArraySchema<Item> = new ArraySchema<Item>();

	@:type("array", Player)
	public var players: ArraySchema<Player> = new ArraySchema<Player>();

}
