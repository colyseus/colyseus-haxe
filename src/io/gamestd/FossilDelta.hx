package io.gamestd;
import haxe.io.Bytes;

class FossilDelta {

    // Hash window width in bytes. Must be a power of two.
    public static var NHASH = 16;

    // "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"
    public static var zDigits = [ 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 126 ];

    public static var zValue = [
      -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
      0,  1,  2,  3,  4,  5,  6,  7,    8,  9, -1, -1, -1, -1, -1, -1,
      -1, 10, 11, 12, 13, 14, 15, 16,   17, 18, 19, 20, 21, 22, 23, 24,
      25, 26, 27, 28, 29, 30, 31, 32,   33, 34, 35, -1, -1, -1, -1, 36,
      -1, 37, 38, 39, 40, 41, 42, 43,   44, 45, 46, 47, 48, 49, 50, 51,
      52, 53, 54, 55, 56, 57, 58, 59,   60, 61, 62, -1, -1, -1, 63, -1
    ];

    // Return a 32-bit checksum of the array.
    private static function checksum(arr: Bytes) {
      var sum0 = 0, sum1 = 0, sum2 = 0, sum3 = 0,
          z = 0, N = arr.length;

      //TODO measure if this unrolling is helpful.
      while (N >= 16) {
        sum0 = sum0 + arr.get(z+0) | 0;
        sum1 = sum1 + arr.get(z+1) | 0;
        sum2 = sum2 + arr.get(z+2) | 0;
        sum3 = sum3 + arr.get(z+3) | 0;

        sum0 = sum0 + arr.get(z+4) | 0;
        sum1 = sum1 + arr.get(z+5) | 0;
        sum2 = sum2 + arr.get(z+6) | 0;
        sum3 = sum3 + arr.get(z+7) | 0;

        sum0 = sum0 + arr.get(z+8) | 0;
        sum1 = sum1 + arr.get(z+9) | 0;
        sum2 = sum2 + arr.get(z+10) | 0;
        sum3 = sum3 + arr.get(z+11) | 0;

        sum0 = sum0 + arr.get(z+12) | 0;
        sum1 = sum1 + arr.get(z+13) | 0;
        sum2 = sum2 + arr.get(z+14) | 0;
        sum3 = sum3 + arr.get(z+15) | 0;

        z += 16;
        N -= 16;
      }
      while (N >= 4) {
        sum0 = sum0 + arr.get(z+0) | 0;
        sum1 = sum1 + arr.get(z+1) | 0;
        sum2 = sum2 + arr.get(z+2) | 0;
        sum3 = sum3 + arr.get(z+3) | 0;
        z += 4;
        N -= 4;
      }
      sum3 = (((sum3 + (sum2 << 8) | 0) + (sum1 << 16) | 0) + (sum0 << 24) | 0);
      // jshint -W086
      switch (N) {
        case 3: sum3 = sum3 + (arr.get(z+2) <<  8) | 0; // falls through
        case 2: sum3 = sum3 + (arr.get(z+1) << 16) | 0; // falls through
        case 1: sum3 = sum3 + (arr.get(z+0) << 24) | 0; // falls through
      }
      return sum3 >>> 0;
    }

    public static function Apply (src: Bytes, delta: Bytes, verifyChecksum: Bool = false) {
      var limit: Int;
      var total = 0;
      var zDelta = new Reader(delta);
      var lenSrc = src.length;
      var lenDelta = delta.length;

      limit = zDelta.getInt();
      if (zDelta.getChar() != '\n')
        throw "size integer not terminated by 'n'";

      var zOut = new Writer();
      while (zDelta.haveBytes()) {
        var cnt: Int, ofst: Int;
        cnt = zDelta.getInt();

        var char = zDelta.getChar();
        if (char == '@') {
            ofst = zDelta.getInt();

            if (zDelta.haveBytes() && zDelta.getChar() != ',')
              throw "copy command not terminated by ','";
            total += cnt;

            if (total > limit)
              throw 'copy exceeds output file size';

            if (ofst+cnt > lenSrc)
              throw 'copy extends past end of input';

            zOut.putArray(src, ofst, ofst+cnt);

        } else if (char == ':') {
            total += cnt;

            if (total > limit)
              throw 'insert command gives an output larger than predicted';

            if (cnt > lenDelta)
              throw 'insert count exceeds size of delta';

            zOut.putArray(zDelta.bytes, zDelta.pos, zDelta.pos+cnt);
            zDelta.pos += cnt;

        } else if (char == ';') {
            var out = zOut.toArray();

            if ((verifyChecksum) && cnt != checksum(out))
              throw 'bad checksum';

            if (total != limit)
              throw 'generated size does not match predicted size';
            return out;

        } else {
            throw 'unknown delta operator';

        }
      }

      throw 'unterminated delta';
    }

}