// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
// 

package schema.instancesharingtypes;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class Player extends Schema {
	@:type("ref", Position)
	public var position: Position = new Position();

}
