
class TestMain {

  static function main() {
    var r = new haxe.unit.TestRunner();
    r.add(new ClientTestCase());
    r.add(new StateContainerTestCase());
    r.add(new SchemaSerializerTestCase());
    r.run();
  }

}
