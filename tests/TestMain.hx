class TestMain {

  static function main() {
    var r = new haxe.unit.TestRunner();

    r.add(new MsgpackTestCase());
    // r.add(new ClientTestCase());
    // r.add(new StateContainerTestCase());
    r.add(new StorageTestCase());

    r.add(new SchemaSerializerTestCase());
    // r.add(new AuthTestCase());

    r.run();
  }

}
