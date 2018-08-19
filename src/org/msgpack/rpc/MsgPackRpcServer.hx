package org.msgpack.rpc;

#if !php 
	#error "Not implemented for this target platform, php only"
#end

import haxe.remoting.Context;
import org.msgpack.MsgPack;
import php.Web;
import sys.io.File;

class MsgPackRpcServer {
	public static function run(ctx:Context) {
		if (Web.getMethod() != "POST") {
			Web.setReturnCode(501);
			return;
		}

		var inp = File.read("php://input", true);
		inp.bigEndian = true;
		var msg = MsgPack.decode(inp.readAll());

		if (msg == null || msg[0] > 0) {
			Web.setReturnCode(501);
			return;
		}
		
		var res = [ 1, msg[1], null, ctx.call(cast(msg[2]).split("."), cast(msg[3])) ];
		var out = File.write("php://output", true);
		out.bigEndian = true;
		out.write(MsgPack.encode(res));
	}
}
