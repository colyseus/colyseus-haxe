package io.colyseus.error;

//
// TODO: extend from haxe.Exception (Haxe 4.1.0)
//
class MatchMakeError {
    public var code: Int;
    public var message: String;

    public function new(code: Int, message: String) {
        this.code = code;
        this.message = message;
    }
}