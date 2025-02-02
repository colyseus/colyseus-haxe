package io.colyseus.serializer.schema.types;

import io.colyseus.serializer.schema.Schema.DataChange;
import io.colyseus.serializer.schema.Callbacks;

class OrderedMapIterator<K,V> {
    var map : OrderedMap<K,V>;
    var index : Int = 0;
    public function new(omap:OrderedMap<K,V>) { map = omap; }
    public function hasNext() : Bool { return index < map._keys.length;}
    public function next() : V { return map.get(map._keys[index++]); }
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
    public function keyValueIterator() return this.map.keyValueIterator();
    public function remove(key: K) return map.remove(key) && _keys.remove(key);
    public function exists(key: K) return map.exists(key);
    public function get(key: K) return map.get(key);
    public inline function keys() return _keys.iterator();
}


@:keep
@:generic
class MapSchema<T> implements IRef implements ISchemaCollection {
  public var __refId: Int;
  public var _childType: Dynamic;

  private var _callbacks: Map<Int, Array<Dynamic>> = null;
  private var __isMapSchema: Bool = true;

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
    this.items.remove(index);
    this.indexes.remove(fieldIndex);
  }

  public var items:OrderedMap<String, T> = new OrderedMap<String, T>(new Map<String, T>());
  public var indexes:Map<Int, String> = new Map<Int, String>();

  public var length(get, null): Int;
  function get_length() { return Lambda.count(this.items._keys); }

  public function new() {}

  public function clear(changes: Array<DataChange>, refs: ReferenceTracker) {
    Callbacks.removeChildRefs(this, changes, refs);

    this.items.clear();
    this.indexes.clear();
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

    for (key in this.items._keys) {
      data.push(key + " => " + this.items.get(key));
    }

    return "MapSchema ("+ Lambda.count(this.items) +", __refId => "+this.__refId+") { " + data.join(", ") + " }";
  }
}