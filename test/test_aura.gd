extends TestCase

# The shaman's shield aura. It makes the shaman a priority target: kill the
# escort and the wave dies normally, ignore it and everything takes an extra
# hit.
#
# Pure module, so the live board and the headless harness run the identical
# rule. A rule only the board ran would make every balance number the harness
# produces a fiction - the lesson from resistance landing on one side only.

func _shaman(id: int, at: Vector2) -> Dictionary:
	return {"id": id, "position": at, "alive": true, "dying": false, "kind": &"shaman"}

func _mob(id: int, at: Vector2, shield: int = 0) -> Dictionary:
	return {"id": id, "position": at, "alive": true, "dying": false,
		"kind": &"goblin", "shield": shield}

func test_an_enemy_in_range_is_granted_a_charge() -> bool:
	var granted := Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, Vector2(10, 0))], 0.0)
	assert_true(granted.has(2), "the neighbour was shielded")
	return true

func test_an_enemy_out_of_range_is_not() -> bool:
	var far := Vector2(Aura.RADIUS + 1.0, 0.0)
	var granted := Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, far)], 0.0)
	assert_false(granted.has(2), "out of range, no charge")
	return true

func test_the_radius_boundary_is_inclusive() -> bool:
	var edge := Vector2(Aura.RADIUS, 0.0)
	assert_true(Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, edge)], 0.0).has(2),
		"exactly at the radius is covered, matching Damage.in_splash's boundary")
	return true

# The shaman carries its own shield from the table. Letting the aura top it up
# would make a lone shaman unkillable by the one build meant to answer it.
func test_a_shaman_does_not_shield_itself() -> bool:
	var s := _shaman(1, Vector2.ZERO)
	assert_false(Aura.grant([s], [s], 0.0).has(1),
		"the aura is for the escort, not the caster")
	return true

func test_a_shaman_does_not_shield_another_shaman() -> bool:
	var a := _shaman(1, Vector2.ZERO)
	var b := _shaman(2, Vector2(10, 0))
	assert_eq(Aura.grant([a, b], [a, b], 0.0), [],
		"two shamans cannot prop each other up")
	return true

# The cap is stated as a LITERAL here on purpose. Writing the precondition as
# Aura.MAX_GRANTED_CHARGES makes the test move with the constant, so raising
# the cap to 99 changes nothing and the test passes vacuously - found by
# mutation testing.
func test_the_cap_is_two_charges() -> bool:
	assert_eq(Aura.MAX_GRANTED_CHARGES, 2,
		"stated as a literal, or a raised cap moves every test with it")
	return true

func test_an_enemy_at_the_cap_is_not_topped_up() -> bool:
	assert_false(Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, Vector2(10, 0), 2)], 0.0).has(2),
		"two charges is the cap, so no top-up")
	assert_true(Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(3, Vector2(10, 0), 1)], 0.0).has(3),
		"but one charge is still below it")
	return true

func test_a_dead_enemy_is_not_shielded() -> bool:
	var corpse := _mob(2, Vector2(10, 0))
	corpse["alive"] = false
	assert_false(Aura.grant([_shaman(1, Vector2.ZERO)], [corpse], 0.0).has(2),
		"corpses take no buffs")
	return true

func test_a_dying_enemy_is_not_shielded() -> bool:
	var dying := _mob(2, Vector2(10, 0))
	dying["dying"] = true
	assert_false(Aura.grant([_shaman(1, Vector2.ZERO)], [dying], 0.0).has(2),
		"nor do enemies mid-death-animation")
	return true

# Not every tick: an aura that refilled a charge the instant a tower stripped
# it would not be a buff, it would be invulnerability.
func test_the_aura_only_fires_on_its_cooldown() -> bool:
	var s := [_shaman(1, Vector2.ZERO)]
	var m := [_mob(2, Vector2(10, 0))]
	assert_true(Aura.grant(s, m, 0.0).has(2), "fires at zero")
	assert_false(Aura.grant(s, m, Aura.COOLDOWN_MS * 0.5).has(2), "not mid-cooldown")
	assert_true(Aura.grant(s, m, Aura.COOLDOWN_MS).has(2), "fires again on the beat")
	return true

func test_no_shamans_means_no_grants() -> bool:
	assert_eq(Aura.grant([], [_mob(2, Vector2.ZERO)], 0.0), [],
		"nothing to cast it")
	return true

func test_the_result_never_repeats_an_id() -> bool:
	var granted := Aura.grant(
		[_shaman(1, Vector2.ZERO), _shaman(3, Vector2(20, 0))],
		[_mob(2, Vector2(10, 0))], 0.0)
	assert_eq(granted.size(), 1, "one enemy, one grant, however many casters")
	return true

# Pure: it reports, it does not apply. A rule that mutated the caller's state
# could not also be run by the harness against its own dictionaries.
func test_grant_does_not_mutate_its_arguments() -> bool:
	var mobs := [_mob(2, Vector2(10, 0))]
	var snapshot := mobs.duplicate(true)
	Aura.grant([_shaman(1, Vector2.ZERO)], mobs, 0.0)
	assert_eq(mobs, snapshot, "the enemy list is untouched")
	return true

# Stateless, so two runs with the same clock agree - which is what the
# harness's reproducibility claim rests on.
func test_the_same_clock_always_gives_the_same_answer() -> bool:
	var s := [_shaman(1, Vector2.ZERO)]
	var m := [_mob(2, Vector2(10, 0))]
	for i in 5:
		assert_eq(Aura.grant(s, m, Aura.COOLDOWN_MS), [2], "run %d agrees" % i)
	return true

func test_a_negative_clock_grants_nothing() -> bool:
	assert_eq(Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, Vector2(10, 0))], -100.0), [],
		"a nonsense clock is inert rather than firing")
	return true
