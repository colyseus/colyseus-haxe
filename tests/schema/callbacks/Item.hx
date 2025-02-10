// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 3.0.0-alpha.48
// 

package schema.callbacks;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class Item extends Schema {
	@:type("string")
	public var name: String = "";

	@:type("number")
	public var value: Dynamic = 0;

}
