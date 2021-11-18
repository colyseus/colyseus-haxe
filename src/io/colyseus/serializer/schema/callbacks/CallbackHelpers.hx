package io.colyseus.serializer.schema.callbacks;

import io.colyseus.serializer.schema.types.ISchemaCollection;

class CallbackHelpers {
    public static function addCallback(
        callbacks: Map<Int, Array<Dynamic>>,
        op: Int,
        callback: Dynamic,
        ?existing: ISchemaCollection
    ) {
        // initialize list of callbacks
        if (callbacks.get(op) == null) {
			callbacks.set(op, new Array<Dynamic>());
        }

        callbacks[op].push(callback);

        //
        // Trigger callback for existing elements
        // - OPERATION.ADD
        // - OPERATION.REPLACE
        //
        if (existing != null) {
            for (it in existing.keyValueIterator()) {
                callback(it.value, it.key);
            }
        }

        return () -> callbacks[op].remove(callback);
    }

    public static function addPropertyCallback(
        callbacks: Map<String, Array<Dynamic>>,
        field: String,
        callback: Dynamic
    ) {
        // initialize list of callbacks
        if (callbacks.get(field) == null) {
			callbacks.set(field, new Array<Dynamic>());
        }

        callbacks[field].push(callback);

        return () -> callbacks[field].remove(callback);
    }

    public static function triggerCallbacks0(callbacks:Map<Int, Array<Dynamic>>, op:Int) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(); }
    }

    public static function triggerCallbacks1(callbacks:Map<Int, Array<Dynamic>>, op:Int, arg1: Dynamic) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(arg1); }
    }

    public static function triggerCallbacks2(callbacks:Map<Int, Array<Dynamic>>, op:Int, arg1: Dynamic, arg2: Dynamic) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(arg1, arg2); }
    }

    public static function triggerFieldCallbacks(callbacks:Map<String, Array<Dynamic>>, field:String, arg1: Dynamic, arg2: Dynamic) {
        if (!callbacks.exists(field)) { return; }
        for (callback in callbacks[field]) { callback(arg1, arg2); }
    }

    // static function removeChildRefs(this: CollectionSchema, changes: DataChange[]) {
    //     const needRemoveRef = (typeof (this.$changes.getType()) !== "string");

    //     this.$items.forEach((item: any, key: any) => {
    //         changes.push({
    //             refId: this.$changes.refId,
    //             op: OPERATION.DELETE,
    //             field: key,
    //             value: undefined,
    //             previousValue: item
    //         });

    //         if (needRemoveRef) {
    //             this.$changes.root.removeRef(item['$changes'].refId);
    //         }
    //     });
    // }

}