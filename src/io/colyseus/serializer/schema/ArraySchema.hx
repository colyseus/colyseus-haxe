package io.colyseus.serializer.schema;

@:keep
@:generic
class ArraySchema<T> {
  public var items:Array<T> = [];
  public var length(get, null): Int;

  function get_length() {
      return this.items.length;
  }

  public dynamic function onAdd(item:T, key:Int):Void {}
  public dynamic function onChange(item:T, key:Int):Void {}
  public dynamic function onRemove(item:T, key:Int):Void {}

  public function new() {}

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
      data.push(""+item);
    }
    return "ArraySchema("+Lambda.count(this.items)+") { " + data.join(", ") + " } ";
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