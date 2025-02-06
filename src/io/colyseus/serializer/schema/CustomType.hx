package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;

/**
 * Custom types (ArraySchema, MapSchema, etc.)
 */
class CustomType {
  public static var instance: CustomType = new CustomType();
  public static function getInstance() { return instance; }

  public var types:Array<String> = [];
  private var customTypes: Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

  public function new() {
    this.set("array", ArraySchemaImpl);
    this.set("map", MapSchema);
  }

  public function set(id: String, type: Dynamic) {
    if (!this.customTypes.exists(id)) {
        this.customTypes.set(id, type);
        this.types.push(id);
    }
  }

  public function get(id: String) {
    return this.customTypes.get(id);
  }

  public function getTypes() {
    var customTypes: Array<String> = [];

    for (key in this.customTypes.keys()) {
      customTypes.push(key);
    }

    return customTypes;
  }
}