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

## The best any legal fully-upgraded board manages on a wave, by lives lost.
##
## Measured rather than named. An earlier version of this file hardcoded "every
## kind on sustained" as the strongest board, which was true when splash was on
## three towers and false the moment it went back to one. Claims about "the best
## board" have to find it, or they quietly become claims about whichever board
## used to be best.
func _best_board_result(tier: StringName, wave: int) -> Dictionary:
	var path := _full_path()
	var best := {}
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": wave, "towers": board["towers"],
			"path": path, "difficulty": tier})
		if best.is_empty() or int(r["lives_lost"]) < int(best["lives_lost"]):
			best = r
			best["_name"] = board["name"]
	return best

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

	var path := _full_path()
	for board in _every_legal_maxed_board():
		var full := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		assert_true(full["deepest_progress"] > FIRST_BEND_FRACTION,
			"and the last wave does against full board %s, reached %f"
				% [board["name"], full["deepest_progress"]])
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
## BEST board there is, found by measurement, because a brief that only holds
## for a weak build is the defect this file was rewritten to catch.
func test_hard_costs_the_strongest_board_real_lives_without_ending_the_run() -> bool:
	var r := _best_board_result(Difficulty.HARD, Waves.MAX_WAVES)
	assert_true(r["lives_lost"] > 0, "Hard's last wave costs a full board lives")
	assert_true(r["lives_lost"] < Difficulty.starting_lives(Difficulty.HARD),
		"but not the whole budget, lost %s of %s"
			% [r["lives_lost"], Difficulty.starting_lives(Difficulty.HARD)])
	return true


## The two upgrade branches must stay close to each other.
##
## Measured at wave 30, well past anything a board can hold, and NOT at wave 20.
## That reference is load-bearing and was got wrong once already: at the wave a
## tier is actually decided, the best board loses almost nothing and the worst
## loses a lot, so the ratio measures where the threshold sits rather than how
## far apart the branches are. The same roster read 6.90x at wave 20 and 1.68x
## at wave 30, and moving Nightmare's health by a quarter swung the wave-20
## figure from 12.40x to undefined. A ratio needs both sides to be graded.
##
## Verified against the roster this replaced, by putting splash back on Basic
## and Long Range and re-running: 3.18x, over the bound. With splash confined to
## the Mortar it reads 1.68x. So the bound catches the defect it was written for
## rather than merely describing the fix.
##
## Pinned as a RATIO, not a pair of figures, so re-tuning the difficulty rows
## moves both sides together and leaves the claim intact. Before this work the
## all-sustained board lost 9 lives across a Nightmare run where the all-burst
## board lost 336, which made the branch choice not a choice.
##
## This is the third attempt at an assertion that catches a runaway build, and
## the first that pins a BOUND rather than a board. The six-tower benchmark
## missed it, then the twelve-tower single-split benchmark missed it. A bound
## cannot be satisfied by picking a convenient example.
const MAX_BRANCH_SPREAD := 3.0

## Deep enough that every legal board is overwhelmed, so the comparison is
## graded rather than binary. Composition accumulates from wave 1, so this is a
## real wave the rules already describe, not a synthetic one.
const BRANCH_SPREAD_WAVE := 30

func test_no_upgrade_branch_runs_away_from_the_other() -> bool:
	var path := _full_path()
	var best := 1 << 30
	var worst := 0
	var worst_name := ""
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": BRANCH_SPREAD_WAVE, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		var lost := int(r["lives_lost"])
		if lost > worst:
			worst = lost
			worst_name = board["name"]
		best = mini(best, lost)
	assert_true(best > 0, "every legal board is overwhelmed at the reference wave")
	assert_true(float(worst) <= float(best) * MAX_BRANCH_SPREAD,
		"worst board %s lost %d against the best board's %d, over the %.1fx bound"
			% [worst_name, worst, best, MAX_BRANCH_SPREAD])
	return true


# --------------------------------------------------------------------------
# Placing twelve towers on a map nobody hardcoded
# --------------------------------------------------------------------------

## Every lane of a map, in the order PathFinder reports them.
func _lanes_for(map_name: StringName) -> Array:
	Grid.set_active(Maps.cols(map_name), Maps.rows(map_name))
	return PathFinder.get_all_spawn_paths(Maps.build_tiles(map_name))

## The map's whole tower budget, spaced along its lanes.
##
## THE RULE, stated because a benchmark whose placement is not stated is a
## number nobody can argue with: walk each lane, take evenly spaced points along
## it, and put a tower at the nearest legal spot to each. The budget is divided
## between the lanes rather than spread over a concatenated route - six and six
## on a two-lane map - because both lanes carry the same wave, and spacing by
## total distance would under-cover the shorter one.
##
## Legality is asked of Placement.can_place, the same rule the board enforces,
## rather than reimplemented. Props are deliberately passed as EMPTY: decoration
## is seeded, and a benchmark that moved with the decoration seed would not be a
## benchmark. Build space against decoration is test_placement.gd's job.
func _spread_positions(map_name: StringName) -> Array[Vector2]:
	var lanes := _lanes_for(map_name)
	var budget := int(Maps.get_def(map_name)["tower_budget"])
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(map_name)))
	var radius := Placement.tower_radius(&"basic")
	var tiles := Maps.build_tiles(map_name)

	var positions: Array[Vector2] = []
	var per_lane := int(ceil(float(budget) / float(maxi(1, lanes.size()))))
	for lane in lanes:
		for i in per_lane:
			if positions.size() >= budget:
				break
			var at := int(float(lane.size() - 1) * (float(i) + 0.5) / float(per_lane))
			var spot := _nearest_legal(lane[at], tiles, positions, lanes, bounds, radius)
			if spot != Vector2.INF:
				positions.append(spot)
	return positions

## The legal tile centre closest to a point on the route, searched outward so
## the tower lands beside the road it is meant to cover.
func _nearest_legal(near: Vector2, tiles: Array, placed: Array, lanes: Array,
		bounds: Rect2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for r in tiles.size():
		for c in tiles[r].size():
			var pos := Grid.tile_to_world_center(c, r)
			var distance := pos.distance_to(near)
			if distance >= best_distance:
				continue
			if Placement.can_place(pos, radius, [], placed, lanes, bounds)["ok"]:
				best = pos
				best_distance = distance
	return best

## Twelve towers on any map, each kind on the split named for it.
func _board_on(map_name: StringName, splits: Array) -> Array:
	var positions := _spread_positions(map_name)
	var towers: Array = []
	var per_kind := int(positions.size() / Towers.KINDS.size())
	var i := 0
	for k in Towers.KINDS.size():
		for n in per_kind:
			towers.append({"kind": Towers.KINDS[k],
				"position": positions[i], "tiers": splits[k]})
			i += 1
	return towers

# Where twelve towers land decides what a benchmark says, so the rule is stated
# and pinned rather than left to whatever the loop happened to find. A naive
# "first twelve legal tiles" clusters them in a corner and makes a map look far
# worse than it plays.
func test_every_generated_position_is_one_the_board_would_accept() -> bool:
	for map_name in Maps.DEFS:
		var positions := _spread_positions(map_name)
		var budget := int(Maps.get_def(map_name)["tower_budget"])
		assert_eq(positions.size(), budget,
			"%s yields its whole budget of %d" % [map_name, budget])

		Grid.set_active(Maps.cols(map_name), Maps.rows(map_name))
		var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(map_name)))
		var radius := Placement.tower_radius(&"basic")
		var placed: Array = []
		for pos in positions:
			var verdict := Placement.can_place(
				pos, radius, [], placed, _lanes_for(map_name), bounds)
			assert_true(verdict["ok"],
				"%s position %s is legal, got %s" % [map_name, pos, verdict])
			placed.append(pos)
	return true
