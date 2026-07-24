package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.Schema.OPERATION;
import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Callbacks;

interface IArraySchema extends ISchemaCollection {
	public function setByIndex(fieldIndex:Int, value:Dynamic, operation:Int):Void;

	public function reverse():Void;
    public function indexOf(value: Dynamic): Int;

    public function __onDecodeEnd(): Void;
    public function __resyncPrune(visitedIndexes:Map<Int, Bool>, prune:(Dynamic, Dynamic)->Void, keep:(Dynamic)->Void):Void;
}

@:keep
@:generic
class ArraySchemaImpl<T> implements IRef implements IArraySchema implements ArrayAccess<Int> {
  public var __refId: Int = 0;
  public var _childType: Dynamic;

  public var items:Array<T> = new Array<T>();
  var _deletedIndices:Map<Int, Bool> = new Map<Int, Bool>();

  public var length(get, null): Int;
  function get_length() { return this.items.length; }

  public function getByIndex(index: Int): Dynamic {
    return this.items[index];
  }

  public function setByIndex(index: Int, value: Dynamic, operation: OPERATION): Void {
    // strict ADD only: MOVE_AND_ADD/DELETE_AND_ADD/ADD_BY_REFID must not insert
    if (operation == OPERATION.ADD && this.items[index] != null) {
        // ADD at an occupied index = insert: shift existing items up.
        this.items.insert(index, value);

    } else if (operation == OPERATION.DELETE_AND_MOVE) {
        this.items.splice(index, 1);
        this.items[index] = value;

    } else {
        this.items[index] = value;
    }
  }

  public function deleteByIndex(index: Int): Void {
    this.items[index] = cast null;
    this._deletedIndices.set(index, true);
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
    // Remove deleted items by index (descending to preserve indices)
    var toRemove = [for (i in _deletedIndices.keys()) i];
    toRemove.sort(function(a, b) return b - a);
    for (i in toRemove) {
      if (i >= 0 && i < items.length) {
        items.splice(i, 1);
      }
    }
    _deletedIndices.clear();
  }

  /**
   * Resync sweep (see Decoder.decodeResync): remove every entry whose index
   * the snapshot did not visit. `items` is hole-free here (decode-end
   * compaction already ran; full-sync emits dense ADDs). Visited indexes may
   * be sparse — ADD_BY_REFID resolves to the current client-side index.
   */
  public function __resyncPrune(visitedIndexes:Map<Int, Bool>, prune:(Dynamic, Dynamic)->Void, keep:(Dynamic)->Void):Void {
    var removed = false;
    for (i in 0...this.items.length) {
      var value:Dynamic = this.items[i];
      if (visitedIndexes.exists(i)) { keep(value); continue; }
      removed = true;
      prune(value, i);
      this.deleteByIndex(i);
    }
    if (removed) { this.__onDecodeEnd(); } // compact the holes
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
