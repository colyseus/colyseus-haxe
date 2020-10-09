package io.colyseus.serializer.schema;

import haxe.ds.Either;
import io.colyseus.serializer.schema.types.ISchemaCollection;
import io.colyseus.serializer.schema.types.IRef;
import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;

import haxe.io.Bytes;
import haxe.Constraints.IMap;

// begin macros / decorator
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

typedef DecoratedField = {
  field:Field,
  meta:MetadataEntry
};

#end
class Decorator {
  #if macro
  static public inline var TYPE = ':type';
  static public var classFields = new Map<String, Int>();

  static public function build() {
    var localClass = haxe.macro.Context.getLocalClass().get();
    var fields = haxe.macro.Context.getBuildFields();

    var constructor:haxe.macro.Field = null;
    var exprs:Array<Expr> = [];

    fields = fields.filter(function(f) {
      if (f.name != "new") {
        return true;
      } else {
        constructor = f;
        return false;
      }
    });

    var index = 0;
    var hasSuperClass = localClass.superClass;
    if (hasSuperClass != null) {
      var superClass = hasSuperClass.t.get();

      index = classFields.get(superClass.name);
      if (index == null) {
        index = 0;
      }

      // add super() call on constructor.
      if (constructor == null) {
        exprs.push(macro super());
      } else {
        switch (constructor.kind) {
          case FFun(f):
            exprs.unshift(f.expr);
          default:
        }
      }
    }

    var decoratedFields = getDecoratedFields(fields);
    for (f in decoratedFields) {
      exprs.push(macro $p{["this", "_indexes"]}.set($v{index}, $v{f.field.name}));
      exprs.push(macro $p{["this", "_types"]}.set($v{index}, $e{f.meta.params[0]}));

      if (f.meta.params.length > 1) {
        switch f.meta.params[1].expr {
          case EConst(CIdent(exp)):
            exprs.push(macro $p{["this", "_childTypes"]}.set($v{index}, $i{exp}));
            // exprs.push(macro $p{["this", "_childSchemaTypes"]}.set($v{index}, $i{exp}));

          case EConst(CString(exp)):
            exprs.push(macro $p{["this", "_childTypes"]}.set($v{index}, $v{exp}));
            // exprs.push(macro $p{["this", "_childPrimitiveTypes"]}.set($v{index}, $v{exp}));
          default:
        }
      }

      index++;
    }
    classFields.set(localClass.name, index);

    var constructorArgs = [];
    if(constructor != null){
      switch (constructor.kind) {
        case FFun(f):
          constructorArgs = f.args;
        default:
      }
    }
    // add constructor to fields
    fields.push({
      name: "new",
      pos: haxe.macro.Context.currentPos(),
      access: [APublic],
      kind: FFun({
        args: constructorArgs,
        expr: macro $b{exprs},
        params: [],
        ret: null
      })
    });

    return fields;
  }

  static function getDecoratedFields(fields:Array<Field>)
    return fields.map(getDecoration).filter(notNull);

  static function getDecoration(field:Field):DecoratedField {
    for (meta in field.meta) {
      if (meta.name == TYPE)
        return {
          field: field,
          meta: meta
        };
    }
    return null;
  }

  static function notNull(v:Dynamic)
    return v != null;
  #end
}

// end of macros / decorator

typedef It = {offset:Int}

class Decoder {
  public function new() {}

  public function decodePrimitiveType(type:String, bytes:Bytes, it:It):Dynamic {
    switch (type) {
      case "string":
        return this.string(bytes, it);
      case "number":
        return this.number(bytes, it);
      case "boolean":
        return this.boolean(bytes, it);
      case "int8":
        return this.int8(bytes, it);
      case "uint8":
        return this.uint8(bytes, it);
      case "int16":
        return this.int16(bytes, it);
      case "uint16":
        return this.uint16(bytes, it);
      case "int32":
        return this.int32(bytes, it);
      case "uint32":
        return this.uint32(bytes, it);
      case "int64":
        return this.int64(bytes, it);
      case "uint64":
        return this.uint64(bytes, it);
      case "float32":
        return this.float32(bytes, it);
      case "float64":
        return this.float64(bytes, it);
      default:
        throw "can't decode: " + type;
    }
  }

  public function string(bytes:Bytes, it:It) {
    var prefix = bytes.get(it.offset++);
    var length: Int = 0;

    if (prefix < 0xc0) {
      // fixstr
      length = prefix & 0x1f;

    } else if (prefix == 0xd9) {
      length = uint8(bytes, it);

    } else if (prefix == 0xda) {
      length = uint16(bytes, it);

    } else if (prefix == 0xdb) {
      length = uint32(bytes, it);
    }

    var value = bytes.getString(it.offset, length);
    it.offset += length;

    return value;
  }

  public function number(bytes:Bytes, it:It):Dynamic {
    var prefix = bytes.get(it.offset++);

    if (prefix < 0x80) {
      // positive fixint
      return prefix;

    } else if (prefix == 0xca) {
      // float 32
      return this.float32(bytes, it);

    } else if (prefix == 0xcb) {
      // float 64
      return this.float64(bytes, it);

    } else if (prefix == 0xcc) {
      // uint 8
      return this.uint8(bytes, it);

    } else if (prefix == 0xcd) {
      // uint 16
      return this.uint16(bytes, it);

    } else if (prefix == 0xce) {
      // uint 32
      return this.uint32(bytes, it);

    } else if (prefix == 0xcf) {
      // uint 64
      return this.uint64(bytes, it);

    } else if (prefix == 0xd0) {
      // int 8
      return this.int8(bytes, it);

    } else if (prefix == 0xd1) {
      // int 16
      return this.int16(bytes, it);

    } else if (prefix == 0xd2) {
      // int 32
      return this.int32(bytes, it);

    } else if (prefix == 0xd3) {
      // int 64
      return this.int64(bytes, it);

    } else if (prefix > 0xdf) {
      // negative fixint
      return (0xff - prefix + 1) * -1;
    }

    return 0;
  }

  public function boolean(bytes:Bytes, it:It) {
    return this.uint8(bytes, it) > 0;
  }

  public function int8(bytes:Bytes, it:It) {
    return (this.uint8(bytes, it) : Int) << 24 >> 24;
  }

  public function uint8(bytes:Bytes, it:It): UInt {
    return bytes.get(it.offset++);
  }

  public function int16(bytes:Bytes, it:It) {
    return (this.uint16(bytes, it) : Int) << 16 >> 16;
  }

  public function uint16(bytes:Bytes, it:It): UInt {
    return bytes.get(it.offset++) | bytes.get(it.offset++) << 8;
  }

  public function int32(bytes:Bytes, it:It) {
    var value = bytes.getInt32(it.offset);
    it.offset += 4;
    return value;
  }

  public function uint32(bytes:Bytes, it:It): UInt {
    return this.int32(bytes, it);
  }

  public function int64(bytes:Bytes, it:It) {
    var value = bytes.getInt64(it.offset);
    it.offset += 8;
    return value;
  }

  public function uint64(bytes:Bytes, it:It) {
    var low = this.uint32(bytes, it);
    var high = this.uint32(bytes, it) * Math.pow(2, 32);
    return haxe.Int64.make(cast high, cast low);
  }

  public function float32(bytes:Bytes, it:It) {
    var value = bytes.getFloat(it.offset);
    it.offset += 4;
    return value;
  }

  public function float64(bytes:Bytes, it:It) {
    var value = bytes.getDouble(it.offset);
    it.offset += 8;
    return value;
  }
}

class SPEC {
  public static var SWITCH_TO_STRUCTURE:Int = 255;
  public static var TYPE_ID:Int = 213;

  public static function numberCheck(bytes:Bytes, it:It) {
    var prefix = bytes.get(it.offset);
    return (prefix < 0x80 || (prefix >= 0xca && prefix <= 0xd3));
  }

  public static function arrayCheck(bytes:Bytes, it:It) {
    return bytes.get(it.offset) < 0xa0;
  }

  public static function switchToStructureCheck(bytes:Bytes, it:It) {
    return bytes.get(it.offset) == SWITCH_TO_STRUCTURE;
  }

  public static function stringCheck(bytes, it:It) {
    var prefix = bytes.get(it.offset);
    return ( // fixstr
      (prefix < 0xc0 && prefix > 0xa0) || // str 8
      prefix == 0xd9 || // str 16
      prefix == 0xda || // str 32
      prefix == 0xdb);
  }
}

@:enum
abstract OPERATION(Int) from Int
{
  var ADD = 128;
  var REPLACE = 0;
  var DELETE = 64;
  var DELETE_AND_ADD = 192;
  var CLEAR = 10;
}

typedef DataChange = {
  var op(default,never):OPERATION;
  var field(default,never):String;
  var dynamicIndex(default,never):Any;
  var value(default,never):Any;
  var previousValue(default,never):Any;
}

#if !macro @:autoBuild(io.colyseus.serializer.schema.Decorator.build()) #end
class Schema implements IRef {
  public static var decoder = new Decoder();

  public function new() {}

  public dynamic function onChange(changes:Array<DataChange>):Void {}
  public dynamic function onRemove():Void {}

	public var __refId:Int;

  private var _indexes:Map<Int, String> = new Map<Int, String>();
  private var _types:Map<Int, String> = new Map<Int, String>();
  private var _childTypes:Map<Int, Dynamic> = new Map<Int, Dynamic>();
  // private var _childSchemaTypes:Map<Int, Class<Schema>> = new Map<Int, Class<Schema>>();
  // private var _childPrimitiveTypes:Map<Int, String> = new Map<Int, String>();

  private var refs:ReferenceTracker = null;

	public function setByIndex(fieldIndex: Int, dynamicIndex: Dynamic, value: Dynamic) {
		return Reflect.setProperty(this, this._indexes.get(fieldIndex), value);
  }

  public function getByIndex(fieldIndex: Int) {
    return Reflect.getProperty(this, this._indexes.get(fieldIndex));
  }

  public function deleteByIndex(fieldIndex: Int) {
    Reflect.setField(this, this._indexes.get(fieldIndex), null);
  }

  public function setIndex(fieldIndex: Int, dynamicIndex: Int) {}
  public function getIndex(fieldIndex: Int, dynamicIndex: Int) {}

  public function decode(bytes:Bytes, it:It = null, refs: ReferenceTracker = null) {
    if (it == null) { it = {offset: 0}; }
    if (refs == null) { refs = (this.refs != null) ? this.refs : new ReferenceTracker(); }

    this.refs = refs;

    var refId = 0;
		var ref:Dynamic = this;
    var changes:Array<DataChange> = [];

    var allChanges = new OrderedMap<Int, Array<DataChange>>(new Map<Int, Array<DataChange>>());
    allChanges.set(refId, changes);

    var totalBytes = bytes.length;
		while (it.offset < totalBytes) {
			var byte = bytes.get(it.offset++);

			if (byte == SPEC.SWITCH_TO_STRUCTURE) {
				refId = decoder.number(bytes, it);
				ref = refs.get(refId);

				//
				// Trying to access a reference that haven't been decoded yet.
				//
				if (ref == null) { throw("refId not found: " + refId); }

				// create empty list of changes for this refId.
				changes = [];
				allChanges.set(refId, changes);

				continue;
      }

      trace("\n!! REFID SELECTED => " + refId);
      trace("\nREF => " + ref);

			var isSchema = Std.is(ref, Schema);

      var operation = (isSchema)
        ? (byte >> 6) << 6 // "compressed" index + operation
				: byte; // "uncompressed" index + operation (array/map items)

			// Clear collection structure.
			if (operation == OPERATION.CLEAR) {
				ref.clear(refs);
				continue;
			}

      var fieldIndex:Int = (isSchema)
        ? byte % (operation == 0 ? 255 : operation)
        : decoder.number(bytes, it);

      var fieldName:String = (isSchema)
        ? (ref : Schema)._indexes.get(fieldIndex)
        : "";

			var fieldType:Dynamic = null;
			var childType:Dynamic = null;

      if (isSchema) {
        trace("\nIS SCHEMA!");
        childType = (ref : Schema)._childTypes.get(fieldIndex);
        fieldType = (ref : Schema)._types.get(fieldIndex);

      } else {
        trace("\nNOT SCHEMA!");
        var collectionChildType = (ref : ISchemaCollection)._childType;
        var isPrimitiveFieldType = Std.is(collectionChildType, String);

        fieldType = (isPrimitiveFieldType)
          ? collectionChildType
          : "ref";

        if (!isPrimitiveFieldType) {
          childType = collectionChildType;
        }
      }

      trace("\nisSchema? => " + isSchema);
      trace("\nfieldIndex => " + fieldIndex);
      trace("\nfieldName => " + fieldName);
      try {
        trace("\nfieldType => " + fieldType);

      } catch (e) {
				trace("\nfieldType => " + Type.getClassName(fieldType));

      }

      try {
        trace("\nchildType => " + ((Std.is(childType, String)) ? childType : Type.getClassName(childType)));

      } catch (e) {
				// trace("\nchildType => " + childType);
      }

			var value:Dynamic = null;
			var previousValue:Dynamic = null;
			var dynamicIndex:Dynamic = null;

			if (!isSchema) {
        trace("Will getByIndex() => " + fieldIndex);
        previousValue = ref.getByIndex(fieldIndex);
        trace("Got by index => " + previousValue);

        if ((operation & cast OPERATION.ADD) == OPERATION.ADD) { // ADD or DELETE_AND_ADD
          //
          // TODO: Std.is() will not work with @:generic() types.
          //
          trace("Will check if it's a map schema...");
          trace("IS MAPSCHEMA?? => "  + Std.is(ref, MapSchema));
          dynamicIndex = Std.is(ref, MapSchema)
            ? decoder.string(bytes, it)
            : fieldIndex;

          ref.setIndex(fieldIndex, dynamicIndex);

				} else {
					// here
					dynamicIndex = ref.getIndex(fieldIndex);
				}
			} else {
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
				if (previousValue != null && Std.isOfType(previousValue, IRef)) {
          refs.remove(previousValue.__refId);
				}

				value = null;
      }

      trace("Will decide how to decode...");

			if (fieldName == null) {
        trace("WARNING: @colyseus/schema definition mismatch?");

				//
				// keep skipping next bytes until reaches a known structure
				// by local decoder.
				//
				var nextIterator:It = { offset : it.offset };

				while (it.offset < totalBytes) {
					if (SPEC.switchToStructureCheck(bytes, it)) {
						nextIterator.offset = it.offset + 1;
						if (refs.has(decoder.number(bytes, nextIterator))) {
							break;
						}
					}

					it.offset++;
				}

        continue;

			} else if (operation == OPERATION.DELETE) {
        trace(">>> DELETE OPERATION\n");

				//
				// FIXME: refactor me.
				// Don't do anything.
        //

			} else if (fieldType == "ref") {
        trace(">>> DECODE REF\n");
				refId = decoder.number(bytes, it);
        value = refs.get(refId);

        trace("refId => " + refId);

				if (operation != OPERATION.REPLACE) {
					var concreteChildType = this.getSchemaType(bytes, it, childType);

					if (value == null) {
						value = Type.createInstance(concreteChildType, []);

						if (previousValue != null) {
							 value.onChange = previousValue.onChange;
							 value.onRemove = previousValue.onRemove;

							if (previousValue.__refId > 0 && refId != previousValue.__refId) {
								refs.remove(previousValue.__refId);
							}
						}
					}

					refs.add(refId, value, (value != previousValue));
				}

      // } else if (Std.is(childType, String)) {
      } else if (childType == null) {
        trace(">>> DECODE PRIMITIVE VALUE\n");
        value = decoder.decodePrimitiveType(fieldType, bytes, it);
        trace("value => " + value);

      } else {
        trace(">>> DECODE COLLECTION\n");

        refId = decoder.number(bytes, it);
        value = refs.get(refId);

        trace("refId => " + refId);
        trace("previousValue => " + previousValue);

        var collectionClass = (fieldType == null)
          ? Type.getClass(ref)
          : CustomType.getInstance().get(fieldType);

        trace("Collection class => " + Type.getClassName(collectionClass));

        var valueRef: ISchemaCollection = (refs.has(refId))
          ? previousValue
          : Type.createInstance(collectionClass, []);

        trace("valueRef => " + valueRef);

        value = valueRef.clone();
				value._childType = childType;

        if (previousValue != null)
        {
          value.moveEventHandlers(previousValue);

					if (previousValue.__refId > 0 && refId != previousValue.__refId)
          {
            refs.remove(previousValue.__refId);

            var deletes = new Array<DataChange>();
            Lambda.mapi(previousValue.items, function(index, item) {
              deletes.push({
								op: OPERATION.DELETE,
								field: cast index,
								dynamicIndex: cast index,
								value: null,
								previousValue: item
							});
            });

            allChanges.set(previousValue.__refId, deletes);
          }
        }

        refs.add(refId, value, valueRef != previousValue);
      }

      var hasChange = (previousValue != value);

      if (value != null) {
        //
        // assign `__refId`
        //
        if (Std.is(value, IRef)) { value.__refId = refId; }

        trace("ref.setByIndex => ");
        trace("\nfieldIndex => " + fieldIndex);
        trace("\ndynamicIndex => " + dynamicIndex);
        trace("\nvalue => " + value);
        ref.setByIndex(fieldIndex, dynamicIndex, value);
      }

			if (hasChange) {
				changes.push({
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

  private function triggerChanges (allChanges: OrderedMap<Int, Array<DataChange>>) {
    // TODO
    trace("triggerChanges not implemented.");
  }

  private function triggerAllFillChanges(ref: IRef, allChanges: OrderedMap<Int, Array<DataChange>>) {
    // TODO
    trace("triggerAllFillChanges not implemented.");
  }

  public function triggerAll() {
		//
		// first state not received from the server yet.
		// nothing to trigger.
		//
    if (this.refs == null) { return; }

    var allChanges = new OrderedMap<Int, Array<DataChange>>(new Map<Int, Array<DataChange>>());
    this.triggerAllFillChanges(this, allChanges);
    this.triggerChanges(allChanges);
  }

  private function getSchemaType(bytes: Bytes, it: It, defaultType: Class<Schema>) {
    var type = defaultType;

    if (bytes.get(it.offset) == SPEC.TYPE_ID) {
      it.offset++;
      type = this.refs.context.get(decoder.number(bytes, it));
    }

    return type;
  }

  public function toString () {
    var data = [];
    trace("#toString() => " + Type.getClassName(Type.getClass(this)));
    trace("_indexes => " + this._indexes);

    for (field in this._indexes) {
      data.push(field + " => " + Reflect.getProperty(this, field));
    }

    return "{ " + data.join(", ") + " }";
  }
}
