extends TestCase

func _straight_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])

func test_moves_at_speed_over_time() -> bool:
	var r := Movement.advance(Vector2(0, 0), 1, _straight_path(), 100.0, 100.0)
	assert_eq(r["position"], Vector2(10, 0), "100px/s for 100ms is 10px")
	assert_false(r["advanced_waypoint"], "still travelling")
	assert_false(r["reached_goal"], "not at the end")
	return true

# QUIRK, preserved: arriving consumes the whole tick. The original's if/else
# never advances the index and moves in the same frame; changing it would
# shift every enemy's arrival time.
func test_arrival_consumes_the_whole_tick() -> bool:
	var r := Movement.advance(Vector2(99.5, 0), 1, _straight_path(), 100.0, 100.0)
	assert_true(r["advanced_waypoint"], "waypoint advanced")
	assert_eq(r["path_index"], 2, "index moved on")
	assert_eq(r["position"], Vector2(99.5, 0), "no distance covered this tick")
	return true

# CONTRACT, replacing a removed quirk. This test previously pinned the
# opposite: that a fast enemy overshot the waypoint and steered back, exactly
# as movement.ts does. That behaviour was removed because it soft-locked this
# port, and the reason is the caller, not the rule — Phaser hands the reference
# a measured frame delta so the step jitters, while Godot's _physics_process
# delta is fixed at 1/60s so each enemy's step is a constant. A constant step
# above 2 * WAYPOINT_ARRIVAL_RADIUS can oscillate around a waypoint forever;
# waves 19 and 20 did, and the game became unwinnable. Full reasoning is at the
# arrival test in sim/movement.gd. The new contract: a step that would reach or
# pass the waypoint arrives at it.
func test_a_step_reaching_the_waypoint_arrives_rather_than_overshooting() -> bool:
	# 10000px/s for 100ms is a 1000px step against a 100px leg — massively past.
	var r := Movement.advance(Vector2(0, 0), 1, _straight_path(), 10000.0, 100.0)
	assert_true(r["advanced_waypoint"], "a step that would pass the waypoint arrives at it instead")
	assert_eq(r["path_index"], 2, "index moved on")
	assert_false(r["position"].x > 100.0, "never lands beyond the waypoint")
	# The other quirk is untouched: arriving still costs the whole tick.
	assert_eq(r["position"], Vector2(0, 0), "arrival consumes the tick without moving")
	return true

# The boundary of the new arrival condition. `<=` means a step of exactly the
# remaining distance arrives; without both halves of this, a `<` mutation (or a
# revert to the old `distance < WAYPOINT_ARRIVAL_RADIUS` alone) is invisible
# whenever the remaining distance happens to be under 2px anyway.
func test_arrival_boundary_against_the_step_length() -> bool:
	var path := _straight_path()
	# 40px remain to (100, 0); 400px/s for 100ms is exactly 40px.
	var exact := Movement.advance(Vector2(60, 0), 1, path, 400.0, 100.0)
	assert_true(exact["advanced_waypoint"], "a step of exactly the remaining distance arrives")
	assert_eq(exact["position"], Vector2(60, 0), "and consumes the tick without moving")
	# 399px/s covers 39.9px, stopping 0.1px short — still outside the 2px radius.
	var falls_short := Movement.advance(Vector2(60, 0), 1, path, 399.0, 100.0)
	assert_false(falls_short["advanced_waypoint"], "a step that falls short does not arrive")
	assert_almost_eq(falls_short["position"].x, 99.9, 0.0001, "it moves a full step instead")
	return true

# The property the removed quirk broke, pinned directly at the unit level: on a
# fixed timestep an enemy must reach its waypoint in finitely many ticks at ANY
# speed. The old code failed this whenever the approach remainder r and the
# overshoot (step - r) both landed at or above the 2px radius — e.g. a 4.25
# px/tick step against the 48px tile spacing (a wave-19 bee), which alternated
# 2.00/2.25 forever. Swept rather than spot-checked precisely because the old
# behaviour was fine at almost every step size and catastrophic at a few: wave
# 18's 4.125 px/tick converges and wave 19's 4.25 does not, so any single value
# can pass by luck. test_harness.gd's wave sweep is the whole-game twin of this.
func test_every_step_size_reaches_the_waypoint_in_finite_ticks() -> bool:
	var leg := PackedVector2Array([Vector2(0, 0), Vector2(48, 0)])
	var tick_ms := 1000.0 / 60.0
	for i in range(1, 81):
		var step: float = i * 0.125  # 0.125 .. 10.0 px/tick
		var speed: float = step * 1000.0 / tick_ms
		var position := Vector2(0, 0)
		var index := 1
		var ticks := 0
		while index < leg.size() and ticks < 10000:
			var r := Movement.advance(position, index, leg, speed, tick_ms)
			position = r["position"]
			index = r["path_index"]
			ticks += 1
		assert_true(index >= leg.size(),
			"a %.3f px/tick step reaches the waypoint rather than oscillating" % step)
	return true

func test_reaching_the_end_reports_goal() -> bool:
	var path := _straight_path()
	var r := Movement.advance(Vector2(100, 99.5), 2, path, 100.0, 100.0)
	assert_true(r["advanced_waypoint"], "final waypoint consumed")
	assert_true(r["reached_goal"], "path exhausted")
	return true

func test_exhausted_path_stays_at_goal() -> bool:
	var r := Movement.advance(Vector2(100, 100), 3, _straight_path(), 100.0, 100.0)
	assert_true(r["reached_goal"], "already leaked")
	assert_eq(r["position"], Vector2(100, 100), "does not drift")
	return true

func test_direction_ties_fall_to_side() -> bool:
	# |dy| > |dx| picks up/down; equal magnitudes fall to "side".
	var diag := PackedVector2Array([Vector2(0, 0), Vector2(50, 50)])
	var r := Movement.advance(Vector2(0, 0), 1, diag, 10.0, 100.0)
	assert_eq(r["direction"], &"side", "equal dx and dy reads as side")
	return true

func test_direction_up_and_down() -> bool:
	var vertical := PackedVector2Array([Vector2(0, 0), Vector2(0, 100)])
	assert_eq(Movement.advance(Vector2(0, 0), 1, vertical, 10.0, 100.0)["direction"],
		&"down", "positive dy is down")
	var upward := PackedVector2Array([Vector2(0, 100), Vector2(0, 0)])
	assert_eq(Movement.advance(Vector2(0, 100), 1, upward, 10.0, 100.0)["direction"],
		&"up", "negative dy is up")
	return true

func test_moving_left_flag() -> bool:
	var leftward := PackedVector2Array([Vector2(100, 0), Vector2(0, 0)])
	assert_true(Movement.advance(Vector2(100, 0), 1, leftward, 10.0, 100.0)["moving_left"],
		"travelling right-to-left")
	return true

func test_starting_index_skips_a_waypoint_spawned_on_top_of() -> bool:
	var path := _straight_path()
	assert_eq(Movement.starting_path_index(Vector2(0, 0), path), 1,
		"spawned on path[0], head for path[1]")
	assert_eq(Movement.starting_path_index(Vector2(50, 0), path), 0,
		"spawned elsewhere, head for path[0]")
	return true

# Ported from movement.test.ts's "uses a 2px arrival radius". The existing
# tests only probe the radius from one side (close enough to arrive), so a
# widened radius (e.g. 2.0 -> 3.0) would make enemies arrive early without
# any test noticing. This pins both sides against the reference's exact
# boundary values.
func test_arrival_radius_boundary() -> bool:
	assert_eq(Movement.WAYPOINT_ARRIVAL_RADIUS, 2.0, "arrival radius is 2px")
	var path := _straight_path()
	var just_outside := Movement.advance(Vector2(98, 0), 1, path, 100.0, 16.0)
	assert_eq(just_outside["path_index"], 1, "distance of exactly 2.0 does not arrive")
	var just_inside := Movement.advance(Vector2(98.5, 0), 1, path, 100.0, 16.0)
	assert_eq(just_inside["path_index"], 2, "distance of 1.5 arrives")
	return true

# Ported from movement.test.ts's "tolerates sub-pixel spawn offsets". The
# existing spawn-snap test uses an exact-zero offset, so narrowing the
# radius (e.g. 1.0 -> 0.3) goes unnoticed. 0.5 is inside the real radius but
# would miss a narrowed one; 50 stays clearly outside either way.
func test_starting_index_snap_radius_boundary() -> bool:
	var path := _straight_path()
	assert_eq(Movement.starting_path_index(Vector2(0.5, 0.5), path), 1,
		"sub-pixel offset still snaps to path[1]")
	assert_eq(Movement.starting_path_index(Vector2(50, 0), path), 0,
		"a spawn clearly beyond the snap radius heads for path[0]")
	return true
