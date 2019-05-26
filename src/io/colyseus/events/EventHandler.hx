package io.colyseus.events;

import haxe.Constraints.Function;

abstract EventHandler<T:Function>(Array<T>) {
  var handlers(get,never):Array<T>;
  inline function get_handlers() return this;

  public inline function new() {
    this = [];
  }

  @:op(a += b) inline function add(fn:T) {
    this.push(fn);
  }

  @:op(a -= b) inline function remove(fn:T) {
    this.remove(fn);
  }
}

class EventHandlerDispatcher0 {
  public static inline function dispatch(e:EventHandler<Void->Void>) {
    for(fn in @:privateAccess e.handlers) {
      fn();
    }
  }
}

class EventHandlerDispatcher1 {
  public static inline function dispatch<T>(e:EventHandler<T->Void>, arg:T) {
    for(fn in @:privateAccess e.handlers) {
      fn(arg);
    }
  }
}

class EventHandlerDispatcher2 {
  public static inline function dispatch<T1,T2>(e:EventHandler<T1->T2->Void>, arg1:T1, arg2:T2) {
    for(fn in @:privateAccess e.handlers) {
      fn(arg1, arg2);
    }
  }
}