#if (target.threaded && !cppia && haxe_ver >= 4.2)
import io.colyseus.Connection;

/**
 * Native sockets are read on a thread of their own, but their events must run
 * on the thread that opened the connection, when its event loop is progressed.
 *
 * A dead port makes this deterministic: the refused connect is recorded while
 * the socket is created and reported on the socket thread's first `process()`.
 */
class ConnectionThreadingTestCase extends haxe.unit.TestCase {
    public function testEventsRunOnTheOwnerThread() {
        var owner = sys.thread.Thread.current();
        var errors = 0;
        var onOwner = true;

        var conn = new Connection("ws://127.0.0.1:9");
        conn.onError = function(_) {
            errors++;
            if (sys.thread.Thread.current() != owner) onOwner = false;
        };

        // the socket thread has reported the refused connect by now
        Sys.sleep(0.15);
        assertEquals(0, errors);

        owner.events.progress();
        assertTrue(errors >= 1);
        assertTrue(onOwner);
    }
}
#end
