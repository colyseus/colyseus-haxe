import io.colyseus.serializer.schema.types.MapSchema;

class MapSchemaTestCase extends haxe.unit.TestCase {
    public function testKeyValueIterationFollowsInsertionOrder() {
        var map = new MapSchema<Int>();
        for (key in ["zeta", "alpha", "mid", "beta"]) map.items.set(key, key.length);

        assertEquals("zeta,alpha,mid,beta", [for (k => _ in map) k].join(","));
        assertEquals("4,5,3,4", [for (_ => v in map) v].join(","));

        map.items.remove("alpha");
        assertEquals("zeta,mid,beta", [for (k => _ in map) k].join(","));
        assertEquals(3, map.length);
    }
}
