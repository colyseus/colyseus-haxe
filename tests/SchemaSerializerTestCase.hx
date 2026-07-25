import haxe.io.Bytes;
import haxe.io.BytesData;

import io.colyseus.serializer.SchemaSerializer;
import io.colyseus.serializer.schema.ReferenceTracker;
import io.colyseus.serializer.schema.Decoder;
import io.colyseus.serializer.schema.Callbacks;

import schema.primitivetypes.PrimitiveTypes;
import schema.childschematypes.ChildSchemaTypes;
import schema.arrayschematypes.ArraySchemaTypes;
import schema.mapschematypes.MapSchemaTypes;
import schema.mapschemaint8.MapSchemaInt8;
import schema.inheritedtypes.InheritedTypes;
import schema.backwardsforwards.StateV1;
import schema.backwardsforwards.StateV2;
import schema.filteredtypes.State in FilteredTypesState;
import schema.instancesharingtypes.State in InstanceSharingTypes;
import schema.callbacks.CallbacksState;
import schema.arrayschemainsertops.ArraySchemaInsertOps;
import schema.resyncfixtures.ResyncState;
import schema.resyncfixtures.ResyncArrayState;
import schema.resyncfixtures.ResyncStateV1;
import schema.resyncfixtures.ResyncTransientState;
import schema.resyncfixtures.Unit;
import schema.quantized.QState;

import io.colyseus.serializer.schema.Quantize;

class SchemaSerializerTestCase extends haxe.unit.TestCase {

    private function getBytes(arr: Array<Int>) {
        var bytes = Bytes.alloc(arr.length);
        var i: Int = 0;
        for (byte in arr) { bytes.set(i++, byte); }
        return bytes;
    }

    public function testPrimitiveTypes() {
        var state = new PrimitiveTypes();
        var decoder = new Decoder(state);
        var bytes = [128, 128, 129, 255, 130, 0, 128, 131, 255, 255, 132, 0, 0, 0, 128, 133, 255, 255, 255, 255, 134, 0, 0, 0, 0, 0, 0, 0, 128, 135, 255, 255, 255, 255, 255, 255, 31, 0, 136, 204, 204, 204, 253, 137, 255, 255, 255, 255, 255, 255, 239, 127, 138, 208, 128, 139, 204, 255, 140, 209, 0, 128, 141, 205, 255, 255, 142, 210, 0, 0, 0, 128, 143, 203, 0, 0, 224, 255, 255, 255, 239, 65, 144, 203, 0, 0, 0, 0, 0, 0, 224, 195, 145, 203, 255, 255, 255, 255, 255, 255, 63, 67, 146, 203, 61, 255, 145, 224, 255, 255, 239, 199, 147, 203, 153, 153, 153, 153, 153, 153, 185, 127, 148, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 149, 1];
        decoder.decode(getBytes(bytes));

        assertEquals(state.int8, -128);
        assertEquals(state.uint8, 255);
        assertEquals(state.int16, -32768);
        assertEquals(state.uint16, 65535);
        assertEquals(state.int32, -2147483648);

        assertEquals(4294967295, state.uint32);
        // assertEquals(-9223372036854775808, state.int64);
        // assertEquals(9007199254740991, haxe.Int64.toInt(state.uint64));

        assertEquals(state.float32, -3.4028234663852886e+37);
        assertEquals(state.float64, 1.7976931348623157e+308);

        assertEquals(state.varint_int8, -128);
        assertEquals(state.varint_uint8, 255);
        assertEquals(state.varint_int16, -32768);
        assertEquals(state.varint_uint16, 65535);
        assertEquals(state.varint_int32, -2147483648);
        assertEquals(state.varint_uint32, 4294967295);

        // // failing on cpp target
        // assertEquals(state.varint_int64, -9223372036854775808);
        assertEquals(state.varint_uint64, 9007199254740991);
        assertEquals(state.varint_float32, -3.40282347e+38);
        assertEquals(state.varint_float64, 1.7976931348623157e+307);

        assertEquals(state.str, "Hello world");
        assertEquals(state.boolean, true);
    }

    public function testChildSchemaTypes() {
        var state = new ChildSchemaTypes();
        var decoder = new Decoder(state);
        var bytes = [128, 1, 129, 2, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1];
        decoder.decode(getBytes(bytes));

        assertEquals(state.child.x, 500);
        assertEquals(state.child.y, 800);

        assertEquals(state.secondChild.x, 200);
        assertEquals(state.secondChild.y, 300);
    }

    public function testArraySchemaTypes() {
        var state = new ArraySchemaTypes();
        var decoder = new Decoder(state);
        var bytes = [ 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 5, 128, 1, 6, 255, 2, 128, 0, 0, 128, 1, 10, 128, 2, 20, 128, 3, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 128, 1, 163, 116, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 255, 4, 128, 0, 232, 3, 0, 0, 128, 1, 192, 13, 0, 0, 128, 2, 72, 244, 255, 255, 255, 5, 128, 100, 129, 208, 156, 255, 6, 128, 100, 129, 208, 156 ];

        // state.arrayOfSchemas.onAdd((value, key) -> trace("onAdd, arrayOfSchemas => key: " + key + ", value: " + value));
        // state.arrayOfNumbers.onAdd((value, key) -> trace("onAdd, arrayOfNumbers => key: " + key + ", value: " + value));
        // state.arrayOfStrings.onAdd((value, key) -> trace("onAdd, arrayOfStrings => key: " + key + ", value: " + value));
        // state.arrayOfInt32.onAdd((value, key) -> trace("onAdd, arrayOfInt32 => key: " + key + ", value: " + value));

        // state.onChange(function(changes) {
        //     trace("\nCHANGES! => " + changes);
        // });

        decoder.decode(getBytes(bytes));

        assertEquals(state.arrayOfSchemas.length, 2);
        assertEquals(state.arrayOfSchemas.items[0].x, 100);
        assertEquals(state.arrayOfSchemas.items[0].y, -100);
        assertEquals(state.arrayOfSchemas.items[1].x, 100);
        assertEquals(state.arrayOfSchemas.items[1].y, -100);

        assertEquals(state.arrayOfNumbers.length, 4);
        assertEquals(state.arrayOfNumbers.items[0], 0);
        assertEquals(state.arrayOfNumbers.items[1], 10);
        assertEquals(state.arrayOfNumbers.items[2], 20);
        assertEquals(state.arrayOfNumbers.items[3], 3520);

        assertEquals(state.arrayOfStrings.length, 3);
        assertEquals(state.arrayOfStrings.items[0], "one");
        assertEquals(state.arrayOfStrings.items[1], "two");
        assertEquals(state.arrayOfStrings.items[2], "three");

        assertEquals(state.arrayOfInt32.length, 3);
        assertEquals(state.arrayOfInt32.items[0], 1000);
        assertEquals(state.arrayOfInt32.items[1], 3520);
        assertEquals(state.arrayOfInt32.items[2], -3000);

        var popBytes = [ 255, 1, 64, 1, 255, 2, 64, 3, 64, 2, 64, 1, 255, 4, 64, 2, 64, 1, 255, 3, 64, 2, 64, 1 ];
        decoder.decode(getBytes(popBytes));

        assertEquals(1, state.arrayOfSchemas.length);
        assertEquals(1, state.arrayOfNumbers.length);
        assertEquals(1, state.arrayOfStrings.length);
        assertEquals(1, state.arrayOfInt32.length);

        // state.arrayOfSchemas.onRemove = function (value, key) { trace("onRemove, arrayOfSchemas => " + key); };
        // state.arrayOfNumbers.onRemove = function (value, key) { trace("onRemove, arrayOfNumbers => " + key); };
        // state.arrayOfStrings.onRemove = function (value, key) { trace("onRemove, arrayOfStrings => " + key); };
        // state.arrayOfInt32.onRemove = function (value, key) { trace("onRemove, arrayOfInt32 => " + key); };

        var zeroBytes = [ 128, 7, 129, 8, 131, 9, 130, 10, 255, 7, 255, 8, 255, 9, 255, 10 ];
        decoder.decode(getBytes(zeroBytes));

        assertEquals(0, state.arrayOfSchemas.length);
        assertEquals(0, state.arrayOfNumbers.length);
        assertEquals(0, state.arrayOfStrings.length);
        assertEquals(0, state.arrayOfInt32.length);
    }

    public function testMapSchemaTypes() {
        var state = new MapSchemaTypes();
        var decoder = new Decoder<MapSchemaTypes>(state);

        var callbacks = new SchemaCallbacks<MapSchemaTypes>(decoder);

        var mapOfSchemasAddCount = 0;
        var mapOfNumbersAddCount = 0;
        var mapOfStringsAddCount = 0;
        var mapOfInt32AddCount = 0;

        callbacks.onAdd("mapOfSchemas", (value, key) -> mapOfSchemasAddCount++);
        callbacks.onAdd("mapOfNumbers", (value, key) -> mapOfNumbersAddCount++);
        callbacks.onAdd("mapOfStrings", (value, key) -> mapOfStringsAddCount++);
        callbacks.onAdd("mapOfInt32", (value, key) -> mapOfInt32AddCount++);

        var mapOfSchemasRemoveCount = 0;
        var mapOfNumbersRemoveCount = 0;
        var mapOfStringsRemoveCount = 0;
        var mapOfInt32RemoveCount = 0;

        callbacks.onRemove("mapOfSchemas", (value, key) -> mapOfSchemasRemoveCount++);
        callbacks.onRemove("mapOfNumbers", (value, key) -> mapOfNumbersRemoveCount++);
        callbacks.onRemove("mapOfStrings", (value, key) -> mapOfStringsRemoveCount++);
        callbacks.onRemove("mapOfInt32", (value, key) -> mapOfInt32RemoveCount++);

        var mapOfSchemasChangeCount = 0;
        var mapOfNumbersChangeCount = 0;
        var mapOfStringsChangeCount = 0;
        var mapOfInt32ChangeCount = 0;

        callbacks.onChange("mapOfSchemas", (value, key) -> mapOfSchemasChangeCount++);
        callbacks.onChange("mapOfNumbers", (value, key) -> mapOfNumbersChangeCount++);
        callbacks.onChange("mapOfStrings", (value, key) -> mapOfStringsChangeCount++);
        callbacks.onChange("mapOfInt32", (value, key) -> mapOfInt32ChangeCount++);

        decoder.decode(getBytes([128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 163, 111, 110, 101, 5, 128, 1, 163, 116, 119, 111, 6, 128, 2, 165, 116, 104, 114, 101, 101, 7, 255, 2, 128, 0, 163, 111, 110, 101, 1, 128, 1, 163, 116, 119, 111, 2, 128, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 163, 79, 110, 101, 128, 1, 163, 116, 119, 111, 163, 84, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 255, 4, 128, 0, 163, 111, 110, 101, 192, 13, 0, 0, 128, 1, 163, 116, 119, 111, 24, 252, 255, 255, 128, 2, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0, 255, 5, 128, 100, 129, 204, 200, 255, 6, 128, 205, 44, 1, 129, 205, 144, 1, 255, 7, 128, 205, 244, 1, 129, 205, 88, 2]));

        assertEquals(state.mapOfSchemas.length, 3);
        assertEquals(state.mapOfSchemas.get("one").x, 100);
        assertEquals(state.mapOfSchemas.get("one").y, 200);
        assertEquals(state.mapOfSchemas.get("two").x, 300);
        assertEquals(state.mapOfSchemas.get("two").y, 400);
        assertEquals(state.mapOfSchemas.get("three").x, 500);
        assertEquals(state.mapOfSchemas.get("three").y, 600);

        assertEquals(state.mapOfNumbers.length, 3);
        assertEquals(state.mapOfNumbers.get("one"), 1);
        assertEquals(state.mapOfNumbers.get("two"), 2);
        assertEquals(state.mapOfNumbers.get("three"), 3520);

        assertEquals(state.mapOfStrings.length, 3);
        assertEquals(state.mapOfStrings.get("one"), "One");
        assertEquals(state.mapOfStrings.get("two"), "Two");
        assertEquals(state.mapOfStrings.get("three"), "Three");

        assertEquals(state.mapOfInt32.length, 3);
        assertEquals(state.mapOfInt32.get("one"), 3520);
        assertEquals(state.mapOfInt32.get("two"), -1000);
        assertEquals(state.mapOfInt32.get("three"), 2000);

        assertEquals(mapOfSchemasAddCount, 3);
        assertEquals(mapOfNumbersAddCount, 3);
        assertEquals(mapOfStringsAddCount, 3);
        assertEquals(mapOfInt32AddCount, 3);

        assertEquals(mapOfSchemasChangeCount, 3);
        assertEquals(mapOfNumbersChangeCount, 3);
        assertEquals(mapOfStringsChangeCount, 3);
        assertEquals(mapOfInt32ChangeCount, 3);

        var deleteBytes = [255, 2, 64, 1, 64, 2, 255, 1, 64, 1, 64, 2, 255, 3, 64, 1, 64, 2, 255, 4, 64, 1, 64, 2];
        decoder.decode(getBytes(deleteBytes));

        assertEquals(state.mapOfSchemas.length, 1);
        assertEquals(state.mapOfNumbers.length, 1);
        assertEquals(state.mapOfStrings.length, 1);
        assertEquals(state.mapOfInt32.length, 1);

        assertEquals(mapOfSchemasRemoveCount, 2);
        assertEquals(mapOfNumbersRemoveCount, 2);
        assertEquals(mapOfStringsRemoveCount, 2);
        assertEquals(mapOfInt32RemoveCount, 2);

        assertEquals(mapOfSchemasChangeCount, 5);
        assertEquals(mapOfNumbersChangeCount, 5);
        assertEquals(mapOfStringsChangeCount, 5);
        assertEquals(mapOfInt32ChangeCount, 5);
    }

    public function testMapSchemaInt8() {
        var state = new MapSchemaInt8();
        var decoder = new Decoder(state);
        var bytes = [128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 129, 1, 255, 1, 128, 0, 163, 98, 98, 98, 1, 128, 1, 163, 97, 97, 97, 1, 128, 2, 163, 50, 50, 49, 1, 128, 3, 163, 48, 50, 49, 1, 128, 4, 162, 49, 53, 1, 128, 5, 162, 49, 48, 1 ];

        decoder.decode(getBytes(bytes));

        assertEquals(state.status, "Hello world");
        assertEquals(state.mapOfInt8.get("bbb"), 1);
        assertEquals(state.mapOfInt8.get("aaa"), 1);
        assertEquals(state.mapOfInt8.get("221"), 1);
        assertEquals(state.mapOfInt8.get("021"), 1);
        assertEquals(state.mapOfInt8.get("15"), 1);
        assertEquals(state.mapOfInt8.get("10"), 1);

        var addBytes = [255, 1, 0, 5, 2 ];
        decoder.decode(getBytes(addBytes));

        assertEquals(state.mapOfInt8.get("bbb"), 1);
        assertEquals(state.mapOfInt8.get("aaa"), 1);
        assertEquals(state.mapOfInt8.get("221"), 1);
        assertEquals(state.mapOfInt8.get("021"), 1);
        assertEquals(state.mapOfInt8.get("15"), 1);
        assertEquals(state.mapOfInt8.get("10"), 2);
    }

    //
    ///// TODO: InheritedTypes is not currently supported!
    //
    // public function testInheritedTypes()
    // {
    //     var serializer = new SchemaSerializer<InheritedTypes>(InheritedTypes);
    //     var handshake = [128, 1, 129, 3, 255, 1, 128, 0, 2, 128, 1, 3, 128, 2, 4, 128, 3, 5, 255, 2, 129, 6, 128, 0, 255, 3, 129, 7, 128, 1, 255, 4, 129, 8, 128, 2, 255, 5, 129, 9, 128, 3, 255, 6, 128, 0, 10, 128, 1, 11, 255, 7, 128, 0, 12, 128, 1, 13, 128, 2, 14, 255, 8, 128, 0, 15, 128, 1, 16, 128, 2, 17, 128, 3, 18, 255, 9, 128, 0, 19, 128, 1, 20, 128, 2, 21, 128, 3, 22, 255, 10, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 11, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 12, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 13, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 14, 128, 164, 110, 97, 109, 101, 129, 166, 115, 116, 114, 105, 110, 103, 255, 15, 128, 161, 120, 129, 166, 110, 117, 109, 98, 101, 114, 255, 16, 128, 161, 121, 129, 166, 110, 117, 109, 98, 101, 114, 255, 17, 128, 164, 110, 97, 109, 101, 129, 166, 115, 116, 114, 105, 110, 103, 255, 18, 128, 165, 112, 111, 119, 101, 114, 129, 166, 110, 117, 109, 98, 101, 114, 255, 19, 128, 166, 101, 110, 116, 105, 116, 121, 130, 0, 129, 163, 114, 101, 102, 255, 20, 128, 166, 112, 108, 97, 121, 101, 114, 130, 1, 129, 163, 114, 101, 102, 255, 21, 128, 163, 98, 111, 116, 130, 2, 129, 163, 114, 101, 102, 255, 22, 128, 163, 97, 110, 121, 130, 0, 129, 163, 114, 101, 102];
    //     serializer.handshake(getBytes(handshake), 0);

    //     var bytes = [128, 1, 129, 2, 130, 3, 131, 4, 213, 2, 255, 1, 128, 205, 244, 1, 129, 205, 32, 3, 255, 2, 128, 204, 200, 129, 205, 44, 1, 130, 166, 80, 108, 97, 121, 101, 114, 255, 3, 128, 100, 129, 204, 150, 130, 163, 66, 111, 116, 131, 204, 200, 255, 4, 131, 100];
    //     serializer.setState(getBytes(bytes));

    //     var state = serializer.getState();

    //     assertTrue(Type.getClassName(Type.getClass(state.entity)) == "schema.inheritedtypes.Entity");
    //     assertEquals(state.entity.x, 500);
    //     assertEquals(state.entity.y, 800);

    //     assertTrue(Type.getClassName(Type.getClass(state.player)) == "schema.inheritedtypes.Player");
    //     assertEquals(state.player.x, 200);
    //     assertEquals(state.player.y, 300);
    //     assertEquals(state.player.name, "Player");

    //     assertTrue(Type.getClassName(Type.getClass(state.bot)) == "schema.inheritedtypes.Bot");
    //     assertEquals(state.bot.x, 100);
    //     assertEquals(state.bot.y, 150);
    //     assertEquals(state.bot.name, "Bot");
    //     assertEquals(state.bot.power, 200);

    // }

    public function testBackwardsForwards() {
        var statev1bytes = [129, 1, 128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 255, 1, 128, 0, 163, 111, 110, 101, 2, 255, 2, 128, 203, 232, 229, 22, 37, 231, 231, 209, 63, 129, 203, 240, 138, 15, 5, 219, 40, 223, 63 ];
        var statev2bytes = [128, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 130, 10];

        var statev2 = new StateV2();
        var decoderv2 = new Decoder(statev2);
        decoderv2.decode(getBytes(statev1bytes));
        assertEquals(statev2.str, "Hello world");

        var statev1 = new StateV1();
        var decoderv1 = new Decoder(statev1);
        decoderv1.decode(getBytes(statev2bytes));
        assertEquals(statev1.str, "Hello world");

        //    Assert.DoesNotThrow(() =>
        //    {
        // // uses StateV1 handshake with StateV2 structure.
        // var serializer = new Colyseus.SchemaSerializer<SchemaTest.Forwards.StateV2>();
        // byte[] handshake = { 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 2, 2, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 0, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 174, 97, 114, 114, 97, 121, 79, 102, 83, 116, 114, 105, 110, 103, 115, 1, 172, 97, 114, 114, 97, 121, 58, 115, 116, 114, 105, 110, 103, 2, 255, 193, 193, 3, 0, 3, 1, 3, 3, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 2, 193, 2, 0, 169, 99, 111, 117, 110, 116, 100, 111, 119, 110, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 1 };
        // serializer.Handshake(handshake, 0);
        // }, "reflection should be backwards compatible");

        // Assert.DoesNotThrow(() =>
        // {
        // // uses StateV2 handshake with StateV1 structure.
        // var serializer = new Colyseus.SchemaSerializer<SchemaTest.Backwards.StateV1>();
        // byte[] handshake = { 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 2, 2, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 0, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 174, 97, 114, 114, 97, 121, 79, 102, 83, 116, 114, 105, 110, 103, 115, 1, 172, 97, 114, 114, 97, 121, 58, 115, 116, 114, 105, 110, 103, 2, 255, 193, 193, 3, 0, 3, 1, 3, 3, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 2, 193, 2, 0, 169, 99, 111, 117, 110, 116, 100, 111, 119, 110, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 3 };
        // serializer.Handshake(handshake, 0);
        // }, "reflection should be forwards compatible");
    }

    // public function testFilteredTypes() {
    //     var client1 = new FilteredTypesState();
    //     var decoder1 = new Decoder(client1);
    //     decoder1.decode(getBytes([255, 0, 130, 1, 128, 2, 128, 2, 255, 1, 128, 0, 4, 255, 2, 128, 163, 111, 110, 101, 255, 2, 128, 163, 111, 110, 101, 255, 4, 128, 163, 111, 110, 101]));
    //     assertEquals("one", client1.playerOne.name);
    //     assertEquals("one", client1.players[0].name);
    //     assertEquals("", client1.playerTwo.name);

    //     var client2 = new FilteredTypesState();
    //     var decoder2 = new Decoder(client2);
    //     decoder2.decode(getBytes([255, 0, 130, 1, 129, 3, 129, 3, 255, 1, 128, 1, 5, 255, 3, 128, 163, 116, 119, 111, 255, 3, 128, 163, 116, 119, 111, 255, 5, 128, 163, 116, 119, 111]));
    //     assertEquals("two", client2.playerTwo.name);
    //     assertEquals("two", client2.players[0].name);
    //     assertEquals("", client2.playerOne.name);
    // }

    public function testInstanceSharingTypes() {
        var client = new InstanceSharingTypes();
        var decoder = new Decoder(client);
        var refs = decoder.refs;
        decoder.decode(getBytes([130, 1, 131, 2, 128, 3, 129, 3, 255, 3, 128, 4, 255, 4, 128, 10, 129, 10]));
        assertEquals(client.player1, client.player2);
        assertEquals(client.player1.position, client.player2.position);
        assertEquals(2, refs.refCounts[client.player1.__refId]);
        assertEquals(5, refs.count());

        decoder.decode(getBytes([64, 65, 255, 0, 64, 65]));
        assertEquals(null, client.player1);
        assertEquals(null, client.player2);
        assertEquals(3, refs.count());

        decoder.decode(getBytes([255, 1, 128, 0, 5, 128, 1, 5, 128, 2, 5, 128, 3, 7, 255, 5, 128, 6, 255, 6, 128, 10, 129, 10, 255, 7, 128, 8, 255, 8, 128, 10, 129, 10]));
        assertEquals(client.arrayOfPlayers[0], client.arrayOfPlayers[1]);
        assertEquals(client.arrayOfPlayers[1], client.arrayOfPlayers[2]);
        assertFalse(client.arrayOfPlayers[2] == client.arrayOfPlayers[3]);
        assertEquals(7, refs.count());

        decoder.decode(getBytes([255, 1, 64, 3, 64, 2, 64, 1]));
        assertEquals(1, client.arrayOfPlayers.length);
        assertEquals(5, refs.count());
        var previousArraySchemaRefId = client.arrayOfPlayers.__refId;

        // Replacing ArraySchema
        decoder.decode(getBytes([194, 9, 255, 9, 128, 0, 10, 255, 10, 128, 11, 255, 11, 128, 10, 129, 20]));
        assertFalse(refs.has(previousArraySchemaRefId));
        assertEquals(1, client.arrayOfPlayers.length);
        assertEquals(5, refs.count());

        // Clearing ArraySchema
        decoder.decode(getBytes([255, 9, 10]));
        assertEquals(0, client.arrayOfPlayers.length);
        assertEquals(3, refs.count());
    }

    public function testCallbacks() {
        var state = new CallbacksState();
        var decoder = new Decoder<CallbacksState>(state);
        var callbacks = new SchemaCallbacks<CallbacksState>(decoder);

        var onListenContainer = 0;
        var onPlayerAdd = 0;
        var onPlayerRemove = 0;
        var onPlayerChange = 0;
        var onItemAdd = 0;
        var onItemRemove = 0;
        var onItemChange = 0;

        callbacks.listen("container", (container, previousValue) -> {
            onListenContainer++;

            callbacks.onAdd(container, "playersMap", (player, key) -> {
                onPlayerAdd++;

                callbacks.onAdd(player, "items", (item, key) -> {
                    onItemAdd++;
                });

                callbacks.onChange(player, "items", (item, key) -> {
                    onItemChange++;
                });

                callbacks.onRemove(player, "items", (item, key) -> {
                    onItemRemove++;
                });
            });

            callbacks.onChange(container, "playersMap", (item, key) -> {
                onPlayerChange++;
            });

            callbacks.onRemove(container, "playersMap", (item, key) -> {
                onPlayerRemove++;
            });
        });

        // (initial)
        decoder.decode(getBytes([ 128, 1, 255, 1, 128, 2, 255, 2 ]));

		// (1st encode)
		decoder.decode(getBytes([ 255, 1, 255, 2, 128, 0, 163, 111, 110, 101, 3, 128, 1, 163, 116, 119, 111, 9, 255, 2, 255, 3, 128, 4, 129, 5, 255, 4, 128, 1, 129, 2, 130, 3, 255, 5, 128, 0, 166, 105, 116, 101, 109, 45, 49, 6, 128, 1, 166, 105, 116, 101, 109, 45, 50, 7, 128, 2, 166, 105, 116, 101, 109, 45, 51, 8, 255, 6, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 7, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 8, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3, 255, 9, 128, 10, 129, 11, 255, 10, 128, 1, 129, 2, 130, 3, 255, 11, 128, 0, 166, 105, 116, 101, 109, 45, 49, 12, 128, 1, 166, 105, 116, 101, 109, 45, 50, 13, 128, 2, 166, 105, 116, 101, 109, 45, 51, 14, 255, 12, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 13, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 14, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3 ]));

		assertEquals(1, onListenContainer);
		assertEquals(2, onPlayerAdd);
		assertEquals(2, onPlayerChange);
		assertEquals(6, onItemAdd);
		assertEquals(6, onItemChange);

		// (2nd encode)
		decoder.decode(getBytes([ 255, 1, 255, 2, 64, 1, 128, 2, 165, 116, 104, 114, 101, 101, 16, 255, 2, 255, 3, 255, 4, 255, 5, 64, 0, 64, 1, 128, 3, 166, 105, 116, 101, 109, 45, 52, 15, 255, 8, 255, 5, 255, 5, 255, 15, 128, 166, 73, 116, 101, 109, 32, 52, 129, 4, 255, 2, 255, 16, 128, 17, 129, 18, 255, 17, 128, 1, 129, 2, 130, 3, 255, 18, 128, 0, 166, 105, 116, 101, 109, 45, 49, 19, 128, 1, 166, 105, 116, 101, 109, 45, 50, 20, 128, 2, 166, 105, 116, 101, 109, 45, 51, 21, 255, 19, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 20, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 21, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3 ]));

		// (new container)
		decoder.decode(getBytes([ 128, 22, 255, 2, 255, 5, 255, 5, 255, 2, 255, 0, 255, 22, 128, 23, 255, 23, 128, 0, 164, 108, 97, 115, 116, 24, 255, 24, 128, 25, 129, 26, 255, 25, 128, 10, 129, 10, 130, 10, 255, 26, 128, 0, 163, 111, 110, 101, 27, 255, 27, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1 ]));

        assertEquals(4, onPlayerAdd);
        assertEquals(1, onPlayerRemove);
		assertEquals(5, onPlayerChange);
        assertEquals(11, onItemAdd);
        assertEquals(2, onItemRemove);
        assertEquals(13, onItemChange);
    }

    public function testOnChangeVoidCallbackOnPrimitiveCollections() {
        // Test that onChange(collection, () -> ...) fires for primitive collections.
        // Regression test for: onChange with Void->Void was silently dropped on
        // collections because triggerChanges only fired callbacks0 for Schema refs.

        // --- ArraySchema of primitives ---
        var arrayState = new ArraySchemaTypes();
        var arrayDecoder = new Decoder(arrayState);
        var arrayCallbacks = new SchemaCallbacks<ArraySchemaTypes>(arrayDecoder);

        // Decode initial state to populate collections
        var arrayInitBytes = [ 128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 5, 128, 1, 6, 255, 2, 128, 0, 0, 128, 1, 10, 128, 2, 20, 128, 3, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 128, 1, 163, 116, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 255, 4, 128, 0, 232, 3, 0, 0, 128, 1, 192, 13, 0, 0, 128, 2, 72, 244, 255, 255, 255, 5, 128, 100, 129, 208, 156, 255, 6, 128, 100, 129, 208, 156 ];
        arrayDecoder.decode(getBytes(arrayInitBytes));

        // Register Void->Void onChange on primitive array collections
        var arrayNumbersChanged = 0;
        var arrayStringsChanged = 0;
        var arrayInt32Changed = 0;

        arrayCallbacks.onChange(arrayState.arrayOfNumbers, () -> arrayNumbersChanged++);
        arrayCallbacks.onChange(arrayState.arrayOfStrings, () -> arrayStringsChanged++);
        arrayCallbacks.onChange(arrayState.arrayOfInt32, () -> arrayInt32Changed++);

        // Decode a mutation that removes items from collections
        var arrayPopBytes = [ 255, 1, 64, 1, 255, 2, 64, 3, 64, 2, 64, 1, 255, 4, 64, 2, 64, 1, 255, 3, 64, 2, 64, 1 ];
        arrayDecoder.decode(getBytes(arrayPopBytes));

        assertEquals(1, arrayNumbersChanged);
        assertEquals(1, arrayStringsChanged);
        assertEquals(1, arrayInt32Changed);

        // --- MapSchema of primitives ---
        var mapState = new MapSchemaTypes();
        var mapDecoder = new Decoder<MapSchemaTypes>(mapState);
        var mapCallbacks = new SchemaCallbacks<MapSchemaTypes>(mapDecoder);

        // Decode initial state to populate map collections
        var mapInitBytes = [128, 1, 129, 2, 130, 3, 131, 4, 255, 1, 128, 0, 163, 111, 110, 101, 5, 128, 1, 163, 116, 119, 111, 6, 128, 2, 165, 116, 104, 114, 101, 101, 7, 255, 2, 128, 0, 163, 111, 110, 101, 1, 128, 1, 163, 116, 119, 111, 2, 128, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 255, 3, 128, 0, 163, 111, 110, 101, 163, 79, 110, 101, 128, 1, 163, 116, 119, 111, 163, 84, 119, 111, 128, 2, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 255, 4, 128, 0, 163, 111, 110, 101, 192, 13, 0, 0, 128, 1, 163, 116, 119, 111, 24, 252, 255, 255, 128, 2, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0, 255, 5, 128, 100, 129, 204, 200, 255, 6, 128, 205, 44, 1, 129, 205, 144, 1, 255, 7, 128, 205, 244, 1, 129, 205, 88, 2];
        mapDecoder.decode(getBytes(mapInitBytes));

        // Register Void->Void onChange on primitive map collections
        var mapNumbersChanged = 0;
        var mapStringsChanged = 0;
        var mapInt32Changed = 0;

        mapCallbacks.onChange(mapState.mapOfNumbers, () -> mapNumbersChanged++);
        mapCallbacks.onChange(mapState.mapOfStrings, () -> mapStringsChanged++);
        mapCallbacks.onChange(mapState.mapOfInt32, () -> mapInt32Changed++);

        // Decode a mutation that deletes items from maps
        var mapDeleteBytes = [255, 2, 64, 1, 64, 2, 255, 1, 64, 1, 64, 2, 255, 3, 64, 1, 64, 2, 255, 4, 64, 1, 64, 2];
        mapDecoder.decode(getBytes(mapDeleteBytes));

        assertEquals(1, mapNumbersChanged);
        assertEquals(1, mapStringsChanged);
        assertEquals(1, mapInt32Changed);
    }

    public function testIsTriggeringPreventsDoubleCallbacks() {
        // Regression test for the isTriggering guard in triggerCallbacks2.
        //
        // When an onAdd handler registers a nested onAdd on a child collection,
        // addCallbackOrWaitCollectionAvailable checks `immediate && !isTriggering`.
        // Since triggerCallbacks2 sets isTriggering=true before invoking callbacks,
        // the nested registration skips the "immediate" path and only the normal
        // triggerChanges dispatch fires — preventing double callbacks.
        //
        // Without isTriggering: each item callback would fire TWICE per item
        // (once from immediate, once from triggerChanges) → 12 instead of 6.

        var state = new CallbacksState();
        var decoder = new Decoder<CallbacksState>(state);
        var callbacks = new SchemaCallbacks<CallbacksState>(decoder);

        // Decode initial state: container with empty playersMap
        decoder.decode(getBytes([ 128, 1, 255, 1, 128, 2, 255, 2 ]));

        var onItemAdd = 0;
        var onPlayerAdd = 0;

        // Register onAdd directly on the container's playersMap.
        // When a player is added, the nested onAdd on player.items runs while
        // isTriggering=true (set by triggerCallbacks2), so the immediate path
        // in addCallbackOrWaitCollectionAvailable is correctly skipped.
        callbacks.onAdd(state.container, "playersMap", (player, key) -> {
            onPlayerAdd++;

            callbacks.onAdd(player, "items", (item, k) -> {
                onItemAdd++;
            });
        });

        // Decode: adds 2 players, each with 3 items, in a single patch.
        decoder.decode(getBytes([ 255, 1, 255, 2, 128, 0, 163, 111, 110, 101, 3, 128, 1, 163, 116, 119, 111, 9, 255, 2, 255, 3, 128, 4, 129, 5, 255, 4, 128, 1, 129, 2, 130, 3, 255, 5, 128, 0, 166, 105, 116, 101, 109, 45, 49, 6, 128, 1, 166, 105, 116, 101, 109, 45, 50, 7, 128, 2, 166, 105, 116, 101, 109, 45, 51, 8, 255, 6, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 7, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 8, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3, 255, 9, 128, 10, 129, 11, 255, 10, 128, 1, 129, 2, 130, 3, 255, 11, 128, 0, 166, 105, 116, 101, 109, 45, 49, 12, 128, 1, 166, 105, 116, 101, 109, 45, 50, 13, 128, 2, 166, 105, 116, 101, 109, 45, 51, 14, 255, 12, 128, 166, 73, 116, 101, 109, 32, 49, 129, 1, 255, 13, 128, 166, 73, 116, 101, 109, 32, 50, 129, 2, 255, 14, 128, 166, 73, 116, 101, 109, 32, 51, 129, 3 ]));

        assertEquals(2, onPlayerAdd);
        // 2 players x 3 items = 6 (no double-fire)
        assertEquals(6, onItemAdd);
    }

    //
    // Fixtures below generated by schema-5.0
    // test-external/generate-arrayschema-fixtures.ts (self-verified against
    // the 5.0 JS Decoder). See TODO/sdk-decoders-arrayschema-insert.md.
    //

    public function testArraySchemaUnshift() {
        // ADD at an occupied index = insert (not only index 0)
        var snapshot = [128, 1, 129, 2, 130, 3, 255, 1, 128, 0, 1, 128, 1, 2, 128, 2, 3];

        // consecutive unshift: [1,2,3] -> unshift(0); unshift(-1)
        var state = new ArraySchemaInsertOps();
        var decoder = new Decoder(state);
        decoder.decode(getBytes(snapshot));
        decoder.decode(getBytes([255, 1, 128, 0, 255, 128, 1, 0]));
        assertEquals(5, state.numbers.length);
        assertEquals(-1., state.numbers.items[0]);
        assertEquals(0., state.numbers.items[1]);
        assertEquals(1., state.numbers.items[2]);
        assertEquals(2., state.numbers.items[3]);
        assertEquals(3., state.numbers.items[4]);

        // multi-item unshift: [1,2,3] -> unshift(-1, -2)
        state = new ArraySchemaInsertOps();
        decoder = new Decoder(state);
        decoder.decode(getBytes(snapshot));
        decoder.decode(getBytes([255, 1, 128, 0, 255, 128, 1, 254]));
        assertEquals(5, state.numbers.length);
        assertEquals(-1., state.numbers.items[0]);
        assertEquals(-2., state.numbers.items[1]);
        assertEquals(1., state.numbers.items[2]);

        // pending same-tick ops: arr[2]=99; push(4); unshift(0)
        state = new ArraySchemaInsertOps();
        decoder = new Decoder(state);
        decoder.decode(getBytes(snapshot));
        decoder.decode(getBytes([255, 1, 128, 0, 0, 0, 3, 99, 128, 4, 4]));
        assertEquals(5, state.numbers.length);
        assertEquals(0., state.numbers.items[0]);
        assertEquals(1., state.numbers.items[1]);
        assertEquals(2., state.numbers.items[2]);
        assertEquals(99., state.numbers.items[3]);
        assertEquals(4., state.numbers.items[4]);

        // clear + unshift in the same tick: clear(); unshift(9); unshift(8)
        state = new ArraySchemaInsertOps();
        decoder = new Decoder(state);
        decoder.decode(getBytes(snapshot));
        decoder.decode(getBytes([255, 1, 10, 128, 0, 8, 128, 1, 9]));
        assertEquals(2, state.numbers.length);
        assertEquals(8., state.numbers.items[0]);
        assertEquals(9., state.numbers.items[1]);
    }

    public function testArraySchemaUnshiftSchemaInstances() {
        // [Item(1), Item(2)] -> unshift(Item(0)); unshift(Item(-1))
        var state = new ArraySchemaInsertOps();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 130, 3, 255, 2, 128, 0, 4, 128, 1, 5, 255, 4, 128, 1, 255, 5, 128, 2]));
        decoder.decode(getBytes([255, 2, 128, 0, 7, 128, 1, 6, 255, 6, 128, 0, 255, 7, 128, 255]));

        assertEquals(4, state.items.length);
        assertEquals(-1., state.items.items[0].value);
        assertEquals(0., state.items.items[1].value);
        assertEquals(1., state.items.items[2].value);
        assertEquals(2., state.items.items[3].value);

        // no refId leaks
        assertEquals(8, decoder.refs.count());
    }

    public function testArraySchemaSortNoInsert() {
        // sort() emits REPLACE at occupied indexes (incl. 0) — must NOT insert
        var state = new ArraySchemaInsertOps();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 130, 3, 255, 3, 128, 0, 4, 128, 1, 5, 128, 2, 6, 128, 3, 7, 128, 4, 8, 255, 4, 128, 163, 79, 110, 101, 129, 10, 130, 0, 255, 5, 128, 163, 84, 119, 111, 129, 30, 130, 1, 255, 6, 128, 165, 84, 104, 114, 101, 101, 129, 20, 130, 2, 255, 7, 128, 164, 70, 111, 117, 114, 129, 50, 130, 3, 255, 8, 128, 164, 70, 105, 118, 101, 129, 40, 130, 4]));
        assertEquals(5, state.players.length);
        assertEquals("One", state.players.items[0].name);
        assertEquals("Five", state.players.items[4].name);

        // sort by y desc
        decoder.decode(getBytes([255, 3, 0, 0, 8, 0, 1, 7, 0, 2, 6, 0, 3, 5, 0, 4, 4]));
        assertEquals(5, state.players.length);
        assertEquals("Five", state.players.items[0].name);
        assertEquals("Four", state.players.items[1].name);
        assertEquals("Three", state.players.items[2].name);
        assertEquals("Two", state.players.items[3].name);
        assertEquals("One", state.players.items[4].name);

        // sort by x
        decoder.decode(getBytes([255, 3, 0, 0, 4, 0, 1, 6, 0, 2, 5, 0, 3, 8, 0, 4, 7]));
        assertEquals(5, state.players.length);
        assertEquals("One", state.players.items[0].name);
        assertEquals("Three", state.players.items[1].name);
        assertEquals("Two", state.players.items[2].name);
        assertEquals("Five", state.players.items[3].name);
        assertEquals("Four", state.players.items[4].name);
    }

    public function testArraySchemaStaleDeleteByRefId() {
        // mid-tick join: the same shared patch is decoded by an old client
        // (knows all refIds) and a fresh client (bootstrapped mid-tick, only
        // knows the survivors). Stale DELETE_BY_REFIDs must be skipped
        // silently: no write, no onRemove.
        var sharedPatch = [255, 2, 33, 4, 33, 5, 33, 6];

        var oldState = new ArraySchemaInsertOps();
        var oldDecoder = new Decoder(oldState);
        oldDecoder.decode(getBytes([128, 1, 129, 2, 130, 3, 255, 2, 128, 0, 4, 128, 1, 5, 128, 2, 6, 128, 3, 7, 128, 4, 8, 255, 4, 128, 0, 255, 5, 128, 1, 255, 6, 128, 2, 255, 7, 128, 3, 255, 8, 128, 4]));

        var freshState = new ArraySchemaInsertOps();
        var freshDecoder = new Decoder(freshState);
        freshDecoder.decode(getBytes([128, 1, 129, 2, 130, 3, 255, 2, 128, 0, 6, 128, 1, 7, 128, 2, 8, 255, 6, 128, 2, 255, 7, 128, 3, 255, 8, 128, 4]));

        var oldRemoveCount = 0;
        var freshRemoveCount = 0;
        var oldCallbacks = new SchemaCallbacks<ArraySchemaInsertOps>(oldDecoder);
        var freshCallbacks = new SchemaCallbacks<ArraySchemaInsertOps>(freshDecoder);
        oldCallbacks.onRemove("items", (value, key) -> oldRemoveCount++);
        freshCallbacks.onRemove("items", (value, key) -> freshRemoveCount++);

        oldDecoder.decode(getBytes(sharedPatch));
        freshDecoder.decode(getBytes(sharedPatch));

        // both converge to the server state: [3, 4]
        assertEquals(2, oldState.items.length);
        assertEquals(3., oldState.items.items[0].value);
        assertEquals(4., oldState.items.items[1].value);
        assertEquals(2, freshState.items.length);
        assertEquals(3., freshState.items.items[0].value);
        assertEquals(4., freshState.items.items[1].value);

        // old client applied 3 deletes; fresh client skipped the 2 stale ones
        assertEquals(3, oldRemoveCount);
        assertEquals(1, freshRemoveCount);

        // ref counts converge too (stale refIds were never tracked by fresh)
        assertEquals(6, oldDecoder.refs.count());
        assertEquals(6, freshDecoder.refs.count());
    }

    public function testArraySchemaMove() {
        // MOVE (32): existing instances swapped via move(); positional write,
        // must NOT insert. MOVE_AND_ADD (160): new instance at occupied slot.
        var state = new ArraySchemaInsertOps();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 130, 3, 255, 2, 128, 0, 4, 128, 1, 5, 128, 2, 6, 255, 4, 128, 1, 255, 5, 128, 2, 255, 6, 128, 3]));

        // move(): swap arr[0] <-> arr[1] — carries MOVE (32) ops
        decoder.decode(getBytes([255, 2, 32, 0, 5, 32, 1, 4, 255, 4, 128, 1]));
        assertEquals(3, state.items.length);
        assertEquals(2., state.items.items[0].value);
        assertEquals(1., state.items.items[1].value);
        assertEquals(3., state.items.items[2].value);

        // move(): new Item(9) written at occupied slot 2 — MOVE_AND_ADD (160)
        decoder.decode(getBytes([255, 2, 160, 2, 7, 255, 7, 128, 9]));
        assertEquals(3, state.items.length);
        assertEquals(2., state.items.items[0].value);
        assertEquals(1., state.items.items[1].value);
        assertEquals(9., state.items.items[2].value);
    }

    //
    // decodeResync fixtures below generated by schema-5.0
    // test-external/generate-resync-fixtures.ts (self-verified against the
    // 5.0 JS Decoder). Contract: PORTING_RESYNC.md / test/ResyncSweep.test.ts.
    //

    public function testResyncGhostMap() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 128, 1, 162, 101, 50, 5, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4, 255, 5, 128, 163, 116, 119, 111, 129, 100, 130, 6]));

        var removedItems:Array<Dynamic> = [];
        var removedKeys:Array<String> = [];
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onRemove("units", (u, k) -> { removedItems.push(u); removedKeys.push(k); });

        var ghost = state.units.get("e2");

        // offline: e2 died; its DELETE patch was never delivered
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4]));

        assertEquals(1, state.units.length);
        assertTrue(state.units.get("e1") != null);
        assertEquals(1, removedItems.length);
        assertTrue(removedItems[0] == ghost); // the REAL previous instance
        assertEquals("e2", removedKeys[0]);
        assertEquals(5, decoder.refs.count());
    }

    public function testResyncPrunePrimitiveMap() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 2, 128, 0, 162, 116, 49, 10, 128, 1, 162, 116, 50, 20, 128, 2, 162, 116, 51, 30]));

        var removed:Array<Dynamic> = [];
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onRemove("trees", (v, k) -> removed.push([v, k]));

        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 2, 128, 0, 162, 116, 49, 10, 128, 2, 162, 116, 51, 30]));

        assertEquals(2, state.trees.length);
        assertEquals(10., state.trees.get("t1"));
        assertTrue(state.trees.get("t2") == null);
        assertEquals(30., state.trees.get("t3"));
        assertEquals(1, removed.length);
        assertEquals(20., removed[0][0]);
        assertEquals("t2", removed[0][1]);
    }

    public function testResyncNestedCollection() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 164, 104, 101, 114, 111, 3, 255, 3, 128, 164, 104, 101, 114, 111, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 6, 128, 2, 7, 255, 5, 128, 0, 255, 6, 128, 1, 255, 7, 128, 2]));

        var heroBefore = state.units.get("hero");

        // offline: hero lost the middle gem
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 164, 104, 101, 114, 111, 3, 255, 3, 128, 164, 104, 101, 114, 111, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 7, 255, 5, 128, 0, 255, 7, 128, 2]));

        assertTrue(state.units.get("hero") == heroBefore); // retained parent keeps identity
        assertEquals(2, state.units.get("hero").gems.length);
        assertEquals(0., state.units.get("hero").gems.items[0].price);
        assertEquals(2., state.units.get("hero").gems.items[1].price);
    }

    public function testResyncViewInterior() {
        // snapshots are view-encoded (ADD_BY_REFID ops)
        var state = new ResyncArrayState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([255, 0, 128, 1, 255, 1, 129, 2, 2, 129, 4, 4, 129, 6, 6, 255, 2, 128, 161, 97, 129, 100, 130, 3, 255, 4, 128, 161, 98, 129, 100, 130, 5, 255, 6, 128, 161, 99, 129, 100, 130, 7]));
        assertEquals(3, state.arr.length);

        // offline: b left the view — an interior index, not the tail
        decoder.decodeResync(getBytes([255, 0, 128, 1, 255, 1, 129, 2, 2, 129, 6, 6, 255, 2, 128, 161, 97, 129, 100, 130, 3, 255, 6, 128, 161, 99, 129, 100, 130, 7]));

        assertEquals(2, state.arr.length);
        assertEquals("a", state.arr.items[0].name);
        assertEquals("c", state.arr.items[1].name);
    }

    public function testResyncEmptiedCollection() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 128, 1, 162, 101, 50, 5, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4, 255, 5, 128, 163, 116, 119, 111, 129, 100, 130, 6]));

        var removals = 0;
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onRemove("units", (_, _) -> removals++);

        decoder.decodeResync(getBytes([128, 1, 129, 2]));

        assertEquals(0, state.units.length);
        assertEquals(2, removals);
    }

    public function testResyncNoDoubleDecrement() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 164, 114, 105, 99, 104, 3, 128, 1, 164, 107, 101, 101, 112, 10, 255, 3, 128, 164, 114, 105, 99, 104, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 6, 128, 2, 7, 128, 3, 8, 128, 4, 9, 255, 5, 128, 0, 255, 6, 128, 1, 255, 7, 128, 2, 255, 8, 128, 3, 255, 9, 128, 4, 255, 10, 128, 164, 107, 101, 101, 112, 129, 100, 130, 11, 255, 11, 128, 0, 12, 128, 1, 13, 255, 12, 128, 0, 255, 13, 128, 1]));

        // offline: 'rich' (5 nested gems) died — GC must release the subtree exactly once
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 1, 164, 107, 101, 101, 112, 10, 255, 10, 128, 164, 107, 101, 101, 112, 129, 100, 130, 11, 255, 11, 128, 0, 12, 128, 1, 13, 255, 12, 128, 0, 255, 13, 128, 1]));

        assertEquals(1, state.units.length);
        assertEquals(2, state.units.get("keep").gems.length);
        assertEquals(7, decoder.refs.count());
    }

    public function testResyncLateDelete() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 128, 1, 162, 101, 50, 5, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4, 255, 5, 128, 163, 116, 119, 111, 129, 100, 130, 6]));

        var removals = 0;
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onRemove("units", (_, _) -> removals++);

        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4]));
        assertEquals(1, removals);

        // the DELETE patch encoded before the resync arrives late — no re-fire
        decoder.decode(getBytes([255, 1, 64, 1]));

        assertEquals(1, removals);
        assertEquals(1, state.units.length);
    }

    public function testResyncSurvivorIdentity() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 128, 1, 164, 103, 111, 110, 101, 5, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4, 255, 5, 128, 164, 103, 111, 110, 101, 129, 100, 130, 6]));

        var survivor = state.units.get("e1");

        var adds = 0;
        var hpValues:Array<Float> = [];
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onAdd("units", (_, _) -> adds++, false);
        callbacks.listen(survivor, "hp", (hp, _) -> hpValues.push(hp), false);

        // offline: survivor's hp changed to 55, sibling died
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 255, 3, 128, 163, 111, 110, 101, 129, 55, 130, 4]));

        assertTrue(state.units.get("e1") == survivor); // same instance across resync
        assertEquals(0, adds); // onAdd must not re-fire for survivors
        assertEquals(1, hpValues.length);
        assertEquals(55., hpValues[0]);

        // callbacks stay wired for live patches after the resync
        decoder.decode(getBytes([255, 3, 129, 77]));
        assertEquals(2, hpValues.length);
        assertEquals(77., hpValues[1]);
    }

    public function testResyncRekey() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 163, 111, 108, 100, 3, 255, 3, 128, 165, 109, 111, 118, 101, 114, 129, 100, 130, 4]));

        var instance = state.units.get("old");

        var adds:Array<String> = [];
        var removes:Array<String> = [];
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onAdd("units", (_, k) -> adds.push(k), false);
        callbacks.onRemove("units", (_, k) -> removes.push(k));

        // offline: the same server instance moved to a new key
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 1, 163, 110, 101, 119, 3, 255, 3, 128, 165, 109, 111, 118, 101, 114, 129, 100, 130, 4]));

        assertTrue(state.units.get("new") == instance); // same instance under the new key
        assertTrue(state.units.get("old") == null);
        assertEquals(1, adds.length);
        assertEquals("new", adds[0]);
        assertEquals(1, removes.length);
        assertEquals("old", removes[0]);
        assertEquals(5, decoder.refs.count());
    }

    public function testResyncReplaceSameKey() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 161, 107, 3, 255, 3, 128, 165, 102, 105, 114, 115, 116, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 6, 255, 5, 128, 0, 255, 6, 128, 1]));

        var oldInstance = state.units.get("k");
        var oldRefId = (oldInstance : Unit).__refId;

        var adds = 0;
        var removes:Array<Dynamic> = [];
        var callbacks = new SchemaCallbacks<ResyncState>(decoder);
        callbacks.onAdd("units", (_, _) -> adds++, false);
        callbacks.onRemove("units", (u, _) -> removes.push(u));

        // offline: the entity at "k" died and a NEW one spawned at the same key
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 1, 161, 107, 7, 255, 7, 128, 166, 115, 101, 99, 111, 110, 100, 129, 100, 130, 8]));

        assertEquals("second", state.units.get("k").name);
        assertTrue(state.units.get("k") != oldInstance); // fresh instance
        assertEquals(1, removes.length);
        assertTrue(removes[0] == oldInstance);
        assertEquals(1, adds);
        assertFalse(decoder.refs.has(oldRefId)); // old ref GC'd
        assertEquals(5, decoder.refs.count());
    }

    public function testResyncDamaged() {
        // version skew: the resync payload comes from a server whose Player
        // has an extra field → schema-mismatch skip → damage flag → sweep
        // ABORTED (keeping a ghost beats deleting live entries on bad data)
        var state = new ResyncStateV1();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 255, 1, 128, 0, 162, 112, 49, 2, 128, 1, 162, 112, 50, 3, 255, 2, 128, 1, 255, 3, 128, 2]));
        assertEquals(2, state.players.length);

        decoder.decodeResync(getBytes([128, 1, 255, 1, 128, 0, 162, 112, 49, 2, 255, 2, 128, 1, 129, 162, 104, 105]));

        assertEquals(2, state.players.length); // ghost p2 retained, no crash
    }

    public function testResyncTransient() {
        var state = new ResyncTransientState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 255, 1, 128, 0, 162, 101, 49, 3, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4]));
        // transient entries arrive via patch only — never via full snapshots
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 255, 2, 128, 0, 162, 108, 49, 1, 128, 1, 162, 108, 50, 2, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4]));
        assertEquals(2, state.locals.length);

        // the resync snapshot never mentions locals → presence rule leaves it alone
        decoder.decodeResync(getBytes([128, 1, 255, 1, 128, 0, 162, 101, 49, 3, 128, 1, 162, 101, 50, 5, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4, 255, 5, 128, 163, 116, 119, 111, 129, 100, 130, 6]));

        assertEquals(2, state.locals.length); // transient data survives the sweep
        assertEquals(2, state.units.length);
    }

    public function testResyncPlainAdditive() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 162, 101, 49, 3, 255, 3, 128, 163, 111, 110, 101, 129, 100, 130, 4]));
        decoder.decode(getBytes([255, 1, 128, 1, 162, 101, 50, 5, 255, 5, 128, 163, 116, 119, 111, 129, 100, 130, 6]));
        // (a DELETE patch for e1 was dropped — never delivered)
        decoder.decode(getBytes([255, 5, 129, 42]));

        assertEquals(2, state.units.length); // plain decode stays additive

        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 1, 162, 101, 50, 5, 255, 5, 128, 163, 116, 119, 111, 129, 42, 130, 6]));

        assertEquals(1, state.units.length); // resync reconciles
        assertEquals(42., state.units.get("e2").hp);
    }

    public function testResyncTailTrim() {
        var state = new ResyncState();
        var decoder = new Decoder(state);
        decoder.decode(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 164, 104, 101, 114, 111, 3, 255, 3, 128, 164, 104, 101, 114, 111, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 6, 128, 2, 7, 128, 3, 8, 255, 5, 128, 0, 255, 6, 128, 1, 255, 7, 128, 2, 255, 8, 128, 3]));

        // offline: hero lost the last two gems
        decoder.decodeResync(getBytes([128, 1, 129, 2, 255, 1, 128, 0, 164, 104, 101, 114, 111, 3, 255, 3, 128, 164, 104, 101, 114, 111, 129, 100, 130, 4, 255, 4, 128, 0, 5, 128, 1, 6, 255, 5, 128, 0, 255, 6, 128, 1]));

        assertEquals(2, state.units.get("hero").gems.length);
        assertEquals(0., state.units.get("hero").gems.items[0].price);
        assertEquals(1., state.units.get("hero").gems.items[1].price);
        assertEquals(7, decoder.refs.count());
    }

    // rows: desc, input, q, roundtrip — behavior lock from the JS reference codec;
    // generated by schema-5.0 test-external/generate-quantized-fixtures.ts
    static var QUANTIZE_CODEC_VECTORS = "clamp8_0_10, 0, 0, 0
clamp8_0_10, 1, 26, 1.0196078431372548
clamp8_0_10, 10, 255, 10
clamp8_0_10, 0.0196078431372549, 1, 0.0392156862745098
clamp8_0_10, 5.5, 140, 5.490196078431373
clamp8_0_10, -1.5, 0, 0
clamp8_0_10, 1.5, 38, 1.4901960784313726
clamp8_0_10, 0.3, 8, 0.3137254901960784
clamp8_0_10, -99, 0, 0
clamp8_0_10, 99, 255, 10
clamp8_0_10, 3.141592653589793, 80, 3.1372549019607843
clamp8_0_10, 6.283185307179586, 160, 6.2745098039215685
clamp8_0_10, 7.283185307179586, 186, 7.294117647058823
clamp8_0_10, -1, 0, 0
clamp8_0_10, 360, 255, 10
clamp8_0_10, 720.5, 255, 10
clamp8_0_10, 1000000, 255, 10
clamp8_0_10, -1000000, 0, 0
clamp8_0_10, 0.123456789, 3, 0.11764705882352941
clamp8_0_10, NaN, 0, 0
clamp8_0_10, Infinity, 255, 10
clamp8_0_10, -Infinity, 0, 0
clamp16_pitch, 0, 32768, 0.00002288853284504455
clamp16_pitch, 1, 54613, 1.000022888532845
clamp16_pitch, 10, 65535, 1.5
clamp16_pitch, 0.0196078431372549, 33196, 0.01961547264820318
clamp16_pitch, 5.5, 65535, 1.5
clamp16_pitch, -1.5, 0, -1.5
clamp16_pitch, 1.5, 65535, 1.5
clamp16_pitch, 0.3, 39321, 0.2999999999999998
clamp16_pitch, -99, 0, -1.5
clamp16_pitch, 99, 65535, 1.5
clamp16_pitch, 3.141592653589793, 65535, 1.5
clamp16_pitch, 6.283185307179586, 65535, 1.5
clamp16_pitch, 7.283185307179586, 65535, 1.5
clamp16_pitch, -1, 10923, -0.999977111467155
clamp16_pitch, 360, 65535, 1.5
clamp16_pitch, 720.5, 65535, 1.5
clamp16_pitch, 1000000, 65535, 1.5
clamp16_pitch, -1000000, 0, -1.5
clamp16_pitch, 0.123456789, 35464, 0.12343785763332571
clamp16_pitch, NaN, 0, -1.5
clamp16_pitch, Infinity, 65535, 1.5
clamp16_pitch, -Infinity, 0, -1.5
clamp32_unit, 0, 0, 0
clamp32_unit, 1, 4294967295, 1
clamp32_unit, 10, 4294967295, 1
clamp32_unit, 0.0196078431372549, 84215045, 0.0196078431372549
clamp32_unit, 5.5, 4294967295, 1
clamp32_unit, -1.5, 0, 0
clamp32_unit, 1.5, 4294967295, 1
clamp32_unit, 0.3, 1288490189, 0.3000000001164153
clamp32_unit, -99, 0, 0
clamp32_unit, 99, 4294967295, 1
clamp32_unit, 3.141592653589793, 4294967295, 1
clamp32_unit, 6.283185307179586, 4294967295, 1
clamp32_unit, 7.283185307179586, 4294967295, 1
clamp32_unit, -1, 0, 0
clamp32_unit, 360, 4294967295, 1
clamp32_unit, 720.5, 4294967295, 1
clamp32_unit, 1000000, 4294967295, 1
clamp32_unit, -1000000, 0, 0
clamp32_unit, 0.123456789, 530242871, 0.12345678897655028
clamp32_unit, NaN, 0, 0
clamp32_unit, Infinity, 4294967295, 1
clamp32_unit, -Infinity, 0, 0
wrap16_angle, 0, 0, 0
wrap16_angle, 1, 10430, 0.9999637261029524
wrap16_angle, 10, 38768, 3.7168354490469087
wrap16_angle, 0.0196078431372549, 205, 0.019654128844784777
wrap16_angle, 5.5, 57367, 5.4999922411647235
wrap16_angle, -1.5, 49890, 4.783143844225915
wrap16_angle, 1.5, 15646, 1.5000414629536714
wrap16_angle, 0.3, 3129, 0.2999891178308857
wrap16_angle, -99, 15969, 1.5310087001091128
wrap16_angle, 99, 49567, 4.752176607070473
wrap16_angle, 3.141592653589793, 32768, 3.141592653589793
wrap16_angle, 6.283185307179586, 0, 0
wrap16_angle, 7.283185307179586, 10430, 0.9999637261029524
wrap16_angle, -1, 55106, 5.283221581076634
wrap16_angle, 360, 19384, 1.8584177245234543
wrap16_angle, 720.5, 43984, 4.216913185897628
wrap16_angle, 1000000, 61806, 5.925576036003746
wrap16_angle, -1000000, 3730, 0.35760927117584007
wrap16_angle, 0.123456789, 1288, 0.12348545342479411
wrap16_angle, NaN, 0, 0
wrap16_angle, Infinity, 0, 0
wrap16_angle, -Infinity, 0, 0
wrap8_degrees, 0, 0, 0
wrap8_degrees, 1, 1, 1.40625
wrap8_degrees, 10, 7, 9.84375
wrap8_degrees, 0.0196078431372549, 0, 0
wrap8_degrees, 5.5, 4, 5.625
wrap8_degrees, -1.5, 255, 358.59375
wrap8_degrees, 1.5, 1, 1.40625
wrap8_degrees, 0.3, 0, 0
wrap8_degrees, -99, 186, 261.5625
wrap8_degrees, 99, 70, 98.4375
wrap8_degrees, 3.141592653589793, 2, 2.8125
wrap8_degrees, 6.283185307179586, 4, 5.625
wrap8_degrees, 7.283185307179586, 5, 7.03125
wrap8_degrees, -1, 255, 358.59375
wrap8_degrees, 360, 0, 0
wrap8_degrees, 720.5, 0, 0
wrap8_degrees, 1000000, 199, 279.84375
wrap8_degrees, -1000000, 57, 80.15625
wrap8_degrees, 0.123456789, 0, 0
wrap8_degrees, NaN, 0, 0
wrap8_degrees, Infinity, 0, 0
wrap8_degrees, -Infinity, 0, 0
wrap32_angle, 0, 0, 0
wrap32_angle, 1, 683565276, 1.000000000619646
wrap32_angle, 10, 2540685460, 3.7168146931651997
wrap32_angle, 0.0196078431372549, 13403241, 0.019607843579674843
wrap32_angle, 5.5, 3759609016, 5.500000000482216
wrap32_angle, -1.5, 3269619383, 4.783185307713036
wrap32_angle, 1.5, 1025347913, 1.4999999994665507
wrap32_angle, 0.3, 205069583, 0.30000000047847736
wrap32_angle, -99, 1046514454, 1.5309649149710003
wrap32_angle, 99, 3248452842, 4.752220392208586
wrap32_angle, 3.141592653589793, 2147483648, 3.141592653589793
wrap32_angle, 6.283185307179586, 0, 0
wrap32_angle, 7.283185307179586, 683565276, 1.000000000619646
wrap32_angle, -1, 3611402020, 5.283185306559941
wrap32_angle, 360, 1270363336, 1.8584374914725412
wrap32_angle, 720.5, 2882509309, 4.216874981791988
wrap32_angle, 1000000, 4050548848, 5.925621140693966
wrap32_angle, -1000000, 244418448, 0.3575641664856201
wrap32_angle, 0.123456789, 84390774, 0.12345678900794896
wrap32_angle, NaN, 0, 0
wrap32_angle, Infinity, 0, 0
wrap32_angle, -Infinity, 0, 0";

    private static function quantizeVectorDescriptor(name: String): Dynamic {
        var TWO_PI = 6.283185307179586;
        return switch (name) {
            case "clamp8_0_10": Quantize.resolve(0, 10, 8, false);
            case "clamp16_pitch": Quantize.resolve(-1.5, 1.5, 16, false);
            case "clamp32_unit": Quantize.resolve(0, 1, 32, false);
            case "wrap16_angle": Quantize.resolve(0, TWO_PI, 16, true);
            case "wrap8_degrees": Quantize.resolve(0, 360, 8, true);
            case "wrap32_angle": Quantize.resolve(0, TWO_PI, 32, true);
            default: throw "unknown descriptor: " + name;
        }
    }

    private static function parseVectorNumber(s: String): Float {
        return switch (s) {
            case "NaN": Math.NaN;
            case "Infinity": Math.POSITIVE_INFINITY;
            case "-Infinity": Math.NEGATIVE_INFINITY;
            default: Std.parseFloat(s);
        }
    }

    public function testQuantizeCodecVectors() {
        var rows = 0;
        for (line in QUANTIZE_CODEC_VECTORS.split("\n")) {
            var cols = StringTools.trim(line).split(", ");
            var desc = quantizeVectorDescriptor(cols[0]);
            var input = parseVectorNumber(cols[1]);
            var expectedQ = Std.parseFloat(cols[2]); // q may exceed Int32 (bits=32)
            var expectedRoundtrip = parseVectorNumber(cols[3]);

            assertEquals(expectedQ, Quantize.quantize(desc, input));
            assertEquals(expectedRoundtrip, Quantize.dequantize(desc, expectedQ));
            rows++;
        }
        assertEquals(132, rows);
    }

    public function testQuantizedState() {
        // wire-decode of quantized fields via @:type("quantized", {...});
        // fixtures generated + self-verified by schema-5.0
        // test-external/generate-quantized-fixtures.ts
        var state = new QState();
        var decoder = new Decoder(state);

        decoder.decode(getBytes([128, 238, 50, 129, 187, 130, 55, 221, 154, 31, 131, 1, 132, 2, 133, 5, 134, 4, 135, 161, 113, 255, 1, 128, 0, 1, 128, 1, 202, 0, 0, 32, 64, 128, 2, 3, 255, 2, 128, 0, 161, 97, 161, 120, 255, 5, 128, 7, 255, 4, 128, 0, 6, 128, 1, 7, 255, 6, 128, 1, 255, 7, 128, 2]));

        assertEquals(1.2500025945283118, state.yaw);
        assertEquals(0.6999999999999997, state.pitch);
        assertEquals(0.12345678897655028, state.precise);
        assertEquals("q", state.label);
        assertEquals(3, state.nums.length);
        assertEquals(2.5, state.nums.items[1]);
        assertEquals("x", state.tags.get("a"));
        assertEquals(7., state.child.v);
        assertEquals(2, state.items.length);
        assertEquals(1., state.items.items[0].v);
        assertEquals(2., state.items.items[1].v);

        // patch: yaw changes, pitch clamps to min, nums grows
        decoder.decode(getBytes([128, 250, 162, 129, 0, 255, 1, 128, 3, 4]));

        assertEquals(4.000046652010295, state.yaw);
        assertEquals(-1.5, state.pitch);
        assertEquals(4, state.nums.length);
    }

}

