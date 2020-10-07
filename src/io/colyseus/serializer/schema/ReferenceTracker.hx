package io.colyseus.serializer.schema;

class ReferenceTracker {
	public var context:Context = new Context();

	public var refs:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var refCounts:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var deletedRefs:Map<Int, Bool> = new Map<Int, Bool>();

	public function new() {}
	public function add(refId:Int, ref:Dynamic, incrementCount:Bool = true) {
		this.refs.set(refId, ref);

		if (incrementCount) {
			var previousCount = (this.refCounts.exists(refId)) ? this.refCounts.get(refId) : 0;
			this.refCounts.set(refId, previousCount + 1);
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

		var addedToDeletedRefs = (this.deletedRefs.get(refId) == null);
		if (addedToDeletedRefs) {
			this.deletedRefs.set(refId, true);
		}

		return addedToDeletedRefs;
	}

	public function garbageCollection() {
		// TODO:
  }

	public function clear() {
		this.refs.clear();
		this.refCounts.clear();
		this.deletedRefs.clear();
	}
}
