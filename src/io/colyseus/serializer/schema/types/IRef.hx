package io.colyseus.serializer.schema.types;

interface IRef {
  public var __refId: Int;
  public function getByIndex(fieldIndex: Int): Dynamic;
  public function deleteByIndex(fieldIndex: Int): Void;
}