extends TestCase

## Ported from harness.test.ts, narrowed to this port's interface: no seed
## (nothing in this slice draws from an RNG, so determinism is unconditional),
## no composition override, no lieutenants/bosses/insignia/powers/shots-fired/
## damage-dealt fields — none of that exists in the core slice. Every test
## below either ports directly, ports with a value substituted because the
## reference's exact scenario needs a field this interface doesn't expose, or
## is new and specific to this harness. See task-14-report.md for the full
## line-by-line mapping and what was deliberately not ported.

func _path() -> PackedVector2Array:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	return PathFinder.get_path_from_spawn_to_goal(
		DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED)))

func _total_spawn_count(wave: int) -> int:
	var total := 0
	for entry in Waves.get_composition(wave):
		total += int(entry["count"])
	return total

# --------------------------------------------------------------------------
# Brief's tests, verbatim.
# --------------------------------------------------------------------------

func test_an_undefended_wave_leaks_everything() -> bool:
	var r := Harness.run_wave({"wave": 1, "towers": [], "path": _path()})
	assert_eq(r["kills"], 0, "no towers, no kills")
	assert_eq(r["leaks"], 5, "all five slimes leak")
	assert_eq(r["lives_lost"], 5, "one life each at wave 1")
	assert_false(r["timed_out"], "the wave completed")
	# Ported: "earns no gold" (harness.test.ts "an undefended lane").
	assert_eq(r["gold_earned"], 0, "nothing killed, nothing earned")
	# Regression pin, derived from this implementation and re-confirmed
	# directly, not guessed: how long the wave takes to walk off, at the
	# default tick size. Exists specifically to catch a mutation to the
	# `ticks` counter's own increment (e.g. `ticks += 2`) that would
	# otherwise slip past every other assertion in this file, since nothing
	# else pins an exact tick count.
	assert_eq(r["ticks"], 1636, "wave 1 undefended takes exactly this many ticks at the default tick size")
	return true

func test_a_defended_wave_kills_everything() -> bool:
	# Long Range towers packed onto the first straight give overwhelming cover.
	var towers: Array = []
	for col in [3, 5, 7, 9, 11]:
		towers.append({"kind": &"long", "position": Grid.tile_to_world_center(col, 3)})
	var r := Harness.run_wave({"wave": 1, "towers": towers, "path": _path()})
	assert_eq(r["leaks"], 0, "nothing gets through")
	assert_eq(r["kills"], 5, "all five die")
	assert_eq(r["gold_earned"], 25, "five slimes at 5 gold")
	# Ported: "loses no lives" (harness.test.ts "an overwhelming defence").
	assert_eq(r["lives_lost"], 0, "zero leaks means zero lives lost")
	return true

func test_results_are_reproducible() -> bool:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var a := Harness.run_wave({"wave": 3, "towers": towers, "path": _path()})
	var b := Harness.run_wave({"wave": 3, "towers": towers, "path": _path()})
	assert_eq(a, b, "same input, same result")
	return true

func test_later_waves_are_harder_for_the_same_board() -> bool:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var early := Harness.run_wave({"wave": 2, "towers": towers, "path": _path()})
	var late := Harness.run_wave({"wave": 12, "towers": towers, "path": _path()})
	assert_true(late["leaks"] > early["leaks"],
		"wave 12 leaks more than wave 2 against the same single tower")
	# Regression pin on the exact wave-12 result, derived from this
	# implementation and reconfirmed directly. The ">" comparison above is
	# satisfied by several genuinely-wrong implementations that still leak
	# "more" at a heavier wave for the trivial reason that wave 12 spawns far
	# more enemies than wave 2 regardless of per-enemy scaling (mutation
	# testing found this: hardcoding modifiers to wave 1's, swapping which
	# modifier feeds health vs. speed, and swapping which Towers.DEFS field
	# feeds range vs. fire_rate all still pass the ">" check above). This
	# exact-value pin closes that: any of those defects changes at least one
	# of these four numbers.
	assert_eq(late["kills"], 0, "wave 12 exact: a single basic tower kills nothing")
	assert_eq(late["leaks"], 89, "wave 12 exact: 89 of the wave's enemies get through")
	assert_eq(late["lives_lost"], 335, "wave 12 exact: lives lost at this wave's health-based leak cost")
	assert_eq(late["gold_earned"], 0, "wave 12 exact: no kills means no gold")
	return true

# --------------------------------------------------------------------------
# Ported from harness.test.ts beyond the brief's four tests. Expected values
# are either taken directly from the TS file (where the scenario transfers
# unchanged) or established empirically against this port's own reference
# logic (where the interface differs, e.g. no seed/shots-fired/spawned
# fields) and recorded here, never asserted from a guess.
# --------------------------------------------------------------------------

# Ported: "is identical across repeated runs of a heavier wave" — five
# repeats of a multi-tower, later-wave config, not just the brief's two
# calls. This is the whole point of the harness: without it a balance result
# cannot be reproduced or diagnosed.
func test_repeated_runs_of_a_heavier_wave_are_identical() -> bool:
	var towers := [
		{"kind": &"basic", "position": Grid.tile_to_world_center(3, 3)},
		{"kind": &"fast", "position": Grid.tile_to_world_center(7, 3)},
		{"kind": &"long", "position": Grid.tile_to_world_center(11, 3)},
	]
	var config := {"wave": 8, "towers": towers, "path": _path()}
	var first := Harness.run_wave(config)
	for i in 5:
		assert_eq(Harness.run_wave(config), first, "run %d matches the first" % i)
	return true

# Ported: "does not mutate the config it was given". run_wave reads `wave`,
# `towers`, `path`, `tick_ms` and `max_ticks` off the dictionary it is handed
# and builds its own internal tower/enemy state from copies of their values;
# nothing ever writes back into the caller's config.
func test_run_wave_does_not_mutate_its_config() -> bool:
	var config := {
		"wave": 3,
		"towers": [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}],
		"path": _path(),
	}
	var snapshot := config.duplicate(true)
	Harness.run_wave(config)
	assert_eq(config, snapshot, "the config dictionary is untouched")
	return true

# Ported: "accounts for every enemy as either killed or leaked". The TS
# result exposes `spawned` directly; this port's result does not, so the
# expected total is computed independently from Waves.get_composition (the
# same source of truth the harness itself schedules from) rather than from
# the harness's own tick loop.
func test_every_enemy_is_either_killed_or_leaked() -> bool:
	var path := _path()
	var cols := [3, 5, 7]
	for wave in [1, 3, 5, 7]:
		for tower_count in [0, 1, 3]:
			var towers: Array = []
			for i in tower_count:
				towers.append({"kind": &"basic", "position": Grid.tile_to_world_center(cols[i], 3)})
			var r := Harness.run_wave({"wave": wave, "towers": towers, "path": path})
			assert_eq(r["kills"] + r["leaks"], _total_spawn_count(wave),
				"wave %d, %d towers: every enemy is accounted for" % [wave, tower_count])
	return true

# Ported: "tower strength changes the outcome" (kills more / leaks fewer
# with more towers).
func test_more_towers_kill_more_and_leak_fewer() -> bool:
	var path := _path()
	var one := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var four: Array = []
	for col in [3, 5, 7, 9]:
		four.append({"kind": &"basic", "position": Grid.tile_to_world_center(col, 3)})
	var with_one := Harness.run_wave({"wave": 3, "towers": one, "path": path})
	var with_four := Harness.run_wave({"wave": 3, "towers": four, "path": path})
	assert_true(with_four["kills"] > with_one["kills"], "four towers kill more than one")
	assert_true(with_four["leaks"] < with_one["leaks"], "four towers leak fewer than one")
	return true

# Ported: "range matters" (a tower far from the lane never fires / a tower on
# the lane fires). Substituted for shots_fired (not in this result): a tower
# that never fires produces exactly the undefended result (kills 0, leaks 5);
# a tower on the lane kills at least one enemy.
func test_a_tower_far_from_the_lane_never_engages() -> bool:
	var path := _path()
	var far := Harness.run_wave({
		"wave": 1, "towers": [{"kind": &"basic", "position": Vector2(600, 2000)}], "path": path})
	assert_eq(far["kills"], 0, "out of range, no kills")
	assert_eq(far["leaks"], 5, "out of range, everything gets through same as undefended")
	assert_eq(far["gold_earned"], 0, "out of range, no gold")
	return true

func test_a_tower_on_the_lane_engages() -> bool:
	var near := Harness.run_wave({
		"wave": 1,
		"towers": [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}],
		"path": _path()})
	assert_true(near["kills"] > 0, "in range, at least one kill")
	return true

# New: splash. Not in the TS reference's test list (its splash coverage is
# folded into other scenarios there), but this port's config includes a
# `base_splash_radius`-bearing tower kind (mortar) and nothing above
# exercises it — every other test in this file uses basic/fast/long, all of
# which have zero splash. Mortar one-shots a wave-1 slime outright (damage 5
# >= scaled health 5), so getting all five kills from only 2-3 shots at a
# 2000ms fire rate is only possible if splash is actually reaching bystanders
# clustered near the primary target, not just the target itself.
func test_mortar_splash_kills_more_than_its_shot_count_would_alone() -> bool:
	var towers := [{"kind": &"mortar", "position": Grid.tile_to_world_center(5, 3)}]
	var r := Harness.run_wave({"wave": 1, "towers": towers, "path": _path()})
	assert_eq(r["kills"], 5, "all five slimes die, most of them to splash")
	assert_eq(r["leaks"], 0, "none escape")
	return true

# New: splash against a wave with ogres (wave 5, mortar damage 5 < ogre
# health 8, so a single hit is never lethal there). Wave 1's mortar test
# above one-shots everything, which cannot distinguish "splash reaches
# bystanders correctly" from two related defects mutation testing found
# survive it: the primary target not being excluded from its own splash
# check (so a single shot can apply its damage to the same enemy twice —
# harmless when the first hit is already lethal, since Damage.resolve's own
# "a corpse absorbs nothing" guard makes the second application a no-op, but
# NOT harmless when the first hit merely wounds), and the splash-radius
# comparison itself being inverted (hits everything OUTSIDE the radius
# instead of inside, which this port's spread-out spawn timing makes even
# MORE trigger-happy than the real behaviour, not less). Both defects still
# clear wave 1 perfectly; neither clears wave 5 with these exact numbers.
func test_mortar_splash_does_not_overkill_via_self_double_counting() -> bool:
	var towers := [{"kind": &"mortar", "position": Grid.tile_to_world_center(5, 3)}]
	var r := Harness.run_wave({"wave": 5, "towers": towers, "path": _path()})
	assert_eq(r["kills"], 16, "wave 5 exact: this many die to a single mortar")
	assert_eq(r["leaks"], 10, "wave 5 exact: this many still get through")
	assert_eq(r["gold_earned"], 115, "wave 5 exact: gold from exactly these kills")
	return true

# Review follow-up (post-Task-14): `tower["cooldown"] > 0.0` (line ~99) needs
# a tick_ms that divides its target tower's fire_rate evenly to ever land
# cooldown on exactly 0.0 and expose a `>` vs `>=` mutation — the default
# tick (1000.0/60.0, not exactly representable in binary float) never does.
# mortar's fire_rate (2000.0) divides evenly by tick_ms=40.0 (used elsewhere
# in this file for the same reason, see test_tick_ms_override_is_honored),
# so this reuses that combination against the same wave-5-mortar scenario
# above rather than inventing a new one. Confirmed this actually
# distinguishes the two: `>` (correct) gives kills=16/leaks=10/lives_lost=21
# /gold=115; `>=` (mutated — an exactly-zero cooldown now also skips firing)
# gives kills=15/leaks=11/lives_lost=20/gold=120. Values taken from running
# both variants directly, not derived.
func test_cooldown_boundary_at_an_evenly_dividing_tick_size() -> bool:
	var towers := [{"kind": &"mortar", "position": Grid.tile_to_world_center(5, 3)}]
	var r := Harness.run_wave({"wave": 5, "towers": towers, "path": _path(), "tick_ms": 40.0})
	assert_eq(r["kills"], 16, "exact: cooldown==0.0 still fires (> not >=)")
	assert_eq(r["leaks"], 10, "exact: one fewer leak than the >= mutant")
	assert_eq(r["lives_lost"], 21, "exact: lives lost at this exact leak count")
	assert_eq(r["gold_earned"], 115, "exact: gold from exactly these kills")
	return true

# Review follow-up (post-Task-14): does `e["position"].distance_to(...) <=
# tower["splash"]` (line ~109) ever land a bystander at exactly the splash
# radius, where `<=` vs `<` diverges? Found by sweeping the same
# wave-5-mortar-at-(5,3) scenario above across waves 1-20 at the default tick
# and diffing mutated-vs-unmutated output directly (not derived
# algebraically): wave 10 is the first wave in that sweep where a bystander's
# distance from the mortar's target lands exactly on the splash radius
# (55.0), so `<=` (correct) hits it and `<` (mutated) does not — confirmed
# by running both variants: unmutated gives kills=12/leaks=59/lives_lost=222
# /gold=120; mutated gives kills=9/leaks=62/lives_lost=234/gold=90.
func test_splash_radius_boundary_at_wave_ten() -> bool:
	var towers := [{"kind": &"mortar", "position": Grid.tile_to_world_center(5, 3)}]
	var r := Harness.run_wave({"wave": 10, "towers": towers, "path": _path()})
	assert_eq(r["kills"], 12, "exact: a bystander at exactly the splash radius is hit (<= not <)")
	assert_eq(r["leaks"], 59, "exact: three fewer leaks than the < mutant")
	assert_eq(r["lives_lost"], 222, "exact: lives lost at this exact leak count")
	assert_eq(r["gold_earned"], 120, "exact: gold from exactly these kills")
	return true

# Ported: "stops even under a heavy wave with a weak defence" (termination).
func test_a_heavy_wave_with_a_weak_defence_still_terminates() -> bool:
	var r := Harness.run_wave({
		"wave": 10,
		"towers": [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}],
		"path": _path()})
	assert_false(r["timed_out"], "the wave completes rather than hitting the tick cap")
	assert_true(r["ticks"] < Harness.DEFAULT_MAX_TICKS, "well under the tick budget")
	return true

# Ported: "gives close results at different resolutions" (timestep). A
# result that swings wildly with the tick size is measuring the integrator,
# not the balance.
func test_timestep_gives_close_results_at_different_resolutions() -> bool:
	var path := _path()
	var towers := [{"kind": &"fast", "position": Grid.tile_to_world_center(5, 3)}]
	var coarse := Harness.run_wave({"wave": 3, "towers": towers, "path": path, "tick_ms": 32.0})
	var fine := Harness.run_wave({"wave": 3, "towers": towers, "path": path, "tick_ms": 8.0})
	assert_true(absi(coarse["kills"] - fine["kills"]) <= 2,
		"kill count is stable across a 4x change in tick size")
	return true

# --------------------------------------------------------------------------
# New: config.get() defaulting. Neither test above actually proves tick_ms
# or max_ticks overrides are *applied* rather than silently ignored in favour
# of the DEFAULT_* constant — a mutation that hardcodes DEFAULT_TICK_MS or
# DEFAULT_MAX_TICKS in place of the config.get() call would still satisfy
# every test above (see task-14-report.md's mutation table). These two close
# that gap directly.
#
# Historical note, kept because it is the story of the Critical below: this
# block used to explain that tick_ms=40.0 was chosen over 100.0 to avoid
# Movement.advance's "no clamping to the waypoint" quirk, which at a large
# enough tick size produced a genuine non-converging oscillation (when both
# the approach remainder and the overshoot land at or above the strict `< 2.0`
# arrival radius, position bounces between two distances forever). That quirk
# has since been removed — see sim/movement.gd's arrival test — because the
# same oscillation was reachable at the DEFAULT tick size on waves 19 and 20
# and soft-locked the real game. tick_ms=40.0 is retained here only because
# the surrounding tests' exact tick pins are calibrated to it.
# --------------------------------------------------------------------------

func test_tick_ms_override_is_honored() -> bool:
	var path := _path()
	var default_run := Harness.run_wave({"wave": 1, "towers": [], "path": path})
	var coarser_run := Harness.run_wave({"wave": 1, "towers": [], "path": path, "tick_ms": 40.0})
	assert_false(default_run["timed_out"], "the default-tick run completes")
	assert_false(coarser_run["timed_out"], "the overridden-tick run completes")
	assert_true(coarser_run["ticks"] < default_run["ticks"],
		"a larger tick_ms reaches the same simulated time in fewer ticks; " +
		"if the override were ignored the two tick counts would be equal")
	# Regression pin, exact. The "<" comparison above tolerates a spawn-timing
	# off-by-one-tick defect that mutation testing found survives it (the
	# schedule boundary check accepting a spawn "<=" the current elapsed time
	# vs. only "<" it — a one-tick spawn delay shifts this scenario's total by
	# one without disturbing the inequality above).
	#
	# Re-derived from 712 to 710 when movement.gd's un-clamped overshoot was
	# removed, and this is the largest pacing shift the removal produced
	# anywhere in the suite: at tick_ms=40 a wave-1 slime moves exactly 4.0
	# px/tick, so it is one of the few scenarios where a step exceeds the 2px
	# arrival radius at all. Two ticks out of 712 is 0.3%.
	assert_eq(coarser_run["ticks"], 710, "exact tick count at tick_ms=40 for this scenario")
	return true

func test_max_ticks_override_is_honored() -> bool:
	# A cap far too small for wave 1 (which normally takes over a thousand
	# ticks) to finish in — if max_ticks were ignored in favour of
	# DEFAULT_MAX_TICKS, this would run to completion instead.
	var r := Harness.run_wave({"wave": 1, "towers": [], "path": _path(), "max_ticks": 2})
	assert_true(r["timed_out"], "an unreachably small tick cap forces a timeout")
	assert_eq(r["ticks"], 2, "the loop stops exactly at the overridden cap")
	return true

# INVERTED (was test_an_extreme_tick_size_times_out_rather_than_hanging).
#
# This test used to assert that tick_ms=100 times out, and framed that as a
# feature: proof that max_ticks is what stands between unusual input and an
# infinite loop. That framing was wrong in an important way — it treated a
# non-terminating movement rule as acceptable so long as the harness could
# survive it, which is exactly the reasoning that let waves 19 and 20 ship
# soft-locked (see the wave sweep below). The live game has no tick cap.
#
# With movement.gd's un-clamped overshoot removed, arrival is guaranteed at any
# step size, so an extreme tick size now completes instead of hanging. A tick
# cap is still worth having and is still pinned as honoured — by
# test_max_ticks_override_is_honored above, which does it directly rather than
# by relying on a real defect to trigger it.
func test_an_extreme_tick_size_completes_rather_than_oscillating() -> bool:
	var r := Harness.run_wave({"wave": 1, "towers": [], "path": _path(), "tick_ms": 100.0})
	assert_false(r["timed_out"], "a 100ms tick completes rather than oscillating forever")
	assert_eq(r["ticks"], 312, "exact tick count at tick_ms=100 for this scenario")
	assert_eq(r["leaks"], 5, "all five slimes still walk off the end")
	return true

# --------------------------------------------------------------------------
# THE CRITICAL, and the record of how it survived review. This block used to
# document waves 19 and 20 timing out as a finding-but-not-a-defect, and the
# test below used to assert the timeout. Both are now inverted.
#
# What the original diagnosis got RIGHT — all of it, and it is worth keeping:
# at the default tick size, waves 19 and 20 undefended timed out; the result
# was deterministic; it was not a gradual climb but a sudden cliff at 19 (wave
# 18 and everything below finished under 3200 ticks), found by sweeping every
# wave; and the root cause was correctly traced to Waves.get_modifiers's
# +5%/wave speed_modifier pushing an enemy's per-tick step into the exact
# non-convergent cycle movement.gd's own docstring warned about. Every one of
# those statements was true and independently reconfirmed.
#
# What it got WRONG was one inference: that the harness's max_ticks/timed_out
# "is exactly the mechanism that keeps this from being a genuine infinite
# loop". That is true OF THE HARNESS and false of the game. GameBoard has no
# tick cap. A stuck enemy never reaches the goal, so it never leaks, never
# emits, and never frees — `_enemies_root.get_child_count() == 0` is therefore
# never satisfied, `_on_wave_cleared()` never runs, `wave_state_changed(false)`
# never fires, the Start button stays disabled forever and `victory` is
# unreachable. The player cannot win and cannot lose. Restarting is the only
# exit. Containment reasoning that stops at the test harness does not transfer
# to a caller with a different timing model, and Tasks 17 and 19 then wired
# this same function to exactly such a caller.
#
# The rule was fixed in sim/movement.gd rather than worked around here. The
# sweep below is the assertion that should have existed from the start: it
# states the intent ("every wave terminates") in one line rather than encoding
# one wave's symptom as expected behaviour.
# --------------------------------------------------------------------------

func test_wave_twenty_undefended_completes_at_the_default_tick_size() -> bool:
	var r := Harness.run_wave({"wave": 20, "towers": [], "path": _path()})
	assert_false(r["timed_out"], "wave 20 finishes within the default tick budget")
	# Exact pin. The bee speed that used to trap (150 * 1.75 = 4.375 px/tick)
	# is still the fastest thing in the game, so this number is the direct
	# regression witness for the Critical: a revert to the un-clamped step
	# turns it back into DEFAULT_MAX_TICKS.
	assert_eq(r["ticks"], 3397, "wave 20 undefended takes exactly this many ticks")
	assert_eq(r["leaks"], 161, "every wave-20 enemy walks off the end")
	assert_eq(r["lives_lost"], 644, "lives lost at wave 20's health-based leak cost")
	return true

# The one-line-of-intent test. Waves 19 and 20 soft-locked the game for six
# task-commits while three reviews looked at the code, because nothing anywhere
# asserted the only thing that actually mattered: that a wave ends. Every other
# harness test here picks a wave and pins its numbers, so a wave nobody picked
# was a wave nobody checked. This sweeps all twenty at the tick size the real
# game runs at, undefended (the slowest, longest-running configuration — every
# tower only removes enemies sooner), so the class of bug cannot come back
# silently.
func test_every_wave_undefended_terminates_at_the_default_tick_size() -> bool:
	var path := _path()
	for wave in range(1, Waves.MAX_WAVES + 1):
		var r := Harness.run_wave({"wave": wave, "towers": [], "path": path})
		assert_false(r["timed_out"], "wave %d undefended terminates" % wave)
		assert_true(r["ticks"] < Harness.DEFAULT_MAX_TICKS,
			"wave %d finishes inside the tick budget, took %d" % [wave, r["ticks"]])
		# Termination alone is satisfiable by a wave that ends because its
		# enemies vanish. Every enemy must still be accounted for.
		assert_eq(r["kills"] + r["leaks"], _total_spawn_count(wave),
			"wave %d: every enemy reached an ending" % wave)
	return true

# --------------------------------------------------------------------------
# Deliberately not ported, and why:
#
# - "returns an identical result for an identical seed" — no `seed` param in
#   this interface. Covered instead by test_results_are_reproducible and
#   test_repeated_runs_of_a_heavier_wave_are_identical above, which assert
#   the same property (same input -> same output) without a seed to vary.
# - "late-wave life loss" (wave 5 vs 6, isolated to one slime via a
#   `composition` override) — this interface has no composition override,
#   and Leak.resolve's own wave-5-boundary behaviour is already pinned
#   directly in test/test_leak.gd (Task 10):
#   test_switches_over_exactly_after_wave_five et al. Re-deriving it through
#   a full wave simulation here would not test anything Leak's own suite
#   doesn't already cover more precisely.
# - "explicit compositions" (bee-only wave, empty composition) — same
#   reason: no composition override in this interface, and bee life_loss is
#   already pinned in test/test_data_tables.gd.
# - "insignia reports zero until lieutenants exist" — no insignia field;
#   lieutenants/bosses are out of scope for the core slice (see
#   PROGRESS.md).
# --------------------------------------------------------------------------
