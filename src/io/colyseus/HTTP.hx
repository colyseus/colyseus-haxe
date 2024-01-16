package io.colyseus;

import haxe.ds.Either;
using io.colyseus.events.EventHandler;

using io.colyseus.error.MatchMakeError;
using io.colyseus.error.HttpException;

typedef HttpOptions = {
    ?headers: Map<String, String>,
    ?body: Either<String, Dynamic>
}

@:keep
class HTTP {
    public var authToken: String;
    private var client: Client;

    public function new (client: Client) {
        this.client = client;
    }

    public function get(segments: String, options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request("GET", segments, options, callback);
    }

    public function post(segments: String, options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request("POST", segments, options, callback);
    }

    public function put(segments: String, options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request("PUT", segments, options, callback);
    }

    public function delete(segments: String, options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
		this.request("DELETE", segments, options, callback);
    }

    public function request(method: String, segments: String, options: HttpOptions, callback: (HttpException,Dynamic)->Void) {
        var req = new haxe.Http(this.buildHttpEndpoint(segments));

        if (options.body != null) {
            switch (options.body) {
                case Either.Left(s):
                    req.setPostData(s);
                case Either.Right(d):
                    req.setPostData(haxe.Json.stringify(d));
            }
            req.setHeader("Content-Type", "application/json");
        }

        req.setHeader("Accept", "application/json");

        if (options.headers != null) {
            for (header in options.headers.keys()) {
                req.setHeader(header, options.headers.get(header));
            }
        }

        if (this.authToken != null) {
            req.setHeader("Authorization", "Bearer " + this.authToken);
        }

        var responseStatus: Int = 0;
        req.onStatus = function(status) {
            responseStatus = status;
        };

        req.onData = function(json) {
            var response = haxe.Json.parse(json);

            if (response.error) {
                var code = responseStatus;
                var message = cast response.error;

                if (response.code != null) {
                    code = cast response.code;
                }

                callback(new HttpException(code, message), null);

            } else {
                callback(null, response);
            }
        };

        req.onError = function(err) {
            callback(new HttpException(responseStatus, err), null);
        };

        //
        // PUT/DELETE via POST (workaround)
        //
         if (method != "GET" && method != "POST") {
            req.setHeader("X-HTTP-Method-Override", method);
        }

        req.request(method != "GET");
    }

    public function buildHttpEndpoint(segments: String) {
        return '${(this.client.settings.useSSL) ? "https" : "http"}://${this.client.settings.hostname}${this.getEndpointPort()}/${segments}';
    }

    public function getEndpointPort() {
        return (this.client.settings.port != 80 && this.client.settings.port != 443)
            ? ':${this.client.settings.port}'
            : '';
    }
}
