package schema.macrogenerator;

import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.serializer.schema.Decoder;
import tink.core.Callback.CallbackLink;
import tink.state.*;

@:build(io.colyseus.tools.ObservableSchemaMacro.build(MacroRoot))
class MacroRootObservables {
	public function listen(callbacks:SchemaCallbacks<MacroRoot>, state:MacroRoot):CallbackLink
		return io.colyseus.tools.SchemaListenMacro.listenRef(callbacks, state);

	// Same shape as `listenRef(Callbacks.get(room), room.state)`: a fresh instance per evaluation.
	public function listenDecoder(decoder:Decoder<MacroRoot>, state:MacroRoot):CallbackLink
		return io.colyseus.tools.SchemaListenMacro.listenRef(new SchemaCallbacks<MacroRoot>(decoder), state);
}
