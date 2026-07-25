package io.colyseus.predict;

import io.colyseus.RoomClock;
import io.colyseus.predict.Predict.DrivenChild;

/** Options for `PredictedSpawns`. */
typedef SpawnsOptions = {
	/** Which incoming server entities are this client's to correlate
	    (null = every entity). */
	@:optional var owned: Dynamic -> Bool;
	/** Pairing predicate; null = fifo (oldest pending). */
	@:optional var correlate: (local: Dynamic, server: Dynamic) -> Bool;
	/** Server-clock spawn instant of an authoritative entity — enables the
	    measured input lead. */
	@:optional var spawnTime: Dynamic -> Float;
	/** Advance a pending local each tick (dt seconds, serverNow axis). */
	@:optional var step: (local: Dynamic, dt: Float) -> Void;
	/** Eviction window (ms) given the current rtt; null = max(2·rtt, 600). */
	@:optional var ttl: Float -> Float;
	/** Invoked when a prediction is dropped as a mispredict. */
	@:optional var onReject: (local: Dynamic, id: Int) -> Void;
}

/** A merged logical entity — one per logical spawn. Key sprites on `id`. */
class SpawnEntry {
	public var id: Int;
	public var server: Dynamic;
	public var local: Dynamic;
	public var confirmed: Bool = false;
	/** Measured input lead (ms) — spawnTime(server) − at. */
	public var leadMs: Float = 0;
	@:allow(io.colyseus.predict.PredictedSpawns)
	private var at: Float = Math.NaN;
	@:allow(io.colyseus.predict.PredictedSpawns)
	private var accepted: Bool = false;
	@:allow(io.colyseus.predict.PredictedSpawns)
	private function new() {}
}

/**
 * Predicted-spawn store (port of the JS SDK's `predict/predictedSpawns.ts`):
 * optimistic locals live OUTSIDE the schema collection, correlated to the
 * authoritative entity on its add (fifo or predicate) and collapsed onto one
 * logical entry with a STABLE id — the handoff is invisible.
 */
class PredictedSpawns implements DrivenChild {
	public var dead(default, null): Bool = false;
	public var size(get, never): Int;
	function get_size() return this.order.length;

	private var opts: SpawnsOptions;
	private var clock: RoomClock;
	private var order: Array<SpawnEntry> = []; // insertion order = FIFO order
	private var nextId: Int = 1;
	private var lastTickAt: Float = Math.NaN;

	@:allow(io.colyseus.predict.Predict)
	private var onDisposedInternal: Void -> Void;

	public function new(options: SpawnsOptions, clock: RoomClock) {
		this.opts = (options != null) ? options : {};
		this.clock = clock;
	}

	private function now(): Float {
		return (this.clock != null) ? this.clock.serverNow() : RoomClock.getNow();
	}

	private function entryById(id: Int): SpawnEntry {
		for (entry in this.order) { if (entry.id == id) { return entry; } }
		return null;
	}

	/** Record an optimistic local spawn; returns the entry (stable id). */
	public function spawn(local: Dynamic): SpawnEntry {
		var entry = new SpawnEntry();
		entry.id = this.nextId++;
		entry.local = local;
		entry.at = this.now();
		this.order.push(entry);
		return entry;
	}

	/** Drop a still-pending prediction (no-op once confirmed). */
	public function cancel(id: Int) {
		var entry = this.entryById(id);
		if (entry != null && !entry.confirmed) { this.drop(entry); }
	}

	/** Exempt a still-pending entry from TTL eviction. */
	public function accept(id: Int) {
		var entry = this.entryById(id);
		if (entry != null) { entry.accepted = true; }
	}

	private function drop(entry: SpawnEntry) {
		this.order.remove(entry);
	}

	/** Route the collection's onAdd here. */
	public function handleAdd(server: Dynamic) {
		if (server == null || this.entryFor(server) != null) { return; }

		var owned = this.opts.owned == null || this.opts.owned(server);
		var matched: SpawnEntry = null;
		if (owned) {
			for (entry in this.order) {
				if (entry.confirmed || entry.local == null) { continue; }
				if (this.opts.correlate == null || this.opts.correlate(entry.local, server)) {
					matched = entry;
					break;
				}
			}
		}

		if (matched != null) {
			// transition IN PLACE — same id, the handoff contract
			matched.server = server;
			matched.confirmed = true;
			if (this.opts.spawnTime != null && !Math.isNaN(matched.at)) {
				matched.leadMs = this.opts.spawnTime(server) - matched.at;
			}
		} else {
			var entry = new SpawnEntry();
			entry.id = this.nextId++;
			entry.server = server;
			entry.confirmed = true;
			this.order.push(entry);
		}
	}

	/** Route the collection's onRemove here. */
	public function handleRemove(server: Dynamic) {
		var entry = this.entryFor(server);
		if (entry != null) { this.drop(entry); }
	}

	/** Advance pending locals on the serverNow axis (the same axis the lead
	    lives on — the handoff cannot jump). */
	public function tick(now: Float) {
		var t = (this.clock != null) ? this.clock.serverNow() : now;
		if (this.opts.step != null && !Math.isNaN(this.lastTickAt)) {
			var dt = Math.max(0, (t - this.lastTickAt) / 1000);
			if (dt > 0) {
				for (entry in this.order) {
					if (!entry.confirmed && entry.local != null) {
						this.opts.step(entry.local, dt);
					}
				}
			}
		}
		this.lastTickAt = t;
	}

	/** Drop pending locals older than the TTL — mispredicts. */
	public function prune() {
		if (this.order.length == 0) { return; }
		var t = this.now();
		var rtt: Float = (this.clock != null) ? this.clock.smoothedRtt() : 0;
		var ttl: Float = (this.opts.ttl != null) ? this.opts.ttl(rtt) : Math.max(rtt * 2, 600);
		for (entry in this.order.copy()) {
			if (entry.confirmed || entry.accepted || Math.isNaN(entry.at)) { continue; }
			if (t - entry.at > ttl) {
				this.drop(entry);
				if (this.opts.onReject != null) { this.opts.onReject(entry.local, entry.id); }
			}
		}
	}

	/** Iterate the merged view — exactly one entry per logical entity. */
	public function entries(): Array<SpawnEntry> {
		return this.order;
	}

	public function entryFor(server: Dynamic): SpawnEntry {
		if (server == null) { return null; }
		for (entry in this.order) { if (entry.server == server) { return entry; } }
		return null;
	}

	public function alive(id: Int): Bool {
		return this.entryById(id) != null;
	}

	/** Drop all predictions and tracked entries. */
	public function clear() {
		this.order = [];
	}

	public function dispose() {
		this.dead = true;
		if (this.onDisposedInternal != null) { this.onDisposedInternal(); }
		this.clear();
	}
}
