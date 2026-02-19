# Colyseus Schema Observability Tooling

This repository provides a set of Haxe macros and utilities for creating reactive Colyseus schema models. The tooling enables automatic generation of observable fields, synchronization listeners, and type-safe state management using `tink.state`.

---

## Purpose

The tooling is designed to simplify the integration of Colyseus schemas with reactive Haxe applications by:

- Automatically generating observable fields (`State<T>`).
- Creating listeners for primitive, serialized, and nested schema fields.
- Handling collections (`ArraySchema` and `MapSchema`) with fine-grained change detection.
- Reducing boilerplate and ensuring type safety.

It is intended for developers building real-time applications who want fully reactive schema models without manual listener management.

---

## Components

1. **SchemaListenMacro**
   - Automatically generates `listen`, `onAdd`, `onRemove` listeners for schema fields.
   - Supports nested schemas, arrays, and maps.
   - See [SchemaListenMacro README](./SchemaListenMacro_README.md) for details and examples.

2. **ObservableSchemaMacro**
   - Generates typed `State<T>` fields and a constructor for schema classes.
   - Works via `@:build(ObservableSchemaMacro.build(SchemaClass))`.
   - See [ObservableSchemaMacro README](./ObservableSchemaMacro_README.md) for usage examples.

3. **SchemaTypeUtils**
   - Provides helpers for type extraction, field analysis, struct generation, and collection management.
   - Supports JSON parsing, inner type resolution, and default value generation.
   - Intended as the internal utility layer for macros.
   - See [SchemaTypeUtils README](./SchemaTypeUtils_README.md) for details.

---

## Getting Started

1. Add the tooling package to your Haxe project.
2. Use `ObservableSchemaMacro` to generate reactive schema classes.
3. Use `SchemaListenMacro` to synchronize schema instances with reactive state.
4. Refer to the individual READMEs for detailed usage examples.
5. **Note** that even though observables can be used as is, their full reactive potential can be unlocked with [coconut.data](https://github.com/MVCoconut/coconut.data) Models. 

---

## Example Use Case
The following command would generate the example code located in `MainExample`

`haxe -cp example -cp src -main tools.MainExample -js out/main.js -lib tink_json -lib tink_state -lib tink_http -lib colyseus-websocket -D no-deprecation-warnings -D js-es=6 -D debug_macro`

Inspect the output:
- `GameSchemaDebug` - generated fields
- `ListenDebug` - generated listeners 
- `out/main.js` - look for `io_colyseus_tools_GameObservable` to inspect the generated code

```
---

**Note:** This tooling assumes Haxe 4.x, Colyseus Schema, and `tink.state` (and optionally `tink.json`) are available in your project.