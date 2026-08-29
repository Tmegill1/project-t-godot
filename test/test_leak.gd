extends TestCase

# What a leak costs is the enemy's OWN price, scaled by how much of it
# arrived alive.
#
# The rule this replaced was `min(4, ceil(remaining_health))` past wave 5.
# Every ordinary enemy has at least 4 health from wave 10 on, so the cap
# always bound and a goblin, a bat, a shaman and an ogre all cost exactly 4.
# `life_loss` - the per-kind price the roster is built around - was dead data
# at every wave that mattered, and the run was always exactly five leaks from
# over whatever leaked.
#
# Now: `ceil(life_loss * remaining / max_health)`, floored at one and ceilinged
# at the kind's own price. Two properties come out of that and both are tested
# below: WHICH kind leaked decides what it costs, and an enemy that arrives
# nearly dead costs less than one that walks through untouched.

# --------------------------------------------------------------------------
# The kind decides the price
# --------------------------------------------------------------------------

# The headline of the whole change: at full health each kind costs its own
# declared price, and the ogre's 5 is no longer flattened to a cap.
func test_a_full_health_leak_costs_the_kinds_own_price() -> bool:
	for kind in Enemies.KINDS:
		var flat := int(Enemies.DEFS[kind]["life_loss"])
		assert_eq(
			Leak.resolve({"life_loss": flat, "health": 40.0, "max_health": 40.0}),
			flat,
			"%s costs its own life_loss" % kind)
	return true

# Isolates the change from the old rule. Under `min(4, ceil(health))` these
# four were indistinguishable; the roster only means something if they are not.
func test_the_four_ordinary_kinds_no_longer_cost_the_same() -> bool:
	var costs := {}
	for kind in Enemies.KINDS:
		var flat := int(Enemies.DEFS[kind]["life_loss"])
		costs[kind] = Leak.resolve(
			{"life_loss": flat, "health": 40.0, "max_health": 40.0})
	assert_eq(costs[&"goblin"], 1, "goblin is a scratch")
	assert_eq(costs[&"bat"], 2, "bat costs more than a goblin")
	assert_eq(costs[&"shaman"], 3, "shaman costs more than a bat")
	assert_eq(costs[&"ogre"], 5, "ogre is the worst ordinary leak, uncapped")
	return true

# The cost no longer reads the wave at all, which is what the deleted
# `wave` parameter and `LIFE_LOSS_SCALING_WAVE` were for. A wave-20 goblin
# carries ~24 health against a wave-1 goblin's 5; both cost 1, because both
# arrived whole.
func test_a_full_health_leak_costs_the_same_at_every_wave() -> bool:
	var early := Leak.resolve({"life_loss": 1, "health": 5.0, "max_health": 5.0})
	var late := Leak.resolve({"life_loss": 1, "health": 24.0, "max_health": 24.0})
	assert_eq(early, late, "health compounding does not change a whole enemy's price")
	assert_eq(late, 1, "and the price is the kind's own")
	return true

# --------------------------------------------------------------------------
# How alive it arrived
# --------------------------------------------------------------------------

# The ratio is against the enemy's OWN maximum, not against an absolute
# number of hit points. This is the test that fails if someone reintroduces
# a health-based rule: same remaining health, different max, different cost.
func test_the_cost_scales_against_this_enemys_own_maximum() -> bool:
	var chipped := Leak.resolve({"life_loss": 5, "health": 10.0, "max_health": 100.0})
	var whole := Leak.resolve({"life_loss": 5, "health": 10.0, "max_health": 10.0})
	assert_eq(chipped, 1, "10 of 100 health is a tenth of the price, floored at one")
	assert_eq(whole, 5, "10 of 10 health is the whole price")
	assert_true(chipped < whole,
		"identical remaining health, different price - the ratio is what is read")
	return true

func test_half_health_costs_half_the_price() -> bool:
	assert_eq(Leak.resolve({"life_loss": 4, "health": 50.0, "max_health": 100.0}), 2,
		"half of 4 is 2")
	return true

# Rounds UP, so chip damage never makes a leak free-er than the arithmetic
# says. Mutation guard: `floor` gives 1 here where `ceil` gives 2, and the
# 0.3 ratio is chosen so the two genuinely differ.
func test_a_partial_remainder_rounds_up_never_down() -> bool:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 30.0, "max_health": 100.0}), 2,
		"5 x 0.3 = 1.5 rounds up to 2, not down to 1")
	assert_eq(Leak.resolve({"life_loss": 3, "health": 10.0, "max_health": 100.0}), 1,
		"3 x 0.1 = 0.3 rounds up to 1")
	return true

# --------------------------------------------------------------------------
# The two clamps, pinned independently
# --------------------------------------------------------------------------

# The floor is only reachable at EXACTLY zero remaining health - any positive
# remainder already rounds up to at least one - so this is the only case that
# distinguishes a present floor from an absent one.
func test_an_enemy_that_arrives_at_exactly_zero_health_still_costs_one() -> bool:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 0.0, "max_health": 100.0}), 1,
		"reaching the goal is never free, however little was left of it")
	return true

func test_a_near_zero_remainder_still_costs_one() -> bool:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 0.001, "max_health": 100.0}), 1,
		"a sliver of health is still one life")
	return true

# The ceiling is only reachable when health exceeds max_health, which the game
# never produces - so, like the floor, it needs its own case or a dropped
# clamp is invisible.
func test_health_above_the_maximum_cannot_cost_more_than_the_kinds_price() -> bool:
	assert_eq(Leak.resolve({"life_loss": 2, "health": 500.0, "max_health": 10.0}), 2,
		"the kind's own price is the ceiling, whatever health says")
	return true

# A max_health of zero would divide by zero. Nothing in the game spawns one,
# but Leak takes a plain dictionary and is the last thing standing between a
# malformed spawn and a crash mid-wave.
func test_a_zero_maximum_falls_back_to_the_flat_price() -> bool:
	assert_eq(Leak.resolve({"life_loss": 3, "health": 0.0, "max_health": 0.0}), 3,
		"no ratio to take, so the kind's own price stands")
	return true

# --------------------------------------------------------------------------
# Exemption
# --------------------------------------------------------------------------

func test_exempt_enemies_cost_nothing() -> bool:
	assert_eq(
		Leak.resolve({"life_loss": 5, "health": 8.0, "max_health": 8.0,
			"exempt_from_life_loss": true}),
		0, "exempt escapes free")
	return true

func test_exemption_outranks_a_full_health_leak_of_the_worst_kind() -> bool:
	assert_eq(
		Leak.resolve({"life_loss": 99, "health": 900.0, "max_health": 900.0,
			"exempt_from_life_loss": true}),
		0, "the flag short-circuits before any arithmetic runs")
	return true

# --------------------------------------------------------------------------
# Bosses - unchanged by this rewrite, and re-pinned because of it
# --------------------------------------------------------------------------
#
# A boss carries a DECLARED cost from data/bosses.gd. That was already true
# before this change and stays true: the reason it is declared rather than
# derived is that a health-derived cost compounds without limit, and by
# wave 20 one leak ended the run. The ordinary rule is now bounded by the
# kind's own price rather than by a flat cap, but a boss still bypasses it.

func test_a_boss_costs_its_own_declared_life_loss() -> bool:
	var boss := {"life_loss": 5, "health": 900.0, "max_health": 900.0,
		"boss_life_loss": 10}
	assert_eq(Leak.resolve(boss), 10, "its own cost, not the kind's")
	return true

func test_a_boss_cost_does_not_scale_with_how_alive_it_arrived() -> bool:
	var whole := {"life_loss": 5, "health": 900.0, "max_health": 900.0,
		"boss_life_loss": 10}
	var nearly_dead := {"life_loss": 5, "health": 1.0, "max_health": 900.0,
		"boss_life_loss": 10}
	assert_eq(Leak.resolve(whole), Leak.resolve(nearly_dead),
		"declared, not derived - chipping a boss does not discount it")
	assert_eq(Leak.resolve(nearly_dead), 10, "and the declared value is what stands")
	return true

func test_a_boss_cost_is_not_clamped_by_the_kinds_own_price() -> bool:
	var boss := {"life_loss": 5, "health": 900.0, "max_health": 900.0,
		"boss_life_loss": 10}
	assert_true(Leak.resolve(boss) > 5,
		"the ordinary ceiling is the kind's life_loss; a boss is exempt from it")
	return true

func test_a_zero_or_absent_boss_cost_falls_through_to_the_ordinary_rule() -> bool:
	var no_key := {"life_loss": 2, "health": 30.0, "max_health": 30.0}
	var zero := {"life_loss": 2, "health": 30.0, "max_health": 30.0,
		"boss_life_loss": 0}
	assert_eq(Leak.resolve(no_key), 2, "absent")
	assert_eq(Leak.resolve(zero), 2, "and zero")
	return true

func test_an_exempt_boss_still_costs_nothing() -> bool:
	var exempt := {"life_loss": 5, "health": 900.0, "max_health": 900.0,
		"boss_life_loss": 10, "exempt_from_life_loss": true}
	assert_eq(Leak.resolve(exempt), 0,
		"exemption outranks the boss cost, as it outranks everything")
	return true

# The whole point of the boss override, re-expressed against the new ordinary
# ceiling rather than against the deleted cap: a boss has to be legible as
# worse than anything the ordinary roster can do at full health.
func test_a_boss_leak_hurts_more_than_the_worst_ordinary_leak() -> bool:
	var worst_ordinary := 0
	for kind in Enemies.KINDS:
		worst_ordinary = maxi(worst_ordinary, Leak.resolve({
			"life_loss": int(Enemies.DEFS[kind]["life_loss"]),
			"health": 100.0, "max_health": 100.0}))
	for wave in Bosses.WAVES:
		var boss: Dictionary = Bosses.on_wave(wave)
		var cost := Leak.resolve({"life_loss": 5, "health": float(boss["health"]),
			"max_health": float(boss["health"]),
			"boss_life_loss": int(boss["life_loss"])})
		assert_true(cost > worst_ordinary,
			"the wave %d boss costs more than any ordinary leak can" % wave)
	return true

# --------------------------------------------------------------------------
# Purity
# --------------------------------------------------------------------------

func test_resolve_does_not_mutate_the_enemy() -> bool:
	var enemy := {"life_loss": 1, "health": 12.0, "max_health": 30.0}
	Leak.resolve(enemy)
	assert_eq(enemy, {"life_loss": 1, "health": 12.0, "max_health": 30.0},
		"enemy dictionary is untouched")
	return true

# --------------------------------------------------------------------------
# The life budget still buys a run's worth of mistakes
# --------------------------------------------------------------------------
#
# The old cap's justification was "twenty lives afford at least four
# worst-case leaks". The worst case is now the ogre's 5 rather than the cap's
# 4, so the same claim has to be re-checked against the value that actually
# stands - and against a boss, which is worse than either.

func test_the_life_budget_affords_several_worst_case_ordinary_leaks() -> bool:
	var ogre := Leak.resolve({"life_loss": int(Enemies.DEFS[&"ogre"]["life_loss"]),
		"health": 100.0, "max_health": 100.0})
	assert_true(float(Economy.STARTING_LIVES) / float(ogre) >= 4.0,
		"the life budget affords at least four worst-case ordinary leaks")
	return true

func test_no_single_leak_can_end_a_run_from_full_lives() -> bool:
	var worst := 0
	for wave in Bosses.WAVES:
		worst = maxi(worst, int(Bosses.on_wave(wave)["life_loss"]))
	for kind in Enemies.KINDS:
		worst = maxi(worst, int(Enemies.DEFS[kind]["life_loss"]))
	assert_true(worst < Economy.STARTING_LIVES,
		"the single worst thing in the game is a blow, not the whole run")
	return true
