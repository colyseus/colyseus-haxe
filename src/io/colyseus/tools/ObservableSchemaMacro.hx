package io.colyseus.tools;

#if !macro
interface ObservableSchemaMacro {}
#else
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using tink.MacroApi;

/**
	Build macro that generates typed State<T> fields and a constructor for schema observable classes.
	Used via @:build(ObservableSchemaMacro.build(SchemaClass)).
**/
class ObservableSchemaMacro {
	public static function build(schemaExpr:Expr):Array<Field> {
		var schemaTypeName = schemaExpr.getIdent().sure();
		var schemaType = Context.resolveType(TPath({pack: [], name: schemaTypeName}), schemaExpr.pos);
		var schemaFields = SchemaTypeUtils.extractSchemaFields(schemaType);

		if (schemaFields.length == 0)
			return [];

		var pos = Context.currentPos();
		var fields:Array<Field> = Context.getBuildFields();

		for (sf in schemaFields) {
			var info = SchemaTypeUtils.analyzeFieldType(sf);
			if (info == null) continue;
			var st = info.stateType;
			var init = info.emptyValue;
			fields.push({
				name: sf.name,
				access: [APublic, AFinal],
				kind: info.isSchemaCollection
					? FVar(macro:$st, macro $init)
					: FVar(macro:tink.state.State<$st>, macro new tink.state.State($init)),
				pos: pos
			});
		}

		fields.push({name: "new", access: [APublic], kind: FFun({args: [], ret: null, expr: macro {}}), pos: pos});

		#if debug_macro
		trace('ObservableSchemaMacro.build($schemaTypeName): ${fields.length} fields');
		SchemaTypeUtils.writeFile('${schemaTypeName}Debug', fields);
		#end

		return fields;
	}
}
#end
