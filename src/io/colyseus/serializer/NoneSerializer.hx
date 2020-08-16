package io.colyseus.serializer;

import io.colyseus.serializer.schema.Schema;
import haxe.io.Bytes;

class NoneSerializer implements Serializer {
    public function new () {}
    public function setState(data: Bytes) {}
    public function getState(): Dynamic {
        return null;
    }
    public function patch(data: Bytes) {}
    public function teardown() {}
    public function handshake(bytes: Bytes, offset: Int) {}
}