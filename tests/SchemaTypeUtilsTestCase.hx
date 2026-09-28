class SchemaTypeUtilsTestCase extends haxe.unit.TestCase {
	public function testNestedMapWithChildInSameModule() {
		assertTrue(NestedMapCheck.resolvesChildMap());
	}
}
