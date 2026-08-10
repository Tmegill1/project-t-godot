extends TestCase

# --------------------------------------------------------------------------
# Brief's tests (converted from -> void to -> bool per the harness contract).
# --------------------------------------------------------------------------

func test_flat_cost_at_or_below_the_scaling_wave() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 5.0}, 1), 1, "slime costs 1")
	assert_eq(Leak.resolve({"life_loss": 2, "health": 3.0}, 3), 2, "bee costs 2")
	assert_eq(Leak.resolve({"life_loss": 5, "health": 8.0}, 5), 4, "ogre's 5 caps to 4")
	return true

func test_health_based_cost_past_the_scaling_wave() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 2.0}, 6), 2, "2 health costs 2")
	assert_eq(Leak.resolve({"life_loss": 1, "health": 2.3}, 6), 3, "rounds up")
	return true

# Uncapped, one leaked ogre cost 12 of 20 lives by wave 10 and all of them by
# wave 20, making lives binary rather than a resource.
func test_the_cost_is_capped_at_four() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 40.0}, 20), 4, "capped")
	assert_eq(Leak.resolve({"life_loss": 99, "health": 1.0}, 2), 4, "flat value capped too")
	return true

func test_a_leak_always_costs_at_least_one() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 0.2}, 10), 1, "minimum of one")
	return true

func test_exempt_enemies_cost_nothing() -> bool:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 8.0, "exempt_from_life_loss": true}, 10),
		0, "exempt escapes free")
	return true

# --------------------------------------------------------------------------
# Ported from leak.test.ts beyond the brief's list. Expected values are
# taken directly from the .test.ts file, never derived by running this
# GDScript port.
# --------------------------------------------------------------------------

# Ported: "ignores remaining health entirely" (at/below the scaling wave).
func test_flat_path_ignores_remaining_health() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 999.0}, 5), 1,
		"999 health is irrelevant on the flat path")
	return true

# Ported: "costs the enemy's remaining health instead" — a plain
# integer-valued (non-fractional) case, distinct from the brief's
# fractional-rounding cases.
func test_health_based_cost_with_no_fractional_remainder() -> bool:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 3.0}, 6), 3, "3 health costs 3, below the cap")
	return true

# Ported: "★ caps however much health the enemy escaped with" — the module's
# central load-bearing claim (this is the whole reason the cap exists).
# Checked across a range of magnitudes, not just one value near the cap.
func test_cap_holds_across_a_wide_range_of_health_values() -> bool:
	for health in [10.0, 50.0, 500.0, 5000.0]:
		var enemy := {"life_loss": 1, "health": health}
		assert_eq(Leak.resolve(enemy, 20), Leak.MAX_LIFE_LOSS_PER_LEAK,
			"capped at 4 regardless of how far health has compounded")
	return true

# Ported: "leaves twenty lives worth several mistakes" — the cap's actual
# justification: a starting pool of 20 lives survives at least 4 leaks of
# the worst possible case.
func test_capped_penalty_leaves_several_mistakes_worth_of_lives() -> bool:
	var worst_case := Leak.resolve({"life_loss": 99, "health": 9999.0}, 30)
	assert_true(float(20) / float(worst_case) >= 4.0,
		"twenty lives afford at least four worst-case leaks")
	return true

# Ported: "never costs less than one life" — both a near-zero and an
# exactly-zero remaining health.
func test_health_floor_holds_at_near_zero_and_exactly_zero() -> bool:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 0.1}, 9), 1, "near-zero health still costs one")
	assert_eq(Leak.resolve({"life_loss": 5, "health": 0.0}, 9), 1, "exactly-zero health still costs one")
	return true

# Ported: "switches over exactly after wave 5" — pins the constant and the
# boundary in both directions: wave 5 itself is still flat, wave 6 is
# health-based (and here immediately hits the cap).
func test_switches_over_exactly_after_wave_five() -> bool:
	assert_eq(Leak.LIFE_LOSS_SCALING_WAVE, 5, "the scaling wave constant is 5")
	assert_eq(Leak.resolve({"life_loss": 1, "health": 20.0}, 5), 1, "wave 5 itself is still flat")
	assert_eq(Leak.resolve({"life_loss": 1, "health": 20.0}, 6), 4, "wave 6 is health-based, capped")
	return true

# Ported: exemption holds at a late wave and at the very first wave alike —
# the flag short-circuits before the wave comparison runs at all.
func test_exemption_short_circuits_regardless_of_wave() -> bool:
	var exempt_enemy := {"life_loss": 5, "health": 50.0, "exempt_from_life_loss": true}
	assert_eq(Leak.resolve(exempt_enemy, 9), 0, "exempt at a late wave")
	assert_eq(Leak.resolve(exempt_enemy, 1), 0, "exempt at the very first wave")
	return true

# Ported: "is pure — it does not mutate the enemy".
func test_resolve_does_not_mutate_the_enemy() -> bool:
	var enemy := {"life_loss": 1, "health": 12.0}
	Leak.resolve(enemy, 6)
	assert_eq(enemy, {"life_loss": 1, "health": 12.0}, "enemy dictionary is untouched")
	return true
