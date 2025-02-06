package io.colyseus;

using haxe.Exception;
using io.colyseus.events.EventHandler;
using io.colyseus.error.HttpException;

@:keep
@:generic
typedef AuthData<T> = {
    ?token: String,
    ?user: T,
}

typedef HttpCallback = (HttpException,AuthData<Dynamic>)->Void;

@:keep
class Auth {
    public static var PATH = "/auth";

    private var http: HTTP;
    private var _token: String;
    private var _initialized: Bool;

    private var onChangeHandlers = new EventHandler<Dynamic->Void>();

    public function new (http: HTTP) {
        this.http = http;
        Storage.getItem("colyseus-auth-token").handle(function(token) {
            this.token = token;
        });
    }

    public var token (get, set): String;
    function get_token () : String { return this.http.authToken; }
    function set_token (value: String) : String {
        if (value == null) {
            Storage.removeItem("colyseus-auth-token");
        } else {
            Storage.setItem("colyseus-auth-token", value);
        }
        this.http.authToken = value;
        return value;
    }

    public function onChange(callback: (AuthData<Dynamic>)->Void) {
        this.onChangeHandlers += callback;

        if (!this._initialized) {
            this._initialized = true;
            this.getUserData(function(err, userData) {
                if (err != null) {
                    // user is not logged in, or service is down
                    this.emitChange({ user: null, token: null });

                } else {
                    this.emitChange(userData);
                }
            });
        }

		return function() {
			this.onChangeHandlers -= callback;
		};
    }

    public function getUserData(callback: HttpCallback) {
        if (this.token != null) {
            this.http.get(PATH + "/userdata", null, callback);
        } else {
            callback(new HttpException(-1, "missing auth.token"), null);
        }
    }

    public function registerWithEmailAndPassword(email: String, password: String, opts_or_callback: Dynamic, ?callback: HttpCallback) {
        var options: Dynamic = null;

        if (callback == null) {
            callback = opts_or_callback;
        } else {
            options = opts_or_callback;
        }

		this.http.post(PATH + "/register", {body: cast {email: email, password: password, options: options}}, function(err, data) {
            if (err != null) {
                callback(err, null);
            } else {
                this.emitChange(data);
                callback(null, data);
            }
        });
    }

    public function signInWithEmailAndPassword(email: String, password: String, callback: HttpCallback) {
        this.http.post(PATH + "/login", {body: cast {email: email, password: password}}, function(err, data) {
            if (err != null) {
                callback(err, null);
            } else {
                this.emitChange(data);
                callback(null, data);
            }
        });
    }

    public function signInAnonymously(opts_or_callback: Dynamic, ?callback: HttpCallback) {
        var options: Dynamic = null;

        if (callback == null) {
            callback = opts_or_callback;
        } else {
            options = opts_or_callback;
        }

        this.http.post(PATH + "/anonymous", {body: cast {options: options}}, function(err, data) {
            if (err != null) {
                callback(err, null);
            } else {
                this.emitChange(data);
                callback(null, data);
            }
        });
    }

    public function sendPasswordResetEmail(email: String, callback: HttpCallback) {
		this.http.post(PATH + "/forgot-password", {body: cast {email: email}}, function(err, data) {
            if (err != null) {
                callback(err, null);
            } else {
                callback(null, data);
            }
        });
    }

    public function signInWithProvider(providerName: String, ?options: Dynamic) {
        throw new Exception("not implemented");
    }

    public function signOut() {
        this.emitChange({ user: null, token: null });
    }

    public function emitChange(authData: AuthData<Dynamic>) {
		this.token = authData.token;
        this.onChangeHandlers.dispatch(authData);
    }

}
