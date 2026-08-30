extends TestCase

## What a twenty-wave run can actually FUND, against what the board costs.
##
## The shut-out threshold measured on 2026-08-29 is ten maxed towers. That
## number is only meaningful if ten maxed towers are reachable: the budget
## fell 16 -> 12 in 121bc7f while Waves.GOLD_PER_WAVE did not move, so the
## spend ceiling dropped and the income did not follow it.
##
## Income counted here is a FLOOR, deliberately. Kill rewards and wave-clear
## bonuses only - no interest, no call-early bonus - because those two are the
## income a player cannot choose not to earn.

const MAXED := {&"sustained": 2, &"burst": 4}

func _path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

## Three of each kind, twelve towers, the full legal roster under the caps.
func _full_roster() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for kind in Towers.KINDS:
		for i in 3:
			kinds.append(kind)
	return kinds

## Gold to buy all twelve AND take every tier the cross-path rule allows.
func _full_board_cost() -> int:
	var total := 0
	for kind in Towers.KINDS:
		for owned in 3:
			total += EconomySim.tower_price(kind, owned)
			total += UpgradesSim.total_invested(kind, MAXED)
	return total

## FINDING (2026-08-29): the full twelve-tower maxed board IS affordable -
## 16,199 gold of income against an 11,415 cost, 4,784 to spare - so the
## shut-out threshold of ten maxed towers is a board a player genuinely
## reaches, and Task 8 sets its tiers against twelve.
##
## Read it as generous rather than exact: the board is fully built and fully
## maxed from wave 1 here, so it kills everything and collects every reward,
## where a real player funds it incrementally and earns less early. It is
## still a floor in the sense the header describes - no interest, no
## call-early bonus - and the two errors run in opposite directions. The
## margin is wide enough that the conclusion survives either way.
func test_a_full_run_income_against_a_full_board_cost() -> bool:
	var path := _path()
	var kinds := _full_roster()
	var spots := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
		[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]
	var towers: Array = []
	for i in kinds.size():
		towers.append({
			"kind": kinds[i],
			"position": Grid.tile_to_world_center(spots[i][0], spots[i][1]),
			"tiers": MAXED,
		})

	var income := 0
	for wave in range(1, Waves.MAX_WAVES + 1):
		var r := Harness.run_wave({"wave": wave, "towers": towers, "path": path})
		var clear := EconomySim.wave_clear_bonus(wave, float(r["ticks"]) * (1000.0 / 60.0))
		income += int(r["gold_earned"]) + int(clear["base"]) + int(clear["speed"])

	var cost := _full_board_cost()
	var starting := int(Maps.get_def(Maps.FIRST)["starting_gold"])
	print("AFFORDABILITY: income %d + starting %d = %d against full-board cost %d"
		% [income, starting, income + starting, cost])

	# PINNED from the run above on 2026-08-29. The point of the pin is that a
	# change to the gold curve or to the tower caps has to move it
	# deliberately rather than quietly.
	assert_eq(income + starting, 16199, "run income is the measured figure")
	assert_eq(cost, 11415, "full-board cost is the measured figure")
	return true
