package io.colyseus.serializer;

import haxe.io.Bytes;
import org.msgpack.MsgPack;
import io.gamestd.FossilDelta;
import io.colyseus.state_listener.StateContainer;

class FossilDeltaSerializer implements Serializer {
    public var state = new StateContainer({});
    private var _previousState: Bytes;

    public function new () {}

    public function setState(encodedState: Bytes) {
        this._previousState = encodedState;
        this.state.set(MsgPack.decode(encodedState));
    }

    public function getState(): Dynamic {
        return this.state.state;
    }

    public function patch(patches: Bytes) {
        // apply patch
        this._previousState = FossilDelta.Apply(this._previousState, patches);

        // trigger state callbacks
        this.state.set(MsgPack.decode(this._previousState));
    }

    public function teardown() {
        this.state.removeAllListeners();
    }

    public function handshake(bytes: Bytes, offset: Int) {
    }

}
