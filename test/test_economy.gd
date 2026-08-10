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
