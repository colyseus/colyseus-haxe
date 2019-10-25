// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 0.4.61
// 

package schema.arrayschematypes;
import io.colyseus.serializer.schema.Schema;

class ArraySchemaTypes extends Schema {
	@:type("array", IAmAChild)
	public var arrayOfSchemas: ArraySchema<IAmAChild> = new ArraySchema<IAmAChild>();

	@:type("array", "number")
	public var arrayOfNumbers: ArraySchema<Dynamic> = new ArraySchema<Dynamic>();

	@:type("array", "string")
	public var arrayOfStrings: ArraySchema<String> = new ArraySchema<String>();

	@:type("array", "int32")
	public var arrayOfInt32: ArraySchema<Int> = new ArraySchema<Int>();

}
