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
        var decoder = new Decoder(state);

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
        decoder.decode(getBytes([ 130, 1, 131, 2, 128, 3, 129, 3, 255, 1, 255, 2, 255, 3, 128, 4, 255, 4, 128, 10, 129, 10 ]));
        assertEquals(client.player1, client.player2);
        assertEquals(client.player1.position, client.player2.position);
        assertEquals(2, refs.refCounts[client.player1.__refId]);
        assertEquals(5, refs.count());

        decoder.decode(getBytes([ 64, 65 ]));
        assertEquals(null, client.player1);
        assertEquals(null, client.player2);
        assertEquals(3, refs.count());

        decoder.decode(getBytes([ 255, 1, 128, 0, 5, 128, 1, 5, 128, 2, 5, 128, 3, 7, 255, 5, 128, 6, 255, 6, 128, 10, 129, 10, 255, 7, 128, 8, 255, 8, 128, 10, 129, 10 ]));
        assertEquals(client.arrayOfPlayers[0], client.arrayOfPlayers[1]);
        assertEquals(client.arrayOfPlayers[1], client.arrayOfPlayers[2]);
        assertFalse(client.arrayOfPlayers[2] == client.arrayOfPlayers[3]);
        assertEquals(7, refs.count());

        decoder.decode(getBytes([ 255, 1, 64, 3, 64, 2, 64, 1 ]));
        assertEquals(1, client.arrayOfPlayers.length);
        assertEquals(5, refs.count());
        var previousArraySchemaRefId = client.arrayOfPlayers.__refId;

        // Replacing ArraySchema
        decoder.decode(getBytes([ 130, 9, 255, 9, 128, 0, 10, 255, 10, 128, 11, 255, 11, 128, 10, 129, 20 ]));
        assertFalse(refs.has(previousArraySchemaRefId));
        assertEquals(1, client.arrayOfPlayers.length);
        assertEquals(5, refs.count());

        // Clearing ArraySchema
        decoder.decode(getBytes([ 255, 9, 10 ]));
        assertEquals(0, client.arrayOfPlayers.length);
        assertEquals(3, refs.count());
    }

    public function testCallbacks() {
        var state = new CallbacksState();
        var decoder = new Decoder(state);
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


}

