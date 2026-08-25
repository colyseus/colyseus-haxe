package io.colyseus;

/**
 * Protocol codes occupy bits 0..4 of the leading message byte (values 0..31).
 * Bits 5..7 carry `ProtocolModifier` decorations, OR'd onto the base code at
 * send time. Decoders strip the modifier bits before dispatching:
 *
 *     var code = data.get(0) & ProtocolMasks.CODE;
 *     var modifiers = data.get(0) & ProtocolMasks.MODIFIERS;
 */
enum abstract Protocol(Int) to Int {
    // Room-related (10~18)
    var JOIN_ROOM = 10;
    var ERROR = 11;
    var LEAVE_ROOM = 12;
    var ROOM_DATA = 13;
    var ROOM_STATE = 14;
    var ROOM_STATE_PATCH = 15;
    // var ROOM_DATA_SCHEMA = 16; // deprecated in 0.18 — never dispatched
    var ROOM_DATA_BYTES = 17;
    var PING = 18; // ping/pong share this code (the server echoes it)

    // Input-related (19~20) — consumed by the input layer (not ported yet)
    var ROOM_INPUT_RELIABLE = 19;
    var ROOM_INPUT_UNRELIABLE = 20;

    // Request/response (21~22)
    var ROOM_REQUEST = 21;  // [byte, requestId varint, type(str|num), msgpack payload?]
    var ROOM_RESPONSE = 22; // [byte, requestId varint, status uint8, msgpack payload?]
}

class ProtocolMasks {
    /** Isolates the base protocol code (low 5 bits, values 0..31). */
    public static inline var CODE: Int = 0x1F;
    /** Isolates modifier bits (high 3 bits; only TIMED is assigned today). */
    public static inline var MODIFIERS: Int = 0xE0;
}

/**
 * Modifier bits OR'd into the leading protocol byte. Composable — the decoder
 * strips them in a preamble step that precedes the protocol-code dispatch.
 */
enum abstract ProtocolModifier(Int) to Int {
    /**
     * A `[uint32 sNow][uint32 inputSeq]` prefix precedes the body — server
     * time (ms since room start) + this client's last PROCESSED input seq.
     * Set by the server on ROOM_STATE / ROOM_STATE_PATCH whenever the room
     * called `defineInput()`.
     */
    var TIMED = 0x80;
}

/** Status byte of a ROOM_RESPONSE reply. */
enum abstract ResponseStatus(Int) to Int {
    var OK = 0;
    /** Deliberate, typed rejection — the authored reason rides as the payload. */
    var REJECTED = 1;
    /** Handler fault (threw / no handler) — payload is `{name, message, code?}`. */
    var ERROR = 2;
}

/**
 * Section tags for trailing tagged blobs in the JOIN_ROOM handshake payload:
 * `[tag uint8][length varint][payload]`, repeated until end-of-buffer.
 * Unknown tags are skipped via `length` (forward-compatible).
 */
enum abstract HandshakeSection(Int) to Int {
    /** Reflection bytes for the room's input schema (`defineInput()`). */
    var INPUT_REFLECTION = 1;
    /** Input feature flags + rates the client mirrors (`defineInput()`). */
    var INPUT_OPTIONS = 2;
}

/**
 * Bit flags in the leading byte of the INPUT_OPTIONS handshake section.
 * Some flags imply a trailing varint in the section payload, appended in
 * bit order.
 */
enum abstract InputFlags(Int) to Int {
    /** Reliable inputs carry the SNAPSHOT-timeline stamp (renderTime). */
    var RENDER_TIME = 1;
    /** A `[tickRate varint]` (Hz) follows — the server's fixed step rate. */
    var FIXED_TIMESTEP = 2;
    /** A `[patchRate varint]` (ms) follows — the state-patch interval. */
    var PATCH_RATE = 4;
    /** A `[subSteps varint]` follows — physics sub-steps per input tick. */
    var SUB_STEPS = 8;
    /** Reliable inputs carry the RECKON-timeline stamp (reckonTime). */
    var RECKON_TIME = 16;
}

enum abstract CloseCode(Int) to Int {
    var NORMAL_CLOSURE = 1000;
    var GOING_AWAY = 1001;
    var NO_STATUS_RECEIVED = 1005;
    var ABNORMAL_CLOSURE = 1006;

    var CONSENTED = 4000;
    var SERVER_SHUTDOWN = 4001;
    var WITH_ERROR = 4002;
    var FAILED_TO_RECONNECT = 4003;
    var MAY_TRY_RECONNECT = 4010;
}
