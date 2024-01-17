package io.colyseus;

import tink.core.Future;
import tink.io.std.InputSource;
import tink.io.Source;

// TODO: implement cross-platform Storage
// is it possible via tink.io ?

class Storage {

    public static function getItem(key: String) {
        var fut = new tink.core.FutureTrigger<String>();
		// fut.trigger("dummy");
        return fut;
    }

    public static function setItem(key: String, value: String) {
    }

    public static function removeItem(key: String) {
    }

}
