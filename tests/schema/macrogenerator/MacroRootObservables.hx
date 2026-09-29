package schema.macrogenerator;

import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import tink.core.Callback.CallbackLink;
import tink.state.*;

@:build(io.colyseus.tools.ObservableSchemaMacro.build(MacroRoot))
class MacroRootObservables {
	public function listen(callbacks:SchemaCallbacks<MacroRoot>, state:MacroRoot):CallbackLink
		return io.colyseus.tools.SchemaListenMacro.listenRef(callbacks, state);
}
