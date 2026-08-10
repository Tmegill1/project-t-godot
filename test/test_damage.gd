extends TestCase

func _target(health: float, extra := {}) -> Dictionary:
	var t := {"health": health, "max_health": health, "alive": true}
	t.merge(extra, true)
	return t

# Total time to kill a target, in seconds, for a tower firing at a cadence.
# Ported from damage.test.ts's timeToKill helper.
func _time_to_kill(per_hit: float, fire_rate_ms: float, health: float,
		armor: int = 0, shield: int = 0) -> float:
	var h := health
	var s := shield
	var shots := 0
	while h > 0.0 and shots < 10000:
		var target := {"health": h, "max_health": health, "alive": true,
			"armor": armor, "shield": s}
		var result := Damage.resolve({"damage": per_hit}, target)
		var dealt: float = result["damage_dealt"]
		var remaining_shield: int = result["remaining_shield"]

		# A stalled shot neither hurt the target nor spent a shield charge.
		# Checking shield progress before reassigning matters: spending the
		# final charge leaves shield at 0, which would otherwise read as a
		# stall and report Infinity for a perfectly winnable fight.
		if dealt == 0.0 and remaining_shield == s:
			return INF

		s = remaining_shield
		h = result["remaining_health"]
		shots += 1
	return (shots * fire_rate_ms) / 1000.0

func test_plain_hit_subtracts_health() -> bool:
	var r := Damage.resolve({"damage": 4}, _target(10.0))
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001, "four dealt")
	assert_almost_eq(r["remaining_health"], 6.0, 0.001, "six left")
	assert_false(r["lethal"], "not dead")
	return true

func test_overkill_is_not_counted() -> bool:
	var r := Damage.resolve({"damage": 50}, _target(5.0))
	assert_almost_eq(r["damage_dealt"], 5.0, 0.001, "a 50-damage hit on 5 health dealt 5")
	assert_almost_eq(r["remaining_health"], 0.0, 0.001, "health floors at zero")
	assert_true(r["lethal"], "the hit killed it")
	return true

# Load-bearing even without enemy properties: enemies linger while their death
# animation plays, and without this guard a second projectile already in
# flight would report a kill again and pay the reward twice.
func test_a_corpse_absorbs_nothing() -> bool:
	var dead := {"health": 0.0, "max_health": 5.0, "alive": false}
	var r := Damage.resolve({"damage": 10}, dead)
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no damage to a corpse")
	assert_false(r["lethal"], "cannot kill twice")
	return true

func test_zero_health_target_absorbs_nothing_even_if_flagged_alive() -> bool:
	var r := Damage.resolve({"damage": 10}, {"health": 0.0, "max_health": 5.0, "alive": true})
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "already at zero")
	assert_false(r["lethal"], "no second kill")
	return true

func test_negative_damage_does_not_heal() -> bool:
	var r := Damage.resolve({"damage": -10}, _target(5.0))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "inert, not healing")
	assert_almost_eq(r["remaining_health"], 5.0, 0.001, "health unchanged")
	return true

func test_armour_reduces_each_hit_flatly() -> bool:
	var r := Damage.resolve({"damage": 4}, _target(10.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 1.0, 0.001, "4 minus 3 armour")
	assert_almost_eq(r["armor_absorbed"], 3.0, 0.001, "three absorbed")
	return true

func test_armour_cannot_make_damage_negative() -> bool:
	var r := Damage.resolve({"damage": 2}, _target(10.0, {"armor": 9}))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "floors at zero")
	return true

func test_pierce_ignores_armour() -> bool:
	var r := Damage.resolve({"damage": 4, "pierce": 3}, _target(10.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001, "pierce cancels armour")
	return true

func test_a_shield_swallows_a_whole_hit() -> bool:
	var r := Damage.resolve({"damage": 15}, _target(10.0, {"shield": 2}))
	assert_true(r["shield_absorbed"], "absorbed by shield")
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no health lost")
	assert_eq(r["remaining_shield"], 1, "one charge spent")
	return true

# A zero-damage source must not strip a charge for free, or a tower that
# cannot hurt an armoured target could still peel its shield.
func test_zero_damage_does_not_strip_a_shield() -> bool:
	var r := Damage.resolve({"damage": 0}, _target(10.0, {"shield": 2}))
	assert_false(r["shield_absorbed"], "no charge spent")
	assert_eq(r["remaining_shield"], 2, "shield intact")
	return true

func test_armour_and_shields_are_answered_by_opposite_profiles() -> bool:
	# Rapid cheap fire: 8 hits of 2. Heavy slow fire: 1 hit of 16.
	var armoured := _target(20.0, {"armor": 3})
	var shielded := _target(20.0, {"shield": 3})
	assert_almost_eq(Damage.resolve({"damage": 2}, armoured)["damage_dealt"], 0.0, 0.001,
		"rapid fire is useless against armour")
	assert_almost_eq(Damage.resolve({"damage": 16}, armoured)["damage_dealt"], 13.0, 0.001,
		"a heavy hit punches armour")
	assert_true(Damage.resolve({"damage": 16}, shielded)["shield_absorbed"],
		"a heavy hit is wasted on a shield")
	return true

# --------------------------------------------------------------------------
# Everything below is ported from damage.test.ts beyond what the brief
# listed. The brief's test list was known to drop boundary/exactness cases
# in earlier tasks; these close that gap for this module.
# --------------------------------------------------------------------------

# Ported: "reports lethality when health reaches exactly zero". Pins the
# boundary at health == 0 exactly, distinct from the overkill case above.
func test_lethal_at_exactly_zero_health() -> bool:
	var r := Damage.resolve({"damage": 5}, _target(5.0))
	assert_almost_eq(r["remaining_health"], 0.0, 0.001, "exact kill leaves zero health")
	assert_true(r["lethal"], "exact kill is lethal")
	return true

# Ported: "is a pure function — it does not mutate the target".
func test_resolve_does_not_mutate_target() -> bool:
	var t := _target(10.0)
	Damage.resolve({"damage": 4}, t)
	assert_almost_eq(t["health"], 10.0, 0.001, "target health untouched by resolve")
	return true

# Ported: "applies each source's own damage" — the regression test for the
# defect this module exists to fix: damage used to be a hardcoded constant
# on the projectile, so every tower hit for exactly 3.
func test_applies_each_sources_own_damage() -> bool:
	var t := _target(100.0)
	assert_almost_eq(Damage.resolve({"damage": 3}, t)["remaining_health"], 97.0, 0.001,
		"damage 3 leaves 97")
	assert_almost_eq(Damage.resolve({"damage": 8}, t)["remaining_health"], 92.0, 0.001,
		"damage 8 leaves 92")
	assert_almost_eq(Damage.resolve({"damage": 20}, t)["remaining_health"], 80.0, 0.001,
		"damage 20 leaves 80")
	return true

# Ported: "does not re-report lethality on a corpse" — checks remaining
# health specifically, which the brief's corpse test does not.
func test_corpse_remaining_health_does_not_go_negative() -> bool:
	var dead := {"health": 0.0, "max_health": 5.0, "alive": false}
	var r := Damage.resolve({"damage": 5}, dead)
	assert_false(r["lethal"], "cannot re-kill a corpse")
	assert_almost_eq(r["remaining_health"], 0.0, 0.001, "stays at zero")
	return true

# Ported: "handles zero damage without reporting a kill" — the no-shield
# case; the brief only covers zero damage against a shield.
func test_zero_damage_without_shield_does_not_report_kill() -> bool:
	var r := Damage.resolve({"damage": 0}, _target(10.0))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "zero damage deals nothing")
	assert_false(r["lethal"], "not a kill")
	return true

# Ported: "blocks a hit entirely when armour exceeds the damage". No chip
# floor: checks remaining_health and lethal in addition to damage_dealt.
func test_armour_blocks_a_hit_entirely_when_it_exceeds_damage() -> bool:
	var r := Damage.resolve({"damage": 2}, _target(50.0, {"armor": 5}))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "armour fully blocks the hit")
	assert_almost_eq(r["remaining_health"], 50.0, 0.001, "no chip damage gets through")
	assert_false(r["lethal"], "not lethal")
	return true

# Ported: "never turns a blocked hit into healing" — armour far in excess of
# damage still floors at zero rather than going negative and healing.
func test_armour_never_turns_a_blocked_hit_into_healing() -> bool:
	var r := Damage.resolve({"damage": 1}, _target(20.0, {"armor": 99}))
	assert_almost_eq(r["remaining_health"], 20.0, 0.001, "health does not increase")
	return true

# Ported: pierce "cannot push damage above the source's own value". Without
# the maxf(0, armor - pierce) clamp, pierce in excess of armour would drive
# effective_armor negative and inflate damage_dealt past the source's own
# damage value.
func test_pierce_cannot_push_damage_above_the_sources_own_value() -> bool:
	var r := Damage.resolve({"damage": 10, "pierce": 99}, _target(50.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 10.0, 0.001,
		"pierce cannot inflate past the source's own damage")
	return true

# Ported: pierce "partially offsets heavier armour" — an exact arithmetic
# case (10 - (6 - 2) == 6), distinct from full-cancel and no-effect cases.
func test_pierce_partially_offsets_heavier_armour() -> bool:
	var r := Damage.resolve({"damage": 10, "pierce": 2}, _target(50.0, {"armor": 6}))
	assert_almost_eq(r["damage_dealt"], 6.0, 0.001, "10 minus (6 armour - 2 pierce)")
	return true

# Ported: shields absorb "a hit whole, regardless of its size" — a 999
# damage hit against a 10-health target is still fully absorbed.
func test_shield_absorbs_a_hit_whole_regardless_of_size() -> bool:
	var r := Damage.resolve({"damage": 999}, _target(10.0, {"shield": 2}))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no damage gets through")
	assert_almost_eq(r["remaining_health"], 10.0, 0.001, "health untouched")
	assert_eq(r["remaining_shield"], 1, "one charge spent regardless of hit size")
	assert_true(r["shield_absorbed"], "absorbed")
	return true

# Ported: shields cost "one charge per hit no matter the damage".
func test_shield_costs_one_charge_per_hit_no_matter_the_damage() -> bool:
	var r := Damage.resolve({"damage": 1}, _target(10.0, {"shield": 3}))
	assert_eq(r["remaining_shield"], 2, "exactly one charge spent")
	return true

# Ported: "lets damage through once the charges are gone" — the boundary at
# shield == 0, where a shielded target behaves identically to an unshielded
# one.
func test_shield_at_zero_lets_damage_through() -> bool:
	var r := Damage.resolve({"damage": 4}, _target(10.0, {"shield": 0}))
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001, "no charges left, full damage lands")
	assert_false(r["shield_absorbed"], "nothing to absorb with")
	return true

# Ported: shields "take priority over armour" — a shielded, armoured target
# spends the charge first; armour only applies to hits that get through.
func test_shield_takes_priority_over_armour() -> bool:
	var r := Damage.resolve({"damage": 20}, _target(50.0, {"shield": 1, "armor": 5}))
	assert_true(r["shield_absorbed"], "shield spends first")
	assert_almost_eq(r["armor_absorbed"], 0.0, 0.001,
		"armour never sees a hit the shield already ate")
	assert_eq(r["remaining_shield"], 0, "charge spent")
	return true

# Ported: shields "cannot be pierced" — pierce answers armour only. If it
# answered both, one upgrade path would counter everything.
func test_shield_cannot_be_pierced() -> bool:
	var r := Damage.resolve({"damage": 20, "pierce": 99}, _target(50.0, {"shield": 2}))
	assert_true(r["shield_absorbed"], "pierce does not touch shields")
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "fully absorbed")
	return true

# Ported: "armoured and shielded demand opposite answers" describe block.
# This is the load-bearing claim of the module: if one tower profile beat
# both defences, enemy properties would be decoration. Profiles match the
# shipped tower stats: fast is 2 damage every 500ms, heavy is 15 damage
# every 1500ms.

func test_fast_fire_beats_heavy_hits_against_shields() -> bool:
	var fast := _time_to_kill(2.0, 500.0, 30.0, 0, 6)
	var heavy := _time_to_kill(15.0, 1500.0, 30.0, 0, 6)
	assert_true(fast < heavy, "fast cheap fire beats heavy hits against shields")
	return true

func test_heavy_hits_beat_fast_fire_against_armour() -> bool:
	var fast := _time_to_kill(2.0, 500.0, 30.0, 4, 0)
	var heavy := _time_to_kill(15.0, 1500.0, 30.0, 4, 0)
	assert_true(heavy < fast, "heavy hits beat fast cheap fire against armour")
	return true

func test_rapid_fire_cannot_hurt_armour_at_all() -> bool:
	var fast := _time_to_kill(2.0, 500.0, 30.0, 4, 0)
	assert_true(fast == INF, "2 damage never exceeds 4 armour, so the fight never ends")
	return true

func test_neither_profile_is_a_universal_answer() -> bool:
	var shielded_fast := _time_to_kill(2.0, 500.0, 30.0, 0, 6)
	var shielded_heavy := _time_to_kill(15.0, 1500.0, 30.0, 0, 6)
	var armoured_fast := _time_to_kill(2.0, 500.0, 30.0, 4, 0)
	var armoured_heavy := _time_to_kill(15.0, 1500.0, 30.0, 4, 0)
	assert_true(shielded_fast < shielded_heavy and armoured_heavy < armoured_fast,
		"fast wins shields and heavy wins armour — never the same profile winning both")
	return true

# --------------------------------------------------------------------------
# Closing mutation survivors found by mutation-testing sim/damage.gd (see
# task-9-report.md). None of these come from damage.test.ts directly — the
# reference never has to defend against a malformed Dictionary, or separate
# the corpse guard's two OR'd conditions, the way this port does.
# --------------------------------------------------------------------------

# A Dictionary has no schema, unlike DamageTarget in TS where `alive` is a
# required field. Pins the defensive default: a target dict with no "alive"
# key at all is treated as alive rather than as a corpse.
func test_missing_alive_key_defaults_to_alive() -> bool:
	var r := Damage.resolve({"damage": 4}, {"health": 10.0, "max_health": 10.0})
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001,
		"a target dict with no explicit alive key is treated as alive")
	return true

# The corpse guard is `not alive OR health <= 0`. A target explicitly
# flagged not-alive but with positive health (e.g. a data bug) must still be
# treated as a corpse — this exercises the "not alive" arm on its own,
# independent of the health value.
func test_a_target_flagged_dead_absorbs_nothing_even_with_positive_health() -> bool:
	var r := Damage.resolve({"damage": 10}, {"health": 5.0, "max_health": 5.0, "alive": false})
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "not-alive absorbs nothing regardless of health")
	assert_false(r["lethal"], "cannot kill what the guard already treats as dead")
	return true

# Exercises the "health <= 0" arm of the corpse guard on its own (alive is
# still true), and specifically through its side effect on shields: if the
# guard didn't fire, a zero-health-but-flagged-alive target would fall
# through to the shield-consumption branch and spend a charge for nothing.
func test_zero_health_target_keeps_shield_untouched() -> bool:
	var r := Damage.resolve({"damage": 10},
		{"health": 0.0, "max_health": 5.0, "alive": true, "shield": 2})
	assert_eq(r["remaining_shield"], 2, "a corpse's shield is not spent")
	assert_false(r["shield_absorbed"], "a corpse absorbs nothing, including via shield")
	return true

# The corpse guard's return value hardcodes shield_absorbed=false and
# armor_absorbed=0 - fields the brief's own corpse tests never check.
func test_corpse_reports_no_absorption_of_any_kind() -> bool:
	var dead := {"health": 0.0, "max_health": 5.0, "alive": false, "shield": 3, "armor": 2}
	var r := Damage.resolve({"damage": 10}, dead)
	assert_false(r["shield_absorbed"], "a corpse does not absorb via shield")
	assert_almost_eq(r["armor_absorbed"], 0.0, 0.001, "a corpse does not absorb via armour")
	assert_eq(r["remaining_shield"], 3, "a corpse's shield count is reported unchanged")
	return true

# The shield-consumption branch hardcodes lethal=false - untested by the
# brief's shield test. A shield absorbing a hit can never itself be lethal,
# even against a target with only 1 health left.
func test_shield_absorption_never_reports_lethal() -> bool:
	var r := Damage.resolve({"damage": 999}, _target(1.0, {"shield": 1}))
	assert_false(r["lethal"], "a shield-absorbed hit cannot be lethal, even at 1 health")
	return true

# Pins the lethal threshold at exactly remaining_health <= 0, not some wider
# band: a target left with a fraction of a point of health is still alive.
func test_partial_remaining_health_is_not_lethal() -> bool:
	var r := Damage.resolve({"damage": 9.5}, _target(10.0))
	assert_almost_eq(r["remaining_health"], 0.5, 0.001, "half a point of health remains")
	assert_false(r["lethal"], "still alive with health remaining")
	return true

# Pins the lethal threshold at damage_dealt > 0, not some wider band: a
# killing blow that only had to deal a fraction of a point still counts.
func test_a_small_killing_blow_still_reports_lethal() -> bool:
	var r := Damage.resolve({"damage": 0.5}, _target(0.5))
	assert_almost_eq(r["remaining_health"], 0.0, 0.001, "exact small kill")
	assert_true(r["lethal"], "a sub-1 damage_dealt still kills a sub-1 health target")
	return true

# Reviewer-found gap: incoming damage must be clamped to zero BEFORE armour
# is applied, matching damage.ts's order (`incoming = Math.max(0, source.damage)`
# runs first, armour reduction runs after). Against an unarmoured target, a
# missing/loosened clamp on `incoming` is invisible: after_armor's own floor
# at line 43 produces damage_dealt == 0 and remaining_health == health either
# way. Only a target with nonzero armor exposes it, via armor_absorbed:
# without the early clamp, armor_absorbed becomes (negative incoming) - 0,
# i.e. negative, instead of the correct 0.
#
# Expected values derived from damage.ts's resolveDamage directly (source.ts
# lines 92, 108-110, 120), not from the GDScript under test:
#   incoming = Math.max(0, -10) = 0
#   armor = Math.max(0, 2) = 2; effectiveArmor = Math.max(0, 2 - 0) = 2
#   afterArmor = Math.max(0, 0 - 2) = 0
#   damageDealt = Math.min(0, 5) = 0; remainingHealth = 5 - 0 = 5
#   armorAbsorbed = incoming - afterArmor = 0 - 0 = 0
func test_negative_damage_is_clamped_before_armour_is_applied() -> bool:
	var r := Damage.resolve({"damage": -10}, _target(5.0, {"armor": 2}))
	assert_almost_eq(r["armor_absorbed"], 0.0, 0.001,
		"clamped-to-zero incoming leaves nothing for armour to absorb")
	assert_almost_eq(r["remaining_health"], 5.0, 0.001, "health unchanged")
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no damage dealt")
	return true

# Widened mutation set (round 2) found three more genuine gaps, all the same
# shape as the one above: a malformed/negative input field is clamped to
# zero by the reference (damage.ts: `Math.max(0, target.shield ?? 0)`, and
# analogously for health and pierce), but nothing exercised that clamp with
# a value that would actually go negative.

# `shield` is clamped at the top of resolve(). A negative shield (malformed
# data) must read back as zero, not leak through as a negative number in
# remaining_shield.
func test_negative_shield_value_is_clamped_to_zero() -> bool:
	var r := Damage.resolve({"damage": 5}, _target(10.0, {"shield": -3}))
	assert_eq(r["remaining_shield"], 0, "malformed negative shield reads as zero")
	assert_almost_eq(r["damage_dealt"], 5.0, 0.001, "no shield charge to absorb the hit")
	return true

# The corpse branch clamps remaining_health with maxf(0.0, health). A target
# whose health field is already negative (e.g. clock-skewed damage ticks)
# must still report zero, not a negative remaining_health.
func test_corpse_remaining_health_clamps_negative_input_to_zero() -> bool:
	var deeply_dead := {"health": -50.0, "max_health": 5.0, "alive": false}
	var r := Damage.resolve({"damage": 5}, deeply_dead)
	assert_almost_eq(r["remaining_health"], 0.0, 0.001,
		"negative health input still reports zero, not negative")
	return true

# `pierce` is clamped before it offsets armour. A negative pierce value must
# be inert, not subtract further from armour and increase it — pierce is
# supposed to reduce armour's effect, never amplify it.
func test_negative_pierce_does_not_increase_effective_armour() -> bool:
	var r := Damage.resolve({"damage": 10, "pierce": -5}, _target(50.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 7.0, 0.001,
		"negative pierce is inert: 10 minus the unmodified 3 armour")
	return true
