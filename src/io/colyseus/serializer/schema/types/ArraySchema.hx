package io.colyseus.serializer.schema.types;

@:keep
@:generic
class ArraySchema<T> implements IRef implements ISchemaCollection {
  public var __refId: Int;
  public var _childType: Dynamic;

  public function getIndex(fieldIndex: Int): Dynamic {
    return this.indexes[fieldIndex];
  }

  public function setIndex(fieldIndex: Int, dynamicIndex: Dynamic) {
    this.indexes[fieldIndex] = dynamicIndex;
  }

  public function getByIndex(fieldIndex: Int): Dynamic {
    return this.items.get(this.indexes[fieldIndex]);
  }

  public function setByIndex(index: Int, dynamicIndex: Dynamic, value: Dynamic): Void {
    this.indexes[index] = dynamicIndex;
		this.items.set(dynamicIndex, value);
  }

  public function deleteByIndex(fieldIndex: Int): Void {
    var index = this.indexes[fieldIndex];
    this.items.remove(index);
    this.indexes.remove(fieldIndex);
  }

  public var items:Map<Int, T> = new Map<Int, T>();
  public var indexes:Map<Int, Int> = new Map<Int, Int>();

  public var length(get, null): Int;
  function get_length() { return Lambda.count(this.items); }

  public dynamic function onAdd(item:T, key:Int):Void {}
  public dynamic function onChange(item:T, key:Int):Void {}
  public dynamic function onRemove(item:T, key:Int):Void {}

  public function new() {}

	public function moveEventHandlers(previousInstance: Dynamic) {
    this.onAdd = previousInstance.onAdd;
    this.onChange = previousInstance.onChange;
    this.onRemove = previousInstance.onRemove;
  }

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
			data.push("" + item);
		}

		return "ArraySchema(" + Lambda.count(this.items) + ") { " + data.join(", ") + " } ";
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