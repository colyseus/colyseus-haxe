package io.colyseus.state_listener;

interface PatchObject {
    public var path: Array<String>;
    public var operation: String;// "add" | "remove" | "replace";
    public var value: Dynamic;
}

class Compare {

    public static function compare() {
        var patches: Array<PatchObject> = [];
        this.generate(tree1, tree2, patches, []);
        return patches;
    }

    private static function concat(arr: Array<String>, value: String) {
        var newArr = arr.slice();
        newArr.push(value);
        return newArr;
    }

    private static function objectKeys (obj: Dynamic): Array<String> {
        if (Std.is(obj, Array)) {
            var keys = new Array();
            var length: Int = (cast obj.length) - 1;

            for (i in 0..length) {
                keys.push("" + i);
            }

            return keys;
        }

        if (Std.is(obj, Map)) {
            return obj.keys();
        }

        return Reflect.fields(obj);
    };

    // Dirty check if obj is different from mirror, generate patches and update mirror
    private static function generate(mirror: Dynamic, obj: Dynamic, patches: Array<PatchObject>, path: Array<String>) {
        var newKeys = this.objectKeys(obj);
        var oldKeys = this.objectKeys(mirror);
        var changed = false;
        var deleted = false;

        for (var t = oldKeys.length - 1; t >= 0; t--) {
            var key = oldKeys[t];
            var oldVal = mirror[key];
            if (obj.hasOwnProperty(key) && !(obj[key] === undefined && oldVal !== undefined && Array.isArray(obj) === false)) {
                var newVal = obj[key];
                if (typeof oldVal == "object" && oldVal != null && typeof newVal == "object" && newVal != null) {
                    generate(oldVal, newVal, patches, concat(path, key));
                }
                else {
                    if (oldVal !== newVal) {
                        changed = true;
                        patches.push({operation: "replace", path: concat(path, key), value: newVal});
                    }
                }
            }
            else {
                patches.push({operation: "remove", path: concat(path, key)});
                deleted = true; // property has been deleted
            }
        }

        if (!deleted && newKeys.length == oldKeys.length) {
            return;
        }

        for (var t = newKeys.length - 1; t >= 0; t--) {
            var key = newKeys[t];
            if (!mirror.hasOwnProperty(key) && obj[key] !== undefined) {
                var newVal = obj[key];
                var addPath = concat(path, key);
                // compare deeper additions
                if (typeof newVal == "object" && newVal != null) {
                    generate({}, newVal, patches, addPath);
                }
                patches.push({ operation: "add", path: addPath, value: newVal });
            }
        }
    }

}

