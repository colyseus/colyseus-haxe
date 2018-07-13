package io.colyseus.state_listener;

typedef PatchObject = {
    path: Array<String>,
    operation: String,// "add" | "remove" | "replace";
    ?value: Dynamic
}

class Compare {

    public static function compare(tree1: Dynamic, tree2: Dynamic) {
        var patches: Array<PatchObject> = [];
        generate(tree1, tree2, patches, []);
        return patches;
    }

    private static function concat(arr: Array<String>, value: String) {
        var newArr = arr.copy();
        newArr.push(value);
        return newArr;
    }

    private static function objectKeys (obj: Dynamic): Array<String> {
        if (Std.is(obj, Array)) {
            var keys = new Array();
            var length: Int = ((cast (obj, Array<Dynamic>)).length) - 1;

            for (i in 0...length) {
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
        var newKeys = objectKeys(obj);
        var oldKeys = objectKeys(mirror);
        var changed = false;
        var deleted = false;

        var t = oldKeys.length;
        while (--t >= 0) {
            var key = oldKeys[t];
            var oldVal = Reflect.getProperty(mirror, key);
            var newVal = Reflect.getProperty(mirror, key);

            // if (obj.hasOwnProperty(key) && !(obj[key] == undefined && oldVal != undefined && Array.isArray(obj) == false)) {
            if (
                Reflect.hasField(obj, key) &&
                newVal != null &&
                !(
                    !Reflect.hasField(obj, key) && Reflect.hasField(mirror, key)
                )
            ) {
                if (
                    Reflect.isObject(oldVal) &&
                    oldVal != null &&
                    Reflect.isObject(newVal) &&
                    newVal != null
                ) {
                    generate(oldVal, newVal, patches, concat(path, key));
                }
                else {
                    if (oldVal != newVal) {
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

        var t = oldKeys.length;
        while (--t >= 0) {
            var key: String = newKeys[t];
            var newVal = Reflect.getProperty(obj, key);
            if (newVal != null) {
                var addPath = concat(path, key);

                // compare deeper additions
                if (Reflect.isObject(newVal) && newVal != null) {
                    generate({}, newVal, patches, addPath);
                }

                patches.push({ operation: "add", path: addPath, value: newVal });
            }
        }
    }

}

