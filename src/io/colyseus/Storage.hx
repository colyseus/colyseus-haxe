package io.colyseus;

import tink.core.Future;

#if (flash)
import flash.net.SharedObject;
#end

class Storage {
    public static var PATH = "colyseus-storage";
    private static var inmemoryKV: Map<String, String> = new Map<String,String>();

    public static function getItem(key: String) {
        var fut = new tink.core.FutureTrigger<String>();
		fut.trigger(getData(key));
        return fut;
    }

	public static function setItem(key:String, value:String) {
        setData(key, value);
    }

    public static function removeItem(key: String) {
        removeData(key);
    }

    #if (js)
	private static function getData(name:String)
	{
		final storage = js.Browser.getLocalStorage();
		if (storage == null) {
			return inmemoryKV[name];
        }
		return storage.getItem(PATH + ":" + name);
	}

	private static function setData(name:String, value:String)
	{
		final storage = js.Browser.getLocalStorage();
		if (storage == null) {
            inmemoryKV[name] = value;
			return null;
        }
		return storage.setItem(PATH + ":" + name, value);
	}

	private static function removeData(name:String)
	{
		final storage = js.Browser.getLocalStorage();
		if (storage == null) {
            inmemoryKV[name] = null;
			return null;
        }
		return storage.removeItem(PATH + ":" + name);
	}

	#elseif (flash)

	// Private helper to get the SharedObject instance
	private static function getSharedObject():SharedObject {
		return SharedObject.getLocal(PATH);
	}

	private static function getData(name:String):String {
		var so:SharedObject = getSharedObject();
		// Check if the key exists in the SharedObject's data

		if (Reflect.hasField(so.data, name)) {
			return Reflect.getProperty(so.data, name);
		}
		return null;
	}

	private static function setData(name:String, value:String):Void {
		var so:SharedObject = getSharedObject();
		// Set the value for the given name (key)
		Reflect.setProperty(so.data, name, value);
		// Save the data to disk
		so.flush();
	}

	private static function removeData(name:String):Void {
		var so:SharedObject = getSharedObject();
		// Remove the specific key if it exists
		if (Reflect.hasField(so.data, name)) {
			Reflect.deleteField(so.data, name);
			so.flush(); // Persist the change
		}
	}

    #else

	private static function getData(name:String)
	{
		var path = haxe.io.Path.normalize(PATH + "_" + name + ".cache");
		if (sys.FileSystem.exists(path)) {
			return sys.io.File.getContent(path);
        }
        return null;
	}

	private static function setData(name:String, value:String)
	{
		var path = haxe.io.Path.normalize(PATH + "_" + name + ".cache");
        var writer = sys.io.File.write(path);
		writer.writeString(value);
		writer.close();
	}

	private static function removeData(name:String)
	{
		var path = haxe.io.Path.normalize(PATH + "_" + name + ".cache");
        if (sys.FileSystem.exists(path)) {
			sys.FileSystem.deleteFile(path);
        }
	}

    #end

}
