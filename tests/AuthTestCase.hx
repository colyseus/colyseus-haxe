import io.colyseus.Client;

class UserData {
    public var email: String;
    public var name: String;
    public var errorServerIsStringButClientIsInt: Int;
    public var someAdditionalData: Bool;
}

class AuthTestCase extends haxe.unit.TestCase {
    var client: Client = null;

    override public function setup() {
        client = new Client("http://localhost:2567");
		client.auth.token = null;
    }

    public function testAuthHttpToken() {
        client.auth.token = "123456";
        assertEquals(client.auth.token, client.http.authToken);
    }

    public function testErrorResponse() {
        client.auth.registerWithEmailAndPassword("invaloid email", "123456", function (err, data) {
            assertEquals(null, data);
        });

        assertEquals(true, true);
    }

    public function testRegisterWithEmailAndPassword() {
        var email = "endel" + Math.floor(Math.random() * 99999) + "@colyseus.io";
        var password = "123456";

        var onChangeCount = 0;
        var onChangeWithNullCount = 0;
        client.auth.onChange(function(authData) {
			onChangeCount++;
            if (authData.user != null) {
				assertEquals(email, authData.user.email);
            } else {
				onChangeWithNullCount++;
            }
        });

        client.auth.registerWithEmailAndPassword(email, password, function (err, data) {
            assertEquals(null, err);
            assertEquals(1, onChangeWithNullCount);
            assertEquals(2, onChangeCount);
        });

        assertEquals(true, true);
    }

    public function testSignINWithEmailAndPassword() {
        var email = "endel" + Math.floor(Math.random() * 99999) + "@colyseus.io";
        var password = "123456";

        client.auth.registerWithEmailAndPassword(email, password, function (err, data) {
            // make sure token is clear
            client.auth.token = null;

            var onChangeCount = 0;
            var onChangeWithNullCount = 0;

            client.auth.onChange(function(authData) {
                onChangeCount++;
                if (authData.user != null) {
                    assertEquals(email, authData.user.email);
                } else {
                    onChangeWithNullCount++;
                }
            });

			client.auth.signInWithEmailAndPassword(email, "bad_password", function(err, data) {
                assertEquals(err.message, "invalid_credentials");

				client.auth.signInWithEmailAndPassword(email, password, function(err, data) {
					assertEquals(null, err);
					assertEquals(1, onChangeWithNullCount);
					assertEquals(2, onChangeCount);
					assertEquals(email, data.user.email);
				});
            });
        });

        assertEquals(true, true);
    }

    public function testSignInAnonymously() {
        var onChangeCount = 0;
        var onChangeWithNullCount = 0;

		client.auth.onChange(function(authData) {
            onChangeCount++;
            if (authData.user != null) {
                assertEquals(true, authData.user.anonymous);
                assertEquals(true, authData.user.anonymousId > 0);
            } else {
                onChangeWithNullCount++;
            }
        });

		client.auth.signInAnonymously({something: "hello"}, function(err, data) {
            assertEquals(2, onChangeCount);
            assertEquals(1, onChangeWithNullCount);
            assertEquals(true, data.user.anonymous);
            assertEquals(true, data.user.anonymousId > 0);
            assertEquals("hello", data.user.something);
        });

        assertEquals(true, true);
    }

    public function testSignOut() {
        var onChangeCount = 0;
        var onChangeWithNullCount = 0;

		client.auth.onChange(function(authData) {
            onChangeCount++;
            if (authData.user != null) {
                assertEquals(true, authData.user.anonymous);
                assertEquals(true, authData.user.anonymousId > 0);
            } else {
                onChangeWithNullCount++;
            }
        });

		client.auth.signInAnonymously(function(err, data) {
            assertEquals(true, data.user.anonymous);
            assertEquals(true, data.user.anonymousId > 0);

            client.auth.signOut();
            assertEquals(3, onChangeCount);
            assertEquals(2, onChangeWithNullCount);
        });

        assertEquals(true, true);
    }

}

