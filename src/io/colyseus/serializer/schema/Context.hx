package io.colyseus.serializer.schema;

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