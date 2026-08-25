import RoomProtocolTestCase.StubConnection;
import io.colyseus.InputHandle;
import io.colyseus.RoomClock;
import io.colyseus.predict.Predict;
import io.colyseus.predict.PredictedEventChannel;
import io.colyseus.predict.PredictedSpawns;
import io.colyseus.predict.Reconciler;
import io.colyseus.predict.RollbackController;
import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.serializer.schema.Decoder;
import io.colyseus.serializer.schema.InputEncoder;
import io.colyseus.serializer.schema.Schema;

import schema.predict.ReconState;
import schema.predict.AccelInput;
import schema.predict.PassiveEnt;
import schema.predict.ReckonBall;
import schema.predict.SimPaddle;

/** Payload fixture for the typed event-channel test. */
typedef HitByFixture = { var who: String; var amount: Int; };

/**
 * Phase 4 — Predict layer.
 *
 * Scenarios mirror colyseus-0.18 PORTING/generate-predict-fixtures.cts
 * (self-verified against the JS reference). Contract:
 * PORTING/sdk-ports-predict-layer.md.
 */
class PredictTestCase extends haxe.unit.TestCase {

	private var savedNow: Void -> Float;
	private var now: Float = 0;

	override public function setup() {
		this.savedNow = RoomClock.getNow;
		this.now = 0;
		RoomClock.getNow = () -> this.now;
	}

	override public function tearDown() {
		RoomClock.getNow = this.savedNow;
	}

	private function makeHandle(command: Schema): InputHandle<Dynamic> {
		var encoder = new InputEncoder(command);
		var stub = new StubConnection();
		return @:privateAccess new InputHandle(command, encoder,
			{ stampRender: false, stampReckon: false },
			() -> (stub : io.colyseus.Connection), () -> null);
	}

	private function getBytes(arr: Array<Int>): haxe.io.Bytes {
		var bytes = haxe.io.Bytes.alloc(arr.length);
		for (i in 0...arr.length) { bytes.set(i, arr[i]); }
		return bytes;
	}

	private function assertClose(expected: Float, actual: Float, ?epsilon: Float, ?pos: haxe.PosInfos) {
		if (epsilon == null) { epsilon = 1e-9; }
		assertTrue(Math.abs(expected - actual) <= epsilon, pos);
	}

	/** Pin offset 0: one no-rtt sample at NOW == sNow makes serverNow() == getNow(). */
	private function syncedClock(sNow: Float): RoomClock {
		var clock = new RoomClock();
		this.now = sNow;
		clock.sample(sNow, -1);
		return clock;
	}

	public function testReconcilerCore() {
		var truth = new ReconState();
		var command = new AccelInput();
		var handle = makeHandle(command);
		var me = new Reconciler(truth, {
			input: handle,
			fields: ["x", "vx"],
			step: (ctx, s, cmd) -> {
				s.vx += cmd.ax * ctx.dt;
				s.x += s.vx * ctx.dt;
			},
			smoothMs: 0,
			stepMs: 50,
		});
		var state: ReconState = cast me.state;

		// server mirror: the SAME deterministic step applied to truth
		var serverStep = (ax: Float) -> {
			truth.vx += ax * 0.05;
			truth.x += truth.vx * 0.05;
		};

		// fixture trajectory (f64 bit-exact vs the JS reference)
		var expectedX = [0.025, 0.07500000000000001, 0.15000000000000002,
			0.21250000000000002, 0.2625, 0.30000000000000004];
		var expectedVx = [0.5, 1.0, 1.5, 1.25, 1.0, 0.75];

		this.now = 0; me.tick(this.now);
		var sent: Array<Float> = [];
		for (i in 1...7) {
			this.now = i * 50; me.tick(this.now);
			var ax: Float = (i <= 3) ? 10 : -5;
			sent.push(ax);
			command.ax = ax;
			handle.send();
			assertEquals(expectedX[i - 1], (state.x : Float));
			assertEquals(expectedVx[i - 1], (state.vx : Float));
			if (i >= 3) {
				// trailing ack: server processed input i-2
				serverStep(sent[i - 3]);
				@:privateAccess handle.ackInput(i - 2);
				me.tick(this.now);
			}
			assertEquals(0.0, me.lastCorrectionMag);
		}
		assertEquals(4, me.reconcileSeq);
		assertEquals(0.75, (state.vx : Float));

		// divergent truth: server-side teleport the client didn't predict
		serverStep(sent[3]);
		truth.x += 100;
		@:privateAccess handle.ackInput(5);
		this.now = 350; me.tick(this.now);
		assertClose(100, me.lastCorrectionMag);
		assertClose(-100, me.lastCorrection.get("x"));
		assertClose(100.3, state.x);
	}

	/**
	 * Derived `fields` cover STRINGS too — they ride the mirror verbatim so a
	 * step can branch on them, they never enter the numeric/pose set, and their
	 * presence disables the wire-precision reconcile skip (PORTING.md).
	 */
	public function testDerivedFieldsIncludeStrings() {
		var truth = new SimPaddle();
		truth.x = 1; truth.y = 2; truth.team = "left";
		var command = new AccelInput();
		var handle = makeHandle(command);
		var me = new Reconciler(truth, {
			input: handle,
			step: (ctx, s, cmd) -> { s.x += cmd.ax * ctx.dt; },
			smoothMs: 0,
			stepMs: 50,
		});
		var state: SimPaddle = cast me.state;

		assertEquals("left", state.team);
		assertFalse(@:privateAccess me.historyOn);
		assertEquals("x,y", me.boundRegistrations()[0].fields.join(","));

		// re-adopted on every ack, like any other mirrored field
		this.now = 0; me.tick(this.now);
		command.ax = 10; handle.send();
		truth.team = "right";
		truth.x = 1;
		@:privateAccess handle.ackInput(1);
		this.now = 50; me.tick(this.now);
		assertEquals("right", state.team);
	}

	public function testReconcilerMemoEpoch() {
		var truth = new ReconState();
		var command = new AccelInput();
		var handle = makeHandle(command);
		var computeRuns = 0;
		var me = new Reconciler(truth, {
			input: handle,
			fields: ["x"],
			step: (ctx, s, cmd) -> {
				// memo: computed once live, frozen on replay
				var bonus: Dynamic = ctx.memo(() -> {
					computeRuns++;
					return ((cmd.ax : Float) >= 2) ? (5.0 : Dynamic) : null;
				});
				s.x += cmd.ax + ((bonus != null) ? (bonus : Float) : 0.0);
			},
			smoothMs: 0,
			stepMs: 50,
		});
		var state: ReconState = cast me.state;

		this.now = 0; me.tick(this.now);
		command.ax = 1; handle.send();
		command.ax = 2; handle.send();   // memoizes 5
		command.ax = 1; handle.send();
		assertEquals(9.0, (state.x : Float));
		assertEquals(3, computeRuns);

		// ack 1 with matching truth -> adopt + replay 2..3; memo frozen
		truth.x = 1;
		@:privateAccess handle.ackInput(1);
		this.now = 50; me.tick(this.now);
		assertEquals(9.0, (state.x : Float));
		assertEquals(3, computeRuns);

		// epoch follow: handle reset -> controller self-resets from truth
		truth.x = 42;
		handle.reset();
		this.now = 100; me.tick(this.now);
		assertEquals(42.0, (state.x : Float));
		assertEquals(0, me.pendingCount);
	}

	public function testPassiveSmoothing() {
		var state = new PassiveEnt();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<PassiveEnt> = new SchemaCallbacks<PassiveEnt>(decoder);
		var clock = new RoomClock();
		clock.setPatchInterval(50);
		var predict = Predict.create(callbacks, clock);
		var ent = decoder.state;

		predict.attach(ent, {
			a: { mode: "lerp" },
			b: { mode: "damped" },
			c: { mode: "extrapolate", smoothMs: 0 },
			d: { mode: "raw" },
			yaw: { mode: "lerp", angle: true },
		});

		var patch = (sNow: Float, bytes: Array<Int>) -> {
			this.now = sNow;
			clock.sample(sNow, -1);   // offset 0 -> serverNow == now
			decoder.decode(getBytes(bytes));
		};

		patch(1000, [128, 10, 129, 10, 130, 10, 131, 10, 132, 3]);
		patch(1050, [128, 20, 129, 20, 130, 20, 131, 20, 132, 253]); // yaw -3 (±π seam)
		patch(1100, [128, 30, 129, 30, 130, 30, 131, 30]);

		// fixture reads @1150: lerp(a)=20, raw(d)=30, extrapolate(c)=40
		this.now = 1150; predict.tick(this.now);
		assertEquals(20.0, predict.value(ent, "a"));
		assertEquals(30.0, predict.value(ent, "d"));
		assertEquals(40.0, predict.value(ent, "c"));
		// angle unwrap kept the read on the ±π seam (no glide through 0)
		assertTrue(Math.abs(predict.value(ent, "yaw")) > 3);

		this.now = 1175; predict.tick(this.now);
		assertEquals(25.0, predict.value(ent, "a"));
		assertEquals(45.0, predict.value(ent, "c"));

		// idle-resume gap collapse: a idle 1100->1400 then 40; synthetic
		// held sample (1350, 30) -> 31 / 35 / 40
		patch(1400, [128, 40]);
		this.now = 1455; predict.tick(this.now);
		assertEquals(31.0, predict.value(ent, "a"));
		this.now = 1475; predict.tick(this.now);
		assertEquals(35.0, predict.value(ent, "a"));
		this.now = 1500; predict.tick(this.now);
		assertEquals(40.0, predict.value(ent, "a"));
	}

	public function testTickDefaultsToTheClock() {
		var state = new PassiveEnt();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<PassiveEnt> = new SchemaCallbacks<PassiveEnt>(decoder);
		var predict = Predict.create(callbacks, new RoomClock());
		@:privateAccess predict.adoptFixedStep(50);

		// The render time is what pins `now` to an axis; the send budget only
		// sees deltas, so a constant offset would cancel out of it unnoticed.
		this.now = 1234;
		assertEquals(0, predict.tick());        // first frame has no delta
		assertEquals(1234.0, @:privateAccess predict.renderTime);

		this.now = 1334;
		assertEquals(2, predict.tick());        // 100ms of a 50ms step
		assertEquals(1334.0, @:privateAccess predict.renderTime);
	}

	public function testReckonValueAt() {
		var state = new ReckonBall();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<ReckonBall> = new SchemaCallbacks<ReckonBall>(decoder);
		var clock = new RoomClock();
		var predict = Predict.create(callbacks, clock);
		var ball = decoder.state;

		predict.attach(ball, {
			mode: "reckon",
			fields: ["x"],
			// dt: Float is load-bearing — `attach` takes an untyped config, so an
			// inferred dt binds to Int against the Dynamic `s.vx` and a 0.01s
			// substep truncates to 0 on cpp/hl.
			step: (s: Dynamic, dt: Float, _elapsed: Float) -> { s.x += s.vx * dt; },
			smoothMs: 0,   // raw projection
			substep: 10,
		});

		// patch: x=100 vx=50 stamped sNow=1000 (offset 0 -> serverNow == now)
		this.now = 1000;
		clock.sample(1000, -1);
		decoder.decode(getBytes([128, 100, 129, 50]));

		// fixture: 1000->100, 1050->102.5, 1100->105, 1200->110
		var traj = [[1000.0, 100.0], [1050.0, 102.5], [1100.0, 105.0], [1200.0, 110.0]];
		for (pair in traj) {
			this.now = pair[0];
			predict.tick(this.now);
			assertClose(pair[1], predict.value(ball, "x"));
		}

		// valueAt: arbitrary instant raw; the past clamps to the snapshot
		assertClose(107.5, predict.valueAt(ball, "x", 1150));
		assertClose(100, predict.valueAt(ball, "x", 900));
	}

	public function testEventChannelSettlement() {
		var clock = syncedClock(1000);

		var log: Array<String> = [];
		var unpredicted = 0;
		var chan = new PredictedEventChannel({
			onPredict: (p) -> log.push("P:" + p),
			onConfirm: (p) -> log.push("C:" + p),
			onReject: (p) -> log.push("R:" + p),
			onUnpredicted: (_key) -> unpredicted++,
			graceTicks: 3,
		}, clock);

		chan.predict("goal-a");
		assertEquals(1, chan.pendingCount);
		assertEquals(1, chan.confirm("goal-a"));
		assertEquals(0, chan.confirm("goal-b"));
		assertEquals(1, unpredicted);

		// pending dedupe
		chan.predict("kill-1");
		chan.predict("kill-1");
		assertEquals(1, chan.pendingCount);

		// sim-born entry with grace auto-reject
		var acked = 10;
		chan.predictFromSim(12, "kill-2", () -> acked);
		assertEquals(2, chan.pendingCount);
		acked = 14;
		chan.prune();
		assertTrue(chan.has("kill-2"));
		acked = 15;   // >= 12 + 3 -> auto-reject
		chan.prune();
		assertFalse(chan.has("kill-2"));

		// UI-born TTL: rtt 0 -> 600ms
		this.now = 1601;
		chan.prune();
		assertEquals(0, chan.pendingCount);

		assertEquals("P:goal-a|C:goal-a|P:kill-1|P:kill-2|R:kill-2|R:kill-1",
			log.join("|"));
	}

	/**
	 * `channel.predict()` is the UI-born form; reaching it from inside a step
	 * that is being RE-simulated would mint a fresh entry per replay. The
	 * reference backstops it, and the warning is the one place `label` earns
	 * its keep.
	 */
	public function testChannelPredictIsIgnoredDuringReplay() {
		var traced: Array<String> = [];
		var savedTrace = haxe.Log.trace;
		haxe.Log.trace = (value: Dynamic, ?_infos: haxe.PosInfos) -> traced.push(Std.string(value));

		var fired = 0;
		var chan: PredictedEventChannel<String> = new PredictedEventChannel({
			label: "hit",
			uniqueBy: (p) -> p,
			onPredict: (_p) -> fired++,
		}, new RoomClock());

		chan.predict("a");
		assertEquals(1, fired);

		// as if a controller were mid-rollback
		@:privateAccess RollbackController._replayDepth = 1;
		chan.predict("b");
		chan.predict("c");
		@:privateAccess RollbackController._replayDepth = 0;
		haxe.Log.trace = savedTrace;

		assertEquals(1, fired);
		assertEquals(1, chan.pendingCount);
		// warned once, and named the channel
		assertEquals(1, traced.length);
		assertTrue(traced[0].indexOf("\"hit\"") > -1);

		// ...and the gate lifts again
		chan.predict("d");
		assertEquals(2, fired);
	}

	/** The replay flag is raised by a real rollback, not just by tests. */
	public function testIsReplayingTracksTheRollbackWindow() {
		var truth = new ReconState();
		var command = new AccelInput();
		var handle = makeHandle(command);
		var duringStep: Array<Bool> = [];
		var me = new Reconciler(truth, {
			input: handle,
			fields: ["x"],
			step: (_ctx, s, cmd) -> {
				duringStep.push(RollbackController.isReplaying());
				s.x += cmd.ax;
			},
			smoothMs: 0,
			stepMs: 50,
		});

		this.now = 0; me.tick(this.now);
		command.ax = 1; handle.send();
		command.ax = 1; handle.send();
		assertEquals("false,false", duringStep.join(","));

		// ack 1 with DIVERGENT truth (a matching one takes the wire-precision
		// skip and never rolls back) -> input 2 replays, and only that step
		// sees the flag
		duringStep = [];
		truth.x = 5;
		@:privateAccess handle.ackInput(1);
		this.now = 50; me.tick(this.now);
		assertEquals("true", duringStep.join(","));
		assertFalse(RollbackController.isReplaying());
	}

	/**
	 * Payload typing, locked in: annotating the first callback's parameter
	 * binds T for the whole channel. The compile IS the test — `h.amount` and
	 * the `predict()` argument below only check against a real `HitBy`.
	 */
	public function testChannelPayloadTypeBindsFromTheFirstCallback() {
		var seen = "";
		var chan = new PredictedEventChannel({
			label: "hit",
			uniqueBy: (h:HitByFixture) -> h.who,
			onPredict: (h) -> seen = h.who + ":" + h.amount,
		}, new RoomClock());

		chan.predict({ who: "a", amount: 2 });
		assertEquals("a:2", seen);
		assertEquals(1, chan.pendingCount);
	}

	public function testSpawnsCorrelation() {
		var clock = syncedClock(1000);

		var rejected: Array<Int> = [];
		var store = new PredictedSpawns({
			owned: (s) -> s.owner == "me",
			spawnTime: (s) -> s.bornMs,
			step: (l, dt) -> { l[0] += 10 * dt; },
			onReject: (_l, id) -> rejected.push(id),
		}, clock);

		var localRocket: Array<Float> = [0];
		var h1 = store.spawn(localRocket);
		assertEquals(1, h1.id);

		// pending local steps on the serverNow axis: 1000->1100 = dt 0.1 -> +1
		store.tick(0);
		this.now = 1100;
		store.tick(0);
		assertClose(1, localRocket[0]);

		// fifo match + lead = bornMs - at = 1080 - 1000
		var server1 = { owner: "me", bornMs: 1080.0 };
		store.handleAdd(server1);
		var e1 = store.entryFor(server1);
		assertEquals(1, e1.id);
		assertTrue(e1.confirmed);
		assertEquals(80.0, e1.leadMs);

		// foreign entity: never consumes a prediction
		var server2 = { owner: "them", bornMs: 1090.0 };
		store.handleAdd(server2);
		assertEquals(0.0, store.entryFor(server2).leadMs);
		assertEquals(null, store.entryFor(server2).local);

		// mispredict prune: unmatched pending, TTL 600
		var h2 = store.spawn(([0.0] : Array<Float>));
		this.now = 1701;
		store.prune();
		assertEquals(1, rejected.length);
		assertEquals(h2.id, rejected[0]);
		assertFalse(store.alive(h2.id));

		// remove drops the confirmed entry
		store.handleRemove(server1);
		assertFalse(store.alive(1));
		assertEquals(1, store.size);
	}
}
