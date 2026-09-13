package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Callbacks;

interface IMapSchema extends ISchemaCollection {
	public function setIndex(index:Int, dynamicIndex:Dynamic):Void;
	public function getIndex(index:Int):Dynamic;
	public function setByIndex(index:Int, dynamicIndex:Dynamic, value:Dynamic):Void;
	public function __resyncPrune(visitedKeys:Map<String, Bool>, prune:(Dynamic, Dynamic)->Void, keep:(Dynamic)->Void):Void;
}

class OrderedMapIterator<K,V> {
    var map : OrderedMap<K,V>;
    var index : Int = 0;
    public function new(omap:OrderedMap<K,V>) { map = omap; }
    public function hasNext() : Bool { return index < map._keys.length;}
    public function next() : V { return map.get(map._keys[index++]); }
}

class OrderedMapKeyValueIterator<K,V> {
    var map : OrderedMap<K,V>;
    var index : Int = 0;
    public inline function new(omap:OrderedMap<K,V>) { map = omap; }
    public inline function hasNext() : Bool { return index < map._keys.length; }
    public inline function next() : {key:K, value:V} {
        var key = map._keys[index++];
        return {key: key, value: map.get(key)};
    }
}

// class OrderedMap<K, V> implements IMap<K, V> {
@:keep
class OrderedMap<K, V> {
    var map:Map<K, V>;

    @:allow(OrderedMapIterator) // TODO: why this doesn't seem to work?
    public var _keys:Array<K>; // FIXME: this should be private
    var idx = 0;

    public function new(_map) {
       _keys = [];
       map = _map;
    }

    public function set(key: K, value: V) {
        if(!map.exists(key)) _keys.push(key);
        map[key] = value;
    }

    public function toString() {
        var _ret = ''; var _cnt = 0; var _len = _keys.length;
        for(k in _keys) _ret += '$k => ${map.get(k)}${(_cnt++<_len-1?", ":"")}';
        return '{$_ret}';
    }

    public function clear() {
      this.map.clear();
      this._keys = [];
    }

    public function iterator() return new OrderedMapIterator<K,V>(this);
    // insertion order, like iterator() and JS Map (the backing Map iterates in hash order)
    public function keyValueIterator() return new OrderedMapKeyValueIterator<K,V>(this);
    public function remove(key: K) return map.remove(key) && _keys.remove(key);
    public function exists(key: K) return map.exists(key);
    public function get(key: K) return map.get(key);
    public inline function keys() return _keys.iterator();
}


@:keep
@:generic
class MapSchema<T> implements IMapSchema {
  public var __refId: Int = 0;
  public var _childType: Dynamic;

  public var items:OrderedMap<String, T> = new OrderedMap<String, T>(new Map<String, T>());
  public var indexes:Map<Int, String> = new Map<Int, String>();

  public function getIndex(fieldIndex: Int) {
    return this.indexes.get(fieldIndex);
  }

  public function setIndex(fieldIndex: Int, dynamicIndex: Dynamic) {
    this.indexes.set(fieldIndex, dynamicIndex);
  }

  public function getByIndex(fieldIndex: Int): Dynamic {
    var index = this.indexes.get(fieldIndex);

    return (index != null)
      ? this.items.get(index)
      : null;
  }

  public function setByIndex(index: Int, dynamicIndex: Dynamic, value: Dynamic): Void {
    this.indexes.set(index, dynamicIndex);
    this.items.set(dynamicIndex, value);
  }

  public function deleteByIndex(fieldIndex: Int): Void {
    var index = this.indexes.get(fieldIndex);
    // stale wire index (e.g. a late DELETE for an entry the resync sweep
    // already removed) — silent no-op; neko's StringMap throws on null keys
    if (index == null) { return; }
    this.items.remove(index);
    this.indexes.remove(fieldIndex);
  }

  public var length(get, null): Int;
  function get_length() { return this.items._keys.length; }

  public function new() {}

  public function clear(changes: Array<DataChange>, refs: ReferenceTracker) {
    Callbacks.removeChildRefs(this, changes, refs);

    this.items.clear();
    this.indexes.clear();
  }

  /**
   * Resync sweep (see Decoder.decodeResync): remove every entry whose KEY
   * the snapshot did not visit — maps prune by string key, NOT wire index
   * (the decoder-side `indexes` journal never evicts stale index→key
   * mappings on re-indexing). Also scrubs ALL index→key rows of swept keys.
   */
  public function __resyncPrune(visitedKeys:Map<String, Bool>, prune:(Dynamic, Dynamic)->Void, keep:(Dynamic)->Void):Void {
    var deletedKeys:Array<String> = [];
    for (key in this.items._keys.copy()) { // copy — no mutation during iteration
      var value = this.items.get(key);
      if (visitedKeys.exists(key)) { keep(value); continue; }
      deletedKeys.push(key);
      prune(value, key);
    }
    for (key in deletedKeys) {
      this.items.remove(key);

      var staleIndexes:Array<Int> = [];
      for (i => k in this.indexes) {
        if (k == key) { staleIndexes.push(i); }
      }
      for (i in staleIndexes) { this.indexes.remove(i); }
    }
  }

  public function clone():MapSchema<T> {
    var cloned = new MapSchema<T>();

    cloned.indexes = this.indexes.copy();

    for (key in this.items._keys) {
      cloned.items.set(key, this.items.get(key));
    }

    return cloned;
  }

  public function iterator() return this.items.iterator();
  public function keyValueIterator() return this.items.keyValueIterator();

  @:arrayAccess
  public inline function get(key:String) {
    return this.items.get(key);
  }

  @:arrayAccess
  public inline function arrayWrite(key:String, value:T):T {
    this.items.set(key, value);
    return value;
  }

  public function toString () {
    var data = [];
    var items = this.items ?? new OrderedMap<String, T>(new Map<String, T>());

    for (key in items._keys) {
        data.push(key + " => " + items.get(key));
    }

    return "MapSchema ("+ Lambda.count(items) +", __refId => "+this.__refId+") { " + data.join(", ") + " }";
  }
}