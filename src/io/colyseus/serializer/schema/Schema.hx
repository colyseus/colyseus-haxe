package io.colyseus.serializer.schema;

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
            exprs.push(macro $p{["this", "_childSchemaTypes"]}.set($v{index}, $i{exp}));

          case EConst(CString(exp)):
            exprs.push(macro $p{["this", "_childPrimitiveTypes"]}.set($v{index}, $v{exp}));
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

class SPEC {
  public static var END_OF_STRUCTURE:Int = 193; // (msgpack spec: never used)
  public static var NIL:Int = 192;
  public static var INDEX_CHANGE:Int = 212;

  public static function numberCheck(bytes:Bytes, it:It) {
    var prefix = bytes.get(it.offset);
    return (prefix < 0x80 || (prefix >= 0xca && prefix <= 0xd3));
  }

  public static function arrayCheck(bytes:Bytes, it:It) {
    return bytes.get(it.offset) < 0xa0;
  }

  public static function nilCheck(bytes:Bytes, it:It) {
    return bytes.get(it.offset) == NIL;
  }

  public static function indexChangeCheck(bytes:Bytes, it:It) {
    return bytes.get(it.offset) == INDEX_CHANGE;
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
    return this.uint8(bytes, it) << 24 >> 24;
  }

  public function uint8(bytes:Bytes, it:It) {
    return bytes.get(it.offset++);
  }

  public function int16(bytes:Bytes, it:It) {
    return this.uint16(bytes, it) << 16 >> 16;
  }

  public function uint16(bytes:Bytes, it:It) {
    return bytes.get(it.offset++) | bytes.get(it.offset++) << 8;
  }

  public function int32(bytes:Bytes, it:It) {
    var value = bytes.getInt32(it.offset);
    it.offset += 4;
    return value;
  }

  public function uint32(bytes:Bytes, it:It) {
    return this.int32(bytes, it) >>> 0;
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

typedef DataChange = {
  var field(default,never):String;
  var value(default,never):Any;
  var previousValue(default,never):Any;
}

@:keep
@:generic
class ArraySchema<T> {
  public var items:Array<T> = [];
  public var length(get, null): Int;

  function get_length() {
      return this.items.length;
  }

  public dynamic function onAdd(item:T, key:Int):Void {}
  public dynamic function onChange(item:T, key:Int):Void {}
  public dynamic function onRemove(item:T, key:Int):Void {}

  public function new() {}

  public function clone():ArraySchema<T> {
    var cloned = new ArraySchema<T>();
    cloned.items = this.items.copy();
    cloned.onAdd = this.onAdd;
    cloned.onChange = this.onChange;
    cloned.onRemove = this.onRemove;
    return cloned;
  }

  public function iterator() {
    return this.items.iterator();
  }

  public function toString () {
    var data = [];
    for (item in this.items) {
      data.push(""+item);
    }
    return "ArraySchema("+Lambda.count(this.items)+") { " + data.join(", ") + " } ";
  }

  /** TODO: This only works with Abstracts! */

  /* @:arrayAccess */
  /* public inline function get(key:Int) { */
  /*   return this.items[key]; */
  /* } */
  /*  */
  /* @:arrayAccess */
  /* public inline function arrayWrite(key:Int, value:T):T { */
  /*   this.items[key] = value; */
  /*   return value; */
  /* } */

}

class OrderedMapIterator<K,V> {
    var map : OrderedMap<K,V>;
    var index : Int = 0;
    public function new(omap:OrderedMap<K,V>) { map = omap; }
    public function hasNext() : Bool { return index < map._keys.length;}
    public function next() : V { return map.get(map._keys[index++]); }
}

// class OrderedMap<K, V> implements IMap<K, V> {
@:keep
class OrderedMap<K, V> {
    var map:Map<K, V>;

    @:allow(OrderedMapIterator) // TODO: why this doesn't seem to work?
    public var _keys:Array<K>; // FIXME: this should be private
    var idx = 0;

    public function new(_map) {
       _keys = [];
       map = _map;
    }

    public function set(key: K, value: V) {
        if(!map.exists(key)) _keys.push(key);
        map[key] = value;
    }

    public function toString() {
        var _ret = ''; var _cnt = 0; var _len = _keys.length;
        for(k in _keys) _ret += '$k => ${map.get(k)}${(_cnt++<_len-1?", ":"")}';
        return '{$_ret}';
    }

    public function iterator() return new OrderedMapIterator<K,V>(this);
    public function remove(key: K) return map.remove(key) && _keys.remove(key);
    public function exists(key: K) return map.exists(key);
    public function get(key: K) return map.get(key);
    public inline function keys() return _keys.iterator();
}


@:keep
@:generic
class MapSchema<T> {
  public var items:OrderedMap<String, T> = new OrderedMap<String, T>(new Map<String, T>());
  public var length(get, null): Int;

  function get_length() {
      return this.items._keys.length;
  }

  public dynamic function onAdd(item:T, key:String):Void {}
  public dynamic function onChange(item:T, key:String):Void {}
  public dynamic function onRemove(item:T, key:String):Void {}

  public function new() {}

  public function clone():MapSchema<T> {
    var cloned = new MapSchema<T>();

    for (key in this.items.keys()) {
      cloned.items.set(key, this.items.get(key));
    }

    cloned.onAdd = this.onAdd;
    cloned.onChange = this.onChange;
    cloned.onRemove = this.onRemove;

    return cloned;
  }

  public function iterator() {
    return this.items.iterator();
  }

  @:arrayAccess
  public inline function get(key:String) {
    return this.items.get(key);
  }

  @:arrayAccess
  public inline function arrayWrite(key:String, value:T):T {
    this.items.set(key, value);
    return value;
  }

  public function toString () {
    var data = [];
    for (key in this.items.keys()) {
      data.push(key + " => " + this.items.get(key));
    }
    return "MapSchema ("+ Lambda.count(this.items) +") { " + data.join(", ") + " }";
  }
}

#if !macro @:autoBuild(io.colyseus.serializer.schema.Decorator.build()) #end
class Schema {
  public static var decoder = new Decoder();

  public function new() {}

  public dynamic function onChange(changes:Array<DataChange>):Void {}
  public dynamic function onRemove():Void {}

  private var _indexes:Map<Int, String> = new Map<Int, String>();
  private var _types:Map<Int, String> = new Map<Int, String>();
  private var _childSchemaTypes:Map<Int, Class<Schema>> = new Map<Int, Class<Schema>>();
  private var _childPrimitiveTypes:Map<Int, String> = new Map<Int, String>();

  public function decode(bytes:Bytes, it:It = null) {
    var changes:Array<DataChange> = [];

    if (it == null) {
      it = {offset: 0};
    }

    var totalBytes = bytes.length;
    while (it.offset < totalBytes) {
      var isNil = SPEC.nilCheck(bytes, it);
      if (isNil) { it.offset++; }

      var index = bytes.get(it.offset++);

      if (index == SPEC.END_OF_STRUCTURE) {
        // reached end of strucutre. skip.
        break;
      }

      var field = this._indexes.get(index);
      var type:Dynamic = this._types.get(index);

      var value:Dynamic = null;
      var hasChange = false;

      if (field == null) {
          continue;

      } else if (isNil) {
          value = null;
          hasChange = true;

      } else if (type == "ref") {
        var constructor:Class<Schema> = this._childSchemaTypes.get(index);

        value = Reflect.getProperty(this, field);
        if (value == null) { value = Type.createInstance(constructor, []); }

        value.decode(bytes, it);
        hasChange = true;

      } else if (type == "array") {
        var isSchemaType = this._childSchemaTypes.exists(index);

        type = (isSchemaType) ? this._childSchemaTypes.get(index) : this._childPrimitiveTypes.get(index);

        var valueRef: Dynamic = Reflect.getProperty(this, field);
        if (valueRef == null) { valueRef = new ArraySchema<Dynamic>(); }

        value = valueRef.clone();

        var newLength:Int = decoder.number(bytes, it);
        var numChanges:Int = cast(Math.min(decoder.number(bytes, it), newLength), Int);

        var hasRemoval = (value.items.length > newLength);
        hasChange = (numChanges > 0) || hasRemoval || value.items.length == 0;

        // FIXME: this may not be reliable. possibly need to encode this variable during
        // serializagion
        var hasIndexChange = false;

        // ensure current array has the same length as encoded one
        if (hasRemoval) {
          var items = cast(valueRef.items, Array<Dynamic>);

          for (i in newLength...valueRef.items.length) {
            var itemRemoved = items[i];

            if (isSchemaType && itemRemoved.onRemove != null) {
              itemRemoved.onRemove();
            }

            // cast is necessary for JavaScript target
            cast(value.items, Array<Dynamic>).remove(itemRemoved);

            valueRef.onRemove(itemRemoved, newLength + i);
          }
        }

        for (i in 0...numChanges) {
          var newIndex:Int = decoder.number(bytes, it);

          var indexChangedFrom:Int = -1; // index change check
          if (SPEC.indexChangeCheck(bytes, it)) {
            it.offset++;
            indexChangedFrom = decoder.number(bytes, it);
            hasIndexChange = true;
          }

          var isNew:Bool = (!hasIndexChange && value.items[newIndex] == null) || (hasIndexChange && indexChangedFrom == -1);

          if (isSchemaType) {
            var item:Schema = null;

            if (isNew) {
              item = Type.createInstance(type, []);
            } else if (indexChangedFrom != -1) {
              item = (cast valueRef).items[indexChangedFrom];
            } else {
              item = (cast valueRef).items[newIndex];
            }

            if (item == null) {
              item = Type.createInstance(type, []);
              isNew = true;
            }

            item.decode(bytes, it);
            value.items[newIndex] = item;

          } else {
            value.items[newIndex] = decoder.decodePrimitiveType(type, bytes, it);
          }

          if (isNew) {
              valueRef.onAdd(value.items[newIndex], newIndex);

          } else {
            valueRef.onChange(value.items[newIndex], newIndex);
          }
        }

      } else if (type == "map") {
        var isSchemaType = this._childSchemaTypes.exists(index);
        type = (isSchemaType) ? this._childSchemaTypes.get(index) : this._childPrimitiveTypes.get(index);

        var valueRef: Dynamic = Reflect.getProperty(this, field);
        if (valueRef == null) { valueRef = new MapSchema<Dynamic>(); }

        value = valueRef.clone();

        var length:Int = decoder.number(bytes, it);
        hasChange = (length > 0);

        // FIXME: this may not be reliable. possibly need to encode this variable during
        // serializagion
        var hasIndexChange:Bool = false;

        var previousKeys = new Array<String>();
        var keysIterator = valueRef.items.keys();
        while (keysIterator.hasNext()) {
          previousKeys.push(keysIterator.next());
        }

        for (i in 0...length) {
          // `encodeAll` may indicate a higher number of indexes it actually encodes
          // TODO: do not encode a higher number than actual encoded entries
          if (it.offset >= bytes.length || bytes.get(it.offset) == SPEC.END_OF_STRUCTURE) {
            break;
          }

          var isNilItem = SPEC.nilCheck(bytes, it);
          if (isNilItem) { it.offset++; }

          // index change check
          var previousKey:String = "";
          if (SPEC.indexChangeCheck(bytes, it)) {
            it.offset++;
            previousKey = previousKeys[decoder.number(bytes, it)];
            hasIndexChange = true;
          }

          var hasMapIndex:Bool = SPEC.numberCheck(bytes, it);

          var newKey = (hasMapIndex) ? previousKeys[decoder.number(bytes, it)] : decoder.string(bytes, it);

          var item: Dynamic;
          var isNew = (!hasIndexChange && !valueRef.items.exists(newKey))
            || (hasIndexChange && previousKey == "" && hasMapIndex);

          if (isNew && isSchemaType) {
            item = Type.createInstance(type, []);

          } else if (previousKey != "") {
            item = valueRef.items.get(previousKey);

          } else {
            item = valueRef.items.get(newKey);
          }

          if (isNilItem) {
            if (item && isSchemaType && item.onRemove != null) {
              item.onRemove();
            }

            valueRef.onRemove(item, newKey);

            value.items.remove(newKey);
            continue;

          } else if (!isSchemaType) {
            var decodedValue: Dynamic = decoder.decodePrimitiveType(type, bytes, it);
            value.items.set(newKey, decodedValue);

          } else {
            item.decode(bytes, it);
            value.items.set(newKey, item);
          }

          if (isNew) {
            valueRef.onAdd(item, newKey);

          } else {
            valueRef.onChange(item, newKey);
          }
        }

      } else {
        value = decoder.decodePrimitiveType(type, bytes, it);
        hasChange = true;
      }

      if (hasChange) {
        changes.push({
            field: field,
            value: value,
            previousValue: Reflect.getProperty(this, field)
        });
      }

      Reflect.setField(this, field, cast value);
    }

    if (changes.length > 0) {
      this.onChange(changes);
    }
  }

  public function toString () {
    var data = [];

    for (field in this._indexes) {
      data.push(field + " => " + Reflect.getProperty(this, field));
    }

    return "{ " + data.join(", ") + " }";
  }
}

class Context {
  public var typeIds:Map<UInt, Class<Schema>> = new Map<UInt, Class<Schema>>();
  public var schemas:Array<Class<Schema>> = new Array();

  public function new() {}

  public function add(schema:Class<Schema>, ?typeid:UInt) {
    if (typeid == null) {
      typeid = schemas.length;
    }

    this.typeIds[typeid] = schema;
    this.schemas.push(schema);
  }

  public function get(typeid:UInt) {
    return this.typeIds[typeid];
  }
}

/**
 * Reflection
 */
class ReflectionField extends Schema {
  @:type("string")
  public var name:String;

  @:type("string")
  public var type:String;

  @:type("uint8")
  public var referencedType:UInt;
}

class ReflectionType extends Schema {
  @:type("uint8")
  public var id:UInt;

  @:type("array", ReflectionField)
  public var fields:ArraySchema<ReflectionField> = new ArraySchema<ReflectionField>();
}

class Reflection extends Schema {
  @:type("array", ReflectionType)
  public var types:ArraySchema<ReflectionType> = new ArraySchema<ReflectionType>();

  @:type("uint8")
  public var rootType:UInt;
}
