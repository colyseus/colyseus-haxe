// 
// THIS FILE HAS BEEN GENERATED AUTOMATICALLY
// DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
// 
// GENERATED USING @colyseus/schema 0.4.30
// 


import io.colyseus.serializer.schema.Schema;

class State extends Schema {
	@:type("map", Player)
	public var players: MapSchema<Player> = new MapSchema<Player>();

}
