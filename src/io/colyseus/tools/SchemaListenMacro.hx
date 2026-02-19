package io.colyseus.tools;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using io.colyseus.tools.SchemaTypeUtils;
using tink.CoreApi;
using tink.MacroApi;

private typedef BuildCtx = {
	cb: Expr,
	source: Expr,
	target: Expr
};

private enum FieldKind {
	FPrimitive;
	FStringSerialized;
	FRef(t:Type);
	FArrayPrimitive;
	FArraySchema(t:Type);
	FMapPrimitive;
	FMapSchema(t:Type);
}
#end

class SchemaListenMacro {

	public static macro function listenRef(cbExpr:Expr, rootExpr:Expr):Expr {
		var rootType = Context.typeof(rootExpr);
		var pos = Context.currentPos();

		var exprs = buildListeners({
			cb: cbExpr,
			source: rootExpr,
			target: macro this
		}, rootType, 0);

		var ret =  macro {
			var link:CallbackLink = null;
			link = $cbExpr.onChange($rootExpr, function() {
				$b{exprs};
				return link;
			});
		};
		#if debug_macro
		SchemaTypeUtils.writeExprToFile('ListenDebug', ret);
		#end
		return ret;
	}

	#if macro
	inline static final MAX_DEPTH:Int = 100;

	static function buildListeners(
		ctx:BuildCtx,
		schemaType:Type,
		depth:Int
	):Array<Expr> {
		if (depth > MAX_DEPTH) {
			Context.error(
				'Max depth ($MAX_DEPTH) exceeded: either you have a recursion (nested schema points to parent schema) or your schema is too complex. Increase MAX_DEPTH if needed.',
				Context.currentPos()
			);
		}
		var result:Array<Expr> = [];
		var fields = SchemaTypeUtils.extractSchemaFields(schemaType);

		for (sf in fields) {
			var kind = classifyField(sf);
			var indent = StringTools.lpad("", "  ", depth);
			var cbExpr:Expr = ctx.cb;
			var sourceExpr:Expr = ctx.source;
			var sourceField = SchemaTypeUtils.fieldExpr(ctx.source, sf.name);
			var parseIfJsonExpr:Expr->Expr = if (SchemaTypeUtils.getSerializedInnerType(sf.haxeType) != null) {
				v -> macro tink.Json.parse($v);
			} else {
				v -> macro $v;
			};

			// Generate unique temp names to avoid variable shadowing in nested schemas
			var tName = tink.MacroApi.tempName("t");
			var itemName = tink.MacroApi.tempName("item");

			switch kind {
				case FPrimitive | FStringSerialized:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					// primitive listener
					result.push(
						macro $cbExpr.listen($sourceExpr, $v{sf.name}, (__v, _) -> $targetField.set(${parseIfJsonExpr(macro __v)}))
					);
				case FRef(inner):
					var targetField = SchemaTypeUtils.fieldExprValue(ctx.target, sf.name);
					result = result.concat(
						buildListeners({
							cb: ctx.cb,
							source: sourceField,
							target: targetField
						}, inner, depth + 1)
					);

				case FArraySchema(inner):
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var rawCT = inner.toComplex();
					var structExpr = buildStructFactoryExpr(inner);

					result.push(macro {
						// factory: raw -> fresh target instance
						function __make(__raw:$rawCT) {
							return $structExpr;
						}

						// ---- initialize existing items ----
						function __rebuild() {
							for ($i{itemName} in ($sourceField.items : Array<$rawCT>)) {
								var $tName = __make($i{itemName});
								$targetField.push(cast $i{tName});

								$b{buildListeners({
									cb: ctx.cb,
									source: macro $i{itemName},
									target: macro $i{tName}
								}, inner, depth + 1)};
							}
						}
						if ($targetField.length == 0) {
							__rebuild();
						}

						// ---- schema rebuild ----
						$cbExpr.listen($sourceExpr, $v{sf.name}, function(_, _) {
							$targetField.clear();
							__rebuild();

							// ---- additions ----
							$cbExpr.onAdd($sourceExpr, $v{sf.name}, function(__item, __index) {
								var $tName = __make(__item);
								$targetField.set(__index, cast $i{tName});

								$b{buildListeners({
									cb: ctx.cb,
									source: macro __item,
									target: macro $i{tName}
								}, inner, depth + 1)};
							});

							// listen for removals
							$cbExpr.onRemove($sourceExpr, $v{sf.name}, function(__item, __index) {
								$targetField.remove(__index);
							});
						});
						// NOTE: replacement of current items in ArraySchema<Schema> is not yet supported;
					});

				case FMapSchema(inner):
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var rawCT = inner.toComplex();
					var structExpr = buildStructFactoryExpr(inner);

					//SchemaTypeUtils.writeExprToFile("DT", structExpr);

					result.push(macro {
						// factory: raw -> fresh target instance
						function __make(__raw:$rawCT) {
							return $structExpr;
						}

						// ---- initialize existing items ----
						function __rebuild() {
							for (__k => $i{itemName} in ($sourceField : io.colyseus.tools.SchemaTypeUtils.MapType<$rawCT>)) {
								var $tName = __make($i{itemName});
								$targetField.set(__k, cast $i{tName});

								$b{buildListeners({
									cb: ctx.cb,
									source: macro $i{itemName},
									target: macro $i{tName}
								}, inner, depth + 1)};
							}
						}
						// initial sync
						__rebuild();

						// ---- schema rebuild ----
						$cbExpr.listen($sourceExpr, $v{sf.name}, function(_, _) {
							$targetField.clear();
							__rebuild();

							// ---- additions ----
							$cbExpr.onAdd($sourceExpr, $v{sf.name}, function(__item, __k) {
								var $tName = __make(__item);
								$targetField.set(__k, cast $i{tName});

								$b{buildListeners({
									cb: ctx.cb,
									source: macro __item,
									target: macro $i{tName}
								}, inner, depth + 1)};
							});

							// ---- removals ----
							$cbExpr.onRemove($sourceExpr, $v{sf.name}, function(_, __k) {
								$targetField.remove(__k);
							});
						});

						// NOTE: replacement of current items in MapSchema<Schema> is not yet supported;
					});

				case FArrayPrimitive:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var ct = SchemaTypeUtils.getCollectionElementOrSerialized(sf).toComplex();

					result.push(macro {
						function __rebuild() {
							$targetField.clear();
							for ($i{itemName} in ($sourceField.items : Array<$ct>)) {
								$targetField.push(${parseIfJsonExpr(macro $i{itemName})});
							}
						}
						// initial sync
						__rebuild();

						// schema re-init
						$cbExpr.listen($sourceExpr, $v{sf.name}, function(_, _) {
							__rebuild();

							// rebuild on any change
							$cbExpr.onChange($sourceField, function() {
								__rebuild();
							});
						});

						// NOTE: no need for fine grained onAdd/onRemove for ArraySchema<Primitive>, complete rebuild on change is enough
					});
				case FMapPrimitive:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var ct = SchemaTypeUtils.getCollectionElementOrSerialized(sf).toComplex();
					result.push(macro {
						function __rebuild() {
							$targetField.clear();
							for (__k => $i{itemName} in ($sourceField : io.colyseus.tools.SchemaTypeUtils.MapType<$ct>)) {
								$targetField.set(__k, ${parseIfJsonExpr(macro $i{itemName})});
							}
						}

						// initial sync
						__rebuild();

						// schema re-init
						$cbExpr.listen($sourceExpr, $v{sf.name}, function(_, _) {
							__rebuild();

							// rebuild on any change
							$cbExpr.onChange($sourceField, function() {
								__rebuild();
							});
						});
						// NOTE: no need for fine grained onAdd/onRemove for MapSchema<Primitive>, complete rebuild on change is enough
					});
			}
		}

		return result;
	}

	static function buildStructFactoryExpr(schemaType:Type):Expr {
		return SchemaTypeUtils.buildStructExpr(schemaType, (sf, info) -> {
			var rawF = SchemaTypeUtils.fieldExpr(macro __raw, sf.name);
			if (info.isSchemaCollection == true)
				info.emptyValue
			else switch sf.schemaTypeInfo.kind {
				case "ref": macro null;
				case "string" if (SchemaTypeUtils.getSerializedInnerType(sf.haxeType) != null):
					var ct = info.stateType;
					macro new State((tink.Json.parse($rawF):$ct));
				case _: macro new State($rawF);
			};
		});
	}

	static function classifyField(sf:SchemaTypeUtils.SchemaFieldInfo):FieldKind {
		return switch sf.schemaTypeInfo.kind {
			case "boolean" | "number":
				FPrimitive;

			case "string":
				SchemaTypeUtils.getSerializedInnerType(sf.haxeType) != null
					? FStringSerialized
					: FPrimitive;

			case "ref":
				var inner = SchemaTypeUtils.getInnerSchemaType(sf);
				inner == null ? FPrimitive : FRef(inner);

			case "array":
				var inner = SchemaTypeUtils.getInnerSchemaType(sf);
				inner != null
					? FArraySchema(inner)
					: FArrayPrimitive;

			case "map":
				var inner = SchemaTypeUtils.getInnerSchemaType(sf);
				inner != null
					? FMapSchema(inner)
					: FMapPrimitive;

			case _:
				FPrimitive;
		};
	}

	static function kindToString(k:FieldKind):String {
		return switch k {
			case FPrimitive: "primitive";
			case FStringSerialized: "string(serialized)";
			case FRef(_): "ref";
			case FArrayPrimitive: "array(primitive)";
			case FArraySchema(_): "array(schema)";
			case FMapPrimitive: "map(primitive)";
			case FMapSchema(_): "map(schema)";
		};
	}

	#end
}
