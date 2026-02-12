
# ObservableSchemaMacro Utilities for Colyseus Schemas

This document provides an overview of the `ObservableSchemaMacro` Haxe utility, which allows automatic generation of reactive `State<T>` fields and constructors for Colyseus schema classes. It explains the macro's purpose, structure, and usage examples.

---

## Overview

`ObservableSchemaMacro` is a build macro designed to simplify the creation of observable schema classes. It automatically generates:

- Typed `State<T>` fields for primitive and serialized schema fields.
- Proper initialization of observable fields.
- A default constructor.

This eliminates repetitive boilerplate when creating reactive schema-based models.

### Key Features

- Generates `tink.state.State<T>` fields for all schema fields.
- Handles primitive, serialized, and schema collection fields.
- Automatically provides default empty values.
- Adds a public constructor for the observable schema class.
- Supports debugging with `#if debug_macro`.

### Dependencies

- Haxe 4.x
- `io.colyseus.serializer.schema` (Colyseus Schema)
- `tink.state` and `tink.macro`

---

## Usage

### Applying the Macro

```haxe
import io.colyseus.tools.ObservableSchemaMacro;

@:build(ObservableSchemaMacro.build(MySchema))
class MyObservableSchema {
}
```

This automatically generates observable fields for each schema property in `MySchema`.

### Generated Fields Example

Given a schema:

```haxe
class PlayerSchema extends Schema {
  public var score:Int;
  public var name:String;
}
```

The macro will generate an observable class equivalent to:

```haxe
class PlayerObservable {
  public final var score:tink.state.State<Int> = new tink.state.State(0);
  public final var name:tink.state.State<String> = new tink.state.State("");

  public function new() {}
}
```

### Notes

- Schema collections (arrays/maps) are generated directly as `State<T>` of the collection type.
- Primitive or serialized fields are wrapped with `tink.state.State`.
- Debugging can be enabled with `#if debug_macro`, which writes generated output to a debug file.

---

## Advantages

- Eliminates boilerplate for creating observable schema classes.
- Automatically aligns observable fields with the underlying schema.
- Supports both primitive fields and collections.
- Integrates cleanly with Colyseus schemas for reactive applications.
- Provides type safety and assigns default values to avoid NPEs at runtime

---

This macro provides a straightforward way to make Colyseus schemas reactive with `tink.state`, ensuring a consistent and type-safe structure for observable schema models.

---

**End of README**

