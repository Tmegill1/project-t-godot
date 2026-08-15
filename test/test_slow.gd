extends TestCase

# Slowing is the Fast tower's branch identity and the only mechanic here that
# changes an enemy's speed after it spawns. It lives in sim/ because the
# harness and the live game both apply it, and two copies would drift.
#
# Note for anyone touching movement: slow only ever REDUCES step size, so it
# moves away from the fixed-step oscillation hazard documented in
# sim/movement.gd, never toward it.
#
# The reference (BaseEnemy.applySlow + entities.effectiveSpeed) stores an
# absolute `slowedUntilMs` deadline against a simulation clock. This port
# counts a remainder down instead, because sim/ has no clock of its own and is
# forbidden one. Two behavioural consequences are pinned below: an expired slow
# forgets its factor here (upstream keeps it forever), and effective_speed
# reads the timer as well as the factor, exactly as effectiveSpeed does.

func test_none_is_no_slow_at_all() -> bool:
	var s := Slow.none()
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "no time left to run")
	return true

func test_effective_speed_is_the_base_when_unslowed() -> bool:
	assert_almost_eq(Slow.effective_speed(100.0, Slow.none()), 100.0, 0.0001, "untouched")
	return true

func test_apply_sets_the_factor_and_duration() -> bool:
	var s := Slow.apply(Slow.none(), 0.7, 1500.0)
	assert_almost_eq(s[&"factor"], 0.7, 0.0001, "factor taken")
	assert_almost_eq(s[&"remaining_ms"], 1500.0, 0.0001, "duration taken")
	return true

func test_effective_speed_applies_the_factor() -> bool:
	var s := Slow.apply(Slow.none(), 0.45, 2500.0)
	assert_almost_eq(Slow.effective_speed(100.0, s), 45.0, 0.0001, "speed scaled")
	return true

# The reference gates on the deadline (`nowMs < enemy.slowedUntilMs`) before it
# ever looks at the factor. apply and tick between them keep the two fields
# consistent, so this only bites a state built by hand - but reading the timer
# makes the function total rather than dependent on an invariant kept elsewhere.
func test_effective_speed_ignores_a_factor_whose_timer_has_run_out() -> bool:
	var expired := {&"factor": 0.5, &"remaining_ms": 0.0}
	assert_almost_eq(Slow.effective_speed(100.0, expired), 100.0, 0.0001, "the deadline gates the factor")
	return true

# Strongest wins, matching resolve_tower_stats. A weaker slow landing on an
# enemy already deeply slowed must not speed it back up.
func test_apply_keeps_the_stronger_of_two_slows() -> bool:
	var strong := Slow.apply(Slow.none(), 0.45, 2500.0)
	var after := Slow.apply(strong, 0.7, 1500.0)
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "the weaker slow did not win")
	return true

# But it must still refresh the clock: standing in a weaker tower's fire keeps
# an enemy slowed rather than letting the strong slow lapse early.
func test_apply_refreshes_the_timer_with_the_longer_remaining() -> bool:
	var nearly_done := {&"factor": 0.45, &"remaining_ms": 100.0}
	var after := Slow.apply(nearly_done, 0.7, 1500.0)
	assert_almost_eq(after[&"remaining_ms"], 1500.0, 0.0001, "the longer timer wins")
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "and the stronger factor is kept")
	return true

# The other half of "the longer timer wins": a short slow landing on a long one
# must not cut the long one short.
func test_apply_keeps_a_longer_running_timer() -> bool:
	var long_running := {&"factor": 0.7, &"remaining_ms": 2000.0}
	var after := Slow.apply(long_running, 0.45, 500.0)
	assert_almost_eq(after[&"remaining_ms"], 2000.0, 0.0001, "the shorter duration did not truncate it")
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "and the stronger factor took over")
	return true

func test_apply_upgrades_to_a_stronger_slow() -> bool:
	var weak := Slow.apply(Slow.none(), 0.7, 1500.0)
	var after := Slow.apply(weak, 0.45, 2500.0)
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "the stronger slow takes over")
	assert_almost_eq(after[&"remaining_ms"], 2500.0, 0.0001, "with its own duration")
	return true

func test_tick_counts_the_timer_down() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 400.0)
	assert_almost_eq(s[&"remaining_ms"], 600.0, 0.0001, "decremented by delta")
	assert_almost_eq(s[&"factor"], 0.5, 0.0001, "still slowed")
	return true

# Expiry must restore full speed exactly at zero, not below it - a negative
# remainder that kept the factor would slow the enemy forever.
func test_tick_restores_full_speed_when_the_timer_runs_out() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 1000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "back to full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "clamped at zero, not negative")
	return true

# Overshooting the deadline in one big tick is the ordinary case at 1/60s
# steps, and must land in the same place as hitting it exactly.
func test_tick_clamps_an_overshoot_to_zero() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 5000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "back to full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "not driven negative")
	return true

func test_tick_is_a_no_op_on_an_unslowed_enemy() -> bool:
	var s := Slow.tick(Slow.none(), 500.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "still full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "not driven negative")
	return true

# A zero delta happens on the first frame of a paused or freshly resumed game.
# It must not expire a slow that has time left.
func test_tick_with_a_zero_delta_leaves_the_slow_running() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 0.0)
	assert_almost_eq(s[&"factor"], 0.5, 0.0001, "still slowed")
	assert_almost_eq(s[&"remaining_ms"], 1000.0, 0.0001, "and the clock has not moved")
	return true

# A factor of 1.0 is "no slow"; applying one must not start a timer that
# later "expires" and does nothing, nor register as a slow in the UI.
func test_apply_ignores_a_factor_of_one() -> bool:
	var s := Slow.apply(Slow.none(), 1.0, 2000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "still unslowed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "no timer started")
	return true

# The guard is `>= 1.0`, not `== 1.0`: a factor above one would otherwise
# speed an enemy up, which no tier grants and nothing else defends against.
func test_apply_ignores_a_factor_above_one() -> bool:
	var s := Slow.apply(Slow.none(), 1.5, 2000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "no speed-up")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "no timer started")
	return true

# Ignoring a non-slow must leave an ACTIVE slow alone. Returning a fresh
# none() here would let a tower with no slow effect cure one that has it.
func test_apply_keeps_an_active_slow_when_given_a_factor_of_one() -> bool:
	var slowed := Slow.apply(Slow.none(), 0.5, 1200.0)
	var after := Slow.apply(slowed, 1.0, 3000.0)
	assert_almost_eq(after[&"factor"], 0.5, 0.0001, "the running slow survived")
	assert_almost_eq(after[&"remaining_ms"], 1200.0, 0.0001, "with its own clock, not the ignored one's")
	return true

func test_apply_does_not_mutate_its_argument() -> bool:
	var original := Slow.none()
	Slow.apply(original, 0.5, 1000.0)
	assert_almost_eq(original[&"factor"], 1.0, 0.0001, "the caller's state is unchanged")
	return true

# The ignore path returns early, so it is the one place a caller could be
# handed the very dictionary it passed in. Writing to the result would then
# reach back into the enemy's own state.
func test_apply_returns_a_copy_when_it_ignores_the_factor() -> bool:
	var original := Slow.apply(Slow.none(), 0.5, 1000.0)
	var after := Slow.apply(original, 1.0, 3000.0)
	after[&"factor"] = 0.1
	assert_almost_eq(original[&"factor"], 0.5, 0.0001, "the caller's state is not aliased")
	return true

func test_tick_does_not_mutate_its_argument() -> bool:
	var original := Slow.apply(Slow.none(), 0.5, 1000.0)
	Slow.tick(original, 400.0)
	assert_almost_eq(original[&"remaining_ms"], 1000.0, 0.0001, "the caller's clock is unchanged")
	assert_almost_eq(original[&"factor"], 0.5, 0.0001, "and so is its factor")
	return true

# A deliberate divergence from the reference, which never clears slowFactor and
# so min()s a new slow against a stale one from a slow that ended long ago.
# Here expiry forgets the factor, so a weak slow after expiry is a weak slow.
func test_an_expired_slow_does_not_strengthen_a_later_weaker_one() -> bool:
	var strong := Slow.apply(Slow.none(), 0.45, 1000.0)
	var expired := Slow.tick(strong, 1000.0)
	var after := Slow.apply(expired, 0.7, 1500.0)
	assert_almost_eq(after[&"factor"], 0.7, 0.0001, "the lapsed slow does not carry over")
	assert_almost_eq(Slow.effective_speed(100.0, after), 70.0, 0.0001, "and the enemy moves at the weak rate")
	return true
