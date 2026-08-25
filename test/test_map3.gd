extends TestCase

# The Coils: one entrance, a serpentine route folding back on itself three
# times. The folds are the point — a tower on a bend covers two passes — so
# these tests pin the fold geometry, not only the endpoints.

func test_dimensions() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	assert_eq(m.size(), 16, "rows")
	assert_eq(m[0].size(), 28, "cols")
	return true

func test_it_has_one_spawn_and_one_goal() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	var spawns := 0
	var goals := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.SPAWN:
				spawns += 1
			elif m[r][c] == Tiles.GOAL:
				goals += 1
	assert_eq(spawns, 1, "one entrance")
	assert_eq(goals, 1, "one goal")
	return true

func test_the_endpoints_are_where_the_reference_puts_them() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	assert_eq(m[2][0], Tiles.SPAWN, "spawn at row 2, column 0")
	assert_eq(m[13][26], Tiles.GOAL, "goal at row 13, column 26")
	return true

# Three horizontal runs at rows 2, 6 and 10 are what makes it serpentine. If
# these collapsed to one the map would be an ordinary lane, and every claim
# about its lower tower budget would stop being true.
func test_the_route_folds_back_on_itself() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	assert_eq(m[2][10], Tiles.PATH, "the first straight")
	assert_eq(m[6][10], Tiles.PATH, "the second, running back")
	assert_eq(m[10][10], Tiles.PATH, "and the third")
	return true

func test_the_folds_are_joined_at_both_ends() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	assert_eq(m[4][23], Tiles.PATH, "the right-hand turn between runs one and two")
	assert_eq(m[8][3], Tiles.PATH, "the left-hand turn between runs two and three")
	return true

func test_the_spawn_reaches_the_goal() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	var paths := PathFinder.get_all_spawn_paths(m)
	assert_eq(paths.size(), 1, "one route")
	assert_true(paths[0].size() > 0, "and it is not a dead end")
	return true

func test_the_layout_is_reproducible_from_the_seed() -> bool:
	var a := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	var b := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	for r in a.size():
		for c in a[r].size():
			assert_eq(a[r][c], b[r][c], "tile %d,%d is the same both times" % [c, r])
	return true

# Unlike the other two maps this one has no combined ceiling: six adjacent and
# nine distant are taken independently. The test states the sum so a future
# "tidy-up" that adds a total cap has to change the test deliberately.
func test_the_scatter_takes_both_lists_independently() -> bool:
	var m := Map3.build(Rng.new(Seeds.DEFAULT_MAP3_SEED))
	var blocked := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.BLOCKED:
				blocked += 1
	var scatter_ceiling := Map3.MAX_ADJACENT_BLOCKED + Map3.MAX_DISTANT_BLOCKED
	assert_eq(scatter_ceiling, 15, "six adjacent plus nine distant, uncapped in total")
	assert_true(blocked <= scatter_ceiling + 18,
		"scatter plus two 3x3 endpoint stamps, got %d" % blocked)
	assert_true(blocked > 0, "and something actually got blocked")
	return true
