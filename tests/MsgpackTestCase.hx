import haxe.io.Bytes;
import haxe.io.BytesOutput;
import org.msgpack.MsgPack;

class MsgpackTestCase extends haxe.unit.TestCase {

    public function testDate() {
		var decoded = MsgPack.decode(this.getBytes([
			130, 164, 114, 111, 111, 109, 129, 169, 99, 114, 101, 97, 116, 101, 100, 65, 116, 215, 0, 0, 0, 1, 116, 249, 113, 223, 56, 169, 115, 101, 115,
			115, 105, 111, 110, 73, 100, 169, 54, 106, 113, 120, 100, 55, 80, 55, 95
		]));

        assertEquals("6jqxd7P7_", decoded.sessionId);
        assertEquals(true, Std.isOfType(decoded.room.createdAt, Date));
        assertEquals("2020-10-05 12:47:03", decoded.room.createdAt.toString());
    }

    public function testUndefined() {
        var decoded = MsgPack.decode(this.getBytes([
			130, 164, 114, 111, 111, 109, 129, 165, 117, 110, 100, 101, 102, 212, 0, 0, 169, 115, 101, 115, 115, 105, 111, 110, 73, 100, 169, 54, 106, 113,
			120, 100, 55, 80, 55, 95
        ]));

        assertEquals("6jqxd7P7_", decoded.sessionId);
        assertEquals(null, decoded.room.undef);
    }

    public function testInfinity() {
        var decoded = MsgPack.decode(this.getBytes([
			130, 164, 114, 111, 111, 109, 129, 170, 109, 97, 120, 67, 108, 105, 101, 110, 116, 115, 203, 127, 240, 0, 0, 0, 0, 0, 0, 169, 115, 101, 115, 115,
			105, 111, 110, 73, 100, 169, 54, 106, 113, 120, 100, 55, 80, 55, 95
        ]));

        assertEquals(Math.POSITIVE_INFINITY, decoded.room.maxClients);
        assertEquals("6jqxd7P7_", decoded.sessionId);
	}

    private function getBytes(bytes: Array<Int>) {
        var builder = new BytesOutput();
        for (byte in bytes) { builder.writeByte(byte); }
        return builder.getBytes();
    }

}
