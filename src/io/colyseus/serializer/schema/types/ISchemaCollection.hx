package io.colyseus.serializer.schema.types;

interface ISchemaCollection {
  public var _childType: Dynamic;

  public function setIndex(index: Int, dynamicIndex: Dynamic): Void;
  public function getIndex(index: Int): Dynamic;
  public function setByIndex(index: Int, dynamicIndex: Dynamic, value: Dynamic): Void;

  public function clone(): ISchemaCollection;
  public function moveEventHandlers(previousInstance: Dynamic): Void;
}