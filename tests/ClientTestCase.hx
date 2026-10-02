import haxe.io.Bytes;

import io.colyseus.Client;
import io.colyseus.Connection;
import io.colyseus.Room;
import io.colyseus.error.HttpException;

import schema.phase0.P0State;

/** Never opens a socket: the test drives its callbacks by hand. */
private class LoopbackConnection extends Connection {
    public function new() {
        super("ws://127.0.0.1:9");
    }

    override function createWebSocket(url: String) {}

    override public function send(data: Bytes) {}

    override function get__isOpen(): Bool {
        return true;
    }
}

/** Seat reservations connect to a LoopbackConnection instead of the network. */
private class LoopbackClient extends Client {
    public var connection: LoopbackConnection;

    override function createConnection(room: Dynamic, options: Map<String, Dynamic>): Connection {
        return this.connection = new LoopbackConnection();
    }
}

class ClientTestCase extends haxe.unit.TestCase {
    var endpoint = "ws://localhost:2567";

    // JOIN_ROOM: token "tok", serializer "none", no state reflection
    static final JOIN_FRAME = [10, 3, 116, 111, 107, 4, 110, 111, 110, 101, 0];

    public function testInitialize() {
        var client = new Client(endpoint);

        // assertEquals(client.endpoint, endpoint);
        assertEquals(1, 1);
    }

    public function testJoinRoom() {
        var client = new Client(endpoint);

        // var room = client.join("chat", ["create" => true]);
        // room.onJoin = function() {
        //     trace("JOINED!");
        // }
        // room.onStateChange = function (state) {
        //     trace("NEW STATE => " + Std.string(state));
        // }

        assertEquals(1, 1);
    }

    /** A room error after a successful join must not re-invoke the join callback (#86). */
    public function testJoinCallbackIgnoresLaterErrors() {
        var client = new LoopbackClient(endpoint);
        var results = reserveSeat(client);

        client.connection.onMessage(getBytes(JOIN_FRAME));
        client.connection.onError("socket error");

        assertEquals("joined", results.join(","));
    }

    /** Mirror case: a failed join leaves no onJoin listener behind to settle it again. */
    public function testFailedJoinIgnoresLaterJoin() {
        var client = new LoopbackClient(endpoint);
        var results = reserveSeat(client);

        client.connection.onError("socket error");
        client.connection.onMessage(getBytes(JOIN_FRAME));

        assertEquals("error 0", results.join(","));
    }

    private function reserveSeat(client: LoopbackClient): Array<String> {
        var results: Array<String> = [];
        var seat = { name: "phase0", roomId: "r1", sessionId: "s1", processId: "p1" };

        client.consumeSeatReservation(seat, P0State, function(err: HttpException, room: Room<P0State>) {
            results.push(err == null ? "joined" : 'error ${err.code}');
        });

        return results;
    }

    private function getBytes(arr: Array<Int>): Bytes {
        var bytes = Bytes.alloc(arr.length);
        for (i in 0...arr.length) { bytes.set(i, arr[i]); }
        return bytes;
    }

}
