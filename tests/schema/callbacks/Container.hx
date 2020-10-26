// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 1.0.1
// 

package schema.callbacks;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.*;

class Container extends Schema {
	@:type("number")
	public var num: Dynamic = 0;

	@:type("string")
	public var str: String = "";

	@:type("ref", Ref)
	public var ref: Ref = new Ref();

	@:type("array", Ref)
	public var arrayOfSchemas: ArraySchema<Ref> = new ArraySchema<Ref>();

	@:type("array", "number")
	public var arrayOfNumbers: ArraySchema<Dynamic> = new ArraySchema<Dynamic>();

	@:type("array", "string")
	public var arrayOfStrings: ArraySchema<String> = new ArraySchema<String>();

}
