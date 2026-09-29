package schema.macrogenerator;

import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import tink.core.Callback.CallbackLink;
import tink.state.*;

@:build(io.colyseus.tools.ObservableSchemaMacro.build(NestedRefRoot))
class NestedRefRootObservables {
	public function listen(callbacks:SchemaCallbacks<NestedRefRoot>, state:NestedRefRoot):CallbackLink
		return io.colyseus.tools.SchemaListenMacro.listenRef(callbacks, state);
}
