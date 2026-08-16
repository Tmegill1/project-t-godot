extends TestCase

# Placement is pure static functions with no engine state, so these tests
# call it directly - no scene tree, no NOTIFICATION_READY, no node freeing.

# --------------------------------------------------------------------------
# distance_to_segment
# --------------------------------------------------------------------------

func test_distance_to_segment_measures_perpendicular_distance_to_the_interior() -> bool:
	var d := Placement.distance_to_segment(Vector2(5.0, 3.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(d, 3.0, 0.0001, "a point above the middle of a horizontal segment is its perpendicular distance away")
	return true

# A projection-only implementation (no clamping) passes the interior case above
# and fails this one: it would project (20, 0) onto the infinite line through
# the segment and report distance 0, rather than 10 from the nearer endpoint.
func test_distance_to_segment_clamps_to_the_nearer_endpoint_when_the_point_is_past_the_end() -> bool:
	var past_b := Placement.distance_to_segment(Vector2(20.0, 0.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(past_b, 10.0, 0.0001, "a point beyond b measures from b, not from the infinite line")

	var past_a := Placement.distance_to_segment(Vector2(-4.0, 0.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(past_a, 4.0, 0.0001, "a point before a measures from a, not from the infinite line")
	return true

# A degenerate segment makes length_squared zero; an unguarded projection
# divides by it and returns NAN, which silently compares false against every
# threshold and would make can_place permit building straight through a path.
func test_distance_to_segment_handles_a_zero_length_segment_without_dividing_by_zero() -> bool:
	var d := Placement.distance_to_segment(Vector2(3.0, 4.0), Vector2(0.0, 0.0), Vector2(0.0, 0.0))
	assert_almost_eq(d, 5.0, 0.0001, "a zero-length segment behaves as the point it is")
	assert_false(is_nan(d), "the degenerate case does not produce NAN")
	return true

# --------------------------------------------------------------------------
# distance_to_paths
# --------------------------------------------------------------------------

func test_distance_to_paths_returns_the_nearest_segment_across_every_path() -> bool:
	var near := PackedVector2Array([Vector2(0.0, 100.0), Vector2(100.0, 100.0)])
	var far := PackedVector2Array([Vector2(0.0, 500.0), Vector2(100.0, 500.0)])
	var d := Placement.distance_to_paths(Vector2(50.0, 90.0), [far, near])
	assert_almost_eq(d, 10.0, 0.0001, "the nearest of several paths wins, whatever order they are given in")
	return true

func test_distance_to_paths_measures_every_segment_of_a_multi_point_path() -> bool:
	# An L: right along y=0, then down at x=100. A loop that only measured the
	# first segment would report 100 for a point beside the second leg.
	var path := PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0)])
	var d := Placement.distance_to_paths(Vector2(93.0, 50.0), [path])
	assert_almost_eq(d, 7.0, 0.0001, "a point beside the second leg measures against that leg")
	return true

func test_distance_to_paths_handles_a_single_point_path() -> bool:
	var path := PackedVector2Array([Vector2(10.0, 10.0)])
	var d := Placement.distance_to_paths(Vector2(10.0, 13.0), [path])
	assert_almost_eq(d, 3.0, 0.0001, "a one-point path has no segments and measures from the point itself")
	return true

# No paths means nothing to stay clear of. INF rather than 0.0 so that
# `distance < radius + PATH_HALF_WIDTH` reads false and placement is allowed;
# returning 0.0 would make an empty path list block the entire map.
func test_distance_to_paths_with_no_paths_is_infinitely_far() -> bool:
	assert_true(is_inf(Placement.distance_to_paths(Vector2.ZERO, [])), "no paths means no path proximity constraint")
	return true
