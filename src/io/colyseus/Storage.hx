package io.colyseus;

import tink.core.Future;

class Storage {
    public static var PATH = "colyseus-storage";

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
            trace("[Colyseus Storage] localStorage is not available");
			return null;
        }
		return storage.getItem(PATH + ":" + name);
	}

	private static function setData(name:String, value:String)
	{
		final storage = js.Browser.getLocalStorage();
		if (storage == null) {
            trace("[Colyseus Storage] localStorage is not available");
			return null;
        }
		return storage.setItem(PATH + ":" + name, value);
	}

	private static function removeData(name:String)
	{
		final storage = js.Browser.getLocalStorage();
		if (storage == null) {
            trace("[Colyseus Storage] localStorage is not available");
			return null;
        }
		return storage.removeItem(PATH + ":" + name);
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
