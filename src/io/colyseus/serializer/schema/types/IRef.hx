package io.colyseus.serializer.schema.types;

interface IRef {
  public var __refId: Int;
	public function setByIndex(fieldIndex: Int, dynamicIndex: Dynamic, value: Dynamic): Void;
  public function getByIndex(fieldIndex: Int): Dynamic;
  public function deleteByIndex(fieldIndex: Int): Void;
}