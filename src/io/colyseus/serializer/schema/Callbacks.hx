package io.colyseus.serializer.schema;

import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Schema.OPERATION;
import io.colyseus.serializer.schema.types.IRef;
import io.colyseus.serializer.schema.types.ISchemaCollection;

class Callbacks {
    public static function get<T>(room: Room<T>): SchemaCallbacks<T> {
        var serializer: SchemaSerializer<T> = cast(room.serializer);
        var callbacks = new SchemaCallbacks<T>(serializer.decoder);
        // When used with a Room, enable main-thread callback processing
        // on sys targets (websocket runs on a separate thread).
        callbacks.enableMainLoopProcessing();
        return callbacks;
    }

    public static function removeChildRefs(collection: ISchemaCollection, changes: Array<DataChange>, refs: ReferenceTracker) {
        var needRemoveRef = !Std.isOfType(collection._childType, String);

        for (key => item in collection) {
            changes.push({
                refId: collection.__refId,
                op: cast OPERATION.DELETE,
                field: Std.string(key),
                value: null,
                previousValue: item
            });

            if (needRemoveRef) {
                refs.remove((item : IRef).__refId);
            }
        }
    }
}

@:generic
class SchemaCallbacks<T> {
    private var decoder: Decoder<T>;
    private var isTriggering: Bool = false;

    #if sys
    private var _pendingChanges:Array<Array<DataChange>> = [];
    private var _mutex = new sys.thread.Mutex();
    private var _mainLoopEntry:haxe.MainLoop.MainLoopEntry = null;
    #end

    public function new (decoder: Decoder<T>) {
        this.decoder = decoder;
        this.decoder.triggerChanges = (changes: Array<DataChange>) -> this.triggerChanges(changes);
    }

    /**
     * Enable thread-safe callback processing via haxe.MainLoop.
     * On sys targets, callbacks from the websocket thread are queued
     * and fired on the main thread. Call this after Callbacks.get(room).
     */
    public function enableMainLoopProcessing() {
        #if sys
        this.decoder.triggerChanges = (changes: Array<DataChange>) -> {
            _mutex.acquire();
            _pendingChanges.push(changes);
            _mutex.release();
        };
        if (_mainLoopEntry == null) {
            _mainLoopEntry = haxe.MainLoop.add(() -> processPendingChanges());
        }
        #end
    }

    #if sys
    private function processPendingChanges() {
        _mutex.acquire();
        var batches = _pendingChanges;
        _pendingChanges = [];
        _mutex.release();

        for (changes in batches) {
            triggerChanges(changes);
        }
    }
    #end

	public function listen(
        instanceOrFieldName: Dynamic,
        fieldNameOrCallback: Dynamic,
        ?callbackOrImmediate:Dynamic,
        ?immediate:Bool = true
    ) {
        var instance: IRef;
        var fieldName: String;
        var callback: Dynamic->Dynamic->Void;
        if (Std.isOfType(instanceOrFieldName, String)) {
            instance = cast this.decoder.state;
            fieldName = cast instanceOrFieldName;
            callback = cast fieldNameOrCallback;
            immediate = callbackOrImmediate != null ? cast callbackOrImmediate : true;
        } else {
            instance = cast instanceOrFieldName;
            fieldName = cast fieldNameOrCallback;
            callback = cast callbackOrImmediate;
        }

        var existing = Reflect.getProperty(instance, fieldName);
        if (
            existing != null && Std.isOfType(existing, IRef) &&
            immediate == true && !this.isTriggering
        ) {
            var existingRef:IRef = cast existing;
            if (existingRef.__refId != 0) {
                callback(existing, null);
            }
        }

		return addCallback2(instance.__refId, fieldName, callback);
	}

    public function onAdd(
        instanceOrFieldName: Dynamic,
        fieldNameOrCallback: Dynamic,
        ?callbackOrImmediate: Dynamic,
        ?immediate:Bool = true
    ) {
        var instance: IRef;
        var fieldName: String;
        var callback: Dynamic->Dynamic->Void;
        if (Std.isOfType(instanceOrFieldName, String)) {
            instance = cast this.decoder.state;
            fieldName = cast instanceOrFieldName;
            callback = cast fieldNameOrCallback;
            immediate = callbackOrImmediate != null ? cast callbackOrImmediate : true;
        } else {
            instance = cast instanceOrFieldName;
            fieldName = cast fieldNameOrCallback;
            callback = cast callbackOrImmediate;
        }
        return addCallbackOrWaitCollectionAvailable(instance, fieldName, OPERATION.ADD, callback, immediate);
    }

    public function onChange(
        instanceOrFieldName: Dynamic,
        callbackOrFieldName: Dynamic,
        ?callback: Dynamic->Dynamic->Void
    ) {
        if (callback != null) {
            // 3-arg form: onChange(instance, "field", (value, key) -> ...)
            // Registers as REPLACE on a collection
            var instance: IRef = cast instanceOrFieldName;
            var fieldName: String = cast callbackOrFieldName;
            return addCallbackOrWaitCollectionAvailable(instance, fieldName, OPERATION.REPLACE, callback);
        } else if (Std.isOfType(instanceOrFieldName, String)) {
            // 2-arg shorthand: onChange("field", (value, key) -> ...)
            var fieldName: String = cast instanceOrFieldName;
            var cb2: Dynamic->Dynamic->Void = cast callbackOrFieldName;
            var instance: IRef = cast this.decoder.state;
            return addCallbackOrWaitCollectionAvailable(instance, fieldName, OPERATION.REPLACE, cb2);
        } else {
            // 2-arg form: onChange(instance, () -> ...)
            var instance: IRef = cast instanceOrFieldName;
            var cb0: Void->Void = cast callbackOrFieldName;
            return addCallback0(instance.__refId, "#" + cast(OPERATION.REPLACE, Int), cb0);
        }
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
        callback: Dynamic->Dynamic->Void,
        ?immediate: Bool = true
    ) {
        var _this = this;
        var removeHandler = () -> {}
        var removeCallback = () -> removeHandler();
        var collection: ISchemaCollection = Reflect.getProperty(instance, fieldName);
        if (collection == null || collection.__refId == 0) {
            var removePropertyCallback: Void->Void = () -> {};
            removePropertyCallback = listen(instance, fieldName, (coll, _) -> {
                if (coll != null) {
                    // Remove the property listener now that collection is available
                    removePropertyCallback();
                    removeHandler = _this.addCallback2((coll : IRef).__refId, "#" + cast(operation, Int), callback);
                }
            });
            removeHandler = removePropertyCallback;
            return removeCallback;
        } else {
            if (operation == OPERATION.ADD && immediate && !this.isTriggering) {
                for (key => value in collection) {
                    callback(value, key);
                }
            }
            return addCallback2(collection.__refId, "#" + cast(operation, Int), callback);
        }
    }

    // 0-arg callbacks (onChange)
	public function addCallback0(refId: Int, key: String, callback: Void->Void) {
        var callbackMap = this.decoder.refs.callbacks0.get(refId);
        if (callbackMap == null) {
            callbackMap = new Map<String, Array<Void->Void>>();
            this.decoder.refs.callbacks0[refId] = callbackMap;
        }
        if (callbackMap.get(key) == null) {
			callbackMap.set(key, new Array<Void->Void>());
        }
        callbackMap[key].push(callback);
        return () -> callbackMap[key].remove(callback);
    }

    // 2-arg callbacks (listen, onAdd, onRemove)
    public function addCallback2(refId: Int, key: String, callback: Dynamic->Dynamic->Void) {
        var callbackMap = this.decoder.refs.callbacks2.get(refId);
        if (callbackMap == null) {
            callbackMap = new Map<String, Array<Dynamic->Dynamic->Void>>();
            this.decoder.refs.callbacks2[refId] = callbackMap;
        }
        if (callbackMap.get(key) == null) {
			callbackMap.set(key, new Array<Dynamic->Dynamic->Void>());
        }
        callbackMap[key].push(callback);
        return () -> callbackMap[key].remove(callback);
    }

    public function triggerCallbacks0(callbacks0: Map<String, Array<Void->Void>>, op: Int) {
        var key = "#" + op;
        if (!callbacks0.exists(key)) { return; }
        isTriggering = true;
        for (callback in callbacks0[key]) { callback(); }
        isTriggering = false;
    }

    public function triggerCallbacks2(callbacks2: Map<String, Array<Dynamic->Dynamic->Void>>, op: Int, arg1: Dynamic, arg2: Dynamic) {
        var key = "#" + op;
        if (!callbacks2.exists(key)) { return; }
        isTriggering = true;
        for (callback in callbacks2[key]) { callback(arg1, arg2); }
        isTriggering = false;
    }

	private function triggerChanges(allChanges:Array<DataChange>) {
		var uniqueRefIds = new Map<Int, Bool>();
        var allCallbacks0 = decoder.refs.callbacks0;
        var allCallbacks2 = decoder.refs.callbacks2;

		for (change in allChanges) {
			var refId = change.refId;
			var ref = this.decoder.refs.get(refId);
			var isSchema = Std.isOfType(ref, Schema);
			var cbs0 = allCallbacks0.get(refId);
			var cbs2 = allCallbacks2.get(refId);

			// no callbacks defined, skip this structure!
			if (cbs0 == null && cbs2 == null) { continue; }

			//
			// trigger onRemove on child structure.
			//
			if (((change.op & cast OPERATION.DELETE) == OPERATION.DELETE)
				&& Std.isOfType(change.previousValue, Schema)) {
                var deleteCbs0 = allCallbacks0.get((change.previousValue : Schema).__refId);
                if (deleteCbs0 != null) {
                    triggerCallbacks0(deleteCbs0, cast OPERATION.DELETE);
                }
			}

			if (isSchema) {
				if (!uniqueRefIds.exists(refId)) {
					// trigger onChange
					if (cbs0 != null) {
						triggerCallbacks0(cbs0, cast OPERATION.REPLACE);
					}
				}

                // trigger .listen() on property callbacks
				if (cbs2 != null && cbs2.exists(change.field)) {
					isTriggering = true;

					// iterate a copy — deferred listeners may remove themselves during iteration
					var fieldCallbacks:Array<Dynamic->Dynamic->Void> = cbs2[change.field];
					for (callback in fieldCallbacks.copy()) {
						callback(change.value, change.previousValue);
					}

					isTriggering = false;
				}

			} else {
				if (cbs2 != null) {
					if ((change.op & cast OPERATION.DELETE) == OPERATION.DELETE) {
						if (change.previousValue != null) {
							// trigger onRemove
							triggerCallbacks2(cbs2, cast OPERATION.DELETE, change.previousValue, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
						}

						// Handle DELETE_AND_ADD operations
						if (((change.op & cast OPERATION.ADD) == OPERATION.ADD)) {
							triggerCallbacks2(cbs2, cast OPERATION.ADD, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
						}

					} else if ((change.op & cast OPERATION.ADD) == OPERATION.ADD && change.previousValue != change.value) {
						// trigger onAdd
						triggerCallbacks2(cbs2, cast OPERATION.ADD, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
					}

					if (change.value != change.previousValue) {
						triggerCallbacks2(cbs2, cast OPERATION.REPLACE, change.value, (change.dynamicIndex == null) ? change.field : change.dynamicIndex);
					}
				}
			}

			uniqueRefIds.set(refId, true);
		}
	}
}
