package io.colyseus;

/**
 * Per-room clock-sync + RTT estimator, fed by the `ProtocolModifier.TIMED`
 * prefix the server prepends to state messages when the room declared input
 * via `defineInput()`. Port of the JS SDK's `RoomClock.ts` (RoomClockImpl) —
 * pure math, no transport/schema knowledge.
 *
 * Two independent estimates:
 * - **Clock offset** (`serverNow()`): server-clock-ms-since-room-start minus
 *   local clock. Seeded by the first sample, then EMA-smoothed — offset
 *   updates are GATED to low-jitter packets (RTT within 1.2× the 10s
 *   windowed-minimum RTT), except during a 30-sample post-reset warmup.
 * - **RTT** (`rtt()` / `smoothedRtt()`): fed by the input ack round-trip.
 *   Seeded by the first valid sample; outliers (> 4× smoothed) rejected.
 *
 * A room that never declares input simply never receives TIMED samples: the
 * clock then reports `serverNow() == now()` and zeros — no separate stub
 * class needed.
 */
class RoomClock {
	/** Injectable monotonic ms clock (tests replace this). */
	public static dynamic function getNow(): Float {
		return haxe.Timer.stamp() * 1000;
	}

	private static inline var EMA_ALPHA = 0.1;
	private static inline var RENDER_TAU = 250.0;
	private static inline var RENDER_SNAP = 250.0;
	private static inline var RTT_OUTLIER_X = 4.0;
	private static inline var JITTER_GAIN = 1.0 / 16.0;
	private static inline var JITTER_STALL_X = 4;
	private static inline var RTT_GATE_FACTOR = 1.2;
	private static inline var RTT_GATE_WINDOW = 10000.0;
	private static inline var RTT_GATE_WARMUP = 30;

	private var _clockOffset: Float = 0;
	private var _clockHasSample: Bool = false;
	private var _offsetCount: Int = 0;

	// sliding-window-minimum deque (parallel arrays; front = windowed min)
	private var _rttFloorT: Array<Float> = [];
	private var _rttFloorV: Array<Float> = [];

	private var _rtt: Float = 0;
	private var _smoothedRtt: Float = 0;
	private var _rttHasSample: Bool = false;

	private var _jitter: Float = 0;
	private var _lastRecvTime: Float = -1;

	private var _lastServerTime: Float = 0;
	private var _patchInterval: Float = 0;

	private var _renderTau: Float = RENDER_TAU;
	private var _renderSn: Float = 0;
	private var _renderSnAt: Float = 0;

	public function new() {}

	/** Local monotonic clock (ms) — the un-offset base `serverNow()` builds on. */
	public function now(): Float {
		return RoomClock.getNow();
	}

	/** Estimated server clock: ms since room start (`clock.elapsedTime`
	 *  reconstructed via the wire `sNow` + local offset). Returns the local
	 *  clock until the first sample lands. */
	public function serverNow(): Float {
		return RoomClock.getNow() + this._clockOffset;
	}

	/**
	 * Server clock on a SLEW-LIMITED render timeline: free-runs at 1 ms/ms and
	 * servos toward `serverNow()` (τ ≈ 250 ms), snapping past gaps > 250 ms.
	 * Use for DRAWING remote entities (strips per-patch offset wobble); never
	 * for hit stamps / server-stamped deadlines.
	 */
	public function renderNow(): Float {
		var target = this.serverNow();
		if (this._renderTau <= 0) { return target; }
		var t = RoomClock.getNow();
		if (this._renderSn == 0) { this._renderSn = target; this._renderSnAt = t; return this._renderSn; }
		var dt = Math.min(t - this._renderSnAt, 100); // clamp tab-resume stalls
		if (dt < 0.5) { return this._renderSn; }       // same frame — advance once
		this._renderSnAt = t;
		this._renderSn += dt;                          // free-run at 1 ms/ms
		if (Math.abs(target - this._renderSn) > RENDER_SNAP) { this._renderSn = target; return this._renderSn; }
		this._renderSn += (target - this._renderSn) * (1 - Math.exp(-dt / this._renderTau));
		return this._renderSn;
	}

	/** Set the `renderNow` slew time-constant (ms); `<= 0` disables slewing. */
	public function setRenderTau(milliseconds: Float) {
		this._renderTau = (milliseconds > 0) ? milliseconds : 0;
	}

	/** Most recent RTT sample (ms); `0` until the first valid sample. */
	public function rtt(): Float {
		return this._rtt;
	}

	/** EMA-smoothed RTT (ms); prefer for forward-prediction. */
	public function smoothedRtt(): Float {
		return this._smoothedRtt;
	}

	/** RFC 3550-style interarrival jitter (ms) vs the advertised patch cadence. */
	public function jitter(): Float {
		return this._jitter;
	}

	/** Raw `sNow` of the last TIMED sample — the snapshot's server-encode time.
	 *  `serverNow() − lastServerTime()` = the snapshot's age. */
	public function lastServerTime(): Float {
		return this._lastServerTime;
	}

	/** Server snapshot cadence (`patchRate`, ms); `0` until advertised. */
	public function patchInterval(): Float {
		return this._patchInterval;
	}

	/** Feed the advertised patch cadence (ms) from the input handshake. */
	public function setPatchInterval(milliseconds: Float) {
		this._patchInterval = (milliseconds > 0) ? milliseconds : 0;
	}

	/**
	 * Feed a decoded TIMED sample: `sNow` (ms since room start) updates the
	 * clock offset; `rttSample` (ms round-trip from the input ack, `< 0` if
	 * none this packet) updates the RTT estimate.
	 */
	public function sample(sNow: Float, rttSample: Float) {
		var tNow = RoomClock.getNow();
		var a = EMA_ALPHA;

		// jitter vs the cadence — idle patches round to a whole multiple;
		// bursts (mult 0) and stalls (mult > 4) are skipped
		var PI = this._patchInterval;
		if (this._lastRecvTime >= 0 && PI > 0) {
			var gap = tNow - this._lastRecvTime;
			var mult = Math.round(gap / PI);
			if (mult >= 1 && mult <= JITTER_STALL_X) {
				this._jitter += (Math.abs(gap - mult * PI) - this._jitter) * JITTER_GAIN;
			}
		}
		this._lastRecvTime = tNow;

		this._lastServerTime = sNow;

		// reject impossible / outlier RTT (tab-resume spikes once converged)
		if (rttSample < 0) {
			rttSample = -1;
		} else if (this._smoothedRtt > 0 && rttSample > this._smoothedRtt * RTT_OUTLIER_X) {
			rttSample = -1;
		}

		// offset: prefer the RTT-corrected estimate when a fresh sample exists
		var offsetSample = (rttSample >= 0) ? sNow + rttSample / 2 - tNow : sNow - tNow;
		if (!this._clockHasSample) {
			this._clockOffset = offsetSample;
			this._clockHasSample = true;
			if (rttSample >= 0) { this.pushRttFloor(rttSample, tNow); this._offsetCount = 1; }
		} else if (rttSample >= 0) {
			// gate on the windowed-min RTT floor — except during post-reset warmup
			var floor = this.pushRttFloor(rttSample, tNow);
			var warming = this._offsetCount < RTT_GATE_WARMUP;
			this._offsetCount++;
			if (warming || rttSample <= floor * RTT_GATE_FACTOR) {
				this._clockOffset = this._clockOffset * (1 - a) + offsetSample * a;
			}
		}

		// RTT: seeded on the first valid sample (separate flag from the offset seed)
		if (rttSample >= 0) {
			this._rtt = rttSample;
			if (!this._rttHasSample) {
				this._smoothedRtt = rttSample;
				this._rttHasSample = true;
			} else {
				this._smoothedRtt = this._smoothedRtt * (1 - a) + rttSample * a;
			}
		}
	}

	/** Push an RTT sample into the sliding-window-min deque; returns the floor. */
	private function pushRttFloor(rttSample: Float, tNow: Float): Float {
		var T = this._rttFloorT, V = this._rttFloorV;
		while (V.length > 0 && V[V.length - 1] >= rttSample) { V.pop(); T.pop(); }
		V.push(rttSample); T.push(tNow);
		var cutoff = tNow - RTT_GATE_WINDOW;
		while (T.length > 0 && T[0] < cutoff) { T.shift(); V.shift(); }
		return V[0];
	}

	/** Reset all state (reconnect). τ and patchInterval are config — they survive. */
	public function reset() {
		this._clockOffset = 0;
		this._clockHasSample = false;
		this._offsetCount = 0;
		this._rtt = 0;
		this._smoothedRtt = 0;
		this._rttHasSample = false;
		this._jitter = 0;
		this._lastRecvTime = -1;
		this._lastServerTime = 0;
		this._rttFloorT = [];
		this._rttFloorV = [];
		this._renderSn = 0;
		this._renderSnAt = 0;
	}
}
