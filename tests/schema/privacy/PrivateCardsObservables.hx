package schema.privacy;

import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.tools.SchemaListenMacro;
import tink.core.Callback.CallbackLink;
import tink.state.*;

@:build(io.colyseus.tools.ObservableSchemaMacro.build(PrivateCards))
class PrivateCardsObservables {
	public function listen(callbacks:SchemaCallbacks<PrivateCards>, state:PrivateCards):CallbackLink
		return SchemaListenMacro.listenRef(callbacks, state);
}
