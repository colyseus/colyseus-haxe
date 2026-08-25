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

//
// `dispatch` walks a COPY of the list: a handler is allowed to remove itself
// (or another) while it runs, and mutating the array mid-iteration would make
// the index-based iterator skip whatever slid into the vacated slot. `once`
// depends on this, and so does any `room.onX -= self` inside a handler.
//
// `once` registers a wrapper that unsubscribes BEFORE calling, so a listener
// that throws still doesn't fire twice, and re-entrant dispatch can't either.
//
// It is @:generic so the wrapper closure is built with the CONCRETE parameter
// type: hl erases a method type param to dyn, and a (dyn)->void wrapper stored
// in an Array<Int->Void> segfaults when dispatch calls it with a raw int.
//

class EventHandlerDispatcher0 {
  public static inline function dispatch(e:EventHandler<Void->Void>) {
    for(fn in @:privateAccess e.handlers.copy()) {
      fn();
    }
  }

  /** Listen for the NEXT dispatch only; the listener removes itself. */
  public static function once(e:EventHandler<Void->Void>, fn:Void->Void) {
    var wrapper:Void->Void = null;
    wrapper = function() { e -= wrapper; fn(); };
    e += wrapper;
  }
}

class EventHandlerDispatcher1 {
  public static inline function dispatch<T>(e:EventHandler<T->Void>, arg:T) {
    for(fn in @:privateAccess e.handlers.copy()) {
      fn(arg);
    }
  }

  /** Listen for the NEXT dispatch only; the listener removes itself. */
  @:generic public static function once<T>(e:EventHandler<T->Void>, fn:T->Void) {
    var wrapper:T->Void = null;
    wrapper = function(arg:T) { e -= wrapper; fn(arg); };
    e += wrapper;
  }
}

class EventHandlerDispatcher2 {
  public static inline function dispatch<T1,T2>(e:EventHandler<T1->T2->Void>, arg1:T1, arg2:T2) {
    for(fn in @:privateAccess e.handlers.copy()) {
      fn(arg1, arg2);
    }
  }

  /** Listen for the NEXT dispatch only; the listener removes itself. */
  @:generic public static function once<T1,T2>(e:EventHandler<T1->T2->Void>, fn:T1->T2->Void) {
    var wrapper:T1->T2->Void = null;
    wrapper = function(a1:T1, a2:T2) { e -= wrapper; fn(a1, a2); };
    e += wrapper;
  }
}