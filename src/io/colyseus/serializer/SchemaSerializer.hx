package io.colyseus.serializer;

import io.colyseus.serializer.schema.CustomType;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.Reflection;
import io.colyseus.serializer.schema.ReferenceTracker;
import haxe.io.Bytes;

@:generic
class SchemaSerializer<T> implements Serializer {
	public var state:T;

	private var refs:ReferenceTracker = new ReferenceTracker();

	public function new(cl:Class<T>) {
		this.state = Type.createInstance(cl, []);
	}

	public function setState(data:Bytes) {
		cast(this.state, Schema).decode(data, null, this.refs);
	}

	public function getState():T {
		return this.state;
	}

	public function patch(data:Bytes) {
		cast(this.state, Schema).decode(data, null, this.refs);
	}

	public function teardown() {
		this.refs.clear();
	}

	public function handshake(bytes:Bytes, offset:Int) {
    // TODO: validate local schema based on handshake data
    //
    // var reflection = new Reflection();
    // reflection.decode(bytes, { offset: offset });
    //
	}
}