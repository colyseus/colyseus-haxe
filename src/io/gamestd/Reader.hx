package io.gamestd;
import haxe.io.Bytes;

// Reader reads bytes, chars, ints from array.
class Reader {
    public var bytes: Bytes; // source array
    public var pos: Int; // current position in array

    public function new (array: Bytes) {
        this.bytes = array;
        this.pos = 0;
    }

    public function haveBytes () {
        return this.pos < this.bytes.length;
    }

    public function getByte (): Int {
        var value = this.bytes.get(this.pos);
        this.pos++;
        if (this.pos > this.bytes.length) throw "out of bounds";
        return value;
    }

    public function getChar () {
        return String.fromCharCode(this.getByte());
    }

    public function getInt () {
        var v = 0, c;

        while (this.haveBytes()) {
            c = FossilDelta.zValue[0x7f & this.getByte()];

            if (c < 0) {
                break;
            }

            v = (v<<6) + c;
        }

        this.pos--;

        return v >>> 0;
    }

}
