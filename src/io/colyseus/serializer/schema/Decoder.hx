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

@:generic
class Decoder<T> {
	public var state:T;
	public var context:TypeContext = new TypeContext();
	public var refs:ReferenceTracker = new ReferenceTracker();
	public var triggerChanges:(Array<DataChange>) -> Void = (_:Array<DataChange>) -> {};

	private var allChanges:Array<DataChange>;

	public function new(state:T) {
		this.state = state;
		this.refs.add(0, state);
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

				ref = refs.get(refId);

				//
				// Trying to access a reference that haven't been decoded yet.
				//
				if (ref == null) {
					throw("refId not found: " + refId);
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
				//
				// keep skipping next bytes until reaches a known structure
				// by local decoder.
				//
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
				continue;
			}
		}

		if (Std.isOfType(ref, IArraySchema)) {
			(ref : IArraySchema).__onDecodeEnd();
		}

		this.triggerChanges(allChanges);

		refs.garbageCollection();
	}

	public function decodeSchema(bytes:Bytes, it:It, ref:Schema):Bool {
		var byte = bytes.get(it.offset++);

		var operation = (byte >> 6) << 6; // "compressed" index + operation
		var fieldIndex:Int = byte % (operation == 0 ? 255 : operation);

		var fieldName:String = ref._indexes.get(fieldIndex);
		if (fieldName == null) { return false; }

		var fieldType:Dynamic = ref._types.get(fieldIndex);
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

		var fieldType:Dynamic = null;
		var childType:Dynamic = null;

		var collectionChildType = (ref : ISchemaCollection)._childType;
		var isPrimitiveFieldType = Std.isOfType(collectionChildType, String);

		fieldType = (isPrimitiveFieldType) ? collectionChildType : "ref";

		if (!isPrimitiveFieldType) {
			childType = collectionChildType;
		}

		var r = decodeValue(bytes, it, ref, fieldIndex, fieldType, childType, operation);

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
		var index:Int;

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
			index = ref.indexOf(item);
			ref.deleteByIndex(index);
			allChanges.push({
				refId: ref.__refId,
				op: operation,
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
            } else {
                index = ref.length;
            }

        } else {
            index = Decode.number(bytes, it);
        }

		var fieldType:Dynamic = null;
		var childType:Dynamic = null;

        var collectionChildType = ref._childType;
        var isPrimitiveFieldType = Std.isOfType(collectionChildType, String);

        fieldType = (isPrimitiveFieldType) ? collectionChildType : "ref";

        if (!isPrimitiveFieldType) {
            childType = collectionChildType;
        }

        var r = decodeValue(bytes, it, ref, index, fieldType, childType, operation);

		if (r.value != null) {
			ref.setByIndex(index, cast r.value, operation);
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

		} else if (childType == null) {
			value = Decode.decodePrimitiveType(fieldType, bytes, it);

		} else {
			var refId = Decode.number(bytes, it);

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
							field: cast index,
							dynamicIndex: cast index,
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