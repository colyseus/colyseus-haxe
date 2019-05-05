import io.colyseus.Room;
import org.msgpack.MsgPack;

class RoomFossilDeltaTestCase extends haxe.unit.TestCase {
    var room: RoomFossilDelta;

    override public function setup() {
        room = new RoomFossilDelta("chat");
    }

    public function testInitialize() {
        assertEquals(room.name, "chat");
        assertEquals(Std.string(Reflect.fields(room.state)), "[]");
    }

    public function testSomething() {
        assertEquals(room.name, "chat");
    }

    public function testStateChange () {
        room.onStateChange = function(data) {
            assertEquals(Std.string(Reflect.fields(data)), '[messages]');
            assertEquals(Std.string(data.messages), '[]');
        }
        room.setState(MsgPack.encode({ messages: [] }));
    }

}
