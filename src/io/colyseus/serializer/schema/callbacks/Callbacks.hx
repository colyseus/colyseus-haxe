package io.colyseus.serializer.schema.callbacks;

import io.colyseus.serializer.schema.Schema.OPERATION;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.types.ISchemaCollection;

@:generic
class Callbacks<T> {
    private var decoder: Decoder<T>;
	private var callbacks:Map<Int, Array<Dynamic>> = new Map();

    public function new (decoder: Decoder<T>) {
        this.decoder = decoder;
        this.decoder.triggerChanges = (changes: Array<DataChange>) -> this.triggerChanges(changes);
    }

	// TODO: it would be great to have this strictly typed.
	public function listen(property:String, callback:Dynamic->Dynamic->Void, immediate:Bool = true) {
		if (this.callbacks == null) { this.callbacks = new Map<Int, Array<Dynamic>>(); }

		if (immediate && Reflect.hasField(this, property)) {
			callback(Reflect.getProperty(this, property), null);
		}

		return addCallback(this.callbacks, property, callback);
	}

    public function addCallback(
        callbacks: Map<Int, Array<Dynamic>>,
        // op: Int,
        op: Dynamic,
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
            for (key => value in existing) {
                callback(value, key);
            }
        }

        return () -> callbacks[op].remove(callback);
    }

    public function addPropertyCallback(
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

	private function triggerChanges(allChanges:Array<DataChange>) {
		var uniqueRefIds = new Map<Int, Bool>();

		for (change in allChanges) {
			var refId = change.refId;
			var ref = this.decoder.refs.get(refId);
			var isSchema = Std.isOfType(ref, Schema);
			var callbacks = Reflect.getProperty(ref, "_callbacks");

			//
			// trigger onRemove on child structure.
			//
			if (((change.op & cast OPERATION.DELETE) == OPERATION.DELETE)
				&& Std.isOfType(change.previousValue, Schema)) {
                // TODO: get DELETE callbacks for this instance, and check if exists
                var callbacks: Map<Int, Array<Dynamic>> = null;
                if (callbacks != null) {
                    triggerCallbacks0(callbacks, cast OPERATION.DELETE);
                }
			}

			// no callbacks defined, skip this structure!
			if (callbacks == null) {
				continue;
			}

			if (isSchema) {
				if (!uniqueRefIds.exists(refId)) {
					// trigger onChange
					triggerCallbacks1(callbacks, cast OPERATION.REPLACE, allChanges);
				}

				var propertyCallbacks = Reflect.getProperty(ref, "_propertyCallbacks");
				if (propertyCallbacks != null) {
					triggerFieldCallbacks(propertyCallbacks, change.field, change.value, change.previousValue);
				}
			} else {
				var container = (ref : ISchemaCollection);

				if (change.op == OPERATION.ADD && change.previousValue == null) {
					// container.invokeOnAdd(change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);

				} else if (change.op == OPERATION.DELETE) {
					//
					// FIXME: `previousValue` should always be avaiiable.
					// ADD + DELETE operations are still encoding DELETE operation.
					//
					if (change.previousValue != null) {
						// container.invokeOnRemove(change.previousValue, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
					}
				} else if (change.op == OPERATION.DELETE_AND_ADD) {
					if (change.previousValue != null) {
						// container.invokeOnRemove(change.previousValue, change.dynamicIndex);
					}
					// container.invokeOnAdd(change.value, change.dynamicIndex);
				}

				if (change.value != change.previousValue) {
					// container.invokeOnChange(change.value, change.dynamicIndex);
				}
			}

			uniqueRefIds.set(refId, true);
		}
	}

    public static function removeChildRefs(collection: ISchemaCollection, changes: Array<DataChange>, refs: ReferenceTracker) {
        var needRemoveRef = !Std.isOfType(collection._childType, String);

        for (key => item in collection) {
            changes.push({
                refId: collection.__refId,
                op: cast OPERATION.DELETE,
                field: key,
                value: null,
                previousValue: item
            });

            if (needRemoveRef) {
                refs.remove(Reflect.getProperty(item, "__refId"));
            }
        }
    }

}