package io.colyseus.error;

class HttpException {
    /**
     * For a failed matchmaking request (`join()`, `joinOrCreate()`, `create()`,
     * `joinById()`, `reconnect()`): the server's `ErrorCode` (e.g. 520, 525),
     * or the code of a `ServerError` the room threw. For other `client.http`
     * requests: the HTTP status.
     */
    public var code: Int;
    public var message: String;

    /** The error response's parsed JSON body, or `null` when it had none. */
    public var data: Dynamic;

    public function new(code: Int, message: String, ?data: Dynamic) {
        this.code = code;
        this.message = message;
        this.data = data;
    }
}
