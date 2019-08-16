package io.colyseus;

import haxe.ds.Map;
import haxe.Http;
import haxe.Json;

class Auth {
  public var token: String;

  private var endpoint: String;

  public function new(endpoint: String) {
    this.endpoint = StringTools.replace(endpoint, "ws", "http");
  }

  public function hasToken() {
    return this.token != null;
  }

  public function login() {
    var query = new Map<String, String>();
    // query["deviceId"] = this.getDeviceId();
    // query["platform"] = this.getPlatform();

    this.request("POST", "/auth", query);
  }

  private function getDeviceId() {
    return "";
  }

  private function getPlatform() {
    return "";
  }

  private function request(method: String, segments: String, ?query: Map<String, String>, ?body: String) {
    if (query == null) query = [];

    var queryString: Array<String> = [];
    for (field in query.keys()) { queryString.push(field + "=" + query[field]); }

    if (this.hasToken()) {
      query["token"] = this.token;
    }

    var req = new haxe.Http(this.endpoint + segments + "?" + queryString.join("&"));
    var responseBytes = new haxe.io.BytesOutput();

    if (this.hasToken()) {
      req.setHeader("authorization", "Bearer " + this.token);
    }

    if (body != null) {
      req.setPostData(body);
      req.setHeader("Content-Type", "application/json");
    }

    req.setHeader("Accept", "application/json");

    // req.onStatus = function(status) {
    // };

    req.onData = function(json) {
      trace("RESPONSE:" + json);
    };

    req.onError = function(err) {
      trace("onError");
      trace(err);
    };

#if js
    //
    // Need to install this module in the server
    // https://github.com/expressjs/method-override
    //
    req.setHeader('X-HTTP-Method-Override', method);
    req.request(true);
#else
    req.customRequest(false, responseBytes, null, method);
#end
  }

}