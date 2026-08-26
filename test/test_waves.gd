extends TestCase

func _count_of(wave: int, kind: StringName) -> int:
	for entry in Waves.get_composition(wave):
		if entry["kind"] == kind:
			return entry["count"]
	return 0

func test_max_waves_is_twenty() -> bool:
	assert_eq(Waves.MAX_WAVES, 20, "victory at wave 20")
	return true

func test_wave_one_is_five_goblins() -> bool:
	assert_eq(_count_of(1, &"goblin"), 5, "five goblins")
	assert_eq(_count_of(1, &"bat"), 0, "no bats yet")
	assert_eq(_count_of(1, &"ogre"), 0, "no ogres yet")
	return true

# Composition ACCUMULATES from wave 1, so wave 3 contains waves 1 and 2 too.
# This is surprising and is preserved deliberately.
func test_composition_accumulates_from_wave_one() -> bool:
	assert_eq(_count_of(2, &"goblin"), 8, "5 + 3")
	assert_eq(_count_of(2, &"bat"), 3, "0 + 3")
	assert_eq(_count_of(3, &"goblin"), 11, "5 + 3 + 3")
	assert_eq(_count_of(3, &"bat"), 6, "3 + 3")
	return true

func test_ogres_arrive_at_wave_four() -> bool:
	assert_eq(_count_of(3, &"ogre"), 0, "no ogres at wave 3")
	assert_eq(_count_of(4, &"ogre"), 2, "two ogres at wave 4")
	return true

func test_wave_five_totals() -> bool:
	assert_eq(_count_of(5, &"goblin"), 14, "5+3+3+0+3")
	assert_eq(_count_of(5, &"bat"), 9, "3+3+0+3")
	assert_eq(_count_of(5, &"ogre"), 3, "2+1")
	return true

func test_beyond_wave_five_adds_a_fixed_bundle() -> bool:
	assert_eq(_count_of(6, &"goblin"), 16, "14 + 2")
	assert_eq(_count_of(6, &"bat"), 14, "9 + 5")
	assert_eq(_count_of(6, &"ogre"), 5, "3 + 2")
	assert_eq(_count_of(7, &"goblin"), 18, "two bundles past wave 5")
	return true

func test_modifiers_are_flat_through_wave_five() -> bool:
	for w in range(1, 6):
		var m := Waves.get_modifiers(w)
		assert_almost_eq(m["health_modifier"], 1.0, 0.0001, "wave %d health flat" % w)
		assert_almost_eq(m["speed_modifier"], 1.0, 0.0001, "wave %d speed flat" % w)
	return true

func test_modifiers_scale_past_wave_five() -> bool:
	var m10 := Waves.get_modifiers(10)
	assert_almost_eq(m10["health_modifier"], 1.5, 0.0001, "wave 10 health +50%")
	assert_almost_eq(m10["speed_modifier"], 1.25, 0.0001, "wave 10 speed +25%")
	var m20 := Waves.get_modifiers(20)
	assert_almost_eq(m20["health_modifier"], 2.5, 0.0001, "wave 20 health +150%")
	assert_almost_eq(m20["speed_modifier"], 1.75, 0.0001, "wave 20 speed +75%")
	return true

func test_ogre_delay_trails_the_last_goblin_but_is_capped() -> bool:
	assert_almost_eq(Waves.ogre_spawn_delay(5), 5000.0, 0.001, "4*500 + 3000")
	assert_almost_eq(Waves.ogre_spawn_delay(30), 10000.0, 0.001, "capped at 10s")
	return true

func test_composition_returns_fresh_objects() -> bool:
	var a := Waves.get_composition(5)
	a[0]["count"] = 999
	var b := Waves.get_composition(5)
	assert_false(b[0]["count"] == 999, "callers cannot corrupt later waves")
	return true

# --------------------------------------------------------------------------
# build_schedule — Task 14 pulled this out of Harness (where the original
# brief had it as a private _build_schedule) into a public function here, so
# Task 19's live game board and the headless harness share one
# implementation of when things spawn.
# --------------------------------------------------------------------------

func test_build_schedule_is_sorted_by_time() -> bool:
	# Wave 5 mixes all three kinds with three different start offsets
	# (goblin immediately, bat after BAT_START_DELAY_MS, ogre after the last
	# goblin), so a sort bug is actually reachable here, unlike a
	# single-kind wave.
	var schedule := Waves.build_schedule(5)
	for i in range(1, schedule.size()):
		assert_true(schedule[i]["at_ms"] >= schedule[i - 1]["at_ms"],
			"entry %d (%.1f) is not before entry %d (%.1f)" % [
				i - 1, schedule[i - 1]["at_ms"], i, schedule[i]["at_ms"]])
	return true

func test_wave_four_schedule_has_nineteen_entries() -> bool:
	# Wave 4's composition is 11 goblins + 6 bats + 2 ogres (accumulated from
	# waves 1-4; see test_ogres_arrive_at_wave_four /
	# test_composition_accumulates_from_wave_one above) = 19 spawn instants.
	var schedule := Waves.build_schedule(4)
	assert_eq(schedule.size(), 19, "11 goblins + 6 bats + 2 ogres")
	var goblins := 0
	var bats := 0
	var ogres := 0
	for entry in schedule:
		match entry["kind"]:
			&"goblin": goblins += 1
			&"bat": bats += 1
			&"ogre": ogres += 1
	assert_eq(goblins, 11, "eleven goblin entries")
	assert_eq(bats, 6, "six bat entries")
	assert_eq(ogres, 2, "two ogre entries")
	return true

# BAT_START_DELAY_MS had zero test coverage before this task: mutating 5000
# to 9999 left the whole suite green. Pin the constant directly...
func test_bee_start_delay_ms_is_five_thousand() -> bool:
	assert_almost_eq(Waves.BAT_START_DELAY_MS, 5000.0, 0.001, "bats wait five seconds")
	return true

# ...and, more importantly, pin it through the one place it actually has an
# effect: the schedule the harness and the live board both spawn from. A
# mutation to BAT_START_DELAY_MS that the constant test above somehow missed
# (or a future refactor that stops build_schedule from reading the constant
# at all) would still be caught here, because the earliest bat's at_ms is
# asserted directly against the real constant, not a hardcoded literal.
func test_schedule_starts_the_bee_column_at_bee_start_delay() -> bool:
	# Wave 2 is the first wave with bats (three of them) and no ogres, so the
	# earliest bat entry is unambiguous.
	var schedule := Waves.build_schedule(2)
	var earliest_bee = null
	for entry in schedule:
		if entry["kind"] == &"bat":
			earliest_bee = entry
			break
	assert_true(earliest_bee != null, "wave 2 has bats")
	assert_almost_eq(earliest_bee["at_ms"], Waves.BAT_START_DELAY_MS, 0.001,
		"the bat column starts at BAT_START_DELAY_MS, not some other offset")
	return true

# The ogre column's start time has the same shape of gap the bat tests above
# close: ogre_spawn_delay(goblin_count) is unit-tested directly (see
# test_ogre_delay_trails_the_last_goblin_but_is_capped above), but nothing
# pinned that build_schedule (a) calls it with the wave's own goblin count
# rather than some other kind's count, or (b) calls it at all rather than a
# fixed constant. Both are real, distinct mutations found by mutation
# testing sim/harness.gd and this file together: capturing goblin_count from
# the wrong kind's composition entry, and hardcoding the ogre column to
# start at BAT_START_DELAY_MS instead of the computed delay. Both survived
# every other test in this file (schedule size, sort order, entry counts)
# because none of those look at a specific entry's `at_ms`.
func test_schedule_starts_the_ogre_column_at_the_computed_delay() -> bool:
	# Wave 4 has 11 goblins (see test_wave_four_schedule_has_nineteen_entries
	# above) and 2 ogres, so ogre_spawn_delay(11) = (11-1)*500 + 3000 = 8000,
	# under the 10000 cap. Hardcoded rather than computed via
	# Waves.ogre_spawn_delay(11) here, so this test does not become
	# vacuously self-consistent if that function itself ever regresses.
	var schedule := Waves.build_schedule(4)
	var earliest_ogre = null
	for entry in schedule:
		if entry["kind"] == &"ogre":
			earliest_ogre = entry
			break
	assert_true(earliest_ogre != null, "wave 4 has ogres")
	assert_almost_eq(earliest_ogre["at_ms"], 8000.0, 0.001,
		"the ogre column starts at ogre_spawn_delay(11), not BAT_START_DELAY_MS or any other offset")
	return true

# Review follow-up (post-Task-14): Array.sort_custom is not documented as a
# stable sort on this engine, so a comparator keyed only on at_ms leaves
# tied entries (same at_ms, different kind) in an order that is an artifact
# of the sort implementation rather than the wave data. build_schedule
# breaks ties on push order — composition order is goblin, then bat, then
# ogre (see test_composition_accumulates_from_wave_one /
# test_ogres_arrive_at_wave_four), and within a kind, increasing spawn
# index — mirroring the reference's
# `a.spawn.atMs - b.spawn.atMs || a.index - b.index`
# (td-browser/src/game/sim/harness.ts), whose own comment states the reason
# outright: "so the schedule does not depend on the sort implementation."
#
# test_build_schedule_is_sorted_by_time above uses wave 5, which has zero
# *cross-column* ties at a boundary this test needs (it has goblin/bat ties
# but no bat/ogre ones), so it cannot exercise the ogre column's tie-break.
# Wave 6 has both, ten tied at_ms instants total.
#
# This checks every tied group at wave 6, not one or two cherry-picked
# timestamps — that distinction is not academic. A first version of this
# test asserted only the 5000ms and 10000ms groups and passed even with the
# tie-break deleted entirely (comparator reverted to bare
# `a["at_ms"] < b["at_ms"]`): confirmed directly, by reverting the fix and
# re-running, that on this exact engine build sort_custom's own partitioning
# happens to leave both of those two particular groups in push order by
# coincidence. The very next tied instant, 5500ms, does NOT: the no-tie-break
# comparator puts bat before goblin there, backwards from push order.
# Checking the whole set (not a sample) is what makes this test load-bearing
# rather than a false sense of coverage.
func test_build_schedule_breaks_ties_by_push_order() -> bool:
	# Composition order is goblin, then bat, then ogre (see
	# test_composition_accumulates_from_wave_one / test_ogres_arrive_at_wave_four),
	# so within any tied at_ms, the earlier-pushed kind must sort first.
	var rank := {&"goblin": 0, &"bat": 1, &"ogre": 2}
	var schedule := Waves.build_schedule(6)
	var groups := {}
	for entry in schedule:
		var t = entry["at_ms"]
		if not groups.has(t):
			groups[t] = []
		groups[t].append(entry["kind"])
	var tie_groups_checked := 0
	for t in groups.keys():
		var kinds: Array = groups[t]
		if kinds.size() < 2:
			continue
		tie_groups_checked += 1
		for i in range(1, kinds.size()):
			assert_true(rank[kinds[i - 1]] <= rank[kinds[i]],
				"at %.1fms, %s must not sort after %s (push order: goblin, bat, ogre)" % [
					t, kinds[i - 1], kinds[i]])
	# Confirms the loop above actually exercised ties rather than vacuously
	# passing over a schedule with none (e.g. if get_composition regressed).
	assert_eq(tie_groups_checked, 10, "wave 6 has exactly ten tied at_ms instants to check")
	return true

# --------------------------------------------------------------------------
# The gold modifier (spec 2026-08-24-slice-0-design.md section 4.6)
# --------------------------------------------------------------------------

func test_gold_modifier_is_flat_through_wave_five() -> bool:
	for w in range(1, 6):
		var m := Waves.get_modifiers(w)
		assert_almost_eq(m["gold_modifier"], 1.0, 0.0001, "wave %d gold flat" % w)
	return true

func test_gold_modifier_decays_past_wave_five() -> bool:
	var m10 := Waves.get_modifiers(10)
	assert_almost_eq(m10["gold_modifier"], 0.875, 0.0001, "wave 10: 1.0 - 5*0.025")
	var m20 := Waves.get_modifiers(20)
	assert_almost_eq(m20["gold_modifier"], 0.625, 0.0001, "wave 20: 1.0 - 15*0.025")
	return true

# The floor is a safety rail for endless play, not part of the 20-wave tuning:
# at wave 20 the modifier is 0.625, well clear of it. This test exists so that
# stays true, and so nobody "simplifies" the maxf away.
func test_gold_modifier_never_falls_below_the_floor() -> bool:
	var deep := Waves.get_modifiers(100)
	assert_almost_eq(deep["gold_modifier"], Waves.MIN_GOLD_MODIFIER, 0.0001,
		"a very deep wave clamps at the floor rather than going negative")
	assert_true(Waves.get_modifiers(20)["gold_modifier"] > Waves.MIN_GOLD_MODIFIER,
		"but the floor does not bind anywhere inside the twenty-wave run")
	return true

func test_gold_modifier_shrinks_where_health_and_speed_grow() -> bool:
	var m := Waves.get_modifiers(15)
	assert_true(m["health_modifier"] > 1.0, "health scales up")
	assert_true(m["speed_modifier"] > 1.0, "speed scales up")
	assert_true(m["gold_modifier"] < 1.0, "and gold scales down")
	return true
