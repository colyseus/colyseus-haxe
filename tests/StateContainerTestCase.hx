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
        var c = new StateContainer(newState);
        assertEquals(c.state, newState);
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

        var patches = container.set(newData);
        assertEquals(1, patches.length);
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

        var patches = container.set(newData);
        assertEquals(1, patches.length);
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

        var patches = container.set(newData);
        assertEquals(1, patches.length);
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
        assertEquals(3, patches.length);
        assertEquals(2, listenCalls);
    }

    public function testListenReplace() {
        var newData = getRawData();
        newData.players.key1.position = { x: 50, y: 100 };

        var listenCalls = 0;
        container.listen("players/:id/position/:axis", function(change) {
            listenCalls++;

            assertEquals("key1", change.path.id);

            if (change.path.axis == "x") {
                assertEquals(50, change.value);

            } else if (change.path.axis == "y") {
                assertEquals(100, change.value);
            }
        });

        var patches = container.set(newData);
        assertEquals(2, patches.length);
        assertEquals(2, listenCalls);
    }

    public function testListenReplaceString() {
        var newData = getRawData();
        newData.turn = "mutated";

        var listenCalls = 0;
        container.listen("turn", function(change) {
            listenCalls++;

            assertEquals("mutated", change.value);
        });

        var patches = container.set(newData);
        assertEquals(1, patches.length);
        assertEquals(1, listenCalls);
    }

    public function testListenAddArray() {
        var newData = getRawData();
        newData.messages.push("new value");

        var listenCalls = 0;
        container.listen("messages/:number", function(change) {
            listenCalls++;

            assertEquals("add", change.operation);
            assertEquals("new value", change.value);
            assertEquals("3", change.path.number);
        });

        var patches = container.set(newData);
        assertEquals(1, patches.length);
        assertEquals(1, listenCalls);
    }

    public function testListenRemoveArray() {
        var newData = getRawData();
        newData.messages.shift();

        var listenCalls = 0;
        container.listen("messages/:number", function(change) {
            listenCalls++;

            if (listenCalls == 1) {
                assertEquals("remove", change.operation);
                assertEquals("2", change.path.number);
                assertEquals(null, change.value);

            } else if (listenCalls == 2) {
                assertEquals("replace", change.operation);
                assertEquals("1", change.path.number);
                assertEquals("three", change.value);

            } else if (listenCalls == 3) {
                assertEquals("replace", change.operation);
                assertEquals("0", change.path.number);
                assertEquals("two", change.value);
            }

        });

        var patches = container.set(newData);
        assertEquals(3, patches.length);
        assertEquals(3, listenCalls);
    }

    public function testListenInitialState() {
        var container = new StateContainer({});

        var listenCalls = 0;
        container.listen("players/:id/position/:attribute", function (change) {
            listenCalls++;
		});

		container.listen("turn", function (change) {
			listenCalls++;
		});

		container.listen("game/turn", function (change) {
			listenCalls++;
		});

		container.listen("messages/:number", function (change) {
			listenCalls++;
		});


        container.set(getRawData());
        assertEquals(9, listenCalls);
    }



}
