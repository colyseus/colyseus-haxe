# SchemaListenMacro Utilities for Colyseus Schemas

This document provides an overview of the `SchemaListenMacro` Haxe utility, which helps you synchronize Colyseus Schema objects with reactive listeners using `tink.state` observables. It explains its structure, capabilities, and provides usage examples.

---

## Overview

`SchemaListenMacro` is a Haxe macro designed to automatically generate listeners for Colyseus Schema objects. These listeners allow you to react to changes in schema fields, including nested schemas, arrays, and maps, without manually writing boilerplate code. Should be used together with `ObservableSchemaMacro` that generates required fields that are bound to listeners.

### Key Features

- **Automatic listener generation** for all schema fields.
- Supports **primitives, serialized strings, references, arrays, and maps**.
- Handles **nested schemas recursively**.
- Uses `tink.state.Observable` for reactive state and assigns default non-null values where possible.
- Ensures **safe depth-limited recursion** to prevent infinite loops; still you should avoid referencing parent schemas in inner schemas.

### Dependencies

- Haxe 4.x
- `io.colyseus.serializer.schema` (Colyseus Schema)
- `tink.state` and `tink.macro`
- Optional: `tink.json` for serialized string parsing

---

## Field Classification

`SchemaListenMacro` classifies schema fields into several kinds:

| Kind | Description |
|------|-------------|
| `FPrimitive` | Primitive type (number, boolean) |
| `FStringSerialized` | String that should be parsed with `tink.Json` |
| `FRef(inner)` | Reference to another schema type |
| `FArrayPrimitive` | Array of primitive types |
| `FArraySchema(inner)` | Array of schema objects |
| `FMapPrimitive` | Map with primitive values |
| `FMapSchema(inner)` | Map with schema object values |

---

## Usage

See full example in [MainExample](./MainExample.hx) and how to run it in main [README](./README.md)

---

## Advanced Notes

- Maximum recursion depth is defined by `MAX_DEPTH` (default 100).
- JSON serialized strings are automatically parsed using `tink.Json.parse`.
- Fine-grained `onAdd`/`onRemove` is only generated for ArraySchema/MapSchema of schemas; primitive arrays/maps are fully rebuilt on any change.
- Schema replacements for array/map items are not fully supported; full rebuild is used instead.

---

## Debugging

Enable `#if debug_macro` to output intermediate macro expressions for inspection:
```haxe
#if debug_macro
SchemaTypeUtils.writeExprToFile('ListenDebug', ret);
#end
```

---

This utility drastically reduces boilerplate for keeping UI or reactive state in sync with Colyseus schemas, especially for complex nested structures.

---