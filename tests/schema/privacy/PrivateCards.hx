package schema.privacy;

import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.types.ArraySchema;
import tink.json.Serialized;

class PrivateCards extends Schema {
	@:type("string")
	public var cards:Serialized<Array<Int>>;

	@:type("array", PrivateCardRow)
	public var rows:ArraySchema<PrivateCardRow> = new ArraySchema<PrivateCardRow>();
}

class PrivateCardRow extends Schema {
	@:type("string")
	public var cards:Serialized<Array<Int>>;
}
