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
## The two fully-upgraded splits the cross-path rule allows: a branch passes
## tier 2 only while the other sits at 2 or below, so six tiers land either
## way. SUSTAINED buys fire rate and then splash; BURST buys damage and pierce.
const SUSTAINED := {&"sustained": 4, &"burst": 2}
const BURST := {&"sustained": 2, &"burst": 4}

## The split every benchmark here used to assume, and the reason this file was
## rewritten: it is the WEAKER of the two against late waves, by two orders of
## magnitude. Pinning one build is how a board that shut the hardest tier out
## went on reading as balanced after the benchmark grew from six towers to
## twelve.
const MAXED := BURST

## The Pass is 2,448px end to end and its first bend is 768px in.
const FIRST_BEND_FRACTION := 0.31

func _full_path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

const SPOTS := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
	[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]

## Twelve towers, three of each kind, each kind on the split named for it.
func _board_with(splits: Array) -> Array:
	var towers: Array = []
	var i := 0
	for k in Towers.KINDS.size():
		for n in 3:
			towers.append({"kind": Towers.KINDS[k],
				"position": Grid.tile_to_world_center(SPOTS[i][0], SPOTS[i][1]),
				"tiers": splits[k]})
			i += 1
	return towers

## Every legal fully-upgraded board: each of the four kinds independently takes
## one of the two maxed splits, so there are 2^4 = 16 of them. Cheap to walk -
## the whole set is a few seconds - and the only honest way to ask whether a
## tier can be shut out.
func _every_legal_maxed_board() -> Array:
	var boards: Array = []
	for mask in 16:
		var splits: Array = []
		var name := ""
		for k in Towers.KINDS.size():
			var burst := ((mask >> k) & 1) == 1
			splits.append(BURST if burst else SUSTAINED)
			name += "B" if burst else "S"
		boards.append({"name": name, "towers": _board_with(splits)})
	return boards

## The strongest of the sixteen, measured: every kind on sustained. Splash is
## what answers a late wave, and both towers that can buy it do.
func _strongest_board() -> Array:
	return _board_with([SUSTAINED, SUSTAINED, SUSTAINED, SUSTAINED])

func _full_board() -> Array:
	return _board_with([MAXED, MAXED, MAXED, MAXED])

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

## THE assertion this whole change exists to make, and the one that had to be
## rewritten after it let a shut-out board through.
##
## Directional rather than a magic number, so it survives future retuning; and
## asked of EVERY legal fully-upgraded board rather than one, because the first
## version pinned a single upgrade split and eleven of the sixteen legal boards
## shut Nightmare's last wave out with zero leaks. "A full maxed board" is not
## one board. Whatever else moves, no way of spending the full budget may make
## the hardest tier a walkover.
func test_no_legal_maxed_board_shuts_out_the_hardest_tier() -> bool:
	var path := _full_path()
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		assert_true(r["leaks"] > 0,
			"board %s must not shut out Nightmare's last wave, got %s" % [board["name"], r])
		assert_false(r["timed_out"], "board %s completes" % board["name"])
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

	var full := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _strongest_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(full["deepest_progress"] > FIRST_BEND_FRACTION,
		"and the last wave does against the strongest full board, reached %f"
			% full["deepest_progress"])
	return true

## Normal keeps its shape, by owner decision (2026-08-29): a full maxed board
## should win wave 20 comfortably. Pinned so a later tier change cannot make
## the default harder as a side effect.
func test_every_maxed_board_still_wins_on_normal() -> bool:
	var path := _full_path()
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NORMAL})
		assert_eq(r["leaks"], 0,
			"Normal stays comfortable for completed board %s" % board["name"])
	return true

## Hard's brief, pinned: real lives late, without ending the run. Asked of the
## STRONGEST board, because a brief that only holds for a weak build is the
## defect this file was rewritten to catch.
func test_hard_costs_the_strongest_board_real_lives_without_ending_the_run() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _strongest_board(),
		"path": _full_path(), "difficulty": Difficulty.HARD})
	assert_true(r["lives_lost"] > 0, "Hard's last wave costs a full board lives")
	assert_true(r["lives_lost"] < Difficulty.starting_lives(Difficulty.HARD),
		"but not the whole budget, lost %s of %s"
			% [r["lives_lost"], Difficulty.starting_lives(Difficulty.HARD)])
	return true


## The two upgrade branches must stay close to each other.
##
## Pinned as a RATIO, not a pair of figures, so re-tuning the difficulty rows
## moves both sides together and leaves the claim intact. Measured 2026-08-30 at
## 37x before this work: the all-sustained board lost 9 lives across a Nightmare
## run where the all-burst board lost 336, which made the branch choice not a
## choice. Returning splash to the Mortar brought it to 2.01x on its own, with
## no tuning of the flat values at all - so the gap was never about the numbers,
## it was about three towers being able to buy the same answer.
##
## This is the third attempt at an assertion that catches a runaway build, and
## the first that pins a BOUND rather than a board. The six-tower benchmark
## missed it, then the twelve-tower single-split benchmark missed it. A bound
## cannot be satisfied by picking a convenient example.
const MAX_BRANCH_SPREAD := 3.0

func test_no_upgrade_branch_runs_away_from_the_other() -> bool:
	var path := _full_path()
	var best := 1 << 30
	var worst := 0
	var worst_name := ""
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		var lost := int(r["lives_lost"])
		if lost > worst:
			worst = lost
			worst_name = board["name"]
		best = mini(best, lost)
	assert_true(best > 0, "every legal board loses something on Nightmare's last wave")
	assert_true(float(worst) <= float(best) * MAX_BRANCH_SPREAD,
		"worst board %s lost %d against the best board's %d, over the %.1fx bound"
			% [worst_name, worst, best, MAX_BRANCH_SPREAD])
	return true
