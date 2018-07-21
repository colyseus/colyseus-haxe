import io.colyseus.state_listener.StateContainer;

class StateContainerTestCase extends haxe.unit.TestCase {
    var container: StateContainer;

    override public function setup() {
        container = new StateContainer(this.getRawData());
    }

    private function getRawData (): Dynamic {
        return {
            players: {
                key1: {
                    id: "key1",
                    position: {
                        x: 0,
                        y: 10
                    }
                },
                key2: {
                    id: "key2",
                    position: {
                        x: 10,
                        y: 20
                    }
                }
            },
            game: {
                turn: 0
            },
            turn: "none",
            nil: null,
            messages: ["one", "two", "three"]
        }
    }

    public function testInitialize() {
        var newState = {
            obj: {
                key: "value"
            },
            arr: [1,2,3,4],
            n: 100,
            s: "string",
            u: null
        };
        container.set(newState);
        assertEquals(container.state, newState);
    }

    public function testListenAddString() {
        var newData = getRawData();
        newData.some_field = "hello!";

        var listenCalls = 0;
        container.listen("some_field", function(change) {
            listenCalls++;
            assertEquals("add", change.operation);
            assertEquals("hello!", change.value);
            assertEquals("[]", Std.string(Reflect.fields(change.path)));
            assertEquals("[some_field]", Std.string(change.rawPath));
        });

        container.set(newData);
        assertEquals(1, listenCalls);
    }

    public function testListenReplaceNull() {
        var newData = getRawData();
        newData.nil = 10;

        var listenCalls = 0;
        container.listen("nil", function(change) {
            listenCalls++;
            assertEquals("replace", change.operation);
            assertEquals(10, change.value);
        });

        container.set(newData);
        assertEquals(1, listenCalls);
    }

    public function testListenAddNull() {
        var newData = getRawData();
        newData.nil_new = null;

        var listenCalls = 0;
        container.listen("nil_new", function(change) {
            listenCalls++;
            assertEquals("add", change.operation);
            assertEquals(null, change.value);
        });

        container.set(newData);
        assertEquals(1, listenCalls);
    }

    public function testListenAddRemove() {
        var newData = getRawData();

        Reflect.deleteField(newData.players, "key1");
        newData.players.key3 = { value : "new"};

        var listenCalls = 0;
        container.listen("players/:id", function(change) {
            listenCalls++;

            if (change.operation == "add") {
                assertEquals("key3", change.path.id);
                assertEquals(Std.string({value: "new"}), Std.string(change.value));

            } else if (change.operation == "remove") {
                assertEquals("key1", change.path.id);
            }
        });

        var patches = container.set(newData);
        trace("PATCHES => " + Std.string(patches));

        assertEquals(2, listenCalls);
    }



}
