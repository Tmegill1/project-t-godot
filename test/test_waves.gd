extends TestCase

func _count_of(wave: int, kind: StringName) -> int:
	for entry in Waves.get_composition(wave):
		if entry["kind"] == kind:
			return entry["count"]
	return 0

func test_max_waves_is_twenty() -> bool:
	assert_eq(Waves.MAX_WAVES, 20, "victory at wave 20")
	return true

func test_wave_one_is_five_slimes() -> bool:
	assert_eq(_count_of(1, &"slime"), 5, "five slimes")
	assert_eq(_count_of(1, &"bee"), 0, "no bees yet")
	assert_eq(_count_of(1, &"ogre"), 0, "no ogres yet")
	return true

# Composition ACCUMULATES from wave 1, so wave 3 contains waves 1 and 2 too.
# This is surprising and is preserved deliberately.
func test_composition_accumulates_from_wave_one() -> bool:
	assert_eq(_count_of(2, &"slime"), 8, "5 + 3")
	assert_eq(_count_of(2, &"bee"), 3, "0 + 3")
	assert_eq(_count_of(3, &"slime"), 11, "5 + 3 + 3")
	assert_eq(_count_of(3, &"bee"), 6, "3 + 3")
	return true

func test_ogres_arrive_at_wave_four() -> bool:
	assert_eq(_count_of(3, &"ogre"), 0, "no ogres at wave 3")
	assert_eq(_count_of(4, &"ogre"), 2, "two ogres at wave 4")
	return true

func test_wave_five_totals() -> bool:
	assert_eq(_count_of(5, &"slime"), 14, "5+3+3+0+3")
	assert_eq(_count_of(5, &"bee"), 9, "3+3+0+3")
	assert_eq(_count_of(5, &"ogre"), 3, "2+1")
	return true

func test_beyond_wave_five_adds_a_fixed_bundle() -> bool:
	assert_eq(_count_of(6, &"slime"), 16, "14 + 2")
	assert_eq(_count_of(6, &"bee"), 14, "9 + 5")
	assert_eq(_count_of(6, &"ogre"), 5, "3 + 2")
	assert_eq(_count_of(7, &"slime"), 18, "two bundles past wave 5")
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

func test_ogre_delay_trails_the_last_slime_but_is_capped() -> bool:
	assert_almost_eq(Waves.ogre_spawn_delay(5), 5000.0, 0.001, "4*500 + 3000")
	assert_almost_eq(Waves.ogre_spawn_delay(30), 10000.0, 0.001, "capped at 10s")
	return true

func test_composition_returns_fresh_objects() -> bool:
	var a := Waves.get_composition(5)
	a[0]["count"] = 999
	var b := Waves.get_composition(5)
	assert_false(b[0]["count"] == 999, "callers cannot corrupt later waves")
	return true
