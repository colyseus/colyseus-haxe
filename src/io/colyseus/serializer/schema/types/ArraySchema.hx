package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.Schema.OPERATION;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Callbacks;

interface IArraySchema extends ISchemaCollection {
	public function setByIndex(fieldIndex:Int, value:Dynamic, operation:Int):Void;

	public function reverse():Void;
    public function indexOf(value: Dynamic): Int;

    public function __onDecodeEnd(): Void;
}

@:keep
@:generic
class ArraySchemaImpl<T> implements IRef implements IArraySchema implements ArrayAccess<Int> {
  public var __refId: Int = 0;
  public var _childType: Dynamic;

  public var items:Array<T> = new Array<T>();

  public var length(get, null): Int;
  function get_length() { return this.items.length; }

  public function getByIndex(index: Int): Dynamic {
    return this.items[index];
  }

  public function setByIndex(index: Int, value: Dynamic, operation: OPERATION): Void {
    if (index == 0 && operation == OPERATION.ADD && this.items.length > 0) {
        this.items.insert(0, value);

    } else if (operation == OPERATION.DELETE_AND_MOVE) {
        this.items.splice(index, 1);
        this.items[index] = value;

    } else {
        this.items[index] = value;
    }
  }

  public function deleteByIndex(index: Int): Void {
    this.items[index] = null;
  }

  public function new() {}

  public function clear(changes: Array<DataChange>, refs: ReferenceTracker) {
    Callbacks.removeChildRefs(this, changes, refs);
    while (this.items.length > 0) {
      this.items.pop();
    }
  }

  public function clone():ISchemaCollection {
    var cloned = new ArraySchemaImpl<T>();
    cloned.items = this.items.copy();
    return cloned;
  }

  public function iterator() return this.items.iterator();
  public function keyValueIterator() return this.items.keyValueIterator();

  public function indexOf(value: Dynamic): Int {
    var i: Int = 0;
    for (item in this.items) {
      if (item == value) {
        return i;
      }
      i++;
    }
    return -1;
  }

  public function reverse() {
    this.items.reverse();
  }

  public function __onDecodeEnd() {
    this.items = this.items.filter(function(item) return item != null);
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
		return this.items[_key];
  }
	@:arrayAccess inline function arraySet(_key:Int, _value:T):T {
        this.items[_key] = _value;
		return _value;
	}
}
