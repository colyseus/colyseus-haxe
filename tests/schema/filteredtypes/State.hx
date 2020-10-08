//
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
//
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
//

package schema.filteredtypes;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class State extends Schema {
	@:type("ref", Player)
	public var playerOne: Player = new Player();

	@:type("ref", Player)
	public var playerTwo: Player = new Player();

	@:type("array", Player)
	public var players: ArraySchema<Player> = new ArraySchema<Player>();

}
