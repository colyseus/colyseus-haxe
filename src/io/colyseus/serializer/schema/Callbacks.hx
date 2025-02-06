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
        var collection: IRef = Reflect.getProperty(instance, fieldName);
        if (collection == null || collection.__refId == 0) {
            removeHandler = listen(instance, fieldName, (coll, _) -> {
                removeHandler = _this.addCallback((coll : IRef).__refId, operation, callback);
            });
            return removeCallback;
        } else {
            return addCallback(collection.__refId, operation, callback);
        }
    }

	public function addCallback(refId: Int, operationOrFieldName:Dynamic, callback:Dynamic) {
        var key = (Std.isOfType(operationOrFieldName, String))
            ? operationOrFieldName
            : "#" + operationOrFieldName;

        var callbacks = this.decoder.refs.callbacks.get(refId);
        if (callbacks == null) {
            callbacks = new Map<String, Array<Dynamic>>();
            this.decoder.refs.callbacks[refId] = callbacks;
        }

        // initialize list of callbacks
        if (callbacks.get(key) == null) {
			callbacks.set(key, new Array<Dynamic>());
        }

        callbacks[key].push(callback);

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

    public function triggerCallbacks0(callbacks:Map<String, Array<Dynamic>>, op:Int) {
        var key = "#" + op;
        if (!callbacks.exists(key)) { return; }
        for (callback in callbacks[key]) { callback(); }
    }

    public function triggerCallbacks2(callbacks:Map<String, Array<Dynamic>>, op:Int, arg1: Dynamic, arg2: Dynamic) {
        var key = "#" + op;
        if (!callbacks.exists(key)) { return; }
        for (callback in callbacks[key]) { callback(arg1, arg2); }
    }

    public function triggerFieldCallbacks(callbacks:Map<String, Array<Dynamic>>, field:String, arg1: Dynamic, arg2: Dynamic) {
        if (!callbacks.exists(field)) { return; }
        for (callback in callbacks[field]) { callback(arg1, arg2); }
    }

	private function triggerChanges(allChanges:Array<DataChange>) {
		var uniqueRefIds = new Map<Int, Bool>();
        var allCallbacks = decoder.refs.callbacks;

		for (change in allChanges) {
			var refId = change.refId;
			var ref = this.decoder.refs.get(refId);
			var isSchema = Std.isOfType(ref, Schema);
			var callbacks = allCallbacks.get(refId);

			// no callbacks defined, skip this structure!
			if (callbacks == null) { continue; }

			//
			// trigger onRemove on child structure.
			//
			if (((change.op & cast OPERATION.DELETE) == OPERATION.DELETE)
				&& Std.isOfType(change.previousValue, Schema)) {
                // TODO: get DELETE callbacks for this instance, and check if exists
                var deleteCallbacks: Map<String, Array<Dynamic>> = allCallbacks.get((change.previousValue : Schema).__refId);
                if (deleteCallbacks != null) {
                    triggerCallbacks0(deleteCallbacks, cast OPERATION.DELETE);
                }
			}

			if (isSchema) {
				if (!uniqueRefIds.exists(refId)) {
					// trigger onChange
					triggerCallbacks0(callbacks, cast OPERATION.REPLACE);
				}

                triggerFieldCallbacks(callbacks, change.field, change.value, change.previousValue);
			} else {
				var container = (ref : ISchemaCollection);

			    if ((change.op & cast OPERATION.DELETE) == OPERATION.DELETE) {
                    if (change.previousValue != null) {
                        // triger onRemove
                        triggerCallbacks2(callbacks, cast OPERATION.DELETE, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
                    }

                    // Handle DELETE_AND_ADD operations
                    if (((change.op & cast OPERATION.ADD) == OPERATION.ADD)) {
                        triggerCallbacks2(callbacks, cast OPERATION.ADD, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
                    }

                } else if ((change.op & cast OPERATION.ADD) == OPERATION.ADD && change.previousValue == null) {
                    // triger onAdd
                    triggerCallbacks2(callbacks, cast OPERATION.ADD, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
                }

				if (change.value != change.previousValue) {
                    triggerCallbacks2(callbacks, cast OPERATION.REPLACE, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
				}
			}

			uniqueRefIds.set(refId, true);
		}
	}
}