extends TestCase

# Bosses on waves 10 and 20. A boss is an ORDINARY ENEMY WITH DIFFERENT
# NUMBERS: it moves with sim/movement.gd, is targeted by sim/targeting.gd,
# takes damage through sim/damage.gd and leaks through sim/leak.gd exactly as
# everything else does. Anything needing a special case in those modules does
# not belong here.

func test_bosses_land_on_waves_ten_and_twenty() -> bool:
	assert_true(Bosses.has_boss(10), "wave 10 has a boss")
	assert_true(Bosses.has_boss(20), "wave 20 has a boss")
	assert_false(Bosses.has_boss(9), "wave 9 does not")
	assert_false(Bosses.has_boss(11), "nor does wave 11")
	assert_false(Bosses.has_boss(19), "nor the wave before the last")
	return true

func test_on_wave_returns_empty_rather_than_null_for_an_ordinary_wave() -> bool:
	assert_eq(Bosses.on_wave(7), {}, "an empty dictionary, never null")
	return true

func test_the_final_boss_is_far_worse_than_the_first() -> bool:
	var first := Bosses.on_wave(10)
	var last := Bosses.on_wave(20)
	assert_true(int(last["health"]) > int(first["health"]) * 2,
		"the wave 20 boss has more than twice the health")
	assert_true(int(last["armor"]) > int(first["armor"]), "and more armour")
	assert_true(float(last["display_scale"]) > float(first["display_scale"]),
		"and draws bigger, so it reads as worse before it arrives")
	assert_true(int(last["reward"]) > int(first["reward"]), "and pays more")
	return true

# Everything a boss needs must be a field the ordinary pipeline already reads.
func test_a_boss_is_an_ordinary_enemy_with_different_numbers() -> bool:
	for wave in Bosses.WAVES:
		var b := Bosses.on_wave(wave)
		assert_true(Enemies.DEFS.has(b["kind"]), "%s is a real kind" % b["kind"])
		for key in ["health", "speed", "armor", "shield", "reward", "display_scale", "label"]:
			assert_true(b.has(key), "wave %d boss declares %s" % [wave, key])
	return true

func test_on_wave_returns_a_copy_so_the_table_cannot_be_edited() -> bool:
	var a := Bosses.on_wave(10)
	a["health"] = 1
	assert_true(int(Bosses.on_wave(10)["health"]) > 1, "the table is unchanged")
	return true

func test_the_boss_kind_has_art_and_a_death_sound() -> bool:
	for wave in Bosses.WAVES:
		var kind: StringName = Bosses.on_wave(wave)["kind"]
		assert_true(FileAccess.file_exists("res://assets/art/enemies/%s/walk_0.png" % kind),
			"%s has art" % kind)
		assert_true(AudioManager.SOUNDS.has(StringName("death-%s" % kind)),
			"%s has a death sound" % kind)
	return true

# The troll is boss-only. Putting it in KINDS would field it as rank and file,
# because that is what wave composition iterates.
func test_the_troll_is_boss_only() -> bool:
	assert_true(Enemies.DEFS.has(&"troll"), "the troll has a definition")
	assert_false(Enemies.KINDS.has(&"troll"), "but is not in the ordinary roster")
	for wave in range(1, Waves.MAX_WAVES + 1):
		for entry in Waves.get_composition(wave):
			assert_true(entry["kind"] != &"troll",
				"wave %d does not field trolls as rank and file" % wave)
	return true

# --------------------------------------------------------------------------
# Scheduling
# --------------------------------------------------------------------------

func test_the_boss_is_appended_to_its_waves_schedule() -> bool:
	var bosses := 0
	for entry in Waves.build_schedule(10):
		if entry.get("boss", false):
			bosses += 1
	assert_eq(bosses, 1, "exactly one boss in wave 10's schedule")
	return true

func test_no_boss_in_an_ordinary_waves_schedule() -> bool:
	for entry in Waves.build_schedule(9):
		assert_false(entry.get("boss", false), "wave 9 schedules no boss")
	return true

# A boss arriving beside the first goblin is a boss nobody sees coming, and it
# would also be fought with a board that has not been paid for yet.
func test_the_boss_arrives_after_the_wave_it_headlines() -> bool:
	var boss_at := -1.0
	var last_ordinary := 0.0
	for entry in Waves.build_schedule(20):
		if entry.get("boss", false):
			boss_at = float(entry["at_ms"])
		else:
			last_ordinary = maxf(last_ordinary, float(entry["at_ms"]))
	assert_true(boss_at > last_ordinary, "the boss comes in last")
	return true

func test_the_boss_entry_names_the_boss_kind() -> bool:
	for entry in Waves.build_schedule(10):
		if entry.get("boss", false):
			assert_eq(entry["kind"], Bosses.on_wave(10)["kind"],
				"the schedule entry carries the boss's own kind")
	return true

# --------------------------------------------------------------------------
# Leak cost
# --------------------------------------------------------------------------

# Measured against what the ordinary rule can actually produce rather than
# against a constant. The flat cap this used to compare with is gone: a leak
# now costs the kind's own life_loss scaled by how alive it arrived, so the
# worst ordinary leak is the worst kind arriving whole.
func test_every_boss_declares_what_it_costs_on_leak() -> bool:
	var worst_ordinary := 0
	for kind in Enemies.KINDS:
		worst_ordinary = maxi(worst_ordinary, Leak.resolve({
			"life_loss": int(Enemies.DEFS[kind]["life_loss"]),
			"health": 100.0, "max_health": 100.0}))
	for wave in Bosses.WAVES:
		var b := Bosses.on_wave(wave)
		assert_true(b.has("life_loss"), "wave %d boss declares life_loss" % wave)
		assert_true(int(b["life_loss"]) > worst_ordinary,
			"wave %d boss costs more than any ordinary leak" % wave)
	return true

func test_the_final_boss_costs_more_on_leak_than_the_first() -> bool:
	assert_true(int(Bosses.on_wave(20)["life_loss"]) > int(Bosses.on_wave(10)["life_loss"]),
		"letting the Warlord through is worse than the Chieftain")
	return true

# A boss leak must be a blow, not an instant loss - the player should be able
# to lose one boss and keep playing.
func test_no_single_boss_leak_ends_the_run_outright() -> bool:
	for wave in Bosses.WAVES:
		assert_true(int(Bosses.on_wave(wave)["life_loss"]) < Economy.STARTING_LIVES,
			"wave %d boss is survivable once" % wave)
	return true
