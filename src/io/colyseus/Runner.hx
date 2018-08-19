/**
 * Based on https://gist.github.com/underscorediscovery/e66e72ec702bdcedf5af45f8f4712109
 */
package io.colyseus;

#if neko
    import neko.vm.Thread;
    import neko.vm.Deque;
    import neko.vm.Lock;
#elseif cpp
    import cpp.vm.Thread;
    import cpp.vm.Deque;
    import cpp.vm.Lock;
#end

/**
A simple Haxe class for easily running threads and calling functions on the primary thread.
from https://github.com/underscorediscovery/
Usage:
- call Runner.init() from your primary thread
- call Runner.run() periodically to service callbacks (i.e inside your main loop)
- use Runner.thread(function() { ... }) to make a thread
- use Runner.call_primary(function() { ... }) to run code on the main thread
- use call_primary_ret to run code on the main thread and wait for the return value
*/
class Runner {
    public static var primary : Thread;

    static var queue : Deque<Void->Void>;

    /** Call this on your thread to make primary,
        the calling thread will be used for callbacks. */
    public static function init() {
        queue = new Deque<Void->Void>();
        primary = Thread.current();
    }

    /** Call this on the primary manually,
        Returns the number of callbacks called. */
    public static function run() : Int {
        var more = true;
        var count = 0;

        while(more) {
            var item = queue.pop(false);
            if(item != null) {
                count++; item(); item = null;
            } else {
                more = false; break;
            }
        }

        return count;
    }

    /** Call a function on the primary thread without waiting or blocking.
        If you want return values see call_primary_ret */
    public static function call_primary( _fn:Void->Void ) {
        queue.push(_fn);
    }

    /** Call a function on the primary thread and wait for the return value.
        This will block the calling thread for a maximum of _timeout, default to 0.1s.
        To call without a return or blocking, use call_primary */
    public static function call_primary_ret<T>( _fn:Void->T, _timeout:Float=0.1 ) : Null<T> {
        var res:T = null;
        var start = haxe.Timer.stamp();
        var lock = new Lock();

        //add to main to call this
        queue.push(function() {
            res = _fn();
            lock.release();
        });

        //wait for the lock release or timeout
        lock.wait(_timeout);

        //clean up
        lock = null;

        //return result
        return res;

    }

    /** Create a thread using the given function */
    public static function thread( fn:Void->Void ) : Thread {
        return Thread.create( fn );
    }

} //Runner