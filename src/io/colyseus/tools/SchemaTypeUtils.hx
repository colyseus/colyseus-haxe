package io.colyseus.tools;

#if !macro
interface SchemaTypeUtils {}
#else
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using tink.MacroApi;

class SchemaTypeUtils {

	// ==================================================
	// Normalization helpers
	// ==================================================

	static function followType(t:Type):Type
		return Context.follow(t);

	inline static function pos()
		return Context.currentPos();


	// ==================================================
	// Field extraction
	// ==================================================

	public static function extractSchemaFields(schemaType:Type):Array<SchemaFieldInfo> {
		schemaType = followType(schemaType);

		return switch schemaType {
			case TInst(_.get() => cl, _):
				[
					for (f in cl.fields.get())
						if (f.isPublic)
							switch extractTypeFromMeta(f.meta.get()) {
								case null: continue;
								case typeInfo: {
									name: f.name,
									schemaTypeInfo: typeInfo,
									haxeType: f.type
								};
							}
				];
			case _: [];
		};
	}

	public static function extractTypeFromMeta(metas:Array<MetadataEntry>):Null<SchemaTypeInfo> {
		for (meta in metas) {
			if (meta.name != ":type") continue;
			if (meta.params == null || meta.params.length == 0) continue;

			var kind = switch meta.params[0].getString() {
				case Success(s): s;
				case _: continue;
			};

			var subType =
				meta.params.length > 1
					? switch meta.params[1].expr {
						case EConst(CString(s, _)) | EConst(CIdent(s)): s;
						case _: null;
					}
					: null;

			return {kind: kind, subType: subType};
		}
		return null;
	}

	public static function isSchemaRefSubType(subType:Null<String>):Bool {
		return switch subType {
			case null
				| "number" | "string" | "boolean"
				| "float32" | "float64"
				| "int8" | "int16" | "int32" | "int64"
				| "uint8" | "uint16" | "uint32" | "uint64":
				false;
			case _: true;
		};
	}


	// ==================================================
	// Collection helpers
	// ==================================================

	static function emptyCollectionExpr(isMap:Bool):Expr
		return isMap
			? macro new tink.state.ObservableMap([])
			: macro new tink.state.ObservableArray([]);

	static function buildCollectionType(
		isMap:Bool,
		inner:ComplexType
	):FieldTypeInfo {
		return isMap
			? {
				stateType: macro:tink.state.ObservableMap<String, $inner>,
				emptyValue: emptyCollectionExpr(true),
				isSchemaCollection: true
			}
			: {
				stateType: macro:tink.state.ObservableArray<$inner>,
				emptyValue: emptyCollectionExpr(false),
				isSchemaCollection: true
			};
	}


	// ==================================================
	// Type resolution
	// ==================================================

	public static function resolveSchemaType(
		subTypeName:String,
		haxeType:Null<Type>
	):Null<Type> {
		var elemType = getCollectionElementType(haxeType);
		return elemType ??
			try Context.resolveType(
				TPath({pack: [], name: subTypeName}),
				pos()
			)
			catch (_:Dynamic) null;
	}

	public static function getInnerSchemaType(sf:SchemaFieldInfo):Null<Type> {
		return switch sf.schemaTypeInfo.kind {
			case "ref":
				followType(sf.haxeType);

			case "map" | "array"
				if (isSchemaRefSubType(sf.schemaTypeInfo.subType)):
				resolveSchemaType(
					sf.schemaTypeInfo.subType,
					sf.haxeType
				);

			case _: null;
		};
	}


	// ==================================================
	// Struct building
	// ==================================================

	public static function buildAnonStructType(
		schemaType:Type
	):Null<ComplexType> {

		var fields = extractSchemaFields(schemaType);
		if (fields.length == 0) return null;

		var anonFields:Array<Field> = [];

		for (sf in fields) {
			var info = analyzeFieldType(sf);
			if (info == null) continue;

			var st = info.stateType;

			anonFields.push({
				name: sf.name,
				kind: info.isSchemaCollection
					? FVar(macro:$st, null)
					: FVar(macro:tink.state.State<$st>, null),
				access: [AFinal],
				pos: pos()
			});
		}

		return TAnonymous(anonFields);
	}

	public static function buildEmptyStructExpr(
		schemaType:Type
	):Null<Expr> {

		var fields = extractSchemaFields(schemaType);
		if (fields.length == 0) return null;

		var objFields:Array<ObjectField> = [];

		for (sf in fields) {
			var info = analyzeFieldType(sf);
			if (info == null) continue;

			objFields.push({
				field: sf.name,
				expr: info.isSchemaCollection
					? info.emptyValue
					: macro new tink.state.State(${info.emptyValue})
			});
		}

		return {expr: EObjectDecl(objFields), pos: pos()};
	}


	// ==================================================
	// Field analysis
	// ==================================================

	public static function analyzeFieldType(
		sf:SchemaFieldInfo
	):Null<FieldTypeInfo> {

		return switch sf.schemaTypeInfo.kind {

			case "boolean":
				{stateType: macro:Bool, emptyValue: macro false};

			case "number":
				isFloat(sf.haxeType)
					? {stateType: macro:Float, emptyValue: macro 0.0}
					: {stateType: macro:Int, emptyValue: macro 0};

			case "string":
				switch getSerializedInnerType(sf.haxeType) {
					case null:
						{stateType: macro:String, emptyValue: macro null};
					case inner:
						{
							stateType: inner.toComplex(),
							emptyValue: getDefaultForType(inner)
						};
				};

			case "array" | "map":
				var isMap = sf.schemaTypeInfo.kind == "map";
				var isRef = isSchemaRefSubType(sf.schemaTypeInfo.subType);

				if (isRef) {
					var innerSchemaType = resolveSchemaType(
						sf.schemaTypeInfo.subType,
						sf.haxeType
					);
					if (innerSchemaType == null) return null;

					var anonType = buildAnonStructType(innerSchemaType);
					if (anonType == null) return null;

					return buildCollectionType(isMap, anonType);
				} else {
					var ct = schemaSubTypeToComplexType(
						sf.schemaTypeInfo.subType,
						sf.haxeType
					);
					if (ct == null) return null;

					return buildCollectionType(isMap, ct);
				}

			case "ref":
				var inner = getInnerSchemaType(sf);
				if (inner == null) return null;

				var anon = buildAnonStructType(inner);
				if (anon == null) return null;

				var init = buildEmptyStructExpr(inner);
				if (init == null) return null;

				{stateType: anon, emptyValue: init};

			case _: null;
		};
	}


	// ==================================================
	// Type utilities
	// ==================================================

	public static function isFloat(t:Type):Bool {
		t = followType(t);
		return switch t {
			case TAbstract(_.get() => ab, _):
				ab.name == "Float";
			case _: false;
		};
	}

	public static function getSerializedInnerType(
		t:Type
	):Null<Type> {

		t = followType(t);

		return switch t {
			case TAbstract(_.get() => ab, params)
				if (ab.name == "Serialized" && params.length > 0):
				params[0];

			case TAbstract(_, params):
				for (p in params) {
					var inner = getSerializedInnerType(p);
					if (inner != null) return inner;
				}
				null;

			case _: null;
		};
	}

	public static function getCollectionElementType(
		t:Null<Type>
	):Null<Type> {

		if (t == null) return null;
		t = followType(t);

		return switch t {
			case TInst(_, params) | TAbstract(_, params)
				if (params.length > 0):
				params[0];

			case TInst(_.get() => cl, _)
				if (StringTools.contains(cl.name, "_")):
				switch cl.name.substr(cl.name.lastIndexOf("_") + 1) {
					case "Int": Context.resolveType(macro:Int, pos());
					case "Float": Context.resolveType(macro:Float, pos());
					case "String": Context.resolveType(macro:String, pos());
					case _: null;
				};

			case _: null;
		};
	}

	public static function getCollectionElementOrSerialized(
		sf:SchemaFieldInfo
	):Type {

		var elem = getCollectionElementType(sf.haxeType);
		if (elem != null)
			return followType(elem);

		var serializedInner = getSerializedInnerType(sf.haxeType);
		if (serializedInner != null)
			return followType(serializedInner);

		return Context.resolveType(macro:String, pos());
	}

	public static function schemaSubTypeToComplexType(
		subType:Null<String>,
		haxeType:Null<Type>
	):Null<ComplexType> {

		return switch subType {

			case "number":
				switch getCollectionElementType(haxeType) {
					case null: macro:Float;
					case t if (isFloat(t)): macro:Float;
					case _: macro:Int;
				};

			case "float32" | "float64": macro:Float;

			case "int8" | "int16" | "int32" | "int64"
				| "uint8" | "uint16" | "uint32" | "uint64":
				macro:Int;

			case "string":
				switch getCollectionElementType(haxeType) {
					case null: macro:String;
					case elem:
						switch getSerializedInnerType(elem) {
							case null: macro:String;
							case inner: inner.toComplex();
						};
				};

			case "boolean": macro:Bool;

			case _: null;
		};
	}

	public static function getDefaultForType(t:Type):Expr {
		t = followType(t);

		return switch t {
			case TAbstract(_.get() => ab, _):
				switch ab.name {
					case "Option": macro tink.CoreApi.None;
					case "Dict": macro tink.pure.Dict.empty();
					case "Vector": macro tink.pure.Vector.empty();
					case "ObservableMap": macro tink.state.ObservableMap([]);
					case "ObservableArray": macro tink.state.ObservableArray([]);
					case _: macro null;
				};
			case _: macro null;
		};
	}

	// ==================================================
	// Misc helpers
	// ==================================================

	public static function unwrapValue(
		sf:SchemaFieldInfo,
		v:Expr
	):Expr {
		return switch sf.schemaTypeInfo.kind {
			case "string"
				if (getSerializedInnerType(sf.haxeType) != null):
				macro tink.Json.parse($v);
			case _:
				v;
		};
	}

	public static function fieldExpr(
		e:Expr,
		name:String
	):Expr {
		return {expr: EField(e, name), pos: pos()};
	}

	public static function fieldExprValue(
		target:Expr,
		name:String
	):Expr {
		var f = {expr: EField(target, name), pos: pos()};
		return {expr: EField(f, "value"), pos: pos()};
	}

	public static function writeFile(
		name:String,
		fields:Array<Field>
	) {
		var cls = Context.getLocalClass().get();

		var td:TypeDefinition = {
			pack: cls.pack,
			name: name,
			pos: cls.pos,
			kind: TDClass(),
			fields: fields
		};

		var printer = new haxe.macro.Printer();
		var code = printer.printTypeDefinition(td);

		var info = Context.getPosInfos(cls.pos);
		var dir = haxe.io.Path.directory(info.file);

		sys.io.File.saveContent(
			dir + "/" + name + ".hx",
			code
		);
	}

	public static function writeExprToFile(
		name:String,
		expr:Expr
	) {
		var cls = Context.getLocalClass().get();
		var posInfos = Context.getPosInfos(cls.pos);
		var dir = haxe.io.Path.directory(posInfos.file);

		var printer = new haxe.macro.Printer();
		var code = printer.printExpr(expr);

		sys.io.File.saveContent(
			dir + "/" + name + ".hx",
			code
		);
	}
}


// ==================================================
// Typedefs
// ==================================================

typedef SchemaFieldInfo = {
	name:String,
	schemaTypeInfo:SchemaTypeInfo,
	haxeType:Type
}

typedef SchemaTypeInfo = {
	kind:String,
	subType:Null<String>
}

typedef FieldTypeInfo = {
	stateType:ComplexType,
	emptyValue:Expr,
	?isSchemaCollection:Bool
}

#end

typedef MapType<T> = {
	function keyValueIterator():KeyValueIterator<String, T>;
}