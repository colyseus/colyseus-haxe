package io.colyseus;

using io.colyseus.events.EventHandler;

@:keep
@:generic
typedef AuthData<T> = {
    ?token: String,
    ?user: T,
}

@:keep
class Auth {
    private var http: HTTP;
    private var _token: String;

    private var onChangeHandlers = new EventHandler<Dynamic->Void>();

    public function new (http: HTTP) {
        this.http = http;
    }

    public var token (get, set): String;
    function get_token () : String { return this.http.authToken; }
    function set_token (value: String) : String {
        this.http.authToken = value;
        return value;
    }

    public function emitChange() {
    }

}
