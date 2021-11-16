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