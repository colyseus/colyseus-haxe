# SchemaTypeUtils (Haxe Macro Utilities)

Utility macro helpers for analyzing **Colyseus Schema** classes and
generating strongly-typed `tink.state` observable structures
automatically.

This module is designed to:

-   Inspect `@:type(...)` metadata on Colyseus schema fields
-   Infer field kinds (`number`, `string`, `ref`, `array`, `map`,
    etc.\`)
-   Generate `State<T>`, `ObservableArray<T>`, and `ObservableMap<K, V>`
-   Build anonymous struct types representing nested schemas in type safe way
-   Generate default initialization expressions
-   Provide reusable macro helpers for schema-driven code generation

------------------------------------------------------------------------

# What This Utility Solves

Colyseus schemas are dynamic and callback-driven. This utility allows
you to:

-   Convert schema definitions into strongly typed reactive models
-   Automatically wrap primitive fields into `tink.state.State<T>`
-   Automatically convert schema collections into:
    -   `ObservableArray<T>`
    -   `ObservableMap<String, T>`
-   Recursively generate nested observable structures
-   Remove manual boilerplate

It is intended for macro-driven model generation layers.

------------------------------------------------------------------------

# Core Capabilities

## 1. Extract Schema Fields

Reads public fields with `@:type` metadata.

``` haxe
var fields = SchemaTypeUtils.extractSchemaFields(schemaType);
```

Each field produces:

``` haxe
{
  name: String,
  schemaTypeInfo: { kind:String, subType:Null<String> },
  haxeType: Type
}
```

------------------------------------------------------------------------

## 2. Analyze Field Type

Determines:

-   What observable wrapper to use
-   What default value to assign
-   Whether it's a schema collection

``` haxe
var info = SchemaTypeUtils.analyzeFieldType(schemaField);
```

Returns:

``` haxe
{
  stateType: ComplexType,
  emptyValue: Expr,
  isSchemaCollection: Bool
}
```

Example:

For:

``` haxe
@:type("number")
public var score:Int;
```

Result:

    stateType  -> Int
    emptyValue -> 0
    wrapped as -> State<Int>

For:

``` haxe
@:type("array", "Player")
public var players:ArraySchema<Player>;
```

Result:

    stateType  -> ObservableArray<{...PlayerFields}>
    emptyValue -> new ObservableArray([])

------------------------------------------------------------------------

## 3. Build Anonymous Struct Type

Generates a nested observable structure from a schema.

``` haxe
var anonType = SchemaTypeUtils.buildAnonStructType(schemaType);
```

Example output shape:

``` haxe
{
  name: State<String>,
  score: State<Int>,
  players: ObservableArray<{ ... }>
}
```

------------------------------------------------------------------------

## 4. Build Default Initialization Expression

Creates runtime initializer for nested schema structures.

``` haxe
var initExpr = SchemaTypeUtils.buildEmptyStructExpr(schemaType);
```

Example output:

``` haxe
{
  name: new State(null),
  score: new State(0),
  players: new ObservableArray([])
}
```

------------------------------------------------------------------------

# Example Usage (Minimal Macro Example)

``` haxe
macro function buildModel(schema:Type):TypeDefinition {
  var anon = SchemaTypeUtils.buildAnonStructType(schema);
  var init = SchemaTypeUtils.buildEmptyStructExpr(schema);

  return {
    pack: ["generated"],
    name: "RoomModel",
    kind: TDClass(),
    fields: [
      {
        name: "state",
        access: [APublic],
        kind: FVar(anon, init)
      }
    ]
  };
}
```

------------------------------------------------------------------------

# Intended Architecture

Schema (Colyseus) ↓ SchemaTypeUtils (analysis) ↓ Macro-generated Model ↓
Reactive UI (tink.state / coconut / etc.)

------------------------------------------------------------------------

# Requirements

-   Haxe 4.3+
-   tink libs (tink_core, tink_state, tink_json, tink_macro)
-   Colyseus Haxe client
-   Macro context (compile-time)

------------------------------------------------------------------------

# Design Goals

-   Zero runtime reflection
-   Fully typed generated models
-   Recursive nested schema support
-   No manual observer wiring
-   Compile-time safety

------------------------------------------------------------------------

# Notes

-   Designed for use inside macro context only.
-   Does not perform runtime synchronization --- it only builds types
    and initializers.
-   Intended to be paired with a macro that wires `listen()` /
    `onChange()` logic.
