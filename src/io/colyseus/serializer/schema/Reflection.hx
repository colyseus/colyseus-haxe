package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.ArraySchema;

/**
 * Reflection (schema 5.0 handshake format)
 */
class QuantizedReflection extends Schema {
  @:type("float64")
  public var min:Float;

  @:type("float64")
  public var max:Float;

  @:type("uint8")
  public var bits:Int;

  @:type("uint8")
  public var mode:Int; // 0 = clamp, 1 = wrap
}

class ReflectionField extends Schema {
  @:type("string")
  public var name:String;

  @:type("string")
  public var type:String;

  @:type("number")
  public var referencedType:Int; // -1 = primitive collection (see childPrimitive)

  @:type("string")
  public var childPrimitive:String;

  @:type("ref", QuantizedReflection)
  public var quantized:QuantizedReflection; // null = not quantized
}

class ReflectionType extends Schema {
  @:type("number")
  public var id:UInt;

  @:type("number")
  public var extendsId:UInt;

  @:type("array", ReflectionField)
  public var fields:ArraySchema<ReflectionField> = new ArraySchema<ReflectionField>();
}

class Reflection extends Schema {
  @:type("array", ReflectionType)
  public var types:ArraySchema<ReflectionType> = new ArraySchema<ReflectionType>();

  @:type("number")
  public var rootType:UInt;
}