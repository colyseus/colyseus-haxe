package io.colyseus.serializer.schema;

import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.schema.types.IRef;
import io.colyseus.serializer.schema.Schema.OPERATION;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.types.ISchemaCollection;

class Callbacks {
    @:generic
    public static function get<T>(room: Room<T>): SchemaCallbacks<T> {
        var serializer: SchemaSerializer<T> = cast(room.serializer);
        return new SchemaCallbacks<T>(serializer.decoder);
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

@:generic
class SchemaCallbacks<T> {
    private var decoder: Decoder<T>;

    public function new (decoder: Decoder<T>) {
        this.decoder = decoder;
        this.decoder.triggerChanges = (changes: Array<DataChange>) -> this.triggerChanges(changes);
    }

	public function listen(
        instanceOrFieldName: Dynamic,
        callbackOrProperty: Dynamic,
        ?callback:Dynamic->Dynamic->Void
    ) {
        var instance: IRef;
        var fieldName: String;
        if (Std.isOfType(instanceOrFieldName, String)) {
            instance = cast this.decoder.state;
            fieldName = cast instanceOrFieldName;
            callback = cast callbackOrProperty;
        } else {
            instance = cast instanceOrFieldName;
            fieldName = cast callbackOrProperty;
        }
		return addCallback(instance.__refId, fieldName, callback);
	}

	public function onChange(instance: IRef, callback:Void->Void) {
		return addCallback(instance.__refId, OPERATION.REPLACE, callback);
	}

    public function onAdd(
        instanceOrFieldName: Dynamic,
        callbackOrProperty: Dynamic,
        ?callback:Dynamic->Dynamic->Void
    ) {
        var instance: IRef;
        var fieldName: String;
        if (Std.isOfType(instanceOrFieldName, String)) {
            instance = cast this.decoder.state;
            fieldName = cast instanceOrFieldName;
            callback = cast callbackOrProperty;
        } else {
            instance = cast instanceOrFieldName;
            fieldName = cast callbackOrProperty;
        }
        return addCallbackOrWaitCollectionAvailable(instance, fieldName, OPERATION.ADD, callback);
    }

    public function onRemove(
        instanceOrFieldName: Dynamic,
        callbackOrProperty: Dynamic,
        ?callback:Dynamic->Dynamic->Void
    ) {
        var instance: IRef;
        var fieldName: String;
        if (Std.isOfType(instanceOrFieldName, String)) {
            instance = cast this.decoder.state;
            fieldName = cast instanceOrFieldName;
            callback = cast callbackOrProperty;
        } else {
            instance = cast instanceOrFieldName;
            fieldName = cast callbackOrProperty;
        }
        return addCallbackOrWaitCollectionAvailable(instance, fieldName, OPERATION.DELETE, callback);
    }

    public function addCallbackOrWaitCollectionAvailable(
        instance: IRef,
        fieldName: String,
        operation: OPERATION,
        callback: Dynamic->Dynamic->Void
    ) {
        var _this = this;
        var removeHandler = () -> {}
        var removeCallback = () -> removeHandler();
        var collection: ISchemaCollection = Reflect.getProperty(instance, fieldName);
        if (collection == null) {
            removeHandler = listen(instance, fieldName, (coll, _) -> {
                removeHandler = _this.addCallback(coll.__refId, operation, callback);
            });
            return removeCallback;
        } else {
            return addCallback(collection.__refId, operation, callback);
        }
    }

	public function addCallback(refId: Int, operationOrFieldName:Dynamic, callback:Dynamic) {
        var callbacks = this.decoder.refs.callbacks.get(refId);
        if (callbacks == null) {
            callbacks = new Map<Dynamic, Array<Dynamic>>();
            this.decoder.refs.callbacks[refId] = callbacks;
        }

        // initialize list of callbacks
        if (callbacks.get(operationOrFieldName) == null) {
			callbacks.set(operationOrFieldName, new Array<Dynamic>());
        }

        callbacks[operationOrFieldName].push(callback);

        // //
        // // Trigger callback for existing elements
        // // - OPERATION.ADD
        // // - OPERATION.REPLACE
        // //
        // if (existing != null) {
        //     for (key => value in existing) {
        //         callback(value, key);
        //     }
        // }

        return () -> callbacks[operationOrFieldName].remove(callback);
    }

    public function triggerCallbacks0(callbacks:Map<Int, Array<Dynamic>>, op:Int) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(); }
    }

    public function triggerCallbacks1(callbacks:Map<Int, Array<Dynamic>>, op:Int, arg1: Dynamic) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(arg1); }
    }

    public function triggerCallbacks2(callbacks:Map<Int, Array<Dynamic>>, op:Int, arg1: Dynamic, arg2: Dynamic) {
        if (!callbacks.exists(op)) { return; }
        for (callback in callbacks[op]) { callback(arg1, arg2); }
    }

    public function triggerFieldCallbacks(callbacks:Map<String, Array<Dynamic>>, field:String, arg1: Dynamic, arg2: Dynamic) {
        if (!callbacks.exists(field)) { return; }
        for (callback in callbacks[field]) { callback(arg1, arg2); }
    }

	private function triggerChanges(allChanges:Array<DataChange>) {
		var uniqueRefIds = new Map<Int, Bool>();
        var callbacks = decoder.refs.callbacks;

		for (change in allChanges) {
			var refId = change.refId;
			var ref = this.decoder.refs.get(refId);
			var isSchema = Std.isOfType(ref, Schema);
			var callbacks = callbacks.get(refId);

			// no callbacks defined, skip this structure!
			if (callbacks == null) { continue; }

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
}