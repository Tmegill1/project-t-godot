extends TestCase

# Are the tiers playable from the first wave?
#
# THIS FILE EXISTS BECAUSE EVERY EARLIER SWEEP ASKED THE WRONG BOARD. Hard and
# Nightmare were tuned against a completed, fully-maxed twelve-tower board and
# looked reasonable there. Measured on 2026-08-31 against a player who starts
# with two towers and buys what they can afford, both killed that player on
# WAVE 3 of twenty, on the easiest map - and no amount of ramping the tier in,
# extra lives, extra income or a larger opening purse moved it past wave 14.
#
# A fully-maxed board is roughly TEN TIMES a full-but-unupgraded one, so a tier
# is not one difficulty - it is one curve across a run in which the player's
# board spans that range. The owner's decision was to put the difficulty in the
# BUILD-OUT, where measurement says the run is actually decided.
#
# So this simulates a player rather than a board. It is a FLOOR, not a ceiling:
# it buys the cheapest legal thing whenever it can afford it, never sells, never
# re-places, and never calls a wave early. A real player does better. If this
# player can reach the end of Normal and be pressed on Hard, the tiers are
# playable; if it dies on wave 3, they are not, whatever a maxed board says.

## The Pass's first bend, 768px into its 2,448px route.
const FIRST_BEND_FRACTION := 0.31

func _path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

## Where a player would put the towers they have RIGHT NOW - spaced along the
## route, recomputed every time the board grows.
##
## This is not a nicety. A fixed list of twelve slots, walked in order, puts the
## first two towers side by side at the entrance covering one window between
## them; spacing two towers along the route gives an enemy two windows to walk
## through. Measured, the difference is a run that dies on wave 10 and a run
## that finishes with 7 lives. A benchmark of a BUILD-OUT has to place like a
## player building, or it measures the fixture.
##
## Mirrors test_balance_tuning.gd's placement rule, asked of Placement.can_place
## the same way. Duplicated rather than shared because these are two test files
## and GDScript gives them no common ground short of a class.
func _spread(count: int) -> Array[Vector2]:
	var path := _path()
	var tiles := Maps.build_tiles(Maps.FIRST)
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(Maps.FIRST)))
	var radius := Placement.tower_radius(&"basic")
	var out: Array[Vector2] = []
	for i in count:
		var at := int(float(path.size() - 1) * (float(i) + 0.5) / float(count))
		var best := Vector2.INF
		var best_distance := INF
		for r in tiles.size():
			for c in tiles[r].size():
				var pos := Grid.tile_to_world_center(c, r)
				var distance := pos.distance_to(path[at])
				if distance >= best_distance:
					continue
				if Placement.can_place(pos, radius, [], out, [path], bounds)["ok"]:
					best = pos
					best_distance = distance
		if best != Vector2.INF:
			out.append(best)
	return out

## Plays a whole run at a tier and reports how it went.
##
## Returns lives left (negative or zero means the run was lost), the wave it
## ended on, and the furthest any enemy ever reached.
func _play(tier: StringName) -> Dictionary:
	var path := _path()
	var gold := int(Maps.get_def(Maps.FIRST)["starting_gold"])
	var lives := Difficulty.starting_lives(tier)
	var budget := int(Maps.get_def(Maps.FIRST)["tower_budget"])
	var counts := {}
	for kind in Towers.KINDS:
		counts[kind] = 0
	var towers: Array = []
	var deepest := 0.0
	var reached := 0

	for wave in range(1, Waves.MAX_WAVES + 1):
		reached = wave
		while towers.size() < budget:
			var kind: StringName = &""
			var price := 1 << 30
			for candidate in Towers.KINDS:
				if counts[candidate] >= EconomySim.tower_limit(candidate, Maps.FIRST):
					continue
				var p := EconomySim.tower_price(candidate, counts[candidate])
				if p < price:
					price = p
					kind = candidate
			if kind == &"" or price > gold:
				break
			gold -= price
			var spread := _spread(towers.size() + 1)
			if spread.size() <= towers.size():
				break
			towers.append({"kind": kind, "position": spread[towers.size()],
				"tiers": UpgradesSim.empty_tiers()})
			for i in towers.size():
				towers[i]["position"] = spread[i]
			counts[kind] += 1

		while true:
			var index := -1
			var branch_to_buy: StringName = &""
			var cost := 1 << 30
			for i in towers.size():
				for branch in Upgrades.BRANCHES:
					if not UpgradesSim.can_upgrade(towers[i]["tiers"], branch):
						continue
					var c := UpgradesSim.upgrade_cost(towers[i]["kind"], branch,
						int(towers[i]["tiers"][branch]))
					if c < cost:
						cost = c
						index = i
						branch_to_buy = branch
			if index < 0 or cost > gold:
				break
			gold -= cost
			towers[index]["tiers"] = UpgradesSim.with_upgrade(
				towers[index]["tiers"], branch_to_buy)

		var r := Harness.run_wave({"wave": wave, "towers": towers,
			"path": path, "difficulty": tier})
		lives -= int(r["lives_lost"])
		deepest = maxf(deepest, float(r["deepest_progress"]))
		var clear := EconomySim.wave_clear_bonus(wave, float(r["ticks"]) * (1000.0 / 60.0))
		gold += int(r["gold_earned"]) + int(clear["base"]) + int(clear["speed"]) \
			+ EconomySim.interest_on(gold)
		if lives <= 0:
			break
	return {"lives": lives, "reached": reached, "deepest": deepest}

func test_a_spending_player_finishes_normal() -> bool:
	var run := _play(Difficulty.NORMAL)
	assert_eq(int(run["reached"]), Waves.MAX_WAVES, "Normal is finished, not survived by luck")
	assert_true(int(run["lives"]) > 0, "with lives to spare, %s left" % run["lives"])
	return true

## Hard's brief: pressed the whole way, without the run ever being lost. It used
## to be "costs a completed board real lives on wave 20", which a completed
## board can afford and a building player cannot.
func test_hard_presses_a_spending_player_without_ending_the_run() -> bool:
	var normal := _play(Difficulty.NORMAL)
	var hard := _play(Difficulty.HARD)
	assert_eq(int(hard["reached"]), Waves.MAX_WAVES, "Hard is finishable")
	assert_true(int(hard["lives"]) > 0, "and finished, %s lives left" % hard["lives"])
	assert_true(int(hard["lives"]) < int(normal["lives"]),
		"but it costs more than Normal: %s left against Normal's %s"
			% [hard["lives"], normal["lives"]])
	return true

## Nightmare is meant to beat this player and not a good one. The simulation
## buys the cheapest legal thing and never calls a wave early, so losing late is
## the shape wanted - losing on wave 3, which is what the old rows did, is not.
func test_nightmare_beats_a_careless_player_late_rather_than_early() -> bool:
	var run := _play(Difficulty.NIGHTMARE)
	assert_true(int(run["reached"]) > Waves.MAX_WAVES / 2,
		"Nightmare is played, not merely lost: reached wave %s of %d"
			% [run["reached"], Waves.MAX_WAVES])
	var hard := _play(Difficulty.HARD)
	assert_true(int(run["lives"]) < int(hard["lives"]),
		"and it is harder than Hard, %s against %s" % [run["lives"], hard["lives"]])
	return true

## The owner's original complaint, as a permanent assertion, asked of the board
## a player actually holds rather than of a completed one.
func test_enemies_get_past_the_first_bend_on_the_hardest_tier() -> bool:
	var run := _play(Difficulty.NIGHTMARE)
	assert_true(float(run["deepest"]) > FIRST_BEND_FRACTION,
		"enemies get past the first bend during a Nightmare run, furthest %f"
			% run["deepest"])
	return true

## Every tier must be reachable at all. A tier nobody can start is not a
## difficulty setting.
func test_no_tier_ends_a_run_in_its_opening_waves() -> bool:
	for tier in Difficulty.ORDER:
		var run := _play(tier)
		assert_true(int(run["reached"]) > 5,
			"%s survives its opening, ended on wave %s" % [tier, run["reached"]])
	return true
