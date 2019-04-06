package io.colyseus.serializer;

import io.colyseus.serializer.schema.Schema;
import haxe.io.Bytes;
import haxe.Constraints.Constructible;

@:generic
class SchemaSerializer<T:Constructible<Void->Void>> implements Serializer {
    public var state: Dynamic;

    public function new () {
        this.state = new T();
    }

    public function setState(data: Bytes) {
        this.state.decode(data);
    }

    public function getState(): T {
        return this.state;
    }

    public function patch(data: Bytes) {
        this.state.decode(data);
    }

    public function teardown() {
    }

    public function handshake(bytes: Bytes, offset: Int) {
        // TODO: validate local schema based on handshake data
    }
}