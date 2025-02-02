package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.IRef;
import io.colyseus.serializer.schema.types.ISchemaCollection;
import io.colyseus.serializer.schema.Schema.It;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Schema.SPEC;
import io.colyseus.serializer.schema.Schema.OPERATION;

import io.colyseus.serializer.schema.encoding.Decode;
import haxe.io.Bytes;

@:generic
class Decoder<T> {
	public var state:T;
	public var context:TypeContext = new TypeContext();
    public var refs: ReferenceTracker = new ReferenceTracker();
    public var triggerChanges:(Array<DataChange>)->Void = (_: Array<DataChange>) -> {};

    public function new(state: T) {
        this.state = state;
    }

	public function decode(bytes:Bytes, it:It = null) {
		if (it == null) {
			it = {offset: 0};
		}

		var refId = 0;
		var ref:Dynamic = this.state;
		refs.add(refId, ref);

		var allChanges = new Array<DataChange>();

		var totalBytes = bytes.length;
		while (it.offset < totalBytes) {
			var byte = bytes.get(it.offset++);

			if (byte == SPEC.SWITCH_TO_STRUCTURE) {
				refId = Decode.number(bytes, it);
				ref = refs.get(refId);

				//
				// Trying to access a reference that haven't been decoded yet.
				//
				if (ref == null) {
					throw("refId not found: " + refId);
				}

				continue;
			}

			var isSchema = Std.isOfType(ref, Schema);

			var operation = (isSchema)
                ? (byte >> 6) << 6 // "compressed" index + operation
				: byte; // "uncompressed" index + operation (array/map items)

			// Clear collection structure.
			if (operation == OPERATION.CLEAR) {
				(ref : ISchemaCollection).clear(allChanges, refs);
				continue;
			}

			var fieldIndex:Int = (isSchema)
                ? byte % (operation == 0 ? 255 : operation)
                : Decode.number(bytes, it);

			var fieldName:String = (isSchema)
                ? (ref : Schema)._indexes.get(fieldIndex)
                : "";

			var fieldType:Dynamic = null;
			var childType:Dynamic = null;

			if (isSchema) {
				childType = (ref : Schema)._childTypes.get(fieldIndex);
				fieldType = (ref : Schema)._types.get(fieldIndex);
			} else {
				var collectionChildType = (ref : ISchemaCollection)._childType;
				var isPrimitiveFieldType = Std.isOfType(collectionChildType, String);

				fieldType = (isPrimitiveFieldType) ? collectionChildType : "ref";

				if (!isPrimitiveFieldType) {
					childType = collectionChildType;
				}
			}

			var value:Dynamic = null;
			var previousValue:Dynamic = null;
			var dynamicIndex:Dynamic = null;

			if (!isSchema) {
				previousValue = ref.getByIndex(fieldIndex);

				if ((operation & cast OPERATION.ADD) == OPERATION.ADD) { // ADD or DELETE_AND_ADD
					// FIXME: need to detect if we're operating on a "map" here.
					dynamicIndex = Reflect.getProperty(ref, "__isMapSchema") == true ? Decode.string(bytes, it) : fieldIndex;

					ref.setIndex(fieldIndex, dynamicIndex);
				} else {
					// here
					dynamicIndex = ref.getIndex(fieldIndex);
				}
			} else if (fieldName != null) {
				previousValue = Reflect.getProperty(ref, fieldName);
			}

			//
			// Delete operations
			//
			if ((operation & cast OPERATION.DELETE) == OPERATION.DELETE) {
				if (operation != OPERATION.DELETE_AND_ADD) {
					ref.deleteByIndex(fieldIndex);
				}

				// Flag `refId` for garbage collection.
				if (Std.isOfType(previousValue, IRef) && previousValue.__refId > 0) {
					refs.remove(previousValue.__refId);
				}

				value = null;
			}

			if (fieldName == null) {
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
			} else if (operation == OPERATION.DELETE) {
				//
				// FIXME: refactor me.
				// Don't do anything.
				//
			} else if (fieldType == "ref") {
				var refId = Decode.number(bytes, it);
				value = refs.get(refId);

				if (operation != OPERATION.REPLACE) {
					var concreteChildType = this.getSchemaType(bytes, it, childType);

					if (value == null) {
						value = Type.createInstance(concreteChildType, []);
						value.__refId = refId;

						if (previousValue != null) {
							// (value : Schema).moveEventHandlers(previousValue);

							if (previousValue.__refId > 0 && refId != previousValue.__refId) {
								refs.remove(previousValue.__refId);
							}
						}
					}

					refs.add(refId, value, (value != previousValue));
				}
			} else if (childType == null) {
				value = Decode.decodePrimitiveType(fieldType, bytes, it);
			} else {
				var refId = Decode.number(bytes, it);
				value = refs.get(refId);

				//
				// FIXME: Type.getClass(previousValue)
				// This may not be a reliable call, in case the previousValue is `null`.
				// (The unity3d client does not have this problem because it has a different take on this)
				// TODO:use Type.resolveClass("io.colyseus.serializer.schema.types.MapSchema_XXX")
				//
				var collectionClass = (fieldType == null) ? Type.getClass(ref) : #if (nodejs || js) CustomType.getInstance()
					.get(fieldType) #else Type.getClass(previousValue) #end;

				var valueRef:ISchemaCollection = (refs.has(refId)) ? previousValue : Type.createInstance(collectionClass, []);

				value = valueRef.clone();
				value.__refId = refId;
				value._childType = childType;

				if (previousValue != null) {
					// value.moveEventHandlers(previousValue);

					if (previousValue.__refId > 0 && refId != previousValue.__refId) {
						refs.remove(previousValue.__refId);

						Lambda.mapi(previousValue.items, function(index, item) {
							return allChanges.push({
								refId: refId,
								op: cast OPERATION.DELETE,
								field: cast index,
								dynamicIndex: cast index,
								value: null,
								previousValue: item
							});
						});
					}
				}

				refs.add(refId, value, valueRef != previousValue);
			}

			var hasChange = (previousValue != value);

			if (value != null) {
				ref.setByIndex(fieldIndex, dynamicIndex, value);
			}

			if (hasChange) {
				allChanges.push({
					refId: refId,
					op: operation,
					field: fieldName,
					dynamicIndex: dynamicIndex,
					value: value,
					previousValue: previousValue
				});
			}
		}

		this.triggerChanges(allChanges);

		refs.garbageCollection();
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