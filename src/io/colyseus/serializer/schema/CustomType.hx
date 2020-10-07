package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.ArraySchema;
import io.colyseus.serializer.schema.types.MapSchema;

/**
 * Reflection
 */
class CustomType {
  public static var instance: CustomType = new CustomType();
  public static function getInstance() { return instance; }

  private var types: Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();
  public function new() {
    this.types.set("array", ArraySchema);
    this.types.set("map", MapSchema);
  }

  public function set(id: String, type: Dynamic) {
    this.types.set(id, type);
  }

  public function get(id: String) {
    return this.types.get(id);
  }
}