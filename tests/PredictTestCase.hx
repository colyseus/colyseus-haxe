import RoomProtocolTestCase.StubConnection;
import io.colyseus.InputHandle;
import io.colyseus.RoomClock;
import io.colyseus.predict.Predict;
import io.colyseus.predict.PredictedEventChannel;
import io.colyseus.predict.PredictedSpawns;
import io.colyseus.predict.Reconciler;
import io.colyseus.serializer.schema.Callbacks.SchemaCallbacks;
import io.colyseus.serializer.schema.Decoder;
import io.colyseus.serializer.schema.InputEncoder;
import io.colyseus.serializer.schema.Schema;

import schema.predict.ReconState;
import schema.predict.AccelInput;
import schema.predict.PassiveEnt;
import schema.predict.ReckonBall;

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

	private function makeHandle(command: Schema): InputHandle {
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
			smoothing: 0,
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
			smoothing: 0,
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

		predict.track(ent, "a", { mode: "lerp" });
		predict.track(ent, "b", { mode: "damped" });
		predict.track(ent, "c", { mode: "extrapolate", damping: 0 });
		predict.track(ent, "d", { mode: "raw" });
		predict.track(ent, "yaw", { mode: "lerp", angle: true });

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

	public function testReckonValueAt() {
		var state = new ReckonBall();
		var decoder = new Decoder(state);
		var callbacks: SchemaCallbacks<ReckonBall> = new SchemaCallbacks<ReckonBall>(decoder);
		var clock = new RoomClock();
		var predict = Predict.create(callbacks, clock);
		var ball = decoder.state;

		predict.trackReckon(ball, {
			fields: ["x"],
			step: (s, dt, _elapsed) -> { s.x += s.vx * dt; },
			smoothing: 0,   // raw projection
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
