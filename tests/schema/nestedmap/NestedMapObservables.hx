package schema.nestedmap;

import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import tink.core.Callback.CallbackLink;
import tink.state.*;

@:build(io.colyseus.tools.ObservableSchemaMacro.build(NestedMap))
class NestedMapObservables {
	public function listen(callbacks:SchemaCallbacks<NestedMap>, state:NestedMap):CallbackLink
		return io.colyseus.tools.SchemaListenMacro.listenRef(callbacks, state);
}
