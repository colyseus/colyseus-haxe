
class TestMain {

  static function main() {
    var r = new haxe.unit.TestRunner();
    r.add(new ClientTestCase());
    r.add(new RoomFossilDeltaTestCase());
    r.add(new StateContainerTestCase());
    r.run();
  }

}
