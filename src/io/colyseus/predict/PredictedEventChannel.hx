package io.colyseus.predict;

import io.colyseus.RoomClock;
import io.colyseus.predict.Predict.DrivenChild;
import io.colyseus.predict.RollbackController.PredictSink;

/** Options for `PredictedEventChannel`. */
typedef EventChannelOptions = {
	/** The optimistic feedback — fires the moment the event is predicted. */
	@:optional var onPredict: Dynamic -> Void;
	/** The prediction was wrong — undo the optimistic feedback. */
	@:optional var onReject: Dynamic -> Void;
	/** The server agreed (fired by `confirm`, once per settled entry). */
	@:optional var onConfirm: Dynamic -> Void;
	/** A confirm settled NOTHING — the signal arrived unpredicted. */
	@:optional var onUnpredicted: Dynamic -> Void;
	/** Entry identity — payloads mapping to the same value dedupe while
	    pending. Null: string/number payloads key themselves; other payloads
	    share one anonymous slot. */
	@:optional var uniqueBy: Dynamic -> Dynamic;
	/** Sim-born settlement deadline in input ticks (default 10). */
	@:optional var graceTicks: Null<Int>;
	/** UI-born eviction window (ms); null = max(2·rtt, 600). */
	@:optional var ttlMs: Null<Float>;
	/** Min gap (ms) between onPredict fires; null = off. */
	@:optional var cooldownMs: Null<Float>;
}

private class EventEntry {
	public var key: Dynamic;
	public var payload: Dynamic;
	public var seq: Int;
	public var acked: Void -> Int;
	public var at: Float;
	public function new() {}
}

/**
 * Typed optimistic-event channel (port of the JS SDK's
 * `predict/predictedEventChannel.ts`): birth in the predicted sim
 * (`ctx.predict(channel, payload)` — live-only, replay-safe) or from UI
 * (`predict(payload)`); settlement: `confirm()` on the authoritative signal,
 * sim-born grace-tick auto-reject, UI-born wall-clock TTL.
 */
class PredictedEventChannel implements PredictSink implements DrivenChild {
	public var dead(default, null): Bool = false;
	public var pendingCount(get, never): Int;
	function get_pendingCount() return this.entries.length;

	// one anonymous slot for payloads with no derivable key
	private static var SINGLETON_KEY: Dynamic = {};

	private var opts: EventChannelOptions;
	private var clock: RoomClock;
	// pending entries in insertion order (settle-all order); few at a time
	private var entries: Array<EventEntry> = [];
	private var cooldownUntil: Float = Math.NEGATIVE_INFINITY;

	public function new(options: EventChannelOptions, clock: RoomClock) {
		this.opts = (options != null) ? options : {};
		this.clock = clock;
	}

	private function now(): Float {
		return (this.clock != null) ? this.clock.serverNow() : RoomClock.getNow();
	}

	private function keyOf(payload: Dynamic): Dynamic {
		if (this.opts.uniqueBy != null) { return this.opts.uniqueBy(payload); }
		if (Std.isOfType(payload, String) || Std.isOfType(payload, Float)) { return payload; }
		return SINGLETON_KEY;
	}

	private function entryAt(key: Dynamic): Int {
		for (i in 0...this.entries.length) {
			if (this.entries[i].key == key) { return i; }
		}
		return -1;
	}

	/** Sim-born prediction (reached via `ctx.predict` — live steps only). */
	public function predictFromSim(seq: Int, payload: Dynamic, acked: Void -> Int) {
		this.add(seq, payload, acked);
	}

	/** Predict from OUTSIDE the sim (UI-optimistic; wall-clock TTL). */
	public function predict(payload: Dynamic) {
		this.add(-1, payload, null);
	}

	private function add(seq: Int, payload: Dynamic, acked: Void -> Int) {
		var key = this.keyOf(payload);
		if (this.entryAt(key) != -1) { return; } // pending dedupe
		var t = this.now();
		if (this.opts.cooldownMs != null && this.opts.cooldownMs > 0) {
			if (t < this.cooldownUntil) { return; }
			this.cooldownUntil = t + this.opts.cooldownMs;
		}
		var entry = new EventEntry();
		entry.key = key;
		entry.payload = payload;
		entry.seq = seq;
		entry.acked = acked;
		entry.at = t;
		this.entries.push(entry);
		if (this.opts.onPredict != null) { this.opts.onPredict(payload); }
	}

	/** Is a prediction pending? Null key = any. */
	public function has(?key: Dynamic): Bool {
		if (key == null) { return this.entries.length > 0; }
		return this.entryAt(key) != -1;
	}

	private function takeKeys(key: Dynamic): Array<Dynamic> {
		if (key != null) { return [key]; }
		return [for (entry in this.entries) entry.key];
	}

	private function removeEntry(key: Dynamic): EventEntry {
		var i = this.entryAt(key);
		if (i == -1) { return null; }
		return this.entries.splice(i, 1)[0];
	}

	/**
	 * The server agreed: settle the entry for `key` (null = EVERY pending
	 * entry). The entry is removed BEFORE onConfirm fires. Returns the count;
	 * 0 fires onUnpredicted.
	 */
	public function confirm(?key: Dynamic): Int {
		var settled = 0;
		for (k in this.takeKeys(key)) {
			var entry = this.removeEntry(k);
			if (entry == null) { continue; }
			if (this.opts.onConfirm != null) { this.opts.onConfirm(entry.payload); }
			settled++;
		}
		if (settled == 0 && this.opts.onUnpredicted != null) {
			this.opts.onUnpredicted(key);
		}
		return settled;
	}

	/** The server overruled: reject (null key = every pending). Fires onReject. */
	public function reject(?key: Dynamic): Int {
		var rejected = 0;
		for (k in this.takeKeys(key)) {
			var entry = this.removeEntry(k);
			if (entry == null) { continue; }
			if (this.opts.onReject != null) { this.opts.onReject(entry.payload); }
			rejected++;
		}
		return rejected;
	}

	/** Drop every pending entry SILENTLY (no callbacks). */
	public function clear() {
		this.entries = [];
	}

	public function tick(_now: Float) {}

	/** Sim-born grace auto-rejects first, then wall-clock TTL (UI-born only —
	    sim-born entries settle by server progress, not wall time). */
	public function prune() {
		var grace = (this.opts.graceTicks != null) ? this.opts.graceTicks : 10;
		for (entry in this.entries.copy()) {
			if (entry.acked != null && entry.acked() >= entry.seq + grace) {
				this.removeEntry(entry.key);
				if (this.opts.onReject != null) { this.opts.onReject(entry.payload); }
			}
		}
		var rtt: Float = (this.clock != null) ? this.clock.smoothedRtt() : 0;
		var ttl: Float = (this.opts.ttlMs != null && this.opts.ttlMs > 0)
			? this.opts.ttlMs : Math.max(rtt * 2, 600);
		var t = this.now();
		for (entry in this.entries.copy()) {
			if (entry.acked != null) { continue; } // sim-born: progress-settled
			if (t - entry.at > ttl) {
				this.removeEntry(entry.key);
				if (this.opts.onReject != null) { this.opts.onReject(entry.payload); }
			}
		}
	}

	/** Stop being driven and drop all entries (silently). */
	public function dispose() {
		this.dead = true;
		this.clear();
	}
}
