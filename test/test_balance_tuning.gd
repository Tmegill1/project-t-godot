extends TestCase


func test_half_of_the_twelve_tower_roster_leaks_on_wave_eighteen() -> bool:
	var result := Harness.run_wave({"wave": 18, "path": _full_path(), "towers": _mid_board()})
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


## Three of each kind, twelve towers, every tier the cross-path rule allows:
## the board the game actually hands out, and the only one the endgame is
## really played on.
##
## The six-tower case above stays - a mid-run board is worth benchmarking too.
## It simply cannot be the only one, which is what let a board that shut the
## game out completely read as balanced.
const MAXED := {&"sustained": 2, &"burst": 4}

## The Pass is 2,448px end to end and its first bend is 768px in.
const FIRST_BEND_FRACTION := 0.31

func _full_path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

func _full_board() -> Array:
	var kinds: Array[StringName] = []
	for kind in Towers.KINDS:
		for i in 3:
			kinds.append(kind)
	var spots := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
		[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]
	var towers: Array = []
	for i in kinds.size():
		towers.append({"kind": kinds[i],
			"position": Grid.tile_to_world_center(spots[i][0], spots[i][1]), "tiers": MAXED})
	return towers

## Six fully committed towers - roughly the board a player is holding in the
## middle of a run, and the one this file benchmarked exclusively before the
## full roster was added beside it.
func _mid_board() -> Array:
	var kinds: Array[StringName] = [&"basic", &"fast", &"mortar", &"long", &"mortar", &"long"]
	var cols := [3, 5, 7, 9, 11, 13]
	var towers: Array = []
	for i in kinds.size():
		towers.append({"kind": kinds[i],
			"position": Grid.tile_to_world_center(cols[i], 3), "tiers": MAXED})
	return towers

## THE assertion this whole change exists to make. Directional rather than a
## magic number, so it survives future retuning: whatever else moves, the
## hardest tier must not be winnable by simply filling the budget.
func test_a_full_maxed_board_does_not_shut_out_the_hardest_tier() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(r["leaks"] > 0,
		"a full maxed board must not shut out Nightmare's last wave, got %s" % r)
	assert_false(r["timed_out"], "the benchmark completes")
	return true

## The owner's report as a permanent assertion: on Nightmare the enemies get
## past the first bend.
##
## Asked of two boards, and NOT of wave 10 against the full one, which is what
## the plan proposed. Measured on 2026-08-30, wave 10 against twelve maxed
## towers cannot clear the bend at any tier that leaves the late game
## playable - even a 2.5x count / 0.3x interval / 3.0x health row only reaches
## 0.26 there while annihilating waves 13 onward. It is the wrong question:
## nobody owns twelve maxed towers at wave 10, which costs 11,415 gold against
## 16,199 of income across a WHOLE run (see test_affordability.gd).
##
## So the claim is made where it means something. Against the board a player
## actually holds mid-run, wave 10 gets past the bend; against the complete
## board, the last wave does.
func test_enemies_reach_past_the_first_bend_on_the_hardest_tier() -> bool:
	var mid := Harness.run_wave({"wave": 10, "towers": _mid_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(mid["deepest_progress"] > FIRST_BEND_FRACTION,
		"wave 10 gets past the bend against a mid-run board, reached %f"
			% mid["deepest_progress"])

	var full := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(full["deepest_progress"] > FIRST_BEND_FRACTION,
		"and the last wave does against a full one, reached %f"
			% full["deepest_progress"])
	return true

## Normal keeps its shape, by owner decision (2026-08-29): a full maxed board
## should win wave 20 comfortably. Pinned so a later tier change cannot make
## the default harder as a side effect.
func test_a_full_maxed_board_still_wins_on_normal() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NORMAL})
	assert_eq(r["leaks"], 0, "Normal stays comfortable for a completed board")
	return true

## Hard's brief, pinned: real lives late, without ending the run. A full maxed
## board must lose some of its fifteen lives on the last wave and still have
## some left.
func test_hard_costs_a_full_board_real_lives_without_ending_the_run() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.HARD})
	assert_true(r["lives_lost"] > 0, "Hard's last wave costs a full board lives")
	assert_true(r["lives_lost"] < Difficulty.starting_lives(Difficulty.HARD),
		"but not the whole budget, lost %s of %s"
			% [r["lives_lost"], Difficulty.starting_lives(Difficulty.HARD)])
	return true
