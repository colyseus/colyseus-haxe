package io.colyseus.state_listener;

typedef PatchObject = {
    path: Array<String>,
    operation: String,// "add" | "remove" | "replace";
    ?value: Dynamic
}

class Compare {

    public static function getPatchList(tree1: Dynamic, tree2: Dynamic) {
        var patches: Array<PatchObject> = [];
        generate(tree1, tree2, patches, []);
        return patches;
    }

    private static function concat(arr: Array<String>, value: String) {
        var newArr = arr.copy();
        newArr.push("" + value); // cast array indexes to string
        return newArr;
    }

    private static function objectKeys (obj: Dynamic): Array<Dynamic> {
        if (Std.is(obj, Array)) {
            var keys = new Array();
            var length: Int = ((cast (obj, Array<Dynamic>)).length);

            for (i in 0...length) {
                keys.push(i);
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
        var deleted = false;

        for (t in 0...oldKeys.length) {
            var key = oldKeys[t];

            var oldVal = getField(mirror, key);
            var newVal = getField(obj, key);

            // skip if value is the same
            if (oldVal == newVal) {
                continue;
            }

            if (
                newVal != null &&
                !(
                    newVal == null &&
                    oldVal != null &&
                    !Std.is(obj, Array)
                )
            ) {
                if (
                    oldVal != null && newVal != null &&
                    !isBasicType(oldVal) && !isBasicType(newVal) &&
                    (
                        (Std.is(obj, Array) && Std.is(mirror, Array)) ||
                        (Reflect.isObject(obj) && Reflect.isObject(mirror))
                    )
                ) {
                    generate(oldVal, newVal, patches, concat(path, key));
                }
                else {
                    if (oldVal != newVal) {
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

        var t = newKeys.length;
        while (--t >= 0) {
            var key: String = newKeys[t];

            if (!hasField(mirror, key) && hasField(obj, key)) {
                var newVal = getField(obj, key);
                var addPath = concat(path, key);

                if (
                    !isBasicType(newVal) &&
                    Reflect.isObject(newVal) &&
                    newVal != null
                ) {
                    // compare deeper additions
                    generate({}, newVal, patches, addPath);
                }

                patches.push({ operation: "add", path: addPath, value: newVal });
            }
        }
    }

    private static function isBasicType (value: Dynamic) {
        return (Std.is(value, String) || Std.is(value, Int) || Std.is(value, Float) || Std.is(value, Bool));
    }

    private static function getField(obj: Dynamic, field: Dynamic) {
        return Std.is(obj, Array)
            ? obj[field]
            : (Reflect.hasField(obj, field)
                ? Reflect.field(obj, field)
                : null);
    }

    private static function hasField (obj: Dynamic, field: Dynamic) {
        if (Std.is(obj, Array)) {
            return obj[field] != null;

        } else if (Std.string(obj) == "{}") {
            return false;

        } else {
            return Reflect.hasField(obj, field);
        }
    }

}

