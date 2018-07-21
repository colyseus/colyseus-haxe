import io.colyseus.Client;

class ClientTestCase extends haxe.unit.TestCase {
    var endpoint = "ws://localhost:2657";

    public function testInitialize() {
        var client = new Client(endpoint);
        assertEquals(client.endpoint, endpoint);
    }

    public function testJoinRoom() {
        var client = new Client(endpoint);
        client.onOpen = function () {
            trace("OPEN!");
        }

        var room = client.join("chat", ["create" => true]);
        room.onJoin = function() {
            trace("JOINED!");
        }
        room.onStateChange = function (state) {
            trace("NEW STATE => " + Std.string(state));
        }

        assertEquals(1, 1);
    }

}
