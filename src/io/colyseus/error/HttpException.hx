package io.colyseus.error;

class HttpException {
    public var code: Int;
    public var message: String;

    public function new(code: Int, message: String) {
        this.code = code;
        this.message = message;
    }
}
