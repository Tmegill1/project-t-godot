extends TestCase

# Ported from the Phaser build's sim/upgrades.test.ts. Only the tests that
# exercise Task 2's surface (emptyTiers, canUpgrade, withUpgrade, upgradeCost,
# totalInvested) are ported here — resolveTowerStats, visualTier and
# spriteFrameFor belong to Tasks 3/4, which append to the same sim file.
#
# The cross-path rule is the load-bearing one: a branch may pass tier 2 only
# while the other sits at or below CROSS_PATH_CAP. Without it gold is the only
# constraint and every tower converges on the same shape, so its boundaries
# get more coverage than anything else here.

func _tiers(sustained: int, burst: int) -> Dictionary:
	return {&"sustained": sustained, &"burst": burst}

# --------------------------------------------------------------------------
# constants and empty_tiers
# --------------------------------------------------------------------------

func test_max_tier_is_four() -> bool:
	assert_eq(UpgradesSim.MAX_TIER, 4, "four tiers per branch")
	return true

func test_cross_path_cap_is_two() -> bool:
	assert_eq(UpgradesSim.CROSS_PATH_CAP, 2, "the off-branch may sit at two")
	return true

# From "caps the off-branch below the maximum, so both cannot be maxed" -
# a sanity check on the constants themselves, not on any function. Without
# it, setting CROSS_PATH_CAP >= MAX_TIER would silently make the cross-path
# rule toothless (nothing would ever exceed the cap) while every other test
# below still passed on its own fixed tier values.
func test_cross_path_cap_is_below_max_tier() -> bool:
	assert_true(UpgradesSim.CROSS_PATH_CAP < UpgradesSim.MAX_TIER,
		"a branch must be able to exceed the cap, or it is not a cap")
	return true

func test_empty_tiers_starts_both_branches_at_zero() -> bool:
	var t := UpgradesSim.empty_tiers()
	assert_eq(t[&"sustained"], 0, "sustained starts at zero")
	assert_eq(t[&"burst"], 0, "burst starts at zero")
	return true

# From "returns a fresh object each time" - guards against a shared/cached
# dictionary being handed back, which would let mutating one caller's tiers
# corrupt every other caller's "empty" starting point.
func test_empty_tiers_returns_a_fresh_dictionary_each_time() -> bool:
	var a := UpgradesSim.empty_tiers()
	a[&"sustained"] = 3
	assert_eq(UpgradesSim.empty_tiers()[&"sustained"], 0,
		"mutating one empty_tiers() result must not affect the next call")
	return true

# --------------------------------------------------------------------------
# can_upgrade
# --------------------------------------------------------------------------

func test_can_upgrade_allows_the_first_tier_on_either_branch() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(0, 0), &"sustained"), "sustained from zero")
	assert_true(UpgradesSim.can_upgrade(_tiers(0, 0), &"burst"), "burst from zero")
	return true

# From "allows climbing to the cross-path cap on both branches" - the other
# branch sitting exactly at the cap (not over it, and not far below it) must
# still permit reaching the cap.
func test_can_upgrade_allows_climbing_to_the_cap_when_the_other_is_already_at_it() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(1, 2), &"sustained"),
		"sustained 1 -> 2 is at the cap, allowed even with burst already at the cap")
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 1), &"burst"),
		"burst 1 -> 2 is at the cap, allowed even with sustained already at the cap")
	return true

func test_can_upgrade_refuses_past_max_tier() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(4, 0), &"sustained"), "already at MAX_TIER")
	return true

# The exact boundary the rule exists for. At the cap on both, either branch
# may still commit; one step past, the other is locked out.
func test_can_upgrade_allows_passing_the_cap_while_the_other_branch_is_at_it() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 2), &"sustained"),
		"2/2 may still commit either way")
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 2), &"burst"),
		"2/2 may still commit either way")
	return true

func test_can_upgrade_refuses_passing_the_cap_once_the_other_branch_has() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(2, 3), &"sustained"),
		"burst already committed, so sustained cannot pass the cap")
	assert_false(UpgradesSim.can_upgrade(_tiers(3, 2), &"burst"),
		"sustained already committed, so burst cannot pass the cap")
	return true

# From "still allows deepening the branch that already committed" - the
# complement of the test above. Once a branch has itself gone past the cap
# (with the other still at or below it), it must keep being allowed to climb
# further, all the way to MAX_TIER. Without this, a stray `!=` in place of
# `>` on the *committing* branch's own next-tier check (as opposed to the
# other branch's) would lock a tower out of its own chosen path after one
# step past the cap.
func test_can_upgrade_allows_deepening_the_branch_that_already_committed() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(3, 2), &"sustained"),
		"sustained already past the cap and burst still at it: sustained may keep climbing")
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 3), &"burst"),
		"burst already past the cap and sustained still at it: burst may keep climbing")
	return true

# Below the cap the other branch's depth is irrelevant - a committed tower can
# still fill its shallow side out to the cap.
func test_can_upgrade_allows_reaching_the_cap_regardless_of_the_other_branch() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(1, 4), &"sustained"),
		"sustained 1 -> 2 is at the cap, always allowed")
	return true

func test_can_upgrade_refuses_an_unknown_branch() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(0, 0), &"nonsense"),
		"an unknown branch is not upgradeable")
	return true

# --------------------------------------------------------------------------
# with_upgrade
# --------------------------------------------------------------------------

func test_with_upgrade_increments_only_the_named_branch() -> bool:
	var t := UpgradesSim.with_upgrade(_tiers(1, 2), &"sustained")
	assert_eq(t[&"sustained"], 2, "sustained advanced")
	assert_eq(t[&"burst"], 2, "burst untouched")
	return true

func test_with_upgrade_does_not_mutate_its_argument() -> bool:
	var original := _tiers(1, 1)
	UpgradesSim.with_upgrade(original, &"burst")
	assert_eq(original[&"burst"], 1, "the caller's dictionary is unchanged")
	return true

# The reference throws here. GDScript has no exceptions and assert() compiles
# out of release builds, so this returns the tiers unchanged and pushes an
# error instead: loud in tests, inert in a shipped build. Callers gate on
# can_upgrade first.
func test_with_upgrade_returns_tiers_unchanged_on_an_illegal_buy() -> bool:
	var t := UpgradesSim.with_upgrade(_tiers(2, 3), &"sustained")
	assert_eq(t[&"sustained"], 2, "illegal cross-path buy did not apply")
	assert_eq(t[&"burst"], 3, "and nothing else moved")
	return true

# The refusal path returns early, so it is the one place a caller could be
# handed back the very dictionary it passed in; writing to the result would
# then reach into the tower's own tiers. The legal path's copy is pinned by
# test_with_upgrade_does_not_mutate_its_argument, this one is the other half.
# Prints the "Illegal upgrade" error, as the test above does - that push_error
# is the point of the call.
func test_with_upgrade_returns_a_copy_even_when_it_refuses() -> bool:
	var original := _tiers(2, 3)
	var refused := UpgradesSim.with_upgrade(original, &"sustained")
	refused[&"sustained"] = 99
	assert_eq(original[&"sustained"], 2, "a refusal does not alias the caller's tiers")
	return true

# From "can walk a legal path to tier 4" - repeated legal buys on one branch,
# leaving the other untouched, land exactly on MAX_TIER. Exercises the
# composition of can_upgrade and with_upgrade across every intermediate step
# (0->1->2->3->4), including the two steps that cross CROSS_PATH_CAP.
func test_with_upgrade_can_walk_a_legal_path_to_max_tier() -> bool:
	var current := UpgradesSim.empty_tiers()
	for i in range(UpgradesSim.MAX_TIER):
		current = UpgradesSim.with_upgrade(current, &"burst")
	assert_eq(current[&"burst"], UpgradesSim.MAX_TIER, "four legal buys reach MAX_TIER")
	assert_eq(current[&"sustained"], 0, "the untouched branch stays at zero")
	return true

# --------------------------------------------------------------------------
# upgrade_cost
# --------------------------------------------------------------------------

func test_upgrade_cost_reads_the_next_tiers_price() -> bool:
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 0), 30, "first tier")
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 3), 260, "fourth tier")
	return true

func test_upgrade_cost_is_zero_when_maxed_or_negative() -> bool:
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 4), 0, "nothing left to buy")
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", -1), 0, "a bad tier is inert, not a crash")
	return true

# From "quotes a positive price for every reachable tier" - swept over every
# tower kind and both branches, not just basic/sustained. Doubles as a data
# guard: a zero or missing cost anywhere in Task 1's table would surface here.
func test_upgrade_cost_is_positive_for_every_reachable_tier_on_every_tower() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in range(UpgradesSim.MAX_TIER):
				assert_true(UpgradesSim.upgrade_cost(kind, branch, tier) > 0,
					"%s/%s tier %d costs something" % [kind, branch, tier])
	return true

# From "gets more expensive as tiers climb" - each tier costs strictly more
# than the one before it, for every kind and branch. This is the general form
# of what test_upgrade_cost_reads_the_next_tiers_price checks for one kind.
func test_upgrade_cost_increases_with_every_tier_for_every_tower() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in range(1, UpgradesSim.MAX_TIER):
				assert_true(
					UpgradesSim.upgrade_cost(kind, branch, tier) >
					UpgradesSim.upgrade_cost(kind, branch, tier - 1),
					"%s/%s tier %d costs more than tier %d" % [kind, branch, tier, tier - 1])
	return true

# --------------------------------------------------------------------------
# total_invested
# --------------------------------------------------------------------------

func test_total_invested_is_zero_for_an_unupgraded_tower() -> bool:
	assert_eq(UpgradesSim.total_invested(&"basic", UpgradesSim.empty_tiers()), 0, "nothing sunk in")
	return true

func test_total_invested_sums_every_purchased_tier_on_both_branches() -> bool:
	# basic sustained 1-2 = 30 + 60, burst 1-3 = 30 + 65 + 145.
	assert_eq(UpgradesSim.total_invested(&"basic", _tiers(2, 3)), 330,
		"sums both branches up to their current tier")
	return true

func test_total_invested_counts_a_fully_committed_branch() -> bool:
	# long burst 1-4 = 60 + 130 + 260 + 500, sustained 1-2 = 60 + 120.
	assert_eq(UpgradesSim.total_invested(&"long", _tiers(2, 4)), 1130,
		"a maxed branch plus a capped one")
	return true

# --------------------------------------------------------------------------
# visual tier
# --------------------------------------------------------------------------

# Four looks, not seven. A tower can hold six tiers across both branches, but
# six silhouettes are not readable at tile size, and the useful signal is "how
# much is invested here" rather than the exact tier. Driven by the total across
# both branches, so a tower taken deep down one path and one taken evenly both
# read as expensive.
#
# Every boundary is pinned: ceil(total / 2) capped at VISUAL_TIERS - 1 is easy
# to write as floor, or to leave uncapped, and either passes a test that only
# samples the middle.
func test_visual_tier_maps_total_investment_onto_four_looks() -> bool:
	assert_eq(UpgradesSim.visual_tier(_tiers(0, 0)), 0, "0 tiers -> frame 0")
	assert_eq(UpgradesSim.visual_tier(_tiers(1, 0)), 1, "1 tier -> frame 1")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 0)), 1, "2 tiers -> frame 1")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 1)), 2, "3 tiers -> frame 2")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 2)), 2, "4 tiers -> frame 2")
	assert_eq(UpgradesSim.visual_tier(_tiers(3, 2)), 3, "5 tiers -> frame 3")
	assert_eq(UpgradesSim.visual_tier(_tiers(4, 2)), 3, "6 tiers -> frame 3, the cap")
	return true

func test_visual_tiers_constant_is_four() -> bool:
	assert_eq(UpgradesSim.VISUAL_TIERS, 4, "four distinct looks")
	return true

func test_visual_tier_treats_negative_tiers_as_zero() -> bool:
	assert_eq(UpgradesSim.visual_tier(_tiers(-3, 0)), 0,
		"a bad value is inert rather than a negative frame index")
	return true

# The cap is unreachable through legal play: the cross-path rule holds total
# tiers at 6, and ceil(6 / 2) already equals VISUAL_TIERS - 1. That makes it
# defensive code, and defensive code the suite cannot exercise is code nobody
# knows still works - removing the cap entirely would pass every other test
# here. Pinned with an out-of-range total for the same reason the negative
# case above is pinned: sprite_frame_for indexes an array with this result,
# so an uncapped value is an out-of-bounds read rather than a wrong picture.
func test_visual_tier_caps_totals_beyond_the_legal_maximum() -> bool:
	assert_eq(UpgradesSim.visual_tier(_tiers(5, 5)), UpgradesSim.VISUAL_TIERS - 1,
		"a total of 10 clamps to the last look rather than indexing past it")
	return true

# --------------------------------------------------------------------------
# sprite_frame_for
# --------------------------------------------------------------------------

func test_sprite_frame_for_indexes_the_kinds_own_frame_list() -> bool:
	# basic's upgrade_frames are [8, 9, 11, 17].
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(0, 0)), 8, "unupgraded basic")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(1, 0)), 9, "one tier in")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(2, 1)), 11, "three tiers in")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(4, 2)), 17, "fully committed")
	return true

func test_sprite_frame_for_uses_each_kinds_distinct_frames() -> bool:
	assert_eq(UpgradesSim.sprite_frame_for(&"fast", _tiers(0, 0)), 5, "Magic starts at frame 5")
	assert_eq(UpgradesSim.sprite_frame_for(&"mortar", _tiers(0, 0)), 1, "mortar at 1")
	assert_eq(UpgradesSim.sprite_frame_for(&"long", _tiers(0, 0)), 2, "long at 2")
	return true

# The frame list is data and could be shortened; clamping to its length keeps
# a short list from indexing off the end rather than crashing mid-render.
func test_sprite_frame_for_clamps_to_the_available_frames() -> bool:
	var frames: Array = Towers.DEFS[&"basic"]["upgrade_frames"]
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(4, 2)), int(frames[frames.size() - 1]),
		"never indexes past the last frame")
	return true

# --------------------------------------------------------------------------
# resolve_tower_stats
# --------------------------------------------------------------------------

# Multipliers compose, flat bonuses add, and radii/slows/gold take the
# STRONGEST value rather than stacking. The last part is what keeps the number
# a tier's text promises and the number the simulation applies identical:
# stacking would add tier 4's big splash to tier 2's small one and the tower
# would quietly outperform its own description.

func test_resolve_returns_base_stats_for_an_unupgraded_tower() -> bool:
	var base: Dictionary = Towers.DEFS[&"basic"]
	var s := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	assert_almost_eq(s["damage"], float(base["damage"]), 0.0001, "base damage")
	assert_almost_eq(s["fire_rate"], float(base["fire_rate"]), 0.0001, "base fire rate")
	assert_almost_eq(s["range"], float(base["range"]), 0.0001, "base range")
	assert_eq(s["pierce"], int(base["pierce"]), "base pierce")
	assert_almost_eq(s["splash_radius"], float(base["base_splash_radius"]), 0.0001, "base splash")
	assert_eq(s["detection"], bool(base["detection"]), "base detection")
	assert_almost_eq(s["slow_factor"], 1.0, 0.0001, "no slow by default")
	assert_almost_eq(s["gold_multiplier"], 1.0, 0.0001, "no gold bonus by default")
	assert_eq(s["bonus_gold_per_kill"], 0, "no flat gold by default")
	return true

# basic/sustained tiers 1 and 2 take 200ms and 160ms off the interval. They
# must ADD to 360, not compose and not overwrite. This is the test that would
# fail if multiplicative fire rate crept back in.
func test_resolve_adds_fire_rate_bonuses_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"basic"]["fire_rate"])
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(2, 0))
	assert_almost_eq(s["fire_rate"], base - 360.0, 0.5,
		"two flat cuts add to 360ms off the interval")
	return true

# mortar/burst tiers 1 and 2 (Packed Charge, Heavy Shell) add 3 and 5 damage
# with no other effects: 8 more, not a multiple. Distinct from the fire-rate
# test above - damage_bonus has its own `+=` in _apply_effects, so a mutation
# there would not be caught by the fire-rate test alone.
func test_resolve_adds_damage_bonuses_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"mortar"]["damage"])
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(0, 2))
	assert_almost_eq(s["damage"], base + 8.0, 0.5,
		"two flat bonuses add to +8, not a product")
	return true

# long/sustained tiers 1 and 4 (Long Barrel, Carpet Fire) are the only tiers
# on any tower that both carry range_multiplier: 1.2 and 1.33. They must
# compose to 1.596x, not overwrite to 1.33x. Tiers 2-3 add fire-rate and
# splash effects that don't touch range, so buying all four still isolates
# range composition specifically. Expected value is hand-computed from the
# tower's base range and the tiers' own multipliers, not derived from the
# function's own output, so it cannot be tautological the way comparing a
# result to round(that same result) would be.
func test_resolve_composes_range_multipliers_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"long"]["range"])
	var s := UpgradesSim.resolve_tower_stats(&"long", _tiers(4, 0))
	assert_almost_eq(s["range"], round(base * 1.2 * 1.33), 0.5,
		"two range multipliers compose to 1.596x base, not overwrite to 1.33x")
	return true

# mortar/sustained tier 1 sets splash 70, tier 3 sets 95. The larger wins; they
# must not sum to 165.
func test_resolve_takes_the_strongest_splash_rather_than_stacking() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(3, 0))
	assert_almost_eq(s["splash_radius"], 95.0, 0.0001, "the largest radius wins")
	return true

# The tower's own base splash must not be lost when a tier sets a smaller one.
func test_resolve_never_lowers_splash_below_the_towers_base() -> bool:
	var base := float(Towers.DEFS[&"mortar"]["base_splash_radius"])
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(1, 0))
	assert_true(s["splash_radius"] >= base, "a tier can raise splash, never lower it")
	return true

func test_resolve_adds_pierce_bonuses() -> bool:
	# long/burst tier 3 grants 5, tier 4 grants 10 more.
	var s := UpgradesSim.resolve_tower_stats(&"long", _tiers(0, 4))
	# Bought pierce (5 + 10) plus the level term for the four tiers that bought
	# it. Written as a sum rather than a total so the two sources stay legible.
	assert_eq(s["pierce"],
		int(Towers.DEFS[&"long"]["pierce"]) + 15 + 4 * UpgradesSim.PIERCE_PER_TIER,
		"pierce bonuses add, on top of what levelling grants")
	return true

func test_resolve_turns_detection_on_and_never_off() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 3))
	assert_true(s["detection"], "basic/burst tier 3 grants detection")
	return true

# fast/sustained tier 3 slows to 0.7, tier 4 to 0.45. Lower is stronger, and
# the duration must travel with the factor that won.
func test_resolve_takes_the_strongest_slow_with_its_own_duration() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", _tiers(4, 0))
	assert_almost_eq(s["slow_factor"], 0.45, 0.0001, "the stronger slow wins")
	assert_almost_eq(s["slow_duration_ms"], 2500.0, 0.0001, "and brings its own duration")
	return true

func test_resolve_takes_the_strongest_gold_multiplier_and_flat_bonus() -> bool:
	# fast/burst: tier 2 grants +1 flat, tier 3 grants x1.6, tier 4 x2 and +2.
	var s := UpgradesSim.resolve_tower_stats(&"fast", _tiers(0, 4))
	assert_almost_eq(s["gold_multiplier"], 2.0, 0.0001, "the largest multiplier wins")
	assert_eq(s["bonus_gold_per_kill"], 2, "the largest flat bonus wins, rather than summing")
	return true

# Damage is applied per hit and compared against integer health, so the number
# the player is shown and the number the sim applies have to be the same one.
# Fire rate and range round for the same reason, and because upgrades.ts rounds
# all three at the same point.
#
# This test used to compare each stat to round() of ITSELF, which is true of
# every float and pinned nothing - deleting the fire_rate or range rounding
# passed all 4589 checks. Each case below is a tier whose arithmetic actually
# lands off a whole number, with the rounded result written out.
func test_resolve_rounds_damage_fire_rate_and_range() -> bool:
	# 4 * 1.4 = 5.6
	assert_almost_eq(UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 1))["damage"],
		6.0, 0.0001, "damage 5.6 resolves to 6")
	# 500 * 0.75 * 0.75 = 281.25
	assert_almost_eq(UpgradesSim.resolve_tower_stats(&"fast", _tiers(2, 0))["fire_rate"],
		281.0, 0.0001, "fire rate 281.25 resolves to 281")
	# 150 * 1.2 * 1.33 = 239.4
	assert_almost_eq(UpgradesSim.resolve_tower_stats(&"long", _tiers(4, 0))["range"],
		239.0, 0.0001, "range 239.4 resolves to 239")
	return true

func test_resolve_does_not_mutate_the_tower_def() -> bool:
	var before := float(Towers.DEFS[&"basic"]["damage"])
	UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 4))
	assert_almost_eq(float(Towers.DEFS[&"basic"]["damage"]), before, 0.0001,
		"the shared tower table is untouched")
	return true

# --------------------------------------------------------------------------
# Penetration scales with tower level (spec 2026-08-25 section 3.2)
# --------------------------------------------------------------------------
#
# The owner's rule: levelling a tower makes it better at getting THROUGH, not
# only at hitting harder. It is the second guarantee (with the damage floor)
# that no tower is ever walled by late-game armour.

func test_an_unupgraded_tower_has_no_bought_penetration() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", UpgradesSim.empty_tiers())
	assert_eq(int(s["pierce"]), int(Towers.DEFS[&"fast"]["pierce"]),
		"level one carries only its table value")
	return true

func test_penetration_grows_with_total_tiers_bought() -> bool:
	var one := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 1, &"burst": 0})
	var many := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(many["pierce"]) > int(one["pierce"]),
		"a maxed tower gets through more than a barely-upgraded one")
	return true

# The case the rule exists for: neither Magic branch mentions pierce, and it
# must still end up able to hurt an armoured target.
func test_a_maxed_magic_tower_carries_penetration_it_never_bought() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(s["pierce"]) > 0,
		"neither Magic branch mentions pierce, but levelling still grants it")
	return true

# Long Range must stay the specialist rather than being levelled down to
# everyone else: its explicit tiers stack ON TOP of the scaling term.
func test_the_pierce_tiers_stack_on_top_of_the_level_term() -> bool:
	var specialist := UpgradesSim.resolve_tower_stats(&"long", {&"burst": 4, &"sustained": 2})
	var generalist := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(specialist["pierce"]) > int(generalist["pierce"]),
		"same tier count, but Long Range bought pierce as well")
	return true

func test_penetration_counts_both_branches_equally() -> bool:
	var lopsided := UpgradesSim.resolve_tower_stats(&"basic", {&"sustained": 4, &"burst": 0})
	var spread := UpgradesSim.resolve_tower_stats(&"basic", {&"sustained": 2, &"burst": 2})
	assert_eq(int(lopsided["pierce"]), int(spread["pierce"]),
		"four tiers is four tiers, however they were spent")
	return true

# Levelled penetration must do real work SOMEWHERE, and mid-game armour is
# where. Against a wave-20 ogre a maxed Magic tower rides the damage floor,
# and that is the design rather than a shortfall: magic is the shield answer,
# armour is Long Range's, and the floor is what stops magic ever being a dead
# button. An earlier version of this test asserted the opposite and drove
# PIERCE_PER_TIER to 2 - which erased armour for every physical tower. See
# that constant's comment.
func test_levelled_penetration_does_real_work_against_mid_game_armour() -> bool:
	var st := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	var armor := int(Enemies.resistance_for(&"ogre", 10)["armor"])
	var target := {"health": 500.0, "armor": armor, "shield": 0, "alive": true}
	var with_pierce := Damage.resolve({
		"damage": float(st["damage"]), "pierce": int(st["pierce"]),
		"damage_type": &"magic"}, target)
	var without := Damage.resolve({
		"damage": float(st["damage"]), "pierce": 0, "damage_type": &"magic"}, target)
	assert_true(with_pierce["damage_dealt"] > without["damage_dealt"],
		"levelling buys its way through a wave 10 ogre")
	return true

# And against LATE armour it rides the floor - stated, so nobody "fixes" it
# back into erasing armour for everyone else.
func test_a_maxed_magic_tower_rides_the_floor_against_late_armour() -> bool:
	var st := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	var target := {"health": 500.0, "shield": 0, "alive": true,
		"armor": int(Enemies.resistance_for(&"ogre", 20)["armor"])}
	var r := Damage.resolve({"damage": float(st["damage"]), "pierce": int(st["pierce"]),
		"damage_type": &"magic"}, target)
	assert_almost_eq(r["damage_dealt"],
		float(st["damage"]) * Damage.MIN_DAMAGE_FRACTION, 0.001,
		"the floor, not the pierce, is what carries magic against a wave 20 ogre")
	assert_true(r["damage_dealt"] > 0.0, "and it is never nothing")
	return true

# --------------------------------------------------------------------------
# Flat damage and fire rate
# --------------------------------------------------------------------------
#
# These call UpgradesSim._apply_effects directly rather than through a tier.
# At this point no tier in the shipped table carries a flat key, and inventing
# one to test against would mean testing a fixture instead of the rules. The
# leading underscore is convention, not access control - this is the same
# function resolve_tower_stats runs, not a parallel implementation.

# Flat bonuses ADD rather than compose. That is the whole point of the change:
# two tiers of +6 is +12, where two tiers of x1.4 was +96%, and the deeper the
# branch went the worse the shape got.
func test_resolve_adds_flat_damage_bonuses() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	var base: float = stats["damage"]
	UpgradesSim._apply_effects(stats, {&"damage_bonus": 6.0})
	UpgradesSim._apply_effects(stats, {&"damage_bonus": 6.0})
	assert_almost_eq(stats["damage"], base + 12.0, 0.0001,
		"two flat bonuses add rather than compose")
	return true

# Lower is faster, so a fire-rate bonus is SUBTRACTED from the interval.
func test_resolve_subtracts_flat_fire_rate_bonuses() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	var base: float = stats["fire_rate"]
	UpgradesSim._apply_effects(stats, {&"fire_rate_bonus_ms": 200.0})
	assert_almost_eq(stats["fire_rate"], base - 200.0, 0.0001,
		"a fire-rate bonus shortens the interval")
	return true

# Flat bonuses do not compound, but they do not asymptote either: without a
# floor a deep branch walks the interval to zero and then negative, and a
# tower firing every -50ms is an infinite damage source.
func test_a_tower_can_never_out_fire_the_floor() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"fast", UpgradesSim.empty_tiers())
	UpgradesSim._apply_effects(stats, {&"fire_rate_bonus_ms": 999999.0})
	assert_almost_eq(stats["fire_rate"], UpgradesSim.MIN_FIRE_RATE_MS, 0.0001,
		"the interval floors rather than going negative")
	assert_true(UpgradesSim.MIN_FIRE_RATE_MS > 0.0, "and the floor is positive")
	return true

# The Mortar's own comment in data/upgrades.gd states the rule: area damage
# belongs to it, and "a tower that could take them would answer everything."
# Basic and Long Range both used to reach for it, and a board that took them
# did answer everything - eleven of the sixteen legal maxed boards shut the
# hardest tier out with zero leaks.
#
# Asserted on RESOLVED stats rather than on the table, so a tier that grants
# splash by some other route is caught too.
func test_only_the_mortar_ever_resolves_splash() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			var other: StringName = &"burst" if branch == &"sustained" else &"sustained"
			var s := UpgradesSim.resolve_tower_stats(kind,
				{branch: UpgradesSim.MAX_TIER, other: UpgradesSim.CROSS_PATH_CAP})
			var splashes: bool = float(s["splash_radius"]) > 0.0
			assert_eq(splashes, kind == &"mortar",
				"%s/%s splash, got %s" % [kind, branch, s["splash_radius"]])
	return true
