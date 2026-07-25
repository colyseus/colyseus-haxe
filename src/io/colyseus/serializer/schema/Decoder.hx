package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.MapSchema.IMapSchema;
import io.colyseus.serializer.schema.types.ArraySchema.IArraySchema;
import io.colyseus.serializer.schema.types.IRef;
import io.colyseus.serializer.schema.types.ISchemaCollection;
import io.colyseus.serializer.schema.Schema.It;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Schema.SPEC;
import io.colyseus.serializer.schema.Schema.OPERATION;

import io.colyseus.serializer.schema.encoding.Decode;
import haxe.io.Bytes;

typedef DecodedValue = { value : Dynamic, previousValue : Dynamic };

// resync bookkeeping: identities visited per collection refId (map string
// keys + array indexes kept in separate domains — no Dynamic-keyed sets).
typedef ResyncVisited = { keys: Map<String, Bool>, indexes: Map<Int, Bool> };

@:generic
class Decoder<T> {
	public var state:T;
	public var context:TypeContext = new TypeContext();
	public var refs:ReferenceTracker = new ReferenceTracker();
	public var triggerChanges:(Array<DataChange>) -> Void = (_:Array<DataChange>) -> {};

	// non-null only while decodeResync() is in progress — its non-nullness
	// IS the resync-mode flag (see PORTING_RESYNC.md in @colyseus/schema)
	public var resyncVisited: Map<Int, ResyncVisited> = null;
	public var resyncDamaged: Bool = false;

	private var allChanges:Array<DataChange>;

	public function new(state:T) {
		this.state = state;
		this.refs.add(0, state);
	}

	/**
	 * Full-snapshot reconciliation ("resync") decode.
	 *
	 * Behaves exactly like `decode()`, plus: every collection entry the
	 * payload does NOT mention is removed through the regular DELETE path —
	 * `onRemove` callbacks fire with the real previous value and released
	 * refs are garbage-collected. Use it to apply a rejoin/reconnect full
	 * state over an existing decoded tree.
	 *
	 * ONLY valid for full-snapshot payloads (`encodeAll` output). Calling it
	 * on an incremental patch would prune everything the patch doesn't touch.
	 */
	public function decodeResync(bytes:Bytes, it:It = null) {
		resyncVisited = new Map();
		resyncDamaged = false;
		try {
			decode(bytes, it);
			resyncVisited = null;
		} catch (e:Dynamic) {
			resyncVisited = null; // no try/finally in Haxe — reset on both paths
			throw e;
		}
	}

	public function decode(bytes:Bytes, it:It = null) {
		if (it == null) {
			it = {offset: 0};
		}

		allChanges = new Array<DataChange>();

		var refId = 0;
		var ref:Dynamic = this.state;

		var totalBytes = bytes.length;
		while (it.offset < totalBytes) {
			if (bytes.get(it.offset) == SPEC.SWITCH_TO_STRUCTURE) {
				it.offset++;

				refId = Decode.number(bytes, it);

				if (Std.isOfType(ref, IArraySchema)) {
					(ref : IArraySchema).__onDecodeEnd();
				}

				var nextRef:Dynamic = refs.get(refId);

				//
				// Trying to access a reference that haven't been decoded yet.
				//
				if (nextRef == null) {
					trace("WARNING: @colyseus/schema refId not found: " + refId);
					skipCurrentStructure(bytes, it, totalBytes);
				} else {
					ref = nextRef;
				}

				continue;
			}

			var isSchemaDefinitionMismatch = false;

			if (Std.isOfType(ref, Schema)) {
				isSchemaDefinitionMismatch = !decodeSchema(bytes, it, (ref : Schema));

            } else if (Std.isOfType(ref, IMapSchema)) {
				isSchemaDefinitionMismatch = !decodeMapSchema(bytes, it, (ref : IMapSchema));

            } else if (Std.isOfType(ref, IArraySchema)) {
				isSchemaDefinitionMismatch = !decodeArraySchema(bytes, it, (ref : IArraySchema));

            }

            if (isSchemaDefinitionMismatch) {
				trace("WARNING: @colyseus/schema definition mismatch?");
				skipCurrentStructure(bytes, it, totalBytes);
				continue;
			}
		}

		if (Std.isOfType(ref, IArraySchema)) {
			(ref : IArraySchema).__onDecodeEnd();
		}

		// resync mode: prune everything the snapshot didn't visit. Runs
		// before triggerChanges (DELETE changes fire onRemove with the real
		// previousValue) and before GC (refs.remove feeds deletedRefs).
		if (resyncVisited != null) { resyncSweep(); }

		this.triggerChanges(allChanges);

		refs.garbageCollection();
	}

	//
	// keep skipping next bytes until reaches a known structure
	// by local decoder.
	//
	private function skipCurrentStructure(bytes:Bytes, it:It, totalBytes:Int) {
		// a skipped range can swallow other structures' ops — resync
		// visited data is no longer trustworthy
		if (resyncVisited != null) { resyncDamaged = true; }

		var nextIterator:It = {offset: it.offset};

		while (it.offset < totalBytes) {
			if (bytes.get(it.offset) == SPEC.SWITCH_TO_STRUCTURE) {
				nextIterator.offset = it.offset + 1;
				if (refs.has(Decode.number(bytes, nextIterator))) {
					break;
				}
			}

			it.offset++;
		}
	}

	// ─── resync bookkeeping (guarded by `resyncVisited != null` at call sites) ───

	private function resyncVisitedFor(refId:Int):ResyncVisited {
		var set = resyncVisited.get(refId);
		if (set == null) {
			set = { keys: new Map(), indexes: new Map() };
			resyncVisited.set(refId, set);
		}
		return set;
	}

	/**
	 * Release a replaced occupant: full-sync emits plain ADD (never
	 * DELETE_AND_ADD), so an entry whose instance changed while this client
	 * was off the wire would otherwise leak its previous ref. Resync-only —
	 * a live patch's plain ADD can be a positional rewrite where the
	 * occupant moved and is still alive.
	 */
	private function resyncReleaseReplaced(ref:IRef, operation:Int, identity:Dynamic, previousValue:Dynamic, value:Dynamic) {
		if (previousValue != null && operation == OPERATION.ADD && previousValue != value
			&& Std.isOfType(previousValue, IRef) && (previousValue : IRef).__refId > 0) {
			refs.remove((previousValue : IRef).__refId);
			allChanges.push({
				refId: ref.__refId,
				op: cast OPERATION.DELETE,
				field: null,
				dynamicIndex: identity,
				value: null,
				previousValue: previousValue
			});
		}
	}

	private function resyncSweep() {
		if (resyncDamaged) {
			trace("WARNING: @colyseus/schema: resync sweep skipped — parts of the payload could not be decoded. Stale entries may persist until the next resync.");
			return;
		}
		sweepSchema(cast this.state, new Map<Int, Bool>());
	}

	private function sweepSchema(ref:Schema, seen:Map<Int, Bool>) {
		if (seen.exists(ref.__refId)) { return; }
		seen.set(ref.__refId, true);

		for (fieldIndex in ref._indexes.keys()) {
			var t = ref._types.get(fieldIndex);
			if (t != "ref" && t != "array" && t != "map") { continue; }

			var value:Dynamic = ref.getByIndex(fieldIndex);
			if (value == null) { continue; }

			if (t == "ref") {
				sweepSchema(cast value, seen);
			} else {
				sweepCollection(cast value, seen);
			}
		}
	}

	private function sweepCollection(coll:ISchemaCollection, seen:Map<Int, Bool>) {
		if (seen.exists(coll.__refId)) { return; }
		seen.set(coll.__refId, true);

		// null = the collection never appeared in the payload at all — it is
		// not part of full-sync (@transient, view-invisible) and must be left
		// alone. An empty visited set means "present with zero entries".
		var visited = resyncVisited.get(coll.__refId);
		if (visited == null) { return; }

		var prune = function(value:Dynamic, identity:Dynamic) {
			allChanges.push({
				refId: coll.__refId,
				op: cast OPERATION.DELETE,
				field: null,
				dynamicIndex: identity,
				value: null,
				previousValue: value
			});
			if (Std.isOfType(value, IRef) && (value : IRef).__refId > 0) {
				refs.remove((value : IRef).__refId);
			}
		};
		// recurse so nested collections of retained entries sweep too;
		// swept subtrees are left to the GC's transitive walk instead
		// (sweeping them directly would double-decrement shared children)
		var keep = function(value:Dynamic) {
			if (Std.isOfType(value, Schema)) { sweepSchema(cast value, seen); }
		};

		if (Std.isOfType(coll, IMapSchema)) {
			var map:IMapSchema = cast coll;
			map.__resyncPrune(visited.keys, prune, keep);
		} else if (Std.isOfType(coll, IArraySchema)) {
			var arr:IArraySchema = cast coll;
			arr.__resyncPrune(visited.indexes, prune, keep);
		}
	}

	public function decodeSchema(bytes:Bytes, it:It, ref:Schema):Bool {
		var byte = bytes.get(it.offset++);

		var operation = (byte >> 6) << 6; // "compressed" index + operation
		var fieldIndex:Int = byte % (operation == 0 ? 255 : operation);

		var fieldName:String = ref._indexes.get(fieldIndex);
		if (fieldName == null) { return false; }

		var fieldType:String = ref._types.get(fieldIndex);
		var childType:Dynamic = ref._childTypes.get(fieldIndex);

		var r = decodeValue(bytes, it, ref, fieldIndex, fieldType, childType, operation);

		if (r.value != null) {
			ref.setByIndex(fieldIndex, cast r.value);
		}

		if (r.value != r.previousValue) {
			allChanges.push({
				refId: ref.__refId,
				op: operation,
				field: fieldName,
				dynamicIndex: null,
				value: r.value,
				previousValue: r.previousValue
			});
		}
		return true;
	}

	public function decodeMapSchema(bytes:Bytes, it:It, ref:IMapSchema):Bool {
		var operation = bytes.get(it.offset++); // "uncompressed" index + operation (array/map items)

		// Clear collection structure.
		if (operation == OPERATION.CLEAR) {
			ref.clear(allChanges, refs);
			return true;
		}

		var fieldIndex:Int = Decode.number(bytes, it);

		var dynamicIndex:String;
		if ((operation & cast OPERATION.ADD) == OPERATION.ADD) { // ADD or DELETE_AND_ADD
			dynamicIndex = Decode.string(bytes, it);
			ref.setIndex(fieldIndex, dynamicIndex);
		} else {
			dynamicIndex = ref.getIndex(fieldIndex);
		}

		var fieldType:String = null;
		var childType:Dynamic = null;

		var collectionChildType = (ref : ISchemaCollection)._childType;
		var isPrimitiveFieldType = Std.isOfType(collectionChildType, String);

		fieldType = (isPrimitiveFieldType) ? cast(collectionChildType, String) : "ref";

		if (!isPrimitiveFieldType) {
			childType = collectionChildType;
		}

		var r = decodeValue(bytes, it, ref, fieldIndex, fieldType, childType, operation);

		// resync bookkeeping — record even when the value is unchanged
		// (the change list can't serve as the record: its pushes are gated)
		if (resyncVisited != null) {
			resyncVisitedFor(ref.__refId).keys.set(dynamicIndex, true);
			resyncReleaseReplaced(ref, operation, dynamicIndex, r.previousValue, r.value);
		}

		if (r.value != null) {
			ref.setByIndex(fieldIndex, dynamicIndex, cast r.value);
		}

		if (r.value != r.previousValue) {
			allChanges.push({
				refId: ref.__refId,
				op: operation,
				field: null,
				dynamicIndex: dynamicIndex,
				value: r.value,
				previousValue: r.previousValue
			});
		}

		return true;
    }

    public function decodeArraySchema(bytes: Bytes, it: It, ref: IArraySchema): Bool {
		var operation = bytes.get(it.offset++);
		var index:Int = -1;

		// Clear collection structure.
		if (operation == OPERATION.CLEAR) {
			ref.clear(allChanges, refs);
			return true;

		} else if (operation == OPERATION.REVERSE) {
			ref.reverse();
			return true;

		} else if (operation == OPERATION.DELETE_BY_REFID) {
			var refId = Decode.number(bytes, it);
			var item = refs.get(refId);

			// stale DELETE — refId unknown to this decoder (mid-tick joiner)
			if (item == null) { return true; }

			// ref-count decrement — must run even when the item is absent from
			// THIS array (view churn); this branch never reaches decodeValue()
			refs.remove(refId);

			index = ref.indexOf(item);
			if (index == -1) { return true; }

			ref.deleteByIndex(index);
			allChanges.push({
				refId: ref.__refId,
				op: cast OPERATION.DELETE,
				field: null,
				dynamicIndex: index,
				value: null,
				previousValue: item
			});
			return true;

        } else if (operation == OPERATION.ADD_BY_REFID) {
            var refId = Decode.number(bytes, it);
            var item = refs.get(refId);
            if (item != null) {
                index = ref.indexOf(item);
            }
            // fallback to use last index
            if (index == -1 || item == null) {
                index = ref.length;
            }

        } else {
            index = Decode.number(bytes, it);
        }

		var fieldType:String = null;
		var childType:Dynamic = null;

        var collectionChildType = ref._childType;
        var isPrimitiveFieldType = Std.isOfType(collectionChildType, String);

        fieldType = (isPrimitiveFieldType) ? cast(collectionChildType, String) : "ref";

        if (!isPrimitiveFieldType) {
            childType = collectionChildType;
        }

        var r = decodeValue(bytes, it, ref, index, fieldType, childType, operation);

		// resync bookkeeping — identity is the resolved client-side index
		// (ADD_BY_REFID resolves above, so visited indexes may be sparse)
		if (resyncVisited != null) {
			resyncVisitedFor(ref.__refId).indexes.set(index, true);
			resyncReleaseReplaced(ref, operation, index, r.previousValue, r.value);
		}

		if (r.value != null && r.value != r.previousValue) {
			// resync snapshot ADDs are positional overwrites, not inserts
			var writeOp:Int = (resyncVisited != null && operation == OPERATION.ADD) ? cast OPERATION.REPLACE : operation;
			ref.setByIndex(index, cast r.value, writeOp);
		}

		if (r.value != r.previousValue) {
			allChanges.push({
				refId: ref.__refId,
				op: operation,
				field: null,
				dynamicIndex: index,
				value: r.value,
				previousValue: r.previousValue
			});
		}
		return true;
    }

	public function decodeValue(bytes: Bytes, it: It, ref: IRef, fieldIndex: Int, fieldType: String, childType: Dynamic, operation: Int):DecodedValue {
		var value:Dynamic = null;
		var previousValue:Dynamic = ref.getByIndex(fieldIndex);

		//
		// Delete operations
		//
		if ((operation & cast OPERATION.DELETE) == OPERATION.DELETE) {
			// Flag `refId` for garbage collection.
			if (Std.isOfType(previousValue, IRef) && previousValue.__refId > 0) {
				refs.remove(previousValue.__refId);
			}

			if (operation != OPERATION.DELETE_AND_ADD) {
				ref.deleteByIndex(fieldIndex);
			}

			value = null;
		}

		if (operation == OPERATION.DELETE) {
			//
			// FIXME: refactor me.
			// Don't do anything.
			//

		} else if (fieldType == "ref") {
			var refId = Decode.number(bytes, it);
			value = refs.get(refId);

            if (((operation & cast OPERATION.ADD) == OPERATION.ADD)) {
                var concreteChildType = this.getSchemaType(bytes, it, childType);
                if (value == null) {
                    value = Type.createInstance(concreteChildType, []);
                    value.__refId = refId;
                }

				refs.add(refId, value, (
                    value != previousValue || // increment ref count if value has changed
                    (operation == OPERATION.DELETE_AND_ADD && value == previousValue) // increment ref count if it's a DELETE operation
                ));
            }

		} else if (fieldType == "quantized") {
			// childType is the @:type options object; descriptor() caches resolution on it
			var desc = Quantize.descriptor(childType);
			var q: Float = (desc.bits == 8)
				? Decode.uint8(bytes, it)
				: (desc.bits == 16)
					? Decode.uint16(bytes, it)
					: Decode.uint32(bytes, it);
			value = Quantize.dequantize(desc, q);

		} else if (childType == null) {
			value = Decode.decodePrimitiveType(fieldType, bytes, it);

		} else {
			var refId = Decode.number(bytes, it);

			// resync bookkeeping: mark the collection present in the payload —
			// even with zero entries — so the sweep knows it participated
			if (resyncVisited != null && !resyncVisited.exists(refId)) {
				resyncVisited.set(refId, { keys: new Map(), indexes: new Map() });
			}

			//
			// FIXME: Type.getClass(previousValue)
			// This may not be a reliable call, in case the previousValue is `null`.
			// (The unity3d client does not have this problem because it has a different take on this)
			// TODO:use Type.resolveClass("io.colyseus.serializer.schema.types.MapSchema_XXX")
			//
			// var collectionClass = (fieldType == null)
			//     ? Type.getClass(ref)
			//     : CustomType.getInstance().get(fieldType);

			var collectionClass: Dynamic = (fieldType == null)
                ? Type.getClass(ref)
                : #if (nodejs || js) CustomType.getInstance().get(fieldType) #else Type.getClass(previousValue) #end;

			var valueRef:ISchemaCollection = (refs.has(refId))
                ? previousValue ?? refs.get(refId)
                : Type.createInstance(collectionClass, []);

			value = valueRef.clone();
			value.__refId = refId;
			value._childType = childType;

			if (previousValue != null) {
				if (previousValue.__refId > 0 && refId != previousValue.__refId) {
					for (index => item in (previousValue : ISchemaCollection)) {
						if (Std.isOfType(item, IRef) && item.__refId > 0) {
							refs.remove(item.__refId);
						}

						allChanges.push({
							refId: previousValue.__refId,
							op: cast OPERATION.DELETE,
							field: Std.string(index),
							dynamicIndex: index,
							value: null,
							previousValue: item
						});
                    }
				}
			}

			refs.add(refId, value, (
                valueRef != previousValue ||
                (operation == OPERATION.DELETE_AND_ADD && valueRef == previousValue) // increment ref count if it's a DELETE operation
            ));
		}
		return {value: value, previousValue: previousValue};
	}

	private function getSchemaType(bytes:Bytes, it:It, defaultType:Class<Schema>) {
		var type = defaultType;

		if (bytes.get(it.offset) == SPEC.TYPE_ID) {
			it.offset++;
			type = this.context.get(Decode.number(bytes, it));
		}

		return type;
	}

}