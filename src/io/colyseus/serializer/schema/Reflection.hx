package io.colyseus.serializer.schema;

/**
 * Reflection
 */
class ReflectionField extends Schema {
  @:type("string")
  public var name:String;

  @:type("string")
  public var type:String;

  @:type("number")
  public var referencedType:UInt;
}

class ReflectionType extends Schema {
  @:type("number")
  public var id:UInt;

  @:type("array", ReflectionField)
  public var fields:ArraySchema<ReflectionField> = new ArraySchema<ReflectionField>();
}

class Reflection extends Schema {
  @:type("array", ReflectionType)
  public var types:ArraySchema<ReflectionType> = new ArraySchema<ReflectionType>();

  @:type("number")
  public var rootType:UInt;
}