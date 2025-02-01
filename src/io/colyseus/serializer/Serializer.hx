package io.colyseus.serializer;

import io.colyseus.serializer.schema.Schema.It;
import haxe.io.Bytes;

interface Serializer {
    // public function setState(bytes: Bytes, it: Null<It>): Void;
    public function setState(bytes: Bytes): Void;
    public function getState(): Dynamic;

    // public function patch(bytes: Bytes, it: Null<It>): Void;
    public function patch(bytes: Bytes): Void;
    public function teardown(): Void;

    public function handshake(bytes: Bytes, offset: Int): Void;
}