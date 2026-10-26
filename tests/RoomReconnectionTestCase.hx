import haxe.io.Bytes;
import haxe.net.WebSocket.ReadyState;

import RoomProtocolTestCase.StubConnection;
import io.colyseus.Connection;
import io.colyseus.Room;
import io.colyseus.Protocol;
import io.colyseus.Protocol.CloseCode;

import schema.phase0.P0State;

/**
 * A socket the test opens, drops and reconnects by hand; it never touches the
 * network. Like the native socket, it throws on a send while not open.
 */
private class FakeConnection extends StubConnection {
    public var readyState = ReadyState.Open;
    public var attempts = 0;
    public var closes = 0;

    /** close() throws, like neko's socket on a second close. */
    public var closeThrows = false;

    override function createWebSocket(url: String) {}

    override function get__isOpen(): Bool {
        return readyState == ReadyState.Open;
    }

    override public function send(data: Bytes) {
        if (readyState != ReadyState.Open) { throw "websocket not open"; }
        sent.push(data);
    }

    override public function reconnect(?options: ReconnectOptions) {
        attempts++;
        readyState = ReadyState.Connecting;
    }

    // aborting a connecting socket reports an error, then a drop, as in a browser
    override public function close(?code: Int) {
        closes++;
        if (closeThrows) { throw "std@socket_close"; }
        if (readyState == ReadyState.Closed) { return; }
        if (readyState == ReadyState.Connecting) { onError("error"); }
        remoteClose(code != null ? code : (readyState == ReadyState.Open ? CloseCode.NORMAL_CLOSURE : CloseCode.ABNORMAL_CLOSURE));
    }

    /** The far end closes the socket with `code`. */
    public function remoteClose(code: Int) {
        readyState = ReadyState.Closed;
        onClose({ code: code });
    }

    /** The socket dies without a close handshake. */
    public function drop() {
        remoteClose(CloseCode.ABNORMAL_CLOSURE);
    }

    /** The attempt in flight connects; its JOIN_ROOM hasn't arrived yet. */
    public function attemptOpens() {
        readyState = ReadyState.Open;
        onOpen();
    }

    /** The attempt in flight connects and the server answers with a reconnect JOIN_ROOM. */
    public function completeAttempt(joinFrame: Bytes) {
        attemptOpens();
        onMessage(joinFrame);
    }
}

/**
 * A consented `leave()` ends automatic reconnection, whatever state the
 * connection is in, and `onLeave` fires exactly once.
 */
class RoomReconnectionTestCase extends haxe.unit.TestCase {

    // JOIN_ROOM: token "tok", serializer "none", no state reflection
    static final JOIN_FRAME = [10, 3, 116, 111, 107, 4, 110, 111, 110, 101, 0];
    // ERROR: code 524 (MATCHMAKE_EXPIRED), message "expired"
    static final ERROR_FRAME = [11, 0xcd, 2, 12, 0xa7, 101, 120, 112, 105, 114, 101, 100];

    static inline var RETRY_DELAY = 20;

    var room: Room<P0State>;
    var conn: FakeConnection;
    var leaves: Array<Int>;
    var drops: Int;
    var reconnects: Int;
    var errors: Int;

    /** A room on `conn` whose JOIN_ROOM hasn't arrived yet, retrying RETRY_DELAY ms after a drop. */
    function open(?conn: FakeConnection) {
        this.conn = (conn != null) ? conn : new FakeConnection();
        this.room = new Room<P0State>("reconnect", P0State);
        this.room.roomId = "r1";
        this.room.connect(this.conn);

        this.room.reconnection.minUptime = 0;
        this.room.reconnection.minDelay = 0;
        this.room.reconnection.backoff = (_, _) -> RETRY_DELAY;

        leaves = [];
        drops = 0;
        reconnects = 0;
        errors = 0;
        this.room.onLeave += (code) -> leaves.push(code);
        this.room.onDrop += (_) -> drops++;
        this.room.onReconnect += () -> reconnects++;
        this.room.onError += (_, _) -> errors++;
    }

    /** An `open()` room that has joined. */
    function join(?conn: FakeConnection) {
        open(conn);
        this.conn.onMessage(getBytes(JOIN_FRAME));
    }

    /** The retry timer fires. */
    function fireRetry() {
        @:privateAccess this.room.attemptReconnect();
    }

    public function testLeaveCancelsThePendingRetry() {
        join();
        conn.drop();
        assertTrue(room.reconnection.isReconnecting);

        room.leave();
        fireRetry(); // the wait thread's call, which leave() can't cancel
        assertEquals(0, conn.attempts);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertFalse(room.reconnection.isReconnecting);
    }

    public function testLeaveAbortsAnAttemptStillConnecting() {
        join();
        conn.drop();
        fireRetry();
        room.leave(); // the attempt's socket is still connecting

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(1, conn.closes);
        assertEquals(ReadyState.Closed, conn.readyState);
        // the aborted attempt's error and close reach no listener
        assertEquals(1, drops);
        assertEquals(0, errors);
        assertEquals(1, conn.attempts);
    }

    public function testAttemptCompletingAfterLeaveDoesNotRevive() {
        join();
        conn.drop();
        fireRetry();
        room.leave();

        var sent = conn.sent.length;
        conn.completeAttempt(getBytes(JOIN_FRAME)); // a transport that couldn't abort it

        assertEquals(0, reconnects);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertFalse(room.reconnection.isReconnecting);
        assertEquals(ReadyState.Closed, conn.readyState);
        assertEquals(sent, conn.sent.length); // JOIN_ROOM not acknowledged
    }

    /**
     * The native socket thread can still raise an attempt's JOIN_ROOM after
     * leave() closed it; closing it again throws on neko.
     */
    public function testJoinAfterLeaveSurvivesACloseThatThrows() {
        join();
        conn.drop();
        fireRetry();
        room.leave();

        var sent = conn.sent.length;
        conn.closeThrows = true;
        conn.completeAttempt(getBytes(JOIN_FRAME));

        assertEquals(2, conn.closes);
        assertEquals(0, reconnects);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(sent, conn.sent.length);
    }

    public function testLeaveFromOnDropDoesNotReconnect() {
        join();
        room.onDrop += (_) -> room.leave();
        conn.drop();

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(1, drops);
        assertEquals(0, room.reconnection.retryCount);
        assertFalse(room.reconnection.isReconnecting);
    }

    /** The socket thread or the browser has already closed it; the room hears it next. */
    public function testLeaveWhileTheServerCloseIsInFlightKeepsItsCode() {
        join();
        conn.readyState = ReadyState.Closed; // the server kicked us; onClose not delivered yet
        room.leave();
        assertEquals(0, leaves.length);

        conn.onClose({ code: 4321 });

        assertEquals("4321", leaves.join(","));
        assertEquals(0, conn.closes);
        assertEquals(0, drops);
    }

    public function testLeaveWhileAnAttemptIsOpenButNotJoinedLeavesLocally() {
        join();
        conn.drop();
        fireRetry();
        conn.attemptOpens();

        var sent = conn.sent.length;
        room.leave();

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(sent, conn.sent.length); // no LEAVE_ROOM: the attempt has no session yet
        assertEquals(ReadyState.Closed, conn.readyState);

        conn.onMessage(getBytes(JOIN_FRAME)); // already on its way
        assertEquals(0, reconnects);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
    }

    /** The server rejects the attempt (ERROR, then close) after leave() ended the room. */
    public function testRejectedAttemptReportsNoErrorAfterLeave() {
        join();
        conn.drop();
        fireRetry();
        conn.attemptOpens();
        room.leave();

        conn.onMessage(getBytes(ERROR_FRAME)); // already on its way

        assertEquals(0, errors);
        assertEquals(ReadyState.Closed, conn.readyState);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
    }

    public function testLeaveBeforeTheFirstJoinLeavesLocally() {
        open();
        var joins = 0;
        room.onJoin += () -> joins++;

        room.leave(); // the socket is open, the JOIN_ROOM not handled yet

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(0, conn.sent.length);
        assertEquals(ReadyState.Closed, conn.readyState);
        assertEquals(0, errors); // its own close isn't a failed join

        conn.onMessage(getBytes(JOIN_FRAME)); // already on its way
        assertEquals(0, joins);
    }

    public function testDropAfterLeaveRoomWasSentEndsAsConsented() {
        join();
        room.leave();
        assertEquals((Protocol.LEAVE_ROOM: Int), conn.sent[conn.sent.length - 1].get(0));

        conn.drop(); // before the server closed it

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(0, drops);
        assertEquals(0, room.reconnection.retryCount);
    }

    public function testLeaveAfterTheRoomLeftDoesNothing() {
        join();
        conn.remoteClose(4321);
        assertEquals("4321", leaves.join(","));

        var sent = conn.sent.length;
        room.leave();

        assertEquals("4321", leaves.join(","));
        assertEquals(sent, conn.sent.length);
        assertEquals(0, conn.closes);
    }

    public function testRunningOutOfRetriesLeavesOnce() {
        join();
        room.reconnection.maxRetries = 1;
        conn.drop();
        fireRetry();
        conn.drop(); // the attempt fails

        assertEquals('${CloseCode.FAILED_TO_RECONNECT}', leaves.join(","));
        assertFalse(room.reconnection.isReconnecting);

        room.leave();
        assertEquals(1, leaves.length);
    }

    public function testLeaveOnAHealthySocketWaitsForTheServer() {
        join();
        room.leave();

        assertEquals((Protocol.LEAVE_ROOM: Int), conn.sent[conn.sent.length - 1].get(0));
        assertEquals(0, leaves.length);

        conn.remoteClose(CloseCode.CONSENTED);
        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
    }

    #if (target.threaded && !cppia && haxe_ver >= 4.2)
    /** Opened off any event loop, the room waits for its retry on a thread that leave() can't cancel. */
    public function testLeaveStopsARetryWaitingOnAThread() {
        var made = new sys.thread.Lock();
        var looseConn: FakeConnection = null;
        sys.thread.Thread.create(() -> {
            looseConn = new FakeConnection();
            made.release();
        });
        made.wait();

        join(looseConn);
        assertFalse(conn.owner.active);

        conn.drop();
        room.leave();
        Sys.sleep(RETRY_DELAY * 3 / 1000); // past the waiting thread's retry

        assertEquals('${CloseCode.CONSENTED}', leaves.join(","));
        assertEquals(0, conn.attempts);
    }
    #end

    static function getBytes(arr: Array<Int>): Bytes {
        var b = Bytes.alloc(arr.length);
        for (i in 0...arr.length) { b.set(i, arr[i]); }
        return b;
    }
}
