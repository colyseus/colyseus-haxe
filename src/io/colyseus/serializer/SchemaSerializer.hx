package io.colyseus.serializer;

import io.colyseus.serializer.schema.Decoder;
import io.colyseus.serializer.schema.CustomType;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.schema.Reflection;
import io.colyseus.serializer.schema.ReferenceTracker;
import haxe.io.Bytes;

@:generic
class SchemaSerializer<T> implements Serializer {
	public var decoder:Decoder<T>;

	public function new(cl:Class<T>) {
		this.decoder = new Decoder(Type.createInstance(cl, []));
	}

	public function setState(data:Bytes) {
		this.decoder.decode(data);
	}

	public function getState():T {
		return this.decoder.state;
	}

	public function patch(data:Bytes) {
		this.decoder.decode(data);
	}

	public function teardown() {
		this.decoder.refs.clear();
	}

	public function handshake(bytes:Bytes, offset:Int) {
		// TODO: validate local schema based on handshake data
		//
		// var reflection = new Reflection();
		// reflection.decode(bytes, { offset: offset });
		//
	}

}