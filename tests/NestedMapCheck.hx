import haxe.macro.Context;
import haxe.macro.Expr;
import io.colyseus.tools.SchemaTypeUtils;

class NestedMapCheck {
	public static macro function resolvesChildMap():Expr {
		final child = Context.getType("schema.nestedmap.NestedMap.NestedChild");
		final rows = SchemaTypeUtils.extractSchemaFields(child).filter(f -> f.name == "rows")[0];
		final inner = SchemaTypeUtils.getInnerSchemaType(rows);
		final info = SchemaTypeUtils.analyzeFieldType(rows);
		return macro $v{inner != null && info != null && info.isSchemaCollection};
	}
}
