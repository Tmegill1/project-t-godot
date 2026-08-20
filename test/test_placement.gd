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

# --------------------------------------------------------------------------
# tower_radius
# --------------------------------------------------------------------------

# Derived from the `size` multiplier data/towers.gd already carries rather than
# introduced as a new constant, so a tower that is re-sized for art reasons
# cannot end up with a collision radius that disagrees with how it looks.
func test_tower_radius_derives_from_the_size_the_tower_already_declares() -> bool:
	for kind in Towers.KINDS:
		var expected := Tiles.TILE_SIZE * float(Towers.DEFS[kind]["size"]) / 2.0
		assert_almost_eq(Placement.tower_radius(kind), expected, 0.0001,
			"%s's radius is half its displayed width" % kind)
	assert_almost_eq(Placement.tower_radius(&"basic"), 19.2, 0.0001,
		"basic is size 0.8 of a 48px tile, so 19.2px radius")
	return true

# --------------------------------------------------------------------------
# can_place
# --------------------------------------------------------------------------

const _BOUNDS := Rect2(Vector2.ZERO, Vector2(1104.0, 672.0))

# A path far from anything the tests below place, so it never accidentally
# becomes the reason a case is rejected.
func _far_path() -> Array:
	return [PackedVector2Array([Vector2(0.0, 600.0), Vector2(1000.0, 600.0)])]

func test_can_place_accepts_open_ground() -> bool:
	var v := Placement.can_place(Vector2(300.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(v["ok"], "open ground well clear of everything is placeable")
	assert_eq(v["reason"], Placement.REASON_OK, "an accepted spot reports the ok reason")
	return true

func test_can_place_rejects_a_tower_whose_circle_leaves_the_map() -> bool:
	var v := Placement.can_place(Vector2(10.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_false(v["ok"], "a tower at x=10 with radius 20 hangs off the left edge")
	assert_eq(v["reason"], Placement.REASON_OUT_OF_BOUNDS, "and says so")

	var inside := Placement.can_place(Vector2(21.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(inside["ok"], "one pixel further in, the whole circle fits and it is accepted")

	# Right edge: bounds.end.x is 1104.0, so a radius-20 circle's boundary
	# sits at x=1084.
	var right_outside := Placement.can_place(Vector2(1094.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_false(right_outside["ok"], "a tower at x=1094 with radius 20 hangs off the right edge")
	assert_eq(right_outside["reason"], Placement.REASON_OUT_OF_BOUNDS, "and says so")

	var right_inside := Placement.can_place(Vector2(1083.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(right_inside["ok"], "one pixel further in from the right edge, the whole circle fits and it is accepted")

	# Top edge: bounds.position.y is 0.0, so a radius-20 circle's boundary
	# sits at y=20.
	var top_outside := Placement.can_place(Vector2(300.0, 10.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_false(top_outside["ok"], "a tower at y=10 with radius 20 hangs off the top edge")
	assert_eq(top_outside["reason"], Placement.REASON_OUT_OF_BOUNDS, "and says so")

	var top_inside := Placement.can_place(Vector2(300.0, 21.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(top_inside["ok"], "one pixel further in from the top edge, the whole circle fits and it is accepted")

	# Bottom edge: bounds.end.y is 672.0, so a radius-20 circle's boundary
	# sits at y=652.
	var bottom_outside := Placement.can_place(Vector2(300.0, 662.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_false(bottom_outside["ok"], "a tower at y=662 with radius 20 hangs off the bottom edge")
	assert_eq(bottom_outside["reason"], Placement.REASON_OUT_OF_BOUNDS, "and says so")

	var bottom_inside := Placement.can_place(Vector2(300.0, 651.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(bottom_inside["ok"], "one pixel further in from the bottom edge, the whole circle fits and it is accepted")
	return true

func test_can_place_rejects_a_spot_on_the_road() -> bool:
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var v := Placement.can_place(Vector2(250.0, 110.0), 20.0, [], [], path, _BOUNDS)
	assert_false(v["ok"], "10px from the road centre is inside the corridor")
	assert_eq(v["reason"], Placement.REASON_ON_PATH, "and says so")
	return true

func test_can_place_rejects_a_spot_overlapping_a_prop() -> bool:
	var props := [{"pos": Vector2(300.0, 100.0), "radius": 24.0}]
	var v := Placement.can_place(Vector2(320.0, 100.0), 20.0, props, [], _far_path(), _BOUNDS)
	assert_false(v["ok"], "20px from a 24px prop with a 20px tower overlaps")
	assert_eq(v["reason"], Placement.REASON_BLOCKED_BY_PROP, "and says so")

	# Further out than the prop's own radius, but still inside the sum of the
	# two: this is the case that proves the TOWER's radius participates. At
	# 20px above, a mutation dropping `radius` from the sum still rejects,
	# because 20 < 24 holds on the prop's radius alone - so that case on its
	# own cannot tell a correct implementation from a broken one.
	var farther := Placement.can_place(Vector2(330.0, 100.0), 20.0, props, [], _far_path(), _BOUNDS)
	assert_false(farther["ok"], "30px out - past the prop's own 24px radius but inside 24 + 20 - still overlaps")
	assert_eq(farther["reason"], Placement.REASON_BLOCKED_BY_PROP, "and is refused for the prop, not for spacing")
	return true

func test_can_place_rejects_a_spot_too_close_to_another_tower() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var v := Placement.can_place(Vector2(330.0, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_false(v["ok"], "30px apart is inside the 44px minimum spacing")
	assert_eq(v["reason"], Placement.REASON_TOO_CLOSE, "and says so")
	return true

# Each threshold is checked from both sides. `<` vs `<=` is the classic
# surviving mutant, and a range-only check would not catch it.
func test_can_place_thresholds_are_exact_on_both_sides() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var just_inside := Placement.can_place(Vector2(300.0 + 43.9, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_false(just_inside["ok"], "43.9px apart is closer than MIN_TOWER_SPACING and is refused")
	var just_outside := Placement.can_place(Vector2(300.0 + 44.1, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_true(just_outside["ok"], "44.1px apart clears MIN_TOWER_SPACING and is allowed")

	# radius 20 + PATH_HALF_WIDTH 14 = 34
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var near := Placement.can_place(Vector2(250.0, 100.0 + 33.9), 20.0, [], [], path, _BOUNDS)
	assert_false(near["ok"], "33.9px from the road centre is inside radius + PATH_HALF_WIDTH")
	var clear := Placement.can_place(Vector2(250.0, 100.0 + 34.1), 20.0, [], [], path, _BOUNDS)
	assert_true(clear["ok"], "34.1px from the road centre clears the corridor")
	return true

# With several rules failing at once the reported reason must be stable and
# most-explanatory, or the message shown to the player depends on argument
# order. Reordering the checks in can_place is invisible without this.
func test_can_place_reports_the_first_failing_rule_in_a_fixed_precedence() -> bool:
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var props := [{"pos": Vector2(250.0, 105.0), "radius": 24.0}]
	var towers := [Vector2(250.0, 108.0)]

	# On the road AND overlapping a prop AND too close to a tower.
	var v := Placement.can_place(Vector2(250.0, 105.0), 20.0, props, towers, path, _BOUNDS)
	assert_false(v["ok"], "a spot failing every rule is refused")
	assert_eq(v["reason"], Placement.REASON_ON_PATH, "path proximity outranks prop and spacing")

	# Off the road, but overlapping a prop AND too close to a tower.
	var off_road_props := [{"pos": Vector2(250.0, 300.0), "radius": 24.0}]
	var off_road_towers := [Vector2(250.0, 300.0)]
	var v2 := Placement.can_place(Vector2(250.0, 300.0), 20.0, off_road_props, off_road_towers, path, _BOUNDS)
	assert_eq(v2["reason"], Placement.REASON_BLOCKED_BY_PROP, "prop outranks spacing")
	return true

func test_can_place_handles_empty_prop_and_tower_lists() -> bool:
	var v := Placement.can_place(Vector2(300.0, 300.0), 20.0, [], [], [], _BOUNDS)
	assert_true(v["ok"], "an empty board with no paths places anywhere in bounds")
	return true

# min_spacing is a defaulted parameter rather than read from the constant
# inside the function, so balance tuning is a caller-side change and tests can
# pin behaviour at values other than the shipped default.
func test_can_place_accepts_an_overridden_minimum_spacing() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var v := Placement.can_place(Vector2(330.0, 100.0), 20.0, [], towers, _far_path(), _BOUNDS, 20.0)
	assert_true(v["ok"], "30px apart is fine when min_spacing is lowered to 20")
	return true
