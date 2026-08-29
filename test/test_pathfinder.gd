extends TestCase

func _tiny_map() -> Array:
	# 3 rows x 4 cols:  S P P G
	var blank := [
		[Tiles.SPAWN, Tiles.PATH, Tiles.PATH, Tiles.GOAL],
		[Tiles.BUILDABLE, Tiles.BUILDABLE, Tiles.BUILDABLE, Tiles.BUILDABLE],
		[Tiles.BUILDABLE, Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.BUILDABLE],
	]
	return blank

func test_finds_path_on_a_tiny_map() -> bool:
	Grid.set_active(4, 3)
	var paths := PathFinder.get_all_spawn_paths(_tiny_map())
	assert_eq(paths.size(), 1, "one spawn, one path")
	var p: PackedVector2Array = paths[0]
	assert_eq(p.size(), 4, "spawn plus three walked tiles")
	assert_eq(p[0], Grid.tile_to_world_center(0, 0), "starts at the spawn centre")
	assert_eq(p[p.size() - 1], Grid.tile_to_world_center(3, 0), "ends at the goal centre")
	return true

func test_path_does_not_enter_non_walkable_tiles() -> bool:
	Grid.set_active(4, 3)
	var p: PackedVector2Array = PathFinder.get_all_spawn_paths(_tiny_map())[0]
	for point in p:
		var t := Grid.world_to_tile(point.x, point.y)
		var kind = _tiny_map()[t["row"]][t["col"]]
		assert_true(kind in Tiles.WALKABLE, "point %s is on a walkable tile" % point)
	return true

func test_real_map_path_is_connected_and_reaches_goal() -> bool:
	Grid.set_active(Maps.cols(&"demoMap"), Maps.rows(&"demoMap"))
	var map := Maps.build_tiles(&"demoMap")
	var paths := PathFinder.get_all_spawn_paths(map)
	assert_eq(paths.size(), 1, "The Pass has one spawn")
	var p: PackedVector2Array = paths[0]
	assert_true(p.size() > 20, "the route is long, got %d points" % p.size())
	assert_eq(p[0], Grid.tile_to_world_center(0, 4), "starts at the spawn")
	assert_eq(p[p.size() - 1], Grid.tile_to_world_center(21, 10), "ends at the goal")
	# Consecutive points must be exactly one tile apart.
	for i in range(1, p.size()):
		var step := (p[i] - p[i - 1]).length()
		assert_almost_eq(step, float(Tiles.TILE_SIZE), 0.001,
			"step %d is one tile" % i)
	return true

func test_returns_empty_when_no_spawn() -> bool:
	Grid.set_active(2, 1)
	var no_spawn := [[Tiles.BUILDABLE, Tiles.GOAL]]
	assert_eq(PathFinder.get_all_spawn_paths(no_spawn).size(), 0, "no spawn, no paths")
	return true

func _walled_off_map() -> Array:
	# 1 row x 3 cols: S is walled off from G by a blocked tile - no route.
	return [[Tiles.SPAWN, Tiles.BLOCKED, Tiles.GOAL]]

func test_unreachable_goal_falls_back_to_straight_line() -> bool:
	Grid.set_active(3, 1)
	var paths := PathFinder.get_all_spawn_paths(_walled_off_map())
	assert_eq(paths.size(), 1, "one spawn, one (fallback) path")
	var p: PackedVector2Array = paths[0]
	assert_eq(p.size(), 2, "fallback is exactly spawn and goal, no route between")
	assert_eq(p[0], Grid.tile_to_world_center(0, 0), "point 0 is the spawn centre")
	assert_eq(p[1], Grid.tile_to_world_center(2, 0), "point 1 is the goal centre")
	return true

# Later tasks (e.g. Movement.advance) index path[path_index] and derive
# arrival from path.size(); a path must always have at least a start and an
# end, whether or not BFS found a real route. Check this holds both when the
# goal is unreachable (fallback path) and on the real, connected map.
func test_every_path_has_at_least_two_points() -> bool:
	Grid.set_active(3, 1)
	for p in PathFinder.get_all_spawn_paths(_walled_off_map()):
		var walled: PackedVector2Array = p
		assert_true(walled.size() >= 2, "walled-off path has a start and an end")

	Grid.set_active(Maps.cols(&"demoMap"), Maps.rows(&"demoMap"))
	var map := Maps.build_tiles(&"demoMap")
	for p in PathFinder.get_all_spawn_paths(map):
		var real: PackedVector2Array = p
		assert_true(real.size() >= 2, "real map path has a start and an end")
	return true

# --------------------------------------------------------------------------
# Honest reachability
# --------------------------------------------------------------------------
#
# get_all_spawn_paths cannot answer "is this map playable?" - it returns a
# two-point fallback path for an unreachable spawn so Movement.advance always
# has a start and an end. Counting its results therefore always equals
# counting spawns, and a test comparing the two passes on a map with a wall
# across it. One of mine did.

func test_unreachable_spawns_is_empty_on_a_playable_map() -> bool:
	for name in Maps.DEFS:
		assert_eq(PathFinder.unreachable_spawns(Maps.build_tiles(name)), [],
			"%s is playable from every spawn" % name)
	return true

func test_unreachable_spawns_finds_a_walled_off_spawn() -> bool:
	# Structurally perfect and completely unplayable: no walkable route joins
	# the two, because buildable ground is not walkable.
	var walled := MapFormat.parse("S.#.G\n..#..\n..#..")
	assert_eq(MapFormat.validate(walled), [], "precondition: structurally valid")
	assert_eq(PathFinder.unreachable_spawns(walled).size(), 1,
		"the one spawn cannot reach the goal")
	return true

func test_unreachable_spawns_finds_only_the_blocked_one() -> bool:
	# Two spawns, one connected by road and one not.
	var mixed := MapFormat.parse("S====G\n......\nS.....")
	var blocked := PathFinder.unreachable_spawns(mixed)
	assert_eq(blocked.size(), 1, "exactly one spawn is cut off")
	assert_eq(blocked[0], Vector2i(0, 2), "and it is the bottom one")
	return true

func test_a_map_with_no_goal_reports_every_spawn_unreachable() -> bool:
	assert_eq(PathFinder.unreachable_spawns(MapFormat.parse("S==\n...\nS..")).size(), 2,
		"with nothing to reach, no spawn reaches it")
	return true

# The distinction that makes this useful: get_all_spawn_paths still returns a
# path for the blocked spawn, which is why it cannot be used for this.
func test_get_all_spawn_paths_still_returns_a_path_for_an_unreachable_spawn() -> bool:
	var walled := MapFormat.parse("S.#.G\n..#..\n..#..")
	assert_eq(PathFinder.get_all_spawn_paths(walled).size(), 1,
		"a path is still produced, so counting paths proves nothing")
	assert_eq(PathFinder.unreachable_spawns(walled).size(), 1,
		"while this reports the truth")
	return true
