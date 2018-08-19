package org.msgpack.rpc;

#if !flash9
	#error "Not implemented for this target platform, flash9 only"
#end

import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequestMethod;

import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.Event;
import flash.events.SecurityErrorEvent;

import haxe.remoting.AsyncConnection;
import haxe.io.Bytes;
import haxe.Timer;

import org.msgpack.MsgPack;


class MsgPackRpcClient implements AsyncConnection implements Dynamic<AsyncConnection> {

	var data:{ url:String, error:Dynamic->Void };
	var path:Array<String>;
	var fnCb:Array<Dynamic->Void>;

	function new(data, path) {
		this.data = data;
		this.path = path;
		this.fnCb = [];
	}

	public function resolve(name):AsyncConnection {
		var mpc = new MsgPackRpcClient(this.data, this.path.copy());
		mpc.path.push(name);
		return mpc;
	}

	public function setErrorHandler(onError:Dynamic->Void):Void	{
		this.data.error = onError;
	}

	public function call(params:Array<Dynamic>, ?onResult:Dynamic->Void):Void {

		var req         = new URLRequest(this.data.url);
		req.contentType = "application/octet-stream";
		req.method      = URLRequestMethod.POST;
		
		// 0. msgid (0 = request)
		// 1. stamp, int32
		// 2. path, string
		// 3. params, array
		var data:Array<Dynamic> = [ 0, Std.int(Timer.stamp()), this.path.join("."), params ];
		req.data = MsgPack.encode(data).getData();
		
		fnCb[data[1]]   = onResult;

		var ldr         = new URLLoader();
		ldr.dataFormat  = URLLoaderDataFormat.BINARY;

		ldr.addEventListener(Event.COMPLETE, function(e:Event) {

			// 0. msgid (1 = response)
			// 1. stamp, int32
			// 2. error, dynamic
			// 3. result, dynamic
			var res:Array<Dynamic> = MsgPack.decode(Bytes.ofData(ldr.data));
			if (res[0] != 1 || res[2] != null) {
				if (this.data.error != null) {
					this.data.error({ error: "Invalid/error response", data: res });
				}
			}

			if (fnCb[res[1]] != null) {
				var fnResult = fnCb[res[1]];
				fnCb.splice(res[1], 1);
				fnResult(res[3]);
			}
		});

		ldr.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:HTTPStatusEvent) { 
			if (e.status >= 400) {
				// Error HTTP Status code
				if (this.data.error != null) {
					this.data.error(e);
				}
			}
		});

		ldr.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) { 
			if (this.data.error != null) {
				this.data.error(e); 
			}
		});

		ldr.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent) { 
			if (this.data.error != null) {
				this.data.error(e); 
			}
		});

		ldr.load(req);

	}

	public static function connect(url:String, name:String = ""):AsyncConnection {
		var mpc:AsyncConnection = new MsgPackRpcClient({ url: url, error: function(d) throw d }, []);
		return if (name != "") {
			var path = name.split(".");
			for (p in path) {
				mpc = mpc.resolve(p);
			}
			mpc;
		} else {
			mpc;
		}
	}
}
