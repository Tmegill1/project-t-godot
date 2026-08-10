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

# QUIRK, preserved: no clamping, so a fast enemy overshoots and steers back.
func test_fast_enemy_overshoots_rather_than_clamping() -> bool:
	var r := Movement.advance(Vector2(0, 0), 1, _straight_path(), 10000.0, 100.0)
	assert_true(r["position"].x > 100.0, "overshoots the waypoint")
	assert_false(r["advanced_waypoint"], "did not arrive this tick")
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
