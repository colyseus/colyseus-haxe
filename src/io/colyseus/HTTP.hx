package io.colyseus;

import haxe.ds.Either;

using io.colyseus.events.EventHandler;
using io.colyseus.error.MatchMakeError;
using io.colyseus.error.HttpException;

using tink.http.Method;
using tink.http.Header;

typedef HttpOptions = {
    ?headers: Map<String, String>,
    ?body: Dynamic
}

@:keep
class HTTP {
    public var authToken: String;
    private var client: Client;

    public function new (client: Client) {
        this.client = client;
    }

    public function get(segments: String, ?options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request(Method.GET, segments, options, callback);
    }

    public function post(segments: String, ?options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request(Method.POST, segments, options, callback);
    }

    public function put(segments: String, ?options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request(Method.PUT, segments, options, callback);
    }

    public function delete(segments: String, ?options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request(Method.DELETE, segments, options, callback);
    }

    public function request(method: Method, segments: String, ?options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
        var headers = new Array<HeaderField>();
        var body: String = "";

        if (options != null && options.body != null) {
            if (Std.isOfType(options.body, String)) {
                body = cast options.body;
            } else {
                body = haxe.Json.stringify(options.body);
            }
			headers.push(new HeaderField(HeaderName.CONTENT_TYPE, 'application/json'));
			headers.push(new HeaderField(HeaderName.CONTENT_LENGTH, body.length));
        }

        if (options != null && options.headers != null) {
            for (header in options.headers.keys()) {
                headers.push(new HeaderField(header, options.headers.get(header)));
            }
        }

        if (this.authToken != null) {
            headers.push(new HeaderField(HeaderName.AUTHORIZATION, 'Bearer ${this.authToken}'));
        }

        headers.push(new HeaderField(HeaderName.ACCEPT, 'application/json'));

        // trace("HTTP => " + method + " => " + this.buildHttpEndpoint(segments));
        // trace("Headers => " + headers);
        // trace("Body => " + body);

		tink.http.Client.fetch(this.buildHttpEndpoint(segments), {
			method: method,
			headers: headers,
			body: body,
		}).all().handle(function(o) switch o {
			case Success(res):
                var response = haxe.Json.parse(res.body);
                if (response.error) {
                    var code = res.header.statusCode;
                    var message = cast response.error;

                    if (response.code != null) {
                        code = cast response.code;
                    }

                    callback(new HttpException(code, message), null);

                } else {
                    callback(null, response);
                }

			case Failure(e):
                var message = e.message;

                if (Std.isOfType(e.data, String)) {
                    try {
						var response = haxe.Json.parse(e.data);
						if (response.error != null) {
							message = cast response.error;
						}
                    } catch (e: Dynamic) {
                        // ignore
                    }
                }

                callback(new HttpException(e.code, message), null);
		});
    }

    public function buildHttpEndpoint(segments: String) {
        if (segments.charAt(0) == "/") {
            segments = segments.substr(1);
        }
        return '${(this.client.settings.useSSL) ? "https" : "http"}://${this.client.settings.hostname}${this.getEndpointPort()}/${segments}';
    }

    public function getEndpointPort() {
        return (this.client.settings.port != 80 && this.client.settings.port != 443)
            ? ':${this.client.settings.port}'
            : '';
    }
}
