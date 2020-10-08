// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.0-alpha.61
// 

package schema.childschematypes;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class ChildSchemaTypes extends Schema {
	@:type("ref", IAmAChild)
	public var child: IAmAChild = new IAmAChild();

	@:type("ref", IAmAChild)
	public var secondChild: IAmAChild = new IAmAChild();

}
