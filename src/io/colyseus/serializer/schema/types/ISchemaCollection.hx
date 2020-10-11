package io.colyseus.serializer.schema.types;

interface ISchemaCollection extends IRef {
  public var _childType: Dynamic;

  public function invokeOnAdd(item:Any, key:Any):Void;
  public function invokeOnChange(item:Any, key:Any):Void;
  public function invokeOnRemove(item:Any, key:Any):Void;

  public function iterator(): Iterator<Dynamic>;
  public function keyValueIterator():KeyValueIterator<Dynamic, Dynamic>;

  public function setIndex(index: Int, dynamicIndex: Dynamic): Void;
  public function getIndex(index: Int): Dynamic;
  public function setByIndex(index: Int, dynamicIndex: Dynamic, value: Dynamic): Void;

  public function clear(refs: ReferenceTracker): Void;
  public function clone(): ISchemaCollection;
  public function moveEventHandlers(previousInstance: Dynamic): Void;
}