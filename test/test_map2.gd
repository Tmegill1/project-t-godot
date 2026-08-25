extends TestCase

# The Fork: two entrances converging on one route to the goal. Mirrors
# test_demo_map.gd's shape — dimensions, tile kinds, the endpoints, and the
# scatter's bounds — because a map is data, and a golden test is the only
# thing standing between a re-generated map and a silently different board.

func test_dimensions() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	assert_eq(m.size(), 17, "rows")
	assert_eq(m[0].size(), 26, "cols")
	return true

func test_it_has_two_spawns_and_one_goal() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	var spawns := 0
	var goals := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.SPAWN:
				spawns += 1
			elif m[r][c] == Tiles.GOAL:
				goals += 1
	assert_eq(spawns, 2, "the fork's two entrances")
	assert_eq(goals, 1, "converging on one goal")
	return true

func test_the_endpoints_are_where_the_reference_puts_them() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	assert_eq(m[1][0], Tiles.SPAWN, "top left entrance")
	assert_eq(m[12][0], Tiles.SPAWN, "bottom left entrance")
	assert_eq(m[7][24], Tiles.GOAL, "goal on the right at row 7")
	return true

# The convergence is the map's design. If the two legs stopped meeting, it
# would be two independent lanes and every tower would cover half a wave.
func test_the_two_legs_converge_on_one_stretch() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	assert_eq(m[7][15], Tiles.PATH, "the joined stretch runs along row 7")
	assert_eq(m[1][5], Tiles.PATH, "the top leg is separate before it")
	assert_eq(m[12][5], Tiles.PATH, "and so is the bottom leg")
	return true

func test_both_spawns_reach_the_goal() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	var paths := PathFinder.get_all_spawn_paths(m)
	assert_eq(paths.size(), 2, "one path per entrance")
	for p in paths:
		assert_true(p.size() > 0, "and neither is a dead end")
	return true

func test_the_layout_is_reproducible_from_the_seed() -> bool:
	var a := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	var b := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	for r in a.size():
		for c in a[r].size():
			assert_eq(a[r][c], b[r][c], "tile %d,%d is the same both times" % [c, r])
	return true

func test_the_scatter_is_bounded() -> bool:
	var m := Map2.build(Rng.new(Seeds.DEFAULT_MAP2_SEED))
	var blocked := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.BLOCKED:
				blocked += 1
	# The three endpoint footprints are blocked too, so this is a ceiling on
	# the scatter plus three 3x3 stamps, not on the scatter alone.
	assert_true(blocked <= MAX_SCATTER + ENDPOINT_FOOTPRINTS,
		"scatter is bounded, got %d" % blocked)
	assert_true(blocked > 0, "and something actually got blocked")
	return true

const MAX_SCATTER := 12
const ENDPOINT_FOOTPRINTS := 27
