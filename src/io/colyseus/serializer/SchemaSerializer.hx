package io.colyseus.serializer;

import io.colyseus.serializer.schema.Schema;
import haxe.io.Bytes;

@:generic
class SchemaSerializer<T> implements Serializer {
    public var state: T;

    public function new (cl: Class<T>) {
        this.state = Type.createInstance(cl, []);
    }

    public function setState(data: Bytes) {
        cast(this.state, Schema).decode(data);
    }

    public function getState(): T {
        return this.state;
    }

    public function patch(data: Bytes) {
        cast(this.state, Schema).decode(data);
    }

    public function teardown() {
    }

    public function handshake(bytes: Bytes, offset: Int) {
        // TODO: validate local schema based on handshake data
    }
}