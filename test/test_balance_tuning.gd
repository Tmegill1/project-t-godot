extends TestCase


func test_half_of_the_twelve_tower_roster_leaks_on_wave_eighteen() -> bool:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	var path := PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))
	var towers: Array = []
	var kinds: Array[StringName] = [&"basic", &"fast", &"mortar", &"long", &"mortar", &"long"]
	var cols := [3, 5, 7, 9, 11, 13]
	for i in kinds.size():
		towers.append({
			"kind": kinds[i],
			"position": Grid.tile_to_world_center(cols[i], 3),
			"tiers": {&"sustained": 2, &"burst": 4},
		})

	var result := Harness.run_wave({"wave": 18, "path": path, "towers": towers})
	assert_true(result["leaks"] > 0,
		"six fully committed towers must leak on wave 18, got %s" % result)
	assert_false(result["timed_out"], "the balance benchmark completes")
	return true


## The opening, pinned as measured on 2026-08-30.
##
## Three ungraded Basic towers are exactly what 100 starting gold buys at
## 20 + 30 + 40, so this is the board a player has on wave 1 and the one they
## still have on wave 5 if they bank instead of building.
##
## Task 9 set out to give wave 1 a pulse by raising base health and could not:
## see the note above Enemies.DEFS for the sweep and why. This pins the shape
## it failed to move, so the next attempt starts from a number rather than an
## impression.
func test_the_opening_is_a_walkover_and_then_a_cliff() -> bool:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	var path := PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))
	var towers: Array = []
	for col in [5, 7, 9]:
		towers.append({"kind": &"basic", "position": Grid.tile_to_world_center(col, 3)})

	var first := Harness.run_wave({"wave": 1, "towers": towers, "path": path})
	assert_eq(first["leaks"], 0, "wave 1 costs a starting board nothing")
	assert_true(first["deepest_progress"] < 0.31,
		"and is decided before the first bend, at %f" % first["deepest_progress"])

	var fifth := Harness.run_wave({"wave": 5, "towers": towers, "path": path})
	assert_true(fifth["lives_lost"] >= Economy.STARTING_LIVES,
		"wave 5 ends a run that never built past its starting three, at %s lives"
			% fifth["lives_lost"])
	return true
