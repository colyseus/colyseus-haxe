package io.colyseus;

import haxe.io.BytesOutput;
import haxe.Timer;
import io.colyseus.serializer.schema.Schema;
import io.colyseus.serializer.Serializer;
import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.NoneSerializer;
import io.colyseus.serializer.FossilDeltaSerializer;

import io.colyseus.serializer.schema.Schema.It;
import io.colyseus.serializer.schema.Schema.SPEC;
import io.colyseus.serializer.schema.encoding.Decode;
import io.colyseus.serializer.schema.encoding.Encode;

import io.colyseus.Protocol.ProtocolMasks;
import io.colyseus.Protocol.ProtocolModifier;
import io.colyseus.Protocol.ResponseStatus;

using io.colyseus.Protocol.CloseCode;
using io.colyseus.events.EventHandler;

import haxe.io.Bytes;
import haxe.ds.Map;
import org.msgpack.MsgPack;

typedef EnqueuedMessage = {
    data: Bytes
};

typedef PendingRequest = {
    /** Called once with the decoded reply outcome: (ok, payload, faulted). */
    var onReply: (Bool, Dynamic, Bool) -> Void;
    /** Called when the connection closes before a reply arrives. */
    @:optional var onClose: (String) -> Void;
};

typedef ReconnectionOptions = {
    /** Whether automatic reconnection is enabled. Set to false to disable. */
    var enabled: Bool;
    /** The maximum number of reconnection attempts. */
    var maxRetries: Int;
    /** The minimum delay between reconnection attempts (ms). */
    var minDelay: Int;
    /** The maximum delay between reconnection attempts (ms). */
    var maxDelay: Int;
    /** The minimum uptime of the room before reconnection attempts can be made (ms). */
    var minUptime: Int;
    /** The current number of reconnection attempts. */
    var retryCount: Int;
    /** The initial delay between reconnection attempts (ms). */
    var delay: Int;
    /** The maximum number of enqueued messages to buffer. */
    var maxEnqueuedMessages: Int;
    /** Buffer for messages sent while connection is not open. */
    var enqueuedMessages: Array<EnqueuedMessage>;
    /** Whether the room is currently reconnecting. */
    var isReconnecting: Bool;
};

class Room<T> {
    public var roomId: String;
    public var sessionId: String;
    public var reconnectionToken: String;

    public var name: String;

    // callbacks
    public var onJoin = new EventHandler<Void->Void>();
    public var onStateChange = new EventHandler<Dynamic->Void>();
    public var onError = new EventHandler<Int->String->Void>();
    public var onLeave = new EventHandler<Int->Void>();

    public var onDrop = new EventHandler<Int->Void>();
    public var onReconnect = new EventHandler<Void->Void>();

    private var onMessageHandlers = new Map<String, Dynamic->Void>();

    public var connection: Connection;

    public var serializerId: String = null;
    public var serializer: Serializer = null;

    private var tmpStateClass: Class<T>;

    // ping-related
    private var lastPingTime: Float = 0;
    private var pingCallback: Null<Float->Void> = null;

    // request/response (ROOM_REQUEST / ROOM_RESPONSE) correlation state
    public static var defaultRequestTimeout: Int = 10000;
    private var pendingRequests = new Map<Int, PendingRequest>();
    private var nextRequestId: Int = 0;

    // reconnection logic
    public var reconnection: ReconnectionOptions = {
        enabled: true,
        retryCount: 0,
        maxRetries: 15,
        delay: 100,
        minDelay: 100,
        maxDelay: 5000,
        minUptime: 5000,
        maxEnqueuedMessages: 10,
        enqueuedMessages: [],
        isReconnecting: false
    };
    private var joinedAtTime: Float = 0;

    public function new (name: String, ?cls: Class<T>) {
        this.roomId = null;
        this.name = name;
        this.tmpStateClass = cls;

        this.onLeave += (code: Int) -> this.teardown();
    }

    public function connect(connection: Connection) {
        this.connection = connection;
        this.connection.reconnectionEnabled = false;

        this.connection.onMessage = function (bytes) {
            this.onMessageCallback(bytes);
        }

		this.connection.onClose = function(e:Dynamic) {
            // in-flight requests can't be answered on a closed socket
            this.rejectAllPendingRequests("connection closed before a response was received.");

            if (this.joinedAtTime == 0) {
                trace("Room connection was closed unexpectedly (" + e.code + "): " + e.reason);
                this.onError.dispatch(e.code, e.reason);
                return;
            }

            if (
                e.code == CloseCode.NO_STATUS_RECEIVED ||
                e.code == CloseCode.ABNORMAL_CLOSURE ||
                e.code == CloseCode.GOING_AWAY ||
                e.code == CloseCode.MAY_TRY_RECONNECT
            ) {
                this.onDrop.dispatch(e.code);
                this.handleReconnection(e.code);

            } else {
                this.onLeave.dispatch(e.code);
            }
        }

        this.connection.onError = function (e) {
            this.onError.dispatch(0, e);
        };
    }

    public function leave(consented: Bool = true) {
        if (this.connection != null) {
            if (consented) {
				var bytes = new BytesOutput();
				bytes.writeByte(Protocol.LEAVE_ROOM);
                this.connection.send(bytes.getBytes());

            } else {
                this.connection.close();
            }

        } else {
            this.onLeave.dispatch(CloseCode.CONSENTED);
        }
    }

    /** Writes a message type (short string as fixstr, or numeric code). */
    private function writeMessageType(out: BytesOutput, type: Dynamic) {
        if (Std.isOfType(type, String)) {
            var encodedType = Bytes.ofString(type);
            out.writeByte(encodedType.length | 0xa0);
            out.writeBytes(encodedType, 0, encodedType.length);

        } else {
            out.writeByte(type);
        }
    }

    /** Transmits `data`, or buffers it while the connection is not open. */
    private function sendOrEnqueue(data: Bytes) {
        if (!this.connection._isOpen) {
            this.enqueueMessage(data);
        } else {
            this.connection.send(data);
        }
    }

    public function send(type: Dynamic, ?message: Dynamic) {
        var bytesToSend = new BytesOutput();
        bytesToSend.writeByte(Protocol.ROOM_DATA);
        this.writeMessageType(bytesToSend, type);

        if (message != null) {
            var encodedMessage = MsgPack.encode(message);
            bytesToSend.writeBytes(encodedMessage, 0, encodedMessage.length);
        }

        this.sendOrEnqueue(bytesToSend.getBytes());
    }

    public function sendBytes(type: Dynamic, ?bytes: Dynamic) {
        var bytesToSend = new BytesOutput();
        bytesToSend.writeByte(Protocol.ROOM_DATA_BYTES);
        this.writeMessageType(bytesToSend, type);
        bytesToSend.writeBytes(bytes, 0, bytes.length);

        this.sendOrEnqueue(bytesToSend.getBytes());
    }

    /**
     * Send a message and await the server's reply — the value the server
     * returns from its matching `onMessage(type, ...)` handler.
     *
     * The callback receives `(response, error)`; exactly one is non-null.
     * `error` is set when the handler rejects (the authored reason) or
     * throws (`{name, message, code?}`), when the connection closes first,
     * or when no reply arrives within `timeoutMs`
     * (default: `Room.defaultRequestTimeout`).
     */
    public function request(type: Dynamic, ?payload: Dynamic, callback: (Dynamic, Dynamic) -> Void, ?timeoutMs: Int) {
        if (this.connection == null || !this.connection._isOpen) {
            callback(null, 'cannot send request "$type": connection is not open.');
            return;
        }

        // the timer lives in this closure — the pending registry stays
        // unaware of timeouts; the reply callback and onClose both clear it
        var timer: Timer = null;
        var stopTimer = () -> { if (timer != null) { timer.stop(); timer = null; } };

        var requestId = this.sendRequest(type, payload,
            (ok, replyPayload, _) -> {
                stopTimer();
                if (ok) { callback(replyPayload, null); }
                else { callback(null, replyPayload); }
            },
            (reason) -> {
                stopTimer();
                callback(null, reason);
            });

        var ms = (timeoutMs != null) ? timeoutMs : defaultRequestTimeout;
        timer = Timer.delay(() -> {
            this.pendingRequests.remove(requestId);
            callback(null, 'request "$type" timed out after ${ms}ms.');
        }, ms);
    }

    /**
     * Low-level round-trip primitive: registers `onReply` (called once with
     * the decoded outcome when the server replies) and transmits a
     * ROOM_REQUEST frame. `request()` wraps it with a timeout. Returns the
     * request id.
     */
    private function sendRequest(type: Dynamic, payload: Dynamic, onReply: (Bool, Dynamic, Bool) -> Void, ?onClose: (String) -> Void): Int {
        var requestId = this.nextRequestId;
        this.nextRequestId = (this.nextRequestId + 1) & 0x7FFFFFFF; // keep positive

        var bytesToSend = new BytesOutput();
        bytesToSend.writeByte(Protocol.ROOM_REQUEST);
        Encode.uint(bytesToSend, requestId);
        this.writeMessageType(bytesToSend, type);

        if (payload != null) {
            var encodedPayload = MsgPack.encode(payload);
            bytesToSend.writeBytes(encodedPayload, 0, encodedPayload.length);
        }

        // reliable + offline: buffer so it flushes on (re)connect
        this.sendOrEnqueue(bytesToSend.getBytes());

        this.pendingRequests.set(requestId, { onReply: onReply, onClose: onClose });
        return requestId;
    }

    private function rejectAllPendingRequests(reason: String) {
        for (entry in this.pendingRequests) {
            if (entry.onClose != null) { entry.onClose(reason); }
        }
        this.pendingRequests.clear();
    }

    public function ping(callback: Float->Void) {
        // skip if connection is not open
        if (this.connection == null || !this.connection._isOpen) {
            return;
        }

        this.lastPingTime = haxe.Timer.stamp() * 1000;
        this.pingCallback = callback;

        var bytes = new BytesOutput();
        bytes.writeByte(Protocol.PING);
        this.connection.send(bytes.getBytes());
    }

    public function onMessage(type: Dynamic, callback: Dynamic->Void) {
        this.onMessageHandlers[this.getMessageHandlerKey(type)] = callback;
        return this;
    }

    public var state (get, null): T;
    function get_state () : T {
        return this.serializer.getState();
    }

    public function teardown() {
        if (this.serializer != null) {
            this.serializer.teardown();
        }

        // this.onJoin.removeAll();
        // this.onStateChange.removeAll();
        // this.onMessage.removeAll();
        // this.onError.removeAll();
        // this.onLeave.removeAll();
    }

    private function onMessageCallback(data: Bytes) {
        var it:It = {offset: 1};

        // Strip modifier bits (bits 5..7) so the dispatch below stays
        // modifier-agnostic; consume any modifier-attached prefix bytes here.
        var rawByte = data.get(0);
        var code = rawByte & ProtocolMasks.CODE;

        if ((rawByte & ProtocolModifier.TIMED) != 0) {
            // [uint32 sNow][uint32 inputSeq] — server time (ms since room
            // start) + last PROCESSED input seq. Consumed here; feeds the
            // room clock + input ack once the input layer is ported.
            Decode.uint32(data, it);
            Decode.uint32(data, it);
        }

        if (code == Protocol.JOIN_ROOM) {
            var reconnectionToken = data.getString(it.offset + 1, data.get(it.offset));
            it.offset += reconnectionToken.length + 1;

            this.serializerId = data.getString(it.offset + 1, data.get(it.offset));
            it.offset += this.serializerId.length + 1;

            // Instantiate serializer if not locally available
            if (this.serializer == null) {
                if (this.serializerId == "schema") {
                    this.serializer = new SchemaSerializer<T>(tmpStateClass);

                } else if (this.serializerId == "fossil-delta") {
                    this.serializer = new FossilDeltaSerializer();

                } else {
                    this.serializer = new NoneSerializer();
                }
            }

            // State reflection is length-prefixed: the schema handshake must
            // not read past it into the trailing tagged-section bytes. A
            // zero length means reconnect (the serializer already has state).
            var stateReflectionLen: Int = Decode.number(data, it);
            if (stateReflectionLen > 0 && this.serializer != null) {
                this.serializer.handshake(data.sub(0, it.offset + stateReflectionLen), it.offset);
            }
            it.offset += stateReflectionLen;

            // Trailing tagged sections: [tag byte][length varint][payload].
            // Unknown tags are skipped via length (forward-compatible).
            // INPUT_REFLECTION / INPUT_OPTIONS are consumed by the input
            // layer once ported.
            while (it.offset < data.length) {
                it.offset++; // tag (see HandshakeSection)
                var sectionLen: Int = Decode.number(data, it);
                it.offset += sectionLen;
            }

            if (this.joinedAtTime == 0) {
                // First join
                this.joinedAtTime = Timer.stamp() * 1000;
                this.onJoin.dispatch();

            } else {
                // Reconnection successful
                trace("[Colyseus reconnection]: reconnection successful!");
                this.reconnection.isReconnecting = false;
                this.onReconnect.dispatch();
            }

            // store local reconnection token
			this.reconnectionToken = this.roomId + ":" + reconnectionToken;

            // acknowledge JOIN_ROOM
            var bytes = new BytesOutput();
            bytes.writeByte(Protocol.JOIN_ROOM);
            this.connection.send(bytes.getBytes());

            // Send any enqueued messages that were buffered while disconnected
            if (this.reconnection.enqueuedMessages.length > 0) {
                for (message in this.reconnection.enqueuedMessages) {
                    this.connection.send(message.data);
                }
                // Clear the buffer after sending
                this.reconnection.enqueuedMessages = [];
            }

        } else if (code == Protocol.ERROR) {
            var errorCode: Int = Decode.number(data, it);
            var message = Decode.string(data, it);
            trace("Room error: code => " + errorCode + ", message => " + message);
            this.onError.dispatch(errorCode, message);

        } else if (code == Protocol.LEAVE_ROOM) {
            this.leave();

        } else if (code == Protocol.ROOM_STATE) {
            this.setState(data.sub(it.offset, data.length - it.offset));

        } else if (code == Protocol.ROOM_STATE_PATCH) {
            this.patch(data.sub(it.offset, data.length - it.offset));

        } else if (code == Protocol.ROOM_DATA) {
            var type = (SPEC.stringCheck(data, it))
                ? Decode.string(data, it)
                : Decode.number(data, it);

            var message = (data.length > it.offset)
                ? MsgPack.decode(data.sub(it.offset, data.length - it.offset))
                : null;

            this.dispatchMessage(type, message);

        } else if (code == Protocol.ROOM_DATA_BYTES) {
            var type = (SPEC.stringCheck(data, it))
                ? Decode.string(data, it)
                : Decode.number(data, it);

            this.dispatchMessage(type, data.sub(it.offset, data.length - it.offset));

        } else if (code == Protocol.ROOM_RESPONSE) {
            // reply to a pending request()
            var requestId: Int = Decode.number(data, it);
            var status = data.get(it.offset++);
            var payload: Dynamic = (data.length > it.offset)
                ? MsgPack.decode(data.sub(it.offset, data.length - it.offset))
                : null;

            var entry = this.pendingRequests.get(requestId);
            // already answered (e.g. timed out) or unknown id — ignore
            if (entry != null) {
                this.pendingRequests.remove(requestId);
                // the ONE place the wire's three statuses collapse to (ok, payload, faulted):
                entry.onReply(status == ResponseStatus.OK, payload, status == ResponseStatus.ERROR);
            }

        } else if (code == Protocol.PING) {
            if (this.pingCallback != null) {
                var currentTime = haxe.Timer.stamp() * 1000;
                this.pingCallback(Math.round(currentTime - this.lastPingTime));
                this.pingCallback = null;
            }
        }
    }

    private function setState(encodedState: Bytes) {
        this.serializer.setState(encodedState);
        this.onStateChange.dispatch(this.serializer.getState());
    }

    private function patch(binaryPatch: Bytes) {
        this.serializer.patch(binaryPatch);
        this.onStateChange.dispatch(this.serializer.getState());
    }

    private function dispatchMessage(type: Dynamic, message: Dynamic) {
        var messageType = this.getMessageHandlerKey(type);

        if (this.onMessageHandlers.get(messageType) != null) {
            this.onMessageHandlers.get(messageType)(message);

        // } else if (this.onMessageHandlers['*'] != null) {
        //     this.onMessageHandlers.get(messageType)(type, message);

        } else if (messageType.indexOf("__") != 0) {
            trace("onMessage not registered for type " + type);
        }

    }

    private function getMessageHandlerKey(type: Dynamic): String {
        if (Std.isOfType(type, String)) {
            return type;

        } else if (Std.isOfType(type, Int)) {
            return "i" + type;

        } else {
            return "$" + Type.getClassName(Type.getClass(type));
        }
    }

    //
    // Reconnection logic
    //
    private function handleReconnection(code: Int) {
        if (!this.reconnection.enabled) {
            this.onLeave.dispatch(code);
            return;
        }

        var currentTime = Timer.stamp() * 1000;
        if (currentTime - this.joinedAtTime < this.reconnection.minUptime) {
            trace("[Colyseus reconnection]: ❌ Room has not been up for long enough for automatic reconnection. (min uptime: " + this.reconnection.minUptime + "ms)");
            this.onLeave.dispatch(CloseCode.ABNORMAL_CLOSURE);
            return;
        }

        if (!this.reconnection.isReconnecting) {
            this.reconnection.retryCount = 0;
            this.reconnection.isReconnecting = true;
        }

        this.retryReconnection();
    }

    private function retryReconnection() {
        if (this.reconnection.retryCount >= this.reconnection.maxRetries) {
            // No more retries
            trace("[Colyseus reconnection]: ❌ Reconnection failed after " + this.reconnection.maxRetries + " attempts.");
            this.reconnection.isReconnecting = false;
            this.onLeave.dispatch(CloseCode.FAILED_TO_RECONNECT);
            return;
        }

        this.reconnection.retryCount++;

        var delay = Math.min(
            this.reconnection.maxDelay,
            Math.max(
                this.reconnection.minDelay,
                this.exponentialBackoff(this.reconnection.retryCount, this.reconnection.delay)
            )
        );

        trace("[Colyseus reconnection]: ⏳ will retry in " + (delay / 1000) + " seconds...");

        // Wait before attempting reconnection
        Timer.delay(function() {
            trace("[Colyseus reconnection]: 🔄 Re-establishing sessionId '" + this.sessionId + "' with roomId '" + this.roomId + "'... (attempt " + this.reconnection.retryCount + " of " + this.reconnection.maxRetries + ")");

            var tokenParts = this.reconnectionToken.split(":");
            var reconnectToken = tokenParts.length > 1 ? tokenParts[1] : this.reconnectionToken;

            try {
                this.connection.reconnect({
                    reconnectionToken: reconnectToken,
                    skipHandshake: true // we already applied the handshake on first join
                });

            } catch (e:Dynamic) {
                this.retryReconnection();
            }
        }, Std.int(delay));
    }

    private function exponentialBackoff(attempt: Int, delay: Int): Float {
        return Math.floor(Math.pow(2, attempt) * delay);
    }

    private function enqueueMessage(message: Bytes) {
        this.reconnection.enqueuedMessages.push({ data: message });
        if (this.reconnection.enqueuedMessages.length > this.reconnection.maxEnqueuedMessages) {
            this.reconnection.enqueuedMessages.shift();
        }
    }
}
