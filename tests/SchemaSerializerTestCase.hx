import haxe.io.Bytes;
import haxe.io.BytesData;

import io.colyseus.serializer.SchemaSerializer;

import schema.primitivetypes.PrimitiveTypes;
import schema.childschematypes.ChildSchemaTypes;
import schema.arrayschematypes.ArraySchemaTypes;
import schema.mapschematypes.MapSchemaTypes;
import schema.mapschemaint8.MapSchemaInt8;
import schema.inheritedtypes.InheritedTypes;
import schema.backwardsforwards.StateV1;
import schema.backwardsforwards.StateV2;

class SchemaSerializerTestCase extends haxe.unit.TestCase {

    private function getBytes(arr: Array<Int>) {
        var bytes = Bytes.alloc(arr.length);
        var i: Int = 0;
        for (byte in arr) { bytes.set(i++, byte); }
        return bytes;
    }

    public function testPrimitiveTypes() {
        var state = new PrimitiveTypes();
        var bytes = [ 0, 128, 1, 255, 2, 0, 128, 3, 255, 255, 4, 0, 0, 0, 128, 5, 255, 255, 255, 255, 6, 0, 0, 0, 0, 0, 0, 0, 128, 7, 255, 255, 255, 255, 255, 255, 31, 0, 8, 204, 204, 204, 253, 9, 255, 255, 255, 255, 255, 255, 239, 127, 10, 208, 128, 11, 204, 255, 12, 209, 0, 128, 13, 205, 255, 255, 14, 210, 0, 0, 0, 128, 15, 203, 0, 0, 224, 255, 255, 255, 239, 65, 16, 203, 0, 0, 0, 0, 0, 0, 224, 195, 17, 203, 255, 255, 255, 255, 255, 255, 63, 67, 18, 203, 61, 255, 145, 224, 255, 255, 239, 199, 19, 203, 153, 153, 153, 153, 153, 153, 185, 127, 20, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 21, 1 ];
        state.decode(getBytes(bytes));

        assertEquals(state.int8, -128);
        assertEquals(state.uint8, 255);
        assertEquals(state.int16, -32768);
        assertEquals(state.uint16, 65535);
        assertEquals(state.int32, -2147483648);

        assertEquals(4294967295, state.uint32);
        /* assertEquals(-9223372036854775808, state.int64); */
        /* assertEquals(9007199254740991, haxe.Int64.toInt(state.uint64)); */

        assertEquals(state.float32, -3.4028234663852886e+37);
        assertEquals(state.float64, 1.7976931348623157e+308);

        assertEquals(state.varint_int8, -128);
        assertEquals(state.varint_uint8, 255);
        assertEquals(state.varint_int16, -32768);
        assertEquals(state.varint_uint16, 65535);
        assertEquals(state.varint_int32, -2147483648);
        assertEquals(state.varint_uint32, 4294967295);

        /* // failing on cpp target */
        /* assertEquals(state.varint_int64, -9223372036854775808); */
        assertEquals(state.varint_uint64, 9007199254740991);
        assertEquals(state.varint_float32, -3.40282347e+38);
        assertEquals(state.varint_float64, 1.7976931348623157e+307);

        assertEquals(state.str, "Hello world");
        assertEquals(state.boolean, true);
    }

    public function testChildSchemaTypes()
    {
        var state = new ChildSchemaTypes();
        var bytes = [ 0, 0, 205, 244, 1, 1, 205, 32, 3, 193, 1, 0, 204, 200, 1, 205, 44, 1, 193 ];
        state.decode(getBytes(bytes));

        assertEquals(state.child.x, 500);
        assertEquals(state.child.y, 800);

        assertEquals(state.secondChild.x, 200);
        assertEquals(state.secondChild.y, 300);
    }

    public function testArraySchemaTypes()
    {
        var state = new ArraySchemaTypes();
        var bytes = [ 0, 2, 2, 0, 0, 100, 1, 208, 156, 193, 1, 0, 100, 1, 208, 156, 193, 1, 4, 4, 0, 0, 1, 10, 2, 20, 3, 205, 192, 13, 2, 3, 3, 0, 163, 111, 110, 101, 1, 163, 116, 119, 111, 2, 165, 116, 104, 114, 101, 101, 3, 3, 3, 0, 232, 3, 0, 0, 1, 192, 13, 0, 0, 2, 72, 244, 255, 255 ];

        /* state.arrayOfSchemas.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfSchemas => " + key); */
        /* state.arrayOfNumbers.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfNumbers => " + key); */
        /* state.arrayOfStrings.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfStrings => " + key); */
        /* state.arrayOfInt32.OnAdd += (value, key) => Debug.Log("onAdd, arrayOfInt32 => " + key); */

        state.onChange = function(changes) {
            trace("\nCHANGES! => " + changes);
        };

        state.decode(getBytes(bytes));

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

        /* state.arrayOfSchemas.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfSchemas => " + key); */
        /* state.arrayOfNumbers.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfNumbers => " + key); */
        /* state.arrayOfStrings.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfStrings => " + key); */
        /* state.arrayOfInt32.OnRemove += (value, key) => Debug.Log("onRemove, arrayOfInt32 => " + key); */

        var popBytes = [ 0, 1, 0, 1, 1, 0, 3, 1, 0, 2, 1, 0 ];
        state.decode(getBytes(popBytes));

        assertEquals(state.arrayOfSchemas.length, 1);
        assertEquals(state.arrayOfNumbers.length, 1);
        assertEquals(state.arrayOfStrings.length, 1);
        assertEquals(state.arrayOfInt32.length, 1);

        var zeroBytes = [ 0, 0, 0, 1, 0, 0, 2, 0, 0, 3, 0, 0 ];
        state.decode(getBytes(zeroBytes));

        assertEquals(state.arrayOfSchemas.length, 0);
        assertEquals(state.arrayOfNumbers.length, 0);
        assertEquals(state.arrayOfStrings.length, 0);
        assertEquals(state.arrayOfInt32.length, 0);
    }

    public function testMapSchemaTypes()
    {
        var state = new MapSchemaTypes();
        var bytes = [ 0, 3, 163, 111, 110, 101, 0, 100, 1, 204, 200, 193, 163, 116, 119, 111, 0, 205, 44, 1, 1, 205, 144, 1, 193, 165, 116, 104, 114, 101, 101, 0, 205, 244, 1, 1, 205, 88, 2, 193, 1, 3, 163, 111, 110, 101, 1, 163, 116, 119, 111, 2, 165, 116, 104, 114, 101, 101, 205, 192, 13, 2, 3, 163, 111, 110, 101, 163, 79, 110, 101, 163, 116, 119, 111, 163, 84, 119, 111, 165, 116, 104, 114, 101, 101, 165, 84, 104, 114, 101, 101, 3, 3, 163, 111, 110, 101, 192, 13, 0, 0, 163, 116, 119, 111, 24, 252, 255, 255, 165, 116, 104, 114, 101, 101, 208, 7, 0, 0 ];

        /* state.mapOfSchemas.OnAdd += (value, key) => Debug.Log("OnAdd, mapOfSchemas => " + key); */
        /* state.mapOfNumbers.OnAdd += (value, key) => Debug.Log("OnAdd, mapOfNumbers => " + key); */
        /* state.mapOfStrings.OnAdd += (value, key) => Debug.Log("OnAdd, mapOfStrings => " + key); */
        /* state.mapOfInt32.OnAdd += (value, key) => Debug.Log("OnAdd, mapOfInt32 => " + key); */
        /*  */
        /* state.mapOfSchemas.OnRemove += (value, key) => Debug.Log("OnRemove, mapOfSchemas => " + key); */
        /* state.mapOfNumbers.OnRemove += (value, key) => Debug.Log("OnRemove, mapOfNumbers => " + key); */
        /* state.mapOfStrings.OnRemove += (value, key) => Debug.Log("OnRemove, mapOfStrings => " + key); */
        /* state.mapOfInt32.OnRemove += (value, key) => Debug.Log("OnRemove, mapOfInt32 => " + key); */

        state.decode(getBytes(bytes));

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

        var deleteBytes = [ 1, 2, 192, 1, 192, 2, 0, 2, 192, 1, 192, 2, 2, 2, 192, 1, 192, 2, 3, 2, 192, 1, 192, 2 ];
        state.decode(getBytes(deleteBytes));

        assertEquals(state.mapOfSchemas.length, 1);
        assertEquals(state.mapOfNumbers.length, 1);
        assertEquals(state.mapOfStrings.length, 1);
        assertEquals(state.mapOfInt32.length, 1);
    }

    public function testMapSchemaInt8()
    {
        var state = new MapSchemaInt8();
        var bytes = [ 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 1, 6, 163, 98, 98, 98, 1, 163, 97, 97, 97, 1, 163, 50, 50, 49, 1, 163, 48, 50, 49, 1, 162, 49, 53, 1, 162, 49, 48, 1 ];

        state.decode(getBytes(bytes));

        assertEquals(state.status, "Hello world");
        assertEquals(state.mapOfInt8.get("bbb"), 1);
        assertEquals(state.mapOfInt8.get("aaa"), 1);
        assertEquals(state.mapOfInt8.get("221"), 1);
        assertEquals(state.mapOfInt8.get("021"), 1);
        assertEquals(state.mapOfInt8.get("15"), 1);
        assertEquals(state.mapOfInt8.get("10"), 1);

        var addBytes = [ 1, 1, 5, 2 ];
        state.decode(getBytes(addBytes));

        assertEquals(state.mapOfInt8.get("bbb"), 1);
        assertEquals(state.mapOfInt8.get("aaa"), 1);
        assertEquals(state.mapOfInt8.get("221"), 1);
        assertEquals(state.mapOfInt8.get("021"), 1);
        assertEquals(state.mapOfInt8.get("15"), 1);
        assertEquals(state.mapOfInt8.get("10"), 2);
    }

    public function testInheritedTypes()
    {
        var serializer = new SchemaSerializer<InheritedTypes>(InheritedTypes);
        var handshake = [ 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 3, 3, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 165, 112, 111, 119, 101, 114, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 3, 0, 3, 1, 4, 4, 0, 0, 166, 101, 110, 116, 105, 116, 121, 1, 163, 114, 101, 102, 2, 0, 193, 1, 0, 166, 112, 108, 97, 121, 101, 114, 1, 163, 114, 101, 102, 2, 1, 193, 2, 0, 163, 98, 111, 116, 1, 163, 114, 101, 102, 2, 2, 193, 3, 0, 163, 97, 110, 121, 1, 163, 114, 101, 102, 2, 0, 193, 193, 1, 3 ];
        serializer.handshake(getBytes(handshake), 0);

        var bytes = [ 0, 0, 205, 244, 1, 1, 205, 32, 3, 193, 1, 0, 204, 200, 1, 205, 44, 1, 2, 166, 80, 108, 97, 121, 101, 114, 193, 2, 0, 100, 1, 204, 150, 2, 163, 66, 111, 116, 3, 204, 200, 193, 3, 213, 2, 3, 100, 193 ];
        serializer.setState(getBytes(bytes));

        var state = serializer.getState();

        assertTrue(Type.getClassName(Type.getClass(state.entity)) == "schema.inheritedtypes.Entity");
        assertEquals(state.entity.x, 500);
        assertEquals(state.entity.y, 800);

        assertTrue(Type.getClassName(Type.getClass(state.player)) == "schema.inheritedtypes.Player");
        assertEquals(state.player.x, 200);
        assertEquals(state.player.y, 300);
        assertEquals(state.player.name, "Player");

        assertTrue(Type.getClassName(Type.getClass(state.bot)) == "schema.inheritedtypes.Bot");
        assertEquals(state.bot.x, 100);
        assertEquals(state.bot.y, 150);
        assertEquals(state.bot.name, "Bot");
        assertEquals(state.bot.power, 200);

    }

    public function testBackwardsForwards()
    {
        var statev1bytes = [ 1, 1, 163, 111, 110, 101, 0, 203, 64, 45, 212, 207, 108, 69, 148, 63, 1, 203, 120, 56, 150, 252, 58, 73, 224, 63, 193, 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100 ];
        var statev2bytes = [ 0, 171, 72, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100, 2, 10 ];

        var statev2 = new StateV2();
        statev2.decode(getBytes(statev1bytes));
        assertEquals(statev2.str, "Hello world");

        var statev1 = new StateV1();
        statev1.decode(getBytes(statev2bytes));
        assertEquals(statev1.str, "Hello world");

        /*
           Assert.DoesNotThrow(() =>
           {
        // uses StateV1 handshake with StateV2 structure.
        var serializer = new Colyseus.SchemaSerializer<SchemaTest.Forwards.StateV2>();
        byte[] handshake = { 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 2, 2, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 0, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 174, 97, 114, 114, 97, 121, 79, 102, 83, 116, 114, 105, 110, 103, 115, 1, 172, 97, 114, 114, 97, 121, 58, 115, 116, 114, 105, 110, 103, 2, 255, 193, 193, 3, 0, 3, 1, 3, 3, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 2, 193, 2, 0, 169, 99, 111, 117, 110, 116, 100, 111, 119, 110, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 1 };
        serializer.Handshake(handshake, 0);
        }, "reflection should be backwards compatible");

        Assert.DoesNotThrow(() =>
        {
        // uses StateV2 handshake with StateV1 structure.
        var serializer = new Colyseus.SchemaSerializer<SchemaTest.Backwards.StateV1>();
        byte[] handshake = { 0, 4, 4, 0, 0, 0, 1, 2, 2, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 0, 1, 1, 2, 2, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 0, 193, 193, 2, 0, 2, 1, 4, 4, 0, 0, 161, 120, 1, 166, 110, 117, 109, 98, 101, 114, 193, 1, 0, 161, 121, 1, 166, 110, 117, 109, 98, 101, 114, 193, 2, 0, 164, 110, 97, 109, 101, 1, 166, 115, 116, 114, 105, 110, 103, 193, 3, 0, 174, 97, 114, 114, 97, 121, 79, 102, 83, 116, 114, 105, 110, 103, 115, 1, 172, 97, 114, 114, 97, 121, 58, 115, 116, 114, 105, 110, 103, 2, 255, 193, 193, 3, 0, 3, 1, 3, 3, 0, 0, 163, 115, 116, 114, 1, 166, 115, 116, 114, 105, 110, 103, 193, 1, 0, 163, 109, 97, 112, 1, 163, 109, 97, 112, 2, 2, 193, 2, 0, 169, 99, 111, 117, 110, 116, 100, 111, 119, 110, 1, 166, 110, 117, 109, 98, 101, 114, 193, 193, 1, 3 };
        serializer.Handshake(handshake, 0);
        }, "reflection should be forwards compatible");
         */
    }

}

