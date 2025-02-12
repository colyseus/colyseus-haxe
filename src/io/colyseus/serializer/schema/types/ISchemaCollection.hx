package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.Schema.DataChange;

interface ISchemaCollection extends IRef {
  public var _childType: Dynamic;
  public var length(get, null): Int;

  public function iterator(): Iterator<Dynamic>;
  public function keyValueIterator():KeyValueIterator<Dynamic, Dynamic>;

  public function clear(changes: Array<DataChange>, refs: ReferenceTracker): Void;
  public function clone(): ISchemaCollection;
}