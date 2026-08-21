import RoomProtocolTestCase.StubConnection;
import io.colyseus.InputHandle;
import io.colyseus.RoomClock;
import io.colyseus.predict.Predict;
import io.colyseus.predict.Predict.PredictCallbacks;
import io.colyseus.predict.RollbackController.PredictSink;
import io.colyseus.predict.SimReconciler;
import io.colyseus.serializer.schema.InputEncoder;
import io.colyseus.serializer.schema.Schema;

import schema.predict.AccelInput;
import schema.predict.SimPaddle;
import schema.predict.SimPuck;

/**
 * The world handle: a plain typed class, which is the shape the docblock
 * recommends and the shape the air-hockey client ships (`PredictedWorld`).
 * Both fields are replaced in place by mirrors at construction.
 */
private class World {
	public var paddle: SimPaddle;
	public var puck: SimPuck;
	public function new(paddle: SimPaddle, puck: SimPuck) {
		this.paddle = paddle;
		this.puck = puck;
	}
}

/** No field holds a schema instance, so nothing binds. */
private class OpaqueWorld {
	public var n: Float = 0;
	public function new() {}
}

/** Counts what a step declared through `ctx.predict`. */
private class CountingSink implements PredictSink {
	public var seqs: Array<Int> = [];
	public function new() {}
	public function predictFromSim(seq: Int, _payload: Dynamic, _acked: Void -> Int): Void {
		this.seqs.push(seq);
	}
}

/**
 * SimReconciler — the COMPOSITE face: world binding, mirror creation,
 * auto-adopt, pose registration.
 *
 * This class had no test at all, which is how the string-field bug survived:
 * `isScalarType` excluded "string" alongside ref/array/map, so a mirror kept
 * the class default forever while the decoded instance carried the real
 * value. A step branching on it silently simulated the wrong thing.
 */
class SimReconcilerTestCase extends haxe.unit.TestCase {

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

	private function assertClose(expected: Float, actual: Float, ?epsilon: Float, ?pos: haxe.PosInfos) {
		if (epsilon == null) { epsilon = 1e-9; }
		assertTrue(Math.abs(expected - actual) <= epsilon, pos);
	}

	/** Predict needs a callbacks face; the overlay path never touches it. */
	private function noopFace(): PredictCallbacks {
		return {
			listen: (_instance, _field, _handler, _immediate) -> () -> {},
			onAdd: (_parent, _collection, _handler) -> () -> {},
			onRemove: (_parent, _collection, _handler) -> () -> {},
		};
	}

	/** Distinct refIds: Predict's slot map keys on them, and a hand-built
	    schema (the mirror included) otherwise shares refId 0. */
	private function makeParts(): { paddle: SimPaddle, puck: SimPuck } {
		var paddle = new SimPaddle();
		paddle.x = 1; paddle.y = 2; paddle.team = "left";
		paddle.__refId = 7;
		var puck = new SimPuck();
		puck.x = 10; puck.vx = 3;
		puck.__refId = 8;
		return { paddle: paddle, puck: puck };
	}

	/** puck accelerates, paddle drifts — deterministic, shared with "the server". */
	private function stepWorld(ctx: io.colyseus.predict.RollbackController.StepContext,
			w: World, cmd: AccelInput) {
		w.puck.vx += cmd.ax * ctx.dt;
		w.puck.x += w.puck.vx * ctx.dt;
		w.paddle.x += cmd.ax * ctx.dt;
	}

	private function serverStep(paddle: SimPaddle, puck: SimPuck, ax: Float) {
		puck.vx += ax * 0.05;
		puck.x += puck.vx * 0.05;
		paddle.x += ax * 0.05;
	}

	// --- Binding -----------------------------------------------------------

	public function testBindingReplacesWorldFieldsWithSeededMirrors() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var handle = makeHandle(new AccelInput());
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world, step: stepWorld, smoothMs: 0, stepMs: 50,
		});

		// replaced IN PLACE — the caller's own object now points at the mirror
		assertTrue(sim.world == world);
		assertFalse(world.paddle == parts.paddle);
		assertFalse(world.puck == parts.puck);
		assertEquals("schema.predict.SimPaddle", Type.getClassName(Type.getClass(world.paddle)));
		assertEquals("schema.predict.SimPuck", Type.getClassName(Type.getClass(world.puck)));

		// ...and seeded from the source
		assertEquals(1.0, (world.paddle.x : Float));
		assertEquals(2.0, (world.paddle.y : Float));
		assertEquals(10.0, (world.puck.x : Float));
		assertEquals(3.0, (world.puck.vx : Float));

		// pose keys: NUMERIC fields only, "<worldField>.<schemaField>", sorted
		assertEquals("paddle.x,paddle.y,puck.vx,puck.vy,puck.x,puck.y",
			sim.poseKeys().join(","));
	}

	// --- The string-field bug ----------------------------------------------

	public function testStringFieldsRideTheMirrorVerbatim() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var command = new AccelInput();
		var handle = makeHandle(command);
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world, step: stepWorld, smoothMs: 0, stepMs: 50,
		});

		// seeded, not left at the class default — this is the bug
		assertEquals("left", world.paddle.team);

		// ...and re-adopted when the server changes it
		this.now = 0; sim.tick(this.now);
		command.ax = 10; handle.send();
		parts.paddle.team = "right";
		serverStep(parts.paddle, parts.puck, 10);
		@:privateAccess handle.ackInput(1);
		this.now = 50; sim.tick(this.now);
		assertEquals("right", world.paddle.team);

		// never posed: a string has no curve to error-correct
		assertEquals(-1, sim.poseKeys().indexOf("paddle.team"));
		assertTrue(Math.isNaN(sim.value("paddle.team")));
	}

	/** A part whose only scalars are strings still binds — it is state worth
	    restoring on rollback, it just contributes no poses. */
	public function testStringOnlyPartBindsWithoutPoses() {
		var label = new SimPaddle();
		label.team = "left";
		// strip the numeric fields so only `team` remains declared
		label._indexes = [0 => "team"];
		label._types = [0 => "string"];
		label.__refId = 9;

		var parts = makeParts();
		var world = new World(label, parts.puck);
		var handle = makeHandle(new AccelInput());
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world, step: stepWorld, smoothMs: 0, stepMs: 50,
		});

		assertEquals("left", world.paddle.team);
		assertEquals("puck.vx,puck.vy,puck.x,puck.y", sim.poseKeys().join(","));
	}

	// --- Overlay routing ---------------------------------------------------

	/**
	 * `predict.value(decodedInstance, field)` must read the reconciled pose.
	 * The registration carries the SOURCE, not the mirror that replaced it —
	 * easy to break, and the render layer would silently read raw state.
	 */
	public function testPredictValueRoutesThroughTheReconciledPose() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var command = new AccelInput();
		var handle = makeHandle(command);
		var predict = new Predict(noopFace(), new RoomClock());
		var sim = predict.sim({
			input: handle, world: world, step: stepWorld, smoothMs: 0, stepMs: 50,
		});

		this.now = 0; predict.tick(this.now);
		command.ax = 10; handle.send();
		// the pose interpolates between the two latest steps, so let the render
		// clock reach the step that `send` just applied
		this.now = 50; predict.tick(this.now);

		assertClose(sim.value("puck.x"), predict.value(parts.puck, "x"));
		assertClose(sim.value("paddle.x"), predict.value(parts.paddle, "x"));
		// the raw source never moved; the predicted pose did
		assertEquals(10.0, (parts.puck.x : Float));
		assertClose(10.175, predict.value(parts.puck, "x"));
	}

	// --- Adopt + replay ----------------------------------------------------

	/**
	 * The core rollback contract on the composite face: ack an older seq whose
	 * truth diverges, and the unacked inputs replay on top of it rather than
	 * the world snapping to the server value.
	 */
	public function testDivergentAckAdoptsThenReplaysUnackedInputs() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var command = new AccelInput();
		var handle = makeHandle(command);
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world, step: stepWorld, smoothMs: 0, stepMs: 50,
		});

		this.now = 0; sim.tick(this.now);
		for (i in 1...4) {
			command.ax = 10;
			handle.send();          // stepped eagerly on send
		}
		var predicted: Float = world.puck.x;
		assertEquals(3, sim.pendingCount);

		// server processed input 1 only, and teleported the puck
		serverStep(parts.paddle, parts.puck, 10);
		parts.puck.x += 100;
		@:privateAccess handle.ackInput(1);
		this.now = 50; sim.tick(this.now);

		// inputs 2..3 replayed on top of the adopted truth
		assertEquals(2, sim.pendingCount);
		assertClose(predicted + 100, (world.puck.x : Float));
		assertEquals(1, sim.reconcileSeq);
		assertClose(100, sim.lastCorrectionMag);
		// signed the same way as the flat face: predicted - truth
		assertClose(-100, sim.lastCorrection.get("puck.x"));
	}

	/** With smoothing armed the correction lands in the error term, so the
	    RENDERED pose lags the raw predicted state instead of popping. */
	public function testCorrectionDecaysThroughTheErrorTermNotThePose() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var command = new AccelInput();
		var handle = makeHandle(command);
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world, step: stepWorld, smoothMs: 100, stepMs: 50,
		});

		this.now = 0; sim.tick(this.now);
		command.ax = 10; handle.send();

		serverStep(parts.paddle, parts.puck, 10);
		parts.puck.x += 100;
		@:privateAccess handle.ackInput(1);
		this.now = 50; sim.tick(this.now);

		// raw mirror jumped with the truth; the rendered pose has not caught up
		assertClose(100, sim.lastCorrectionMag);
		assertTrue(Math.abs(sim.value("puck.x") - (world.puck.x : Float)) > 1);

		// ...and the gap decays away
		this.now = 1000; sim.tick(this.now);
		assertClose((world.puck.x : Float), sim.value("puck.x"), 0.05);
	}

	// --- adopt optionality -------------------------------------------------

	public function testWorldWithNothingBoundRequiresAdopt() {
		var handle = makeHandle(new AccelInput());
		var message = "";
		try {
			new SimReconciler<OpaqueWorld, AccelInput>({
				input: handle, world: new OpaqueWorld(),
				step: (_ctx, _w, _cmd) -> {}, stepMs: 50,
			});
		} catch (e: Dynamic) {
			message = Std.string(e);
		}
		assertTrue(message.indexOf("`adopt` is required") > -1);
	}

	public function testWorldWithNothingBoundAcceptsAdopt() {
		var handle = makeHandle(new AccelInput());
		var truth = 0.0;
		var w = new OpaqueWorld();
		var sim = new SimReconciler<OpaqueWorld, AccelInput>({
			input: handle, world: w,
			step: (_ctx, world, cmd) -> { world.n += cmd.ax; },
			adopt: (world) -> { world.n = truth; },
			stepMs: 50,
		});

		this.now = 0; sim.tick(this.now);
		var command: AccelInput = cast handle.data;
		command.ax = 5; handle.send();
		assertEquals(5.0, w.n);

		truth = 1;
		@:privateAccess handle.ackInput(1);
		this.now = 50; sim.tick(this.now);
		assertEquals(1.0, w.n);          // adopt ran; nothing left to replay
		assertEquals(0, sim.poseKeys().length);
	}

	// --- ctx.predict -------------------------------------------------------

	/** One-shot presentation must fire on the LIVE step only, never again when
	    that same input replays under rollback. */
	public function testCtxPredictFiresOnceAcrossAReplay() {
		var parts = makeParts();
		var world = new World(parts.paddle, parts.puck);
		var command = new AccelInput();
		var handle = makeHandle(command);
		var sink = new CountingSink();
		var sim = new SimReconciler<World, AccelInput>({
			input: handle, world: world,
			step: (ctx, w, cmd) -> {
				stepWorld(ctx, w, cmd);
				ctx.predict(sink, { ax: cmd.ax });
			},
			smoothMs: 0, stepMs: 50,
		});

		this.now = 0; sim.tick(this.now);
		for (i in 1...4) { command.ax = 10; handle.send(); }
		assertEquals("1,2,3", sink.seqs.join(","));

		// ack 1 -> inputs 2..3 replay, and must NOT re-declare
		serverStep(parts.paddle, parts.puck, 10);
		@:privateAccess handle.ackInput(1);
		this.now = 50; sim.tick(this.now);
		assertEquals("1,2,3", sink.seqs.join(","));
	}
}
