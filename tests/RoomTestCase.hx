import io.colyseus.Room;

import org.msgpack.MsgPack;

class RoomTestCase extends haxe.unit.TestCase {
    var room: Room;

    override public function setup() {
        room = new Room("chat");
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
        room.setState(MsgPack.encode({ messages: [] }), 0, 0);
    }

}
