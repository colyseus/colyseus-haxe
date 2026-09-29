import haxe.io.Bytes;
import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.serializer.schema.Decoder;
import schema.macrogenerator.MacroRoot;
import schema.macrogenerator.MacroRootObservables;
import schema.macrogenerator.NestedRefRoot;
import schema.macrogenerator.NestedRefRootObservables;

class SchemaMacroGeneratorTestCase extends haxe.unit.TestCase {
	// Encoded by @colyseus/schema 5.0.34. The first patch changes items before tick.
	static final INITIAL = [129, 1, 130, 3, 131, 4, 132, 5, 133, 6, 255, 1, 128, 0, 129, 0, 130, 2, 255, 3, 128, 0, 161, 97, 7, 255, 7, 128, 1, 129, 161, 65];
	static final ADD = [255, 3, 128, 1, 161, 98, 8, 255, 8, 128, 2, 129, 161, 66];
	static final DELETE = [255, 3, 64, 0];
	static final ALL_KINDS = [128, 1, 134, 165, 104, 101, 108, 108, 111, 135, 167, 123, 34, 110, 34, 58, 55, 125, 255, 1, 128, 3, 255, 2, 128, 0, 161, 114, 9, 255, 9, 128, 4, 129, 161, 82, 255, 4, 128, 0, 10, 255, 10, 128, 5, 129, 161, 76, 255, 5, 128, 0, 165, 114, 101, 97, 100, 121, 1, 255, 6, 128, 0, 165, 102, 105, 114, 115, 116];
	static final REPLACE_CHILD = [193, 11, 255, 11, 128, 11, 129, 0, 130, 12, 255, 12, 128, 0, 161, 115, 13, 255, 13, 128, 12, 129, 161, 83];
	static final REPLACE_MAP = [194, 14, 255, 14, 128, 0, 161, 99, 15, 255, 15, 128, 6, 129, 161, 67];

	public function testRootMapTracksPatchesWithoutEarlierRootField() {
		var state = new MacroRoot();
		var decoder = new Decoder(state);
		var obs = new MacroRootObservables();
		obs.listen(new SchemaCallbacks<MacroRoot>(decoder), state);

		decode(decoder, INITIAL);
		assertEquals(1, obs.items.get("a").value.value);
		decode(decoder, ADD);
		assertEquals(2, obs.items.get("b").value.value);
		decode(decoder, DELETE);
		assertFalse(obs.items.exists("a"));
		assertEquals("B", obs.items.get("b").name.value);
	}

	public function testLateBindingAndAllFieldKinds() {
		var state = new MacroRoot();
		var decoder = new Decoder(state);
		var callbacks = new SchemaCallbacks<MacroRoot>(decoder);
		decode(decoder, INITIAL);
		decode(decoder, ADD);
		var obs = new MacroRootObservables();
		obs.listen(callbacks, state);
		assertEquals(1, obs.items.get("a").value.value);
		assertEquals(2, obs.items.get("b").value.value);

		decode(decoder, DELETE);
		decode(decoder, ALL_KINDS);
		assertEquals(1, obs.tick.value);
		assertEquals("hello", obs.label.value);
		assertEquals(7, obs.payload.value.n);
		assertEquals(3, obs.child.value.value.value);
		assertFalse(obs.child.value.active.value);
		assertEquals(4, obs.child.value.rows.get("r").value.value);
		assertEquals(5, obs.list.get(0).value.value);
		assertTrue(obs.flags.get("ready"));
		assertEquals("first", obs.names.get(0));
	}

	public function testReplacementAndCancellation() {
		var state = new MacroRoot();
		var decoder = new Decoder(state);
		var obs = new MacroRootObservables();
		var link = obs.listen(new SchemaCallbacks<MacroRoot>(decoder), state);
		decode(decoder, INITIAL);
		decode(decoder, ADD);
		decode(decoder, DELETE);
		decode(decoder, ALL_KINDS);
		var count = listenerCount(decoder);
		for (tick in 2...102) decode(decoder, [128, tick]);
		assertEquals(count, listenerCount(decoder));

		decode(decoder, [255, 1, 128, 9]);
		assertEquals(9, obs.child.value.value.value);
		decode(decoder, REPLACE_CHILD);
		assertEquals(11, obs.child.value.value.value);
		assertFalse(obs.child.value.rows.exists("r"));
		assertEquals(12, obs.child.value.rows.get("s").value.value);
		decode(decoder, [255, 11, 128, 13]);
		assertEquals(13, obs.child.value.value.value);
		decode(decoder, REPLACE_MAP);
		assertFalse(obs.items.exists("b"));
		assertEquals(6, obs.items.get("c").value.value);
		decode(decoder, [255, 15, 128, 7]);
		assertEquals(7, obs.items.get("c").value.value);
		decode(decoder, [65]);
		assertEquals(0, obs.child.value.value.value);
		assertFalse(obs.child.value.rows.exists("s"));
		decode(decoder, [129, 16, 255, 16, 128, 15, 129, 0, 130, 17]);
		assertEquals(15, obs.child.value.value.value);

		link.cancel();
		assertEquals(0, listenerCount(decoder));
		decode(decoder, [255, 16, 128, 14]);
		assertEquals(15, obs.child.value.value.value);
	}

	public function testArrayAndPrimitiveCollectionUpdates() {
		var state = new MacroRoot();
		var decoder = new Decoder(state);
		var obs = new MacroRootObservables();
		var link = obs.listen(new SchemaCallbacks<MacroRoot>(decoder), state);
		decode(decoder, INITIAL);
		decode(decoder, ADD);
		decode(decoder, DELETE);
		decode(decoder, ALL_KINDS);
		decode(decoder, REPLACE_CHILD);
		decode(decoder, REPLACE_MAP);
		decode(decoder, [255, 4, 128, 1, 16, 255, 16, 128, 8, 129, 161, 77]);
		assertEquals(2, obs.list.length);
		assertEquals(8, obs.list.get(1).value.value);
		decode(decoder, [255, 4, 33, 10]);
		assertEquals(1, obs.list.length);
		assertEquals("M", obs.list.get(0).name.value);
		decode(decoder, [255, 5, 0, 0, 0, 128, 1, 165, 111, 116, 104, 101, 114, 1, 255, 6, 128, 1, 166, 115, 101, 99, 111, 110, 100]);
		assertFalse(obs.flags.get("ready"));
		assertTrue(obs.flags.get("other"));
		assertEquals("second", obs.names.get(1));
		decode(decoder, [255, 5, 64, 1, 255, 6, 64, 0]);
		assertFalse(obs.flags.exists("other"));
		assertEquals(1, obs.names.length);
		assertEquals("second", obs.names.get(0));

		decode(decoder, [255, 4, 128, 0, 17, 255, 17, 128, 20, 129, 161, 88]);
		assertEquals("X", obs.list.get(0).name.value);
		assertEquals("M", obs.list.get(1).name.value);
		decode(decoder, [255, 17, 128, 21]);
		assertEquals(21, obs.list.get(0).value.value);
		decode(decoder, [255, 4, 33, 16]);
		assertEquals(1, obs.list.length);
		assertEquals("X", obs.list.get(0).name.value);
		decode(decoder, [255, 17, 128, 22]);
		assertEquals(22, obs.list.get(0).value.value);

		decode(decoder, [196, 18, 255, 18, 128, 0, 165, 102, 114, 101, 115, 104, 1]);
		assertFalse(obs.flags.exists("ready"));
		assertTrue(obs.flags.get("fresh"));
		decode(decoder, [197, 19, 255, 19, 128, 0, 165, 102, 114, 101, 115, 104]);
		assertEquals(1, obs.names.length);
		assertEquals("fresh", obs.names.get(0));
		decode(decoder, [195, 20, 255, 20, 128, 0, 21, 255, 21, 128, 30, 129, 161, 78]);
		assertEquals(1, obs.list.length);
		assertEquals(30, obs.list.get(0).value.value);
		decode(decoder, [255, 21, 128, 31]);
		assertEquals(31, obs.list.get(0).value.value);
		decode(decoder, [255, 20, 192, 0, 22, 255, 22, 128, 40, 129, 161, 81]);
		assertEquals(1, obs.list.length);
		assertEquals("Q", obs.list.get(0).name.value);
		decode(decoder, [255, 22, 128, 41]);
		assertEquals(41, obs.list.get(0).value.value);
		link.cancel();
		assertEquals(0, listenerCount(decoder));
	}

	public function testRefInsideMapItemRebindsAndCancels() {
		var state = new NestedRefRoot();
		var decoder = new Decoder(state);
		var callbacks = new SchemaCallbacks<NestedRefRoot>(decoder);
		var obs = new NestedRefRootObservables();
		var link = obs.listen(callbacks, state);
		decode(decoder, [128, 1, 255, 1, 128, 0, 161, 97, 2, 255, 2, 128, 3, 255, 3, 128, 1]);
		assertEquals(1, obs.items.get("a").leaf.value.value.value);
		decode(decoder, [255, 3, 128, 2]);
		assertEquals(2, obs.items.get("a").leaf.value.value.value);
		decode(decoder, [255, 2, 192, 4, 255, 4, 128, 3]);
		assertEquals(3, obs.items.get("a").leaf.value.value.value);
		decode(decoder, [255, 1, 64, 0]);
		assertFalse(obs.items.exists("a"));
		decode(decoder, [255, 1, 128, 1, 161, 98, 5, 255, 5, 128, 6, 255, 6, 128, 4]);
		assertEquals(4, obs.items.get("b").leaf.value.value.value);
		link.cancel();
		assertEquals(0, listenerCount(decoder));
	}

	public function testMapItemReplacementKeepsOneListener() {
		var state = new MacroRoot();
		var decoder = new Decoder(state);
		var obs = new MacroRootObservables();
		var link = obs.listen(new SchemaCallbacks<MacroRoot>(decoder), state);
		decode(decoder, INITIAL);
		decode(decoder, ADD);
		decode(decoder, DELETE);
		decode(decoder, ALL_KINDS);
		decode(decoder, REPLACE_CHILD);
		decode(decoder, REPLACE_MAP);
		decode(decoder, [255, 15, 128, 7]);
		decode(decoder, [255, 14, 192, 0, 161, 99, 16, 255, 16, 128, 9, 129, 161, 68]);
		assertEquals("D", obs.items.get("c").name.value);
		assertEquals(9, obs.items.get("c").value.value);
		decode(decoder, [255, 16, 128, 10]);
		assertEquals(10, obs.items.get("c").value.value);
		link.cancel();
		assertEquals(0, listenerCount(decoder));
	}

	static function decode<T>(decoder:Decoder<T>, data:Array<Int>) {
		var bytes = Bytes.alloc(data.length);
		for (i in 0...data.length) bytes.set(i, data[i]);
		decoder.decode(bytes);
	}

	static function listenerCount<T>(decoder:Decoder<T>):Int {
		var count = 0;
		for (fields in decoder.refs.callbacks0) for (listeners in fields) count += listeners.length;
		for (fields in decoder.refs.callbacks2) for (listeners in fields) count += listeners.length;
		return count;
	}
}
