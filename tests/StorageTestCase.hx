import io.colyseus.Storage;

class StorageTestCase extends haxe.unit.TestCase {

    public function testStorage() {
        Storage.getItem("value").handle(function(value) {
            assertEquals(null, value);
        });

        Storage.setItem("key", "value100");
        Storage.setItem("key", "value"); // should overwrite

        Storage.getItem("key").handle(function(value) {
            assertEquals("value", value);
        });

        Storage.removeItem("key");

        Storage.getItem("key").handle(function(value) {
            assertEquals(null, value);
        });
    }

}

