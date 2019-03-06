package io.colyseus.serializer;

import haxe.io.Bytes;

interface Serializer {
    public function setState(data: Bytes): Void;
    public function getState(): Dynamic;

    public function patch(patches: Bytes): Void;
    public function teardown(): Void;

    public function handshake(bytes: Bytes, offset: Int): Void;
}