extends TestCase

# The three shipped map layouts, as data.
#
# Replaces test_demo_map.gd, test_map2.gd and test_map3.gd, which tested the
# algorithmic BUILDERS those maps used to have. The builders are gone: their
# output, seeded blocked-tile scatter and all, was baked into the layout files
# once and the text became the truth.
#
# What survives is everything those tests were actually protecting - the
# dimensions, the endpoints, the shape of each route, and the fact that every
# spawn can reach its goal. Those are properties of the MAP, and they are
# exactly what a mis-edited layout file would break.

func _tiles(name: StringName) -> Array:
	return Maps.build_tiles(name)

# --------------------------------------------------------------------------
# Every map, structurally
# --------------------------------------------------------------------------

func test_every_map_has_a_layout_file_on_disk() -> bool:
	for name in Maps.DEFS:
		var path: String = Maps.DEFS[name]["layout"]
		assert_true(FileAccess.file_exists(path), "%s has a layout at %s" % [name, path])
	return true

func test_every_map_matches_its_declared_dimensions() -> bool:
	# The registry and the file are two statements of one fact, and this is
	# what stops them drifting - a map edited to a different width would
	# otherwise render into a viewport sized for the old one.
	for name in Maps.DEFS:
		var t := _tiles(name)
		assert_eq(t.size(), Maps.rows(name), "%s row count" % name)
		assert_eq(t[0].size(), Maps.cols(name), "%s column count" % name)
	return true

func test_every_map_passes_its_own_validator() -> bool:
	for name in Maps.DEFS:
		assert_eq(MapFormat.validate(_tiles(name)), [],
			"%s is structurally valid" % name)
	return true

# The property no structural check can see: a goal you cannot walk to is a map
# that hangs the game rather than one that plays badly.
func test_every_spawn_on_every_map_can_reach_its_goal() -> bool:
	for name in Maps.DEFS:
		var t := _tiles(name)
		var spawns := 0
		for row in t:
			for cell in row:
				if cell == Tiles.SPAWN:
					spawns += 1
		var paths := PathFinder.get_all_spawn_paths(t)
		assert_eq(paths.size(), spawns,
			"%s: every one of its %d spawns reaches the goal" % [name, spawns])
		for p in paths:
			assert_true(p.size() > 1, "%s: and no route is a dead end" % name)
	return true

func test_every_map_leaves_room_to_build() -> bool:
	for name in Maps.DEFS:
		var buildable := 0
		for row in _tiles(name):
			for cell in row:
				if cell == Tiles.BUILDABLE:
					buildable += 1
		assert_true(buildable > Maps.DEFS[name]["tower_budget"] * 4,
			"%s has room for its %d tower budget several times over, got %d cells"
				% [name, Maps.DEFS[name]["tower_budget"], buildable])
	return true

# --------------------------------------------------------------------------
# The Pass
# --------------------------------------------------------------------------

func test_the_pass_is_a_single_route() -> bool:
	var t := _tiles(&"demoMap")
	assert_eq(t.size(), 14, "14 rows")
	assert_eq(t[0].size(), 23, "23 columns")
	assert_eq(t[4][0], Tiles.SPAWN, "spawn on the left at row 4")
	assert_eq(t[10][21], Tiles.GOAL, "goal on the right at row 10")
	assert_eq(PathFinder.get_all_spawn_paths(t).size(), 1, "one route")
	return true

# --------------------------------------------------------------------------
# The Fork
# --------------------------------------------------------------------------

func test_the_fork_has_two_entrances_converging_on_one_goal() -> bool:
	var t := _tiles(&"map2")
	assert_eq(t[1][0], Tiles.SPAWN, "top left entrance")
	assert_eq(t[12][0], Tiles.SPAWN, "bottom left entrance")
	assert_eq(t[7][24], Tiles.GOAL, "one goal, on the right at row 7")
	assert_eq(PathFinder.get_all_spawn_paths(t).size(), 2, "both entrances reach it")
	return true

# The convergence is the map's whole design: a tower on the joined stretch
# covers both streams, one before it covers half the wave.
func test_the_forks_two_legs_actually_converge() -> bool:
	var t := _tiles(&"map2")
	assert_eq(t[7][15], Tiles.PATH, "the joined stretch runs along row 7")
	assert_eq(t[1][5], Tiles.PATH, "the top leg is separate before it")
	assert_eq(t[12][5], Tiles.PATH, "and so is the bottom leg")
	return true

# --------------------------------------------------------------------------
# The Coils
# --------------------------------------------------------------------------

func test_the_coils_is_one_route_that_folds_back_three_times() -> bool:
	var t := _tiles(&"map3")
	assert_eq(t[2][0], Tiles.SPAWN, "spawn at row 2")
	assert_eq(t[13][26], Tiles.GOAL, "goal at row 13")
	assert_eq(PathFinder.get_all_spawn_paths(t).size(), 1, "one route")
	# Three horizontal runs are what make it serpentine. If these collapsed to
	# one the map would be an ordinary lane, and its lower tower budget - 18
	# against The Fork's 20 despite being wider - would stop making sense.
	assert_eq(t[2][10], Tiles.PATH, "the first straight")
	assert_eq(t[6][10], Tiles.PATH, "the second, running back")
	assert_eq(t[10][10], Tiles.PATH, "and the third")
	return true

func test_the_coils_folds_are_joined_at_both_ends() -> bool:
	var t := _tiles(&"map3")
	assert_eq(t[4][23], Tiles.PATH, "the right-hand turn between runs one and two")
	assert_eq(t[8][3], Tiles.PATH, "the left-hand turn between runs two and three")
	return true
