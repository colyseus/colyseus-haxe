package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.encoding.Decode;
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

class SPEC {
  public static var SWITCH_TO_STRUCTURE:Int = 255;
  public static var TYPE_ID:Int = 213;

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
  var refId(default,never):Int;
  var op(default,never):Int;
  var field(default,never):String;
  var value(default,never):Any;
  var ?dynamicIndex(default,never):Any;
  var ?previousValue(default,never):Any;
}

#if !macro @:autoBuild(io.colyseus.serializer.schema.Decorator.build()) #end
@:keepSub
class Schema implements IRef {
  public function new() {}

  public var __refId:Int = 0;

  public var _indexes:Map<Int, String> = new Map<Int, String>();
  public var _types:Map<Int, String> = new Map<Int, String>();
  public var _childTypes:Map<Int, Dynamic> = new Map<Int, Dynamic>();

  private var _refs:ReferenceTracker = null;

  public function setByIndex(fieldIndex: Int, dynamicIndex: Dynamic, value: Dynamic) {
    return Reflect.setField(this, this._indexes.get(fieldIndex), value);
  }

  public function getByIndex(fieldIndex: Int): Any {
    return Reflect.getProperty(this, this._indexes.get(fieldIndex));
  }

  public function deleteByIndex(fieldIndex: Int) {
    Reflect.setField(this, this._indexes.get(fieldIndex), null);
  }

  public function setIndex(fieldIndex: Int, dynamicIndex: Int) {}
  public function getIndex(fieldIndex: Int, dynamicIndex: Int) {}

  public function toString () {
    var data = [];

    for (field in this._indexes) {
      data.push(field + " => " + Reflect.getProperty(this, field));
    }

    return "{ __refId => " + this.__refId + ", " + data.join(", ") + " }";
  }
}
