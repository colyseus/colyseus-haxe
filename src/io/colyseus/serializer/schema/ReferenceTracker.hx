package io.colyseus.serializer.schema;

import io.colyseus.serializer.schema.types.ISchemaCollection;

class ReferenceTracker {
	public var refs:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var refCounts:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var deletedRefs:Map<Int, Bool> = new Map<Int, Bool>();

    // FIXME:
    // - use function/delegate instead of Dynamic as value.
    // - use Either<Int,String> as key
	public var callbacks:Map<Int, Map<String, Array<Dynamic>>> = new Map<Int, Map<String, Array<Dynamic>>>();

	public function new() {}

	public function add(refId:Int, ref:Dynamic, incrementCount:Bool = true) {
		this.refs.set(refId, ref);

		if (incrementCount) {
			var previousCount = (!this.refCounts.exists(refId))
                ? 0
                : this.refCounts.get(refId);

			this.refCounts.set(refId, previousCount + 1);
		}

        if (this.deletedRefs.exists(refId)) {
            this.deletedRefs.remove(refId);
        }
	}

	public function has(refId:Int) {
		return this.refs.exists(refId);
	}

	public function get(refId:Int) {
		return this.refs.get(refId);
	}

	public function remove(refId:Int) {
		this.refCounts.set(refId, this.refCounts.get(refId) - 1);

		if (!this.deletedRefs.exists(refId)) {
			this.deletedRefs.set(refId, true);
			return true;
		}

		return false;
	}

	public function count() {
		return Lambda.count(this.refs);
	}

	public function garbageCollection() {
		var deletedRefs = new Array<Int>();

		for (refId in this.deletedRefs.keys()) {
			deletedRefs.push(refId);
		}

		for (refId in deletedRefs) {
			if (this.refCounts[refId] <= 0) {
				var ref = this.refs[refId];

				if (Std.isOfType(ref, Schema)) {
					var childTypes = (ref : Schema)._childTypes;
					for (fieldIndex in childTypes.keys()) {
						var refId = Reflect.getProperty((ref : Schema).getByIndex(fieldIndex), "__refId");
						if (refId > 0 && this.remove(refId)) {
							deletedRefs.push(refId);
						}
					}
				} else if (!Std.isOfType(ref._childType, String)) {
					for (item in (ref : ISchemaCollection)) {
						var childRefId = Reflect.getProperty(item, "__refId");
						if (childRefId > 0 && this.remove(childRefId)) {
							deletedRefs.push(childRefId);
						}
					}
				}

				this.refs.remove(refId);
				this.refCounts.remove(refId);
				this.callbacks.remove(refId);
			}
		}

		this.deletedRefs.clear();
	}

	public function clear() {
		this.refs.clear();
		this.refCounts.clear();
        this.callbacks.clear();
		this.deletedRefs.clear();
	}
}
