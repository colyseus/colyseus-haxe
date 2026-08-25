package io.colyseus.predict;

/**
 * Reconcile-drift telemetry (port of the JS SDK's `predict/drift.ts`).
 * Fed one |correction| magnitude per reconcile; `ema` tracks the trend,
 * `peak` decays 10%/reconcile so isolated spikes read as jitter.
 */
class Drift {
	public var ema: Float = 0;
	public var peak: Float = 0;

	public function new() {}

	public function update(mag: Float) {
		this.ema += (mag - this.ema) * 0.1;
		this.peak = Math.max(mag, this.peak * 0.9);
	}

	/** "matched" | "jitter" (spiky but not trending) | "diverging" (trending). */
	public function classify(?tolerance: Float): String {
		var floor = (tolerance != null && tolerance > 1e-3) ? tolerance : 1e-3;
		if (this.ema >= floor) { return "diverging"; }
		if (this.peak >= floor) { return "jitter"; }
		return "matched";
	}

	public function reset() {
		this.ema = 0;
		this.peak = 0;
	}
}
