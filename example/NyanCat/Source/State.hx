// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 0.4.20
// 


import io.colyseus.serializer.schema.Schema;

class State extends Schema {
	public var players: MapSchema<Player> = new MapSchema<Player>();

	public function new () {
		super();
		this._indexes = [0 => "players"];
		this._types = [0 => "map"];
		this._childPrimitiveTypes = [];
		this._childSchemaTypes = [0 => Player];
	}

}
