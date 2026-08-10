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
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var map := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
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
