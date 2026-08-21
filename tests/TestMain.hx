class TestMain {

  static function main() {
    var r = new haxe.unit.TestRunner();

    r.add(new MsgpackTestCase());
    r.add(new ClientTestCase());
    // r.add(new StateContainerTestCase());
    r.add(new StorageTestCase());

    r.add(new SchemaSerializerTestCase());
    r.add(new RoomProtocolTestCase());
    r.add(new InputTestCase());
    r.add(new PredictTestCase());
    r.add(new PredictLerpSmoothingTestCase());
    r.add(new PredictAttachConfigTestCase());
    // r.add(new AuthTestCase());

    var success = r.run();
    if (!success) {
      #if sys
      Sys.exit(1);
      #elseif js
      untyped __js__("process.exit(1)");
      #end
    }
  }

}
