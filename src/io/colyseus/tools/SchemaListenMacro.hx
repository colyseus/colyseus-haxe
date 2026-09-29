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
	target: Expr,
	links: Expr
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

		var exprs = buildListeners({
			cb: cbExpr,
			source: rootExpr,
			target: macro this,
			links: macro __links
		}, rootType, 0);

		var ret =  macro {
			var __links:Array<CallbackLink> = [];
			$b{exprs};
			CallbackLink.fromMany(__links);
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
			var linksExpr:Expr = ctx.links;
			var sourceExpr:Expr = ctx.source;
			var sourceField = SchemaTypeUtils.fieldExpr(ctx.source, sf.name);
			var parseIfJsonExpr:Expr->Expr = if (SchemaTypeUtils.getSerializedInnerType(sf.haxeType) != null) {
				v -> macro tink.Json.parse($v);
			} else {
				v -> macro $v;
			};

			switch kind {
				case FPrimitive | FStringSerialized:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var traceMsg = indent + sf.name + " = ";
					// primitive listener
					result.push(
						macro $linksExpr.push($cbExpr.listen($sourceExpr, $v{sf.name}, (__v, _) -> {
							#if debug_macro
							trace($v{traceMsg} + Std.string(__v));
							#end
							$targetField.set(${parseIfJsonExpr(macro __v)});
						}))
					);
				case FRef(inner):
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var sourceType = inner.toComplex();
					var emptyChild = SchemaTypeUtils.buildEmptyStructExpr(inner);
					#if debug_macro
					result.push(macro trace($v{indent + sf.name + " (ref) ->"}));
					#end
					result.push(macro {
						var __childLinks:Array<CallbackLink> = [];
						$linksExpr.push(() -> { for (__link in __childLinks) __link.cancel(); });
						$linksExpr.push($cbExpr.listen($sourceExpr, $v{sf.name}, (__child:$sourceType, _) -> {
							for (__link in __childLinks) __link.cancel();
							__childLinks = [];
							$targetField.set($emptyChild);
							if (__child != null) {
								var __ownerSource = __child;
								var __ownerTarget = $targetField.value;
								$b{buildListeners({cb: ctx.cb, source: macro __ownerSource, target: macro __ownerTarget, links: macro __childLinks}, inner, depth + 1)};
							}
						}));
					});

				case FArraySchema(inner):
					var targetField = SchemaTypeUtils.fieldExpr(macro __ownerTarget, sf.name);
					var ownerTarget = ctx.target;
					var rawCT = inner.toComplex();
					var structExpr = buildStructFactoryExpr(inner);
					var traceAdd = indent + sf.name + " (array<schema>) add[";
					var traceRemove = indent + sf.name + " (array<schema>) remove[";

					result.push(macro {
						var __ownerSource = $sourceExpr;
						var __ownerTarget = $ownerTarget;
						var __itemLinks = new Map<Int, Array<CallbackLink>>();
						var __collectionLinks:Array<CallbackLink> = [];
						$linksExpr.push(() -> {
							for (__links in __itemLinks) for (__link in __links) __link.cancel();
							for (__link in __collectionLinks) __link.cancel();
						});
						// factory: raw -> fresh target instance
						function __make(__raw:$rawCT) {
							return $structExpr;
						}

						// ---- schema rebuild ----
						$linksExpr.push($cbExpr.listen(__ownerSource, $v{sf.name}, function(_, _) {
							for (__link in __collectionLinks) __link.cancel();
							__collectionLinks = [];
							for (__links in __itemLinks) for (__link in __links) __link.cancel();
							__itemLinks = new Map();
							$targetField.clear();

							// ---- additions ----
							__collectionLinks.push($cbExpr.onAdd(__ownerSource, $v{sf.name}, function(__item, __index) {
								#if debug_macro
								trace($v{traceAdd} + Std.string(__index) + "]");
								#end
								var __t = __make(__item);
								if (__index < $targetField.length) {
									var __values = $targetField.toArray();
									__values.insert(__index, cast __t);
									$targetField.replace(__values);
									var __shifted = new Map<Int, Array<CallbackLink>>();
									for (__i => __links in __itemLinks) __shifted.set(__i >= __index ? __i + 1 : __i, __links);
									__itemLinks = __shifted;
								} else $targetField.set(__index, cast __t);
								var __links:Array<CallbackLink> = [];
								__itemLinks.set(__index, __links);

								$b{buildListeners({
									cb: ctx.cb,
									source: macro __item,
									target: macro __t,
									links: macro __links
								}, inner, depth + 1)};
							}));

							// listen for removals
							__collectionLinks.push($cbExpr.onRemove(__ownerSource, $v{sf.name}, function(__item, __index) {
								#if debug_macro
								trace($v{traceRemove} + Std.string(__index) + "]");
								#end
								var __oldLinks = __itemLinks.get(__index);
								if (__oldLinks != null) for (__link in __oldLinks) __link.cancel();
								__itemLinks.remove(__index);
								$targetField.splice(__index, 1);
								var __shifted = new Map<Int, Array<CallbackLink>>();
								for (__i => __links in __itemLinks) __shifted.set(__i > __index ? __i - 1 : __i, __links);
								__itemLinks = __shifted;
							}));
						}));
					});

				case FMapSchema(inner):
					var targetField = SchemaTypeUtils.fieldExpr(macro __ownerTarget, sf.name);
					var ownerTarget = ctx.target;
					var rawCT = inner.toComplex();
					var structExpr = buildStructFactoryExpr(inner);
					var traceAdd = indent + sf.name + " (map<schema>) add[";
					var traceRemove = indent + sf.name + " (map<schema>) remove[";

					//SchemaTypeUtils.writeExprToFile("DT", structExpr);

					result.push(macro {
						var __ownerSource = $sourceExpr;
						var __ownerTarget = $ownerTarget;
						var __itemLinks = new Map<String, Array<CallbackLink>>();
						var __collectionLinks:Array<CallbackLink> = [];
						$linksExpr.push(() -> {
							for (__links in __itemLinks) for (__link in __links) __link.cancel();
							for (__link in __collectionLinks) __link.cancel();
						});
						// factory: raw -> fresh target instance
						function __make(__raw:$rawCT) {
							return $structExpr;
						}

						// ---- schema rebuild ----
						$linksExpr.push($cbExpr.listen(__ownerSource, $v{sf.name}, function(_, _) {
							for (__link in __collectionLinks) __link.cancel();
							__collectionLinks = [];
							for (__links in __itemLinks) for (__link in __links) __link.cancel();
							__itemLinks = new Map();
							$targetField.clear();

							// ---- additions ----
							__collectionLinks.push($cbExpr.onAdd(__ownerSource, $v{sf.name}, function(__item, __k) {
								#if debug_macro
								trace($v{traceAdd} + __k + "]");
								#end
								var __t = __make(__item);
								var __oldLinks = __itemLinks.get(__k);
								if (__oldLinks != null) for (__link in __oldLinks) __link.cancel();
								var __links:Array<CallbackLink> = [];
								__itemLinks.set(__k, __links);
								$targetField.set(__k, cast __t);

								$b{buildListeners({
									cb: ctx.cb,
									source: macro __item,
									target: macro __t,
									links: macro __links
								}, inner, depth + 1)};
							}));

							// ---- removals ----
							__collectionLinks.push($cbExpr.onRemove(__ownerSource, $v{sf.name}, function(_, __k) {
								#if debug_macro
								trace($v{traceRemove} + __k + "]");
								#end
								$targetField.remove(__k);
								var __oldLinks = __itemLinks.get(__k);
								if (__oldLinks != null) for (__link in __oldLinks) __link.cancel();
								__itemLinks.remove(__k);
							}));
						}));

					});

				case FArrayPrimitive:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var ct = SchemaTypeUtils.getCollectionElementOrSerialized(sf).toComplex();
					var traceRebuild = indent + sf.name + " (array<primitive>) rebuild";

					result.push(macro {
						var __collectionLink:CallbackLink = null;
						$linksExpr.push(() -> __collectionLink.cancel());
						function __rebuild() {
							#if debug_macro
							trace($v{traceRebuild});
							#end
							$targetField.clear();
							if ($sourceField != null) {
								for (__item in ($sourceField.items : Array<$ct>)) {
									$targetField.push(${parseIfJsonExpr(macro __item)});
								}
							}
						}

						// schema re-init
						$linksExpr.push($cbExpr.listen($sourceExpr, $v{sf.name}, function(__collection, _) {
							__collectionLink.cancel();
							__rebuild();

							// rebuild on any change
							if (__collection != null) __collectionLink = $cbExpr.onChange(__collection, function() __rebuild());
						}));

						// NOTE: no need for fine grained onAdd/onRemove for ArraySchema<Primitive>, complete rebuild on change is enough
					});
				case FMapPrimitive:
					var targetField = SchemaTypeUtils.fieldExpr(ctx.target, sf.name);
					var ct = SchemaTypeUtils.getCollectionElementOrSerialized(sf).toComplex();
					var traceRebuild = indent + sf.name + " (map<primitive>) rebuild";

					result.push(macro {
						var __collectionLink:CallbackLink = null;
						$linksExpr.push(() -> __collectionLink.cancel());
						function __rebuild() {
							#if debug_macro
							trace($v{traceRebuild});
							#end
							$targetField.clear();
							if ($sourceField != null) {
								for (__k => __item in ($sourceField : io.colyseus.tools.SchemaTypeUtils.MapType<$ct>)) {
									$targetField.set(__k, ${parseIfJsonExpr(macro __item)});
								}
							}
						}

						// schema re-init
						$linksExpr.push($cbExpr.listen($sourceExpr, $v{sf.name}, function(__collection, _) {
							__collectionLink.cancel();
							__rebuild();

							// rebuild on any change
							if (__collection != null) __collectionLink = $cbExpr.onChange(__collection, function() __rebuild());
						}));
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
				case "ref": macro new State(${info.emptyValue});
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
