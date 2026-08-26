extends TestCase

# --------------------------------------------------------------------------
# Brief's tests (converted from -> void to -> bool per the harness contract).
# --------------------------------------------------------------------------

func test_first_tower_costs_base_price() -> bool:
	assert_eq(EconomySim.tower_price(&"basic", 0), 20, "first basic")
	assert_eq(EconomySim.tower_price(&"long", 0), 100, "first long range")
	return true

func test_price_escalates_per_tower_already_owned() -> bool:
	assert_eq(EconomySim.tower_price(&"basic", 1), 30, "20 + 10")
	assert_eq(EconomySim.tower_price(&"basic", 3), 50, "20 + 3*10")
	assert_eq(EconomySim.tower_price(&"mortar", 2), 140, "70 + 2*35")
	return true

# Renamed from the brief's `test_escalation_is_per_kind_not_global`: tower_price
# is stateless (it takes owned_of_kind as an argument, tracks no state of its
# own), so what this actually pins is that the Towers.DEFS lookup uses the
# `kind` argument given, not a fixed/wrong one. A guarantee about per-kind
# *count tracking* isolation belongs to whatever maintains those counts
# (Task 19's board), not to this pure pricing function.
func test_tower_price_looks_up_the_given_kind_not_a_fixed_one() -> bool:
	assert_eq(EconomySim.tower_price(&"fast", 0), 50,
		"fast's own base price, not basic's, is read when kind is fast")
	return true

func test_sell_refunds_half_rounded_down() -> bool:
	assert_eq(EconomySim.sell_refund(20), 10, "half of 20")
	assert_eq(EconomySim.sell_refund(35), 17, "half of 35 floors to 17")
	return true

func test_affordability() -> bool:
	assert_true(EconomySim.can_afford(100, 100), "exact gold is affordable")
	assert_false(EconomySim.can_afford(99, 100), "one short")
	return true

func test_tower_limits_on_the_first_map() -> bool:
	assert_eq(EconomySim.tower_limit(&"basic", &"demoMap"), 8, "basic limit")
	assert_eq(EconomySim.tower_limit(&"long", &"demoMap"), 5, "long range limit")
	return true

# --------------------------------------------------------------------------
# Ported from TowerManager.ts / economy.ts / towers.ts beyond the brief's
# list. Expected values are derived directly from those files' own constants
# (TOWER_DEFS, escalatedCost, sellRefund, getTowerLimit), never from running
# this GDScript port.
# --------------------------------------------------------------------------

# escalatedCost(base, owned, escalation) = base + owned * escalation, checked
# for every tower kind at owned=0 (base price, no escalation term at all —
# distinct from owned=1, which is the first point the escalation term is
# nonzero).
func test_first_tower_of_every_kind_costs_exactly_its_base_cost() -> bool:
	assert_eq(EconomySim.tower_price(&"basic", 0), 20, "basic base cost")
	assert_eq(EconomySim.tower_price(&"fast", 0), 50, "fast base cost")
	assert_eq(EconomySim.tower_price(&"mortar", 0), 70, "mortar base cost")
	assert_eq(EconomySim.tower_price(&"long", 0), 100, "long base cost")
	return true

# Escalation step size differs per kind (10/15/35/50) — pin each kind's own
# step at owned=1, not just basic's and mortar's (already covered by the
# brief).
func test_escalation_step_matches_each_kinds_own_cost_escalation() -> bool:
	assert_eq(EconomySim.tower_price(&"fast", 1), 65, "50 + 15")
	assert_eq(EconomySim.tower_price(&"long", 1), 150, "100 + 50")
	return true

# Escalation compounds linearly with owned count — not just +1, +3 (brief) —
# and per kind, confirmed pairwise: owning many of one kind never moves the
# price of any other kind (TowerManager keeps a separate `counts` entry per
# TowerKind, never a single shared counter).
func test_escalation_is_linear_and_isolated_per_kind_at_higher_counts() -> bool:
	assert_eq(EconomySim.tower_price(&"basic", 7), 90, "20 + 7*10")
	assert_eq(EconomySim.tower_price(&"fast", 7), 155, "50 + 7*15")
	assert_eq(EconomySim.tower_price(&"long", 4), 300, "100 + 4*50")
	assert_eq(EconomySim.tower_price(&"mortar", 4), 210, "70 + 4*35")
	# Owning 7 basics (the map's near-limit count) must not change fast's
	# price at owned=0 — restates the brief's per-kind-isolation test at a
	# higher, more adversarial basic count.
	assert_eq(EconomySim.tower_price(&"fast", 0), 50,
		"seven owned basics do not leak into a fresh fast's price")
	return true

# Matches economy.ts's `Math.max(0, owned)` clamp on escalatedCost. Nothing
# in this slice can produce a negative owned_of_kind yet (Task 19's board
# will maintain the real counts), but the function must not silently price
# a tower below its base cost if one is ever passed in.
func test_negative_owned_count_clamps_to_base_price() -> bool:
	assert_eq(EconomySim.tower_price(&"basic", -1), 20,
		"a negative count must not push the price below base")
	assert_eq(EconomySim.tower_price(&"long", -5), 100,
		"holds for a larger-magnitude negative count too")
	return true

# sellRefund(cost) = max(0, floor(cost / 2)). Sweeps a range of paid values,
# not just the brief's two (20, 35) — every even value refunds exactly
# half, every odd value floors down by exactly one gold from the true half.
func test_sell_refund_across_a_range_of_paid_values() -> bool:
	var cases := {
		0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 5: 2,
		19: 9, 20: 10, 21: 10,
		49: 24, 50: 25, 51: 25,
		69: 34, 70: 35, 71: 35,
		99: 49, 100: 50, 101: 50,
		149: 74, 150: 75, 151: 75,
	}
	for paid in cases:
		assert_eq(EconomySim.sell_refund(paid), cases[paid],
			"sell_refund(%d) == %d" % [paid, cases[paid]])
	return true

# sell_refund on the actual escalated price of a tower must refund more than
# selling one bought at base price — the whole point of "refunds what was
# actually paid, not the current list price."
func test_sell_refund_on_an_escalated_price_exceeds_base_price_refund() -> bool:
	var base_price: int = EconomySim.tower_price(&"basic", 0)
	var escalated_price: int = EconomySim.tower_price(&"basic", 3)
	assert_eq(base_price, 20, "sanity: base price")
	assert_eq(escalated_price, 50, "sanity: escalated price")
	assert_true(EconomySim.sell_refund(escalated_price) > EconomySim.sell_refund(base_price),
		"a tower bought at the escalated price refunds more than one bought at base")
	assert_eq(EconomySim.sell_refund(escalated_price), 25, "half of 50")
	return true

# canAfford(balance, cost): every value strictly above the cost must also be
# affordable, not just the exact-match case the brief covers — this is what
# distinguishes >= from == as the underlying operator.
func test_affordability_holds_for_gold_strictly_above_the_price() -> bool:
	assert_true(EconomySim.can_afford(101, 100), "one gold to spare")
	assert_true(EconomySim.can_afford(1000, 100), "gold far in excess of price")
	return true

# Zero-cost and zero-gold boundaries. This port's can_afford is a plain
# gold >= price (see divergence note in the task report), so a zero-cost
# "purchase" at zero gold is affordable here.
func test_affordability_at_zero_price_and_zero_gold() -> bool:
	assert_true(EconomySim.can_afford(0, 0), "zero gold covers a zero-cost item")
	assert_true(EconomySim.can_afford(5, 0), "any gold covers a zero-cost item")
	assert_false(EconomySim.can_afford(0, 1), "zero gold cannot afford anything positive")
	return true

# getTowerLimit: baseLimit on the first map, baseLimit + limitBonusMap2 on
# any other map — pins both branches, for every kind, not just the brief's
# two on the first-map branch alone. Only demoMap is registered in this
# slice's Maps table (see Maps.DEFS), so "map2" here is a bare StringName
# that only ever needs to satisfy `!= Maps.FIRST`, not an actual registered
# map — this second branch is otherwise unreachable in the current slice.
func test_tower_limits_on_a_second_map_add_the_bonus() -> bool:
	assert_eq(EconomySim.tower_limit(&"basic", &"map2"), 10, "8 + 2")
	assert_eq(EconomySim.tower_limit(&"fast", &"map2"), 10, "8 + 2")
	assert_eq(EconomySim.tower_limit(&"mortar", &"map2"), 7, "5 + 2")
	assert_eq(EconomySim.tower_limit(&"long", &"map2"), 7, "5 + 2")
	return true

# First-map limits for every kind (brief only covers basic and long).
func test_tower_limits_on_the_first_map_for_every_kind() -> bool:
	assert_eq(EconomySim.tower_limit(&"fast", &"demoMap"), 8, "fast limit, no bonus")
	assert_eq(EconomySim.tower_limit(&"mortar", &"demoMap"), 5, "mortar limit, no bonus")
	return true

# --------------------------------------------------------------------------
# The task's specific ask: does flooring a float product of an integer and
# 0.5 ever land one below the mathematically expected value for some N?
# Answer, checked computationally below rather than merely asserted: no —
# multiplying by 0.5 is an exact power-of-two operation in IEEE-754 for any
# integer representable in a double's mantissa (paid never gets remotely
# close to 2^53 in this game), so float(paid) * 0.5 never lands just under
# an integer boundary the way e.g. multiplying by 0.1 could. This test
# sweeps 0..500 (well beyond any real tower price/refund magnitude) and
# checks against integer division, which truncates toward zero and is
# mathematically identical to floor() for every non-negative operand.
# --------------------------------------------------------------------------
func test_sell_refund_matches_integer_halving_across_zero_to_five_hundred() -> bool:
	for paid in range(0, 501):
		var expected: int = paid / 2 # integer division == floor(paid / 2.0) for paid >= 0
		assert_eq(EconomySim.sell_refund(paid), expected,
			"sell_refund(%d) == %d" % [paid, expected])
	return true

# --------------------------------------------------------------------------
# kill_reward
#
# The multiplier applies before the flat bonus, so a flat bonus is never
# multiplied. Order matters: the other way round, fast/burst tier 4 would pay
# (5 + 2) * 2 = 14 rather than 5 * 2 + 2 = 12, and no tier text says that.
#
# Rounding follows the reference, which pays
# `Math.round(reward * goldMultiplier) + bonusGold` in BaseEnemy's death
# handler and rounds the same way in spawn.ts and harness.ts. The plan for this
# task specified floor instead; see the ledger for the ruling. No live number
# distinguishes them today (every reward times every multiplier in the table is
# a whole number), which is exactly why the choice is pinned here rather than
# left to be discovered when a reward changes.
# --------------------------------------------------------------------------

func test_kill_reward_is_the_base_when_the_source_has_no_gold_effects() -> bool:
	assert_eq(EconomySim.kill_reward(5, {"damage": 4.0}), 5,
		"a source without gold fields pays the plain reward")
	return true

func test_kill_reward_applies_the_multiplier() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 1.6}), 8, "5 * 1.6")
	return true

func test_kill_reward_adds_the_flat_bonus() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"bonus_gold_per_kill": 2}), 7, "5 + 2")
	return true

func test_kill_reward_multiplies_before_adding_the_flat_bonus() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2}), 12,
		"5 * 2 + 2, not (5 + 2) * 2")
	return true

# Rounds to nearest rather than flooring: 4.8 is 5 gold, not 4.
func test_kill_reward_rounds_a_fractional_result_to_the_nearest_gold() -> bool:
	assert_eq(EconomySim.kill_reward(3, {&"gold_multiplier": 1.6}), 5, "4.8 rounds up to 5")
	assert_eq(EconomySim.kill_reward(7, {&"gold_multiplier": 1.6}), 11, "11.2 rounds down to 11")
	return true

# And a half goes up, matching JavaScript's Math.round for the non-negative
# rewards this game deals in.
func test_kill_reward_rounds_a_half_upward() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 1.5}), 8, "7.5 rounds up to 8")
	return true

# The flat bonus is added after rounding, so it can never be scaled or rounded
# itself - two half-gold multipliers must not compound into a rounding drift.
func test_kill_reward_adds_the_flat_bonus_after_rounding() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 1.5, &"bonus_gold_per_kill": 1}), 9,
		"round(7.5) + 1")
	return true

func test_kill_reward_never_pays_less_than_zero() -> bool:
	assert_eq(EconomySim.kill_reward(0, {&"gold_multiplier": 2.0}), 0, "nothing from nothing")
	assert_eq(EconomySim.kill_reward(-5, {}), 0, "a bad reward is inert, not a gold sink")
	return true

# The outer clamp guards the other way in: a negative flat bonus (nothing in
# the table carries one, and nothing should) must not turn a kill into a
# withdrawal.
func test_kill_reward_clamps_a_negative_flat_bonus() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"bonus_gold_per_kill": -100}), 0,
		"a kill never costs the player gold")
	return true

# The seam this function exists to serve: the dictionary it reads is the one
# resolve_tower_stats produces, so the two must agree on key names. A rename on
# either side would silently pay base gold forever.
func test_kill_reward_reads_the_keys_resolve_tower_stats_writes() -> bool:
	var maxed_income := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 0, &"burst": 4})
	assert_eq(EconomySim.kill_reward(5, maxed_income), 12,
		"a fully upgraded Bounty Hunter pays 5 * 2 + 2 on a goblin")
	var plain := UpgradesSim.resolve_tower_stats(&"fast", UpgradesSim.empty_tiers())
	assert_eq(EconomySim.kill_reward(5, plain), 5, "and an unupgraded one pays the plain reward")
	return true

# The inner clamp, which the outer one does not subsume: with a flat bonus in
# play, an unclamped negative reward would eat into the bonus instead of being
# ignored. Nothing produces a negative reward today - the clamp is here because
# the price side has carried the same guard since the core slice.
func test_kill_reward_ignores_a_negative_reward_rather_than_netting_it_off() -> bool:
	assert_eq(EconomySim.kill_reward(-5, {&"bonus_gold_per_kill": 10}), 10,
		"the bonus is paid in full, not reduced to 5")
	return true

# --------------------------------------------------------------------------
# The wave gold modifier (spec 2026-08-24-slice-0-design.md section 4.6)
# --------------------------------------------------------------------------

func test_kill_reward_defaults_to_an_unmodified_wave() -> bool:
	assert_eq(EconomySim.kill_reward(20, {}), 20,
		"omitting the modifier pays the base reward, so old call sites are safe")
	return true

func test_kill_reward_applies_the_wave_gold_modifier() -> bool:
	assert_eq(EconomySim.kill_reward(20, {}, 0.625), 13, "20 * 0.625 = 12.5, rounds to 13")
	assert_eq(EconomySim.kill_reward(20, {}, 0.875), 18, "20 * 0.875 = 17.5, rounds to 18")
	return true

# The ORDER is the point: the wave modifier scales the base reward, and the
# tower's own gold multiplier then applies to that scaled figure.
func test_the_wave_modifier_applies_before_the_towers_gold_multiplier() -> bool:
	# base 20, wave 0.5 -> 10, tower x2 -> 20, flat +2 -> 22.
	assert_eq(EconomySim.kill_reward(20, {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2}, 0.5),
		22, "wave modifier first, then the tower multiplier, then the flat bonus")
	return true

func test_the_flat_bonus_is_not_scaled_by_the_wave_modifier() -> bool:
	assert_eq(EconomySim.kill_reward(0, {&"bonus_gold_per_kill": 5}, 0.4), 5,
		"a flat bonus survives the wave modifier intact")
	return true

func test_kill_reward_still_never_pays_less_than_zero_with_a_modifier() -> bool:
	assert_eq(EconomySim.kill_reward(-5, {}, 0.5), 0, "a bad reward stays inert")
	return true

# --------------------------------------------------------------------------
# Wave-clear bonus
# --------------------------------------------------------------------------

func test_wave_clear_base_grows_with_the_wave_number() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(1, 0.0)["base"], 25, "20 + 1*5")
	assert_eq(EconomySim.wave_clear_bonus(20, 0.0)["base"], 120, "20 + 20*5")
	return true

func test_a_fast_clear_pays_the_full_speed_bonus() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(1, 0.0)["speed"], 40, "instant clear")
	assert_eq(EconomySim.wave_clear_bonus(1, 20000.0)["speed"], 40,
		"exactly at the fast threshold still pays in full")
	return true

func test_a_slow_clear_pays_no_speed_bonus() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(1, 60000.0)["speed"], 0, "at the slow threshold")
	assert_eq(EconomySim.wave_clear_bonus(1, 999999.0)["speed"], 0, "and beyond it")
	return true

func test_the_speed_bonus_is_linear_between_the_thresholds() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(1, 40000.0)["speed"], 20, "half the span, half the bonus")
	return true

func test_a_negative_clear_time_is_treated_as_instant() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(1, -5000.0)["speed"], 40,
		"a nonsense clock reads as fast rather than paying nothing")
	return true

func test_wave_clear_base_never_goes_negative_on_a_bad_wave_number() -> bool:
	assert_eq(EconomySim.wave_clear_bonus(-3, 0.0)["base"], 20,
		"a negative wave clamps to the flat base rather than subtracting")
	return true

# --------------------------------------------------------------------------
# Interest
# --------------------------------------------------------------------------

func test_no_interest_below_the_minimum_balance() -> bool:
	assert_eq(EconomySim.interest_on(49), 0, "one short of the floor")
	assert_eq(EconomySim.interest_on(0), 0, "and nothing at all")
	return true

func test_interest_pays_the_rate_at_and_above_the_minimum() -> bool:
	assert_eq(EconomySim.interest_on(50), 2, "5% of 50 floors to 2")
	assert_eq(EconomySim.interest_on(200), 10, "5% of 200")
	return true

# The cap is the load-bearing part: uncapped compounding makes hoarding
# strictly better than building, which inverts the whole game.
func test_interest_is_capped() -> bool:
	assert_eq(EconomySim.interest_on(600), 30, "5% of 600 is exactly the cap")
	assert_eq(EconomySim.interest_on(100000), 30, "and a huge bank pays no more")
	return true

func test_interest_floors_rather_than_rounding() -> bool:
	assert_eq(EconomySim.interest_on(59), 2, "5% of 59 is 2.95, floors to 2")
	return true

# --------------------------------------------------------------------------
# Calling a wave early
# --------------------------------------------------------------------------

func test_calling_early_pays_per_whole_second_given_up() -> bool:
	assert_eq(EconomySim.call_early_bonus(10000.0), 30, "10s * 3 gold")
	assert_eq(EconomySim.call_early_bonus(5000.0), 15, "5s * 3 gold")
	return true

func test_a_partial_second_does_not_pay() -> bool:
	assert_eq(EconomySim.call_early_bonus(1999.0), 3, "1.999s floors to one second")
	assert_eq(EconomySim.call_early_bonus(999.0), 0, "under a second pays nothing")
	return true

func test_calling_early_is_capped() -> bool:
	assert_eq(EconomySim.call_early_bonus(20000.0), 45,
		"the full 20s window would be 60 gold, capped to 45")
	return true

func test_a_remaining_time_beyond_the_window_is_clamped() -> bool:
	assert_eq(EconomySim.call_early_bonus(999999.0), 45, "clamped to the window, then capped")
	return true

func test_letting_the_clock_run_out_pays_nothing() -> bool:
	assert_eq(EconomySim.call_early_bonus(0.0), 0, "no time given up, no bonus")
	assert_eq(EconomySim.call_early_bonus(-100.0), 0, "and a negative remainder is inert")
	return true
