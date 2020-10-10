package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.types.MapSchema.OrderedMap;

@:keep
@:generic
class ArraySchemaImpl<T> implements IRef implements ISchemaCollection implements ArrayAccess<Int> {
  public var __refId: Int;
  public var _childType: Dynamic;

  public function getIndex(fieldIndex: Int): Dynamic {
    return this.indexes.get(fieldIndex);
  }

  public function setIndex(fieldIndex: Int, dynamicIndex: Dynamic) {
    this.indexes.set(fieldIndex, dynamicIndex);
  }

  public function getByIndex(fieldIndex: Int): Dynamic {
    //
    // FIXME: this should be of O(1) complexity.
    //
    var targetIndex: Int = null;
    var i: Int = 0;

    for (key in this.indexes.keys()) {
      if (i == fieldIndex) {
        targetIndex = this.indexes.get(key);
				break;
      }
      i++;
    }

    return (targetIndex == null) ? null : this.items.get(this.indexes.get(targetIndex));
  }

  public function setByIndex(index: Int, dynamicIndex: Dynamic, value: Dynamic): Void {
    this.indexes.set(index, dynamicIndex);
		this.items.set(dynamicIndex, value);
  }

  public function deleteByIndex(fieldIndex: Int): Void {
    var index = this.indexes.get(fieldIndex);
    this.items.remove(index);
    this.indexes.remove(fieldIndex);
  }

  public var items:Map<Int, T> = new Map<Int, T>();
  public var indexes:OrderedMap<Int, Int> = new OrderedMap<Int, Int>(new Map<Int, Int>());

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

  public function clear(refs: ReferenceTracker) {
    if (!Std.isOfType(this._childType, String)) {
      // clear child refs
      for (item in this.items) {
        refs.remove(Reflect.getProperty(item, "__refId"));
      }
    }

    this.items.clear();
    this.indexes.clear();
  }

  public function clone():ArraySchemaImpl<T> {
    var cloned = new ArraySchemaImpl<T>();
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

		return "ArraySchema(" + Lambda.count(this.items) + ") { __refId => " + this.__refId +  ", " + data.join(", ") + " } ";
  }

  /** TODO: This only works with Abstracts! */

	// @:arrayAccess
	// public inline function arrayGet(key:Int) {
	// 	return this.items[key];
	// }

	// @:arrayAccess
	// public inline function arraySet(key:Int, value:T):T {
	// 	this.items.set(key, value);
	// 	return value;
	// }

}

//
// Implement arrayAccess for ArraySchema:
// - arr[x] = y
// - arr[x]
//
@:forward()
abstract ArraySchema<T>(ArraySchemaImpl<T>) {
  public function new () { this = new ArraySchemaImpl<T>(); }
	@:arrayAccess inline function arrayGet(_key:Int):T {
		return this.getByIndex(_key);
  }
	@:arrayAccess inline function arraySet(_key:Int, _value:T):T {
		this.items.set(_key, _value);
		return _value;
	}
}
