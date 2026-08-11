extends TestCase

func test_tile_size_is_48() -> bool:
	assert_eq(Tiles.TILE_SIZE, 48, "tile size matches the Phaser build")
	return true

func test_tile_to_world_returns_tile_centre() -> bool:
	Grid.set_active(23, 14)
	assert_eq(Grid.tile_to_world_center(0, 0), Vector2(24, 24), "first tile centre")
	assert_eq(Grid.tile_to_world_center(2, 3), Vector2(120, 168), "arbitrary tile centre")
	return true

func test_world_to_tile_floors() -> bool:
	Grid.set_active(23, 14)
	var t := Grid.world_to_tile(100.0, 100.0)
	assert_eq(t["col"], 2, "col floors")
	assert_eq(t["row"], 2, "row floors")
	assert_true(t["in_bounds"], "inside the board")
	return true

func test_world_to_tile_reports_out_of_bounds() -> bool:
	Grid.set_active(23, 14)
	assert_false(Grid.world_to_tile(-1.0, 10.0)["in_bounds"], "negative x is out")
	assert_false(Grid.world_to_tile(23 * 48.0, 10.0)["in_bounds"], "past last column is out")
	assert_false(Grid.world_to_tile(10.0, 14 * 48.0)["in_bounds"], "past last row is out")
	return true

# The original's Grid imported the FIRST map's dimensions and used them no
# matter which map was loaded, so 30% of the larger map silently rejected
# every click. set_active is what prevents that; this test is the guard.
func test_bounds_follow_the_active_map() -> bool:
	Grid.set_active(26, 17)
	var t := Grid.world_to_tile(25 * 48.0 + 5.0, 16 * 48.0 + 5.0)
	assert_eq(t["col"], 25, "col on the larger board")
	assert_eq(t["row"], 16, "row on the larger board")
	assert_true(t["in_bounds"], "the outer band of a larger map is usable")
	Grid.set_active(23, 14)
	assert_false(Grid.world_to_tile(25 * 48.0 + 5.0, 16 * 48.0 + 5.0)["in_bounds"],
		"same point is out of bounds on the smaller board")
	return true
