package io.colyseus.serializer.schema;

class ReferenceTracker {
	public var refs:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var refCounts:Map<Int, Dynamic> = new Map<Int, Dynamic>();
	public var deletedRefs:List<Int> = new List<Int>();

	public function new() {}

	public function add(refId:Int, ref:Dynamic) {
        this.refs.set(refId, ref);

        var previousCount = (this.refCounts.exists(refId))
            ? this.refCounts.get(refId)
            : 0;
		this.refCounts.set(refId, previousCount + 1);
	}

	public function remove(refId: Int) {
        this.deletedRefs.push(refId);
		this.refCounts.set(refId, this.refCounts.get(refId) - 1);
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
