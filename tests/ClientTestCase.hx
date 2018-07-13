import io.colyseus.Client;

class ClientTestCase extends haxe.unit.TestCase {
    var client: Client;
    var endpoint = "ws://localhost:2657";

    override public function setup() {
        // client = new Client(endpoint);
    }

    // public function testInitialize() {
    //     assertEquals(client.endpoint, endpoint);
    // }

}
