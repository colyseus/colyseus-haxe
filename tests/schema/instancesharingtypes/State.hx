//
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
//
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
//

package schema.instancesharingtypes;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class State extends Schema {
	@:type("ref", Player)
	public var player1: Player = new Player();

	@:type("ref", Player)
	public var player2: Player = new Player();

	@:type("array", Player)
	public var arrayOfPlayers: ArraySchema<Player> = new ArraySchema<Player>();

	@:type("map", Player)
	public var mapOfPlayers: MapSchema<Player> = new MapSchema<Player>();

}
