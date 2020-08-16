//
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
//
// GENERATED USING @colyseus/schema 0.4.61
//

package schema.inheritedtypes;
import io.colyseus.serializer.schema.*;

class InheritedTypes extends Schema {
	@:type("ref", Entity)
	public var entity: Entity = new Entity();

	@:type("ref", Player)
	public var player: Player = new Player();

	@:type("ref", Bot)
	public var bot: Bot = new Bot();

	@:type("ref", Entity)
	public var any: Entity = new Entity();

}
