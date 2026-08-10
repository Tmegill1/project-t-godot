extends TestCase

func test_enemy_stats_match_the_phaser_build() -> bool:
	var slime: Dictionary = Enemies.DEFS[&"slime"]
	assert_eq(slime["base_speed"], 100.0, "slime speed")
	assert_eq(slime["base_health"], 5, "slime health")
	assert_eq(slime["reward"], 5, "slime reward")
	assert_eq(slime["life_loss"], 1, "slime leak cost")

	var ogre: Dictionary = Enemies.DEFS[&"ogre"]
	assert_eq(ogre["base_speed"], 60.0, "ogre speed")
	assert_eq(ogre["base_health"], 8, "ogre health")
	assert_eq(ogre["reward"], 20, "ogre reward")
	assert_eq(ogre["life_loss"], 5, "ogre leak cost")
	assert_eq(ogre["sprite_scale"], 1.2, "ogre is larger than the others")
	assert_true(ogre["flip_horizontally"], "ogre artwork faces the wrong way")

	var bee: Dictionary = Enemies.DEFS[&"bee"]
	assert_eq(bee["base_speed"], 150.0, "bee speed")
	assert_eq(bee["base_health"], 3, "bee health")
	assert_eq(bee["reward"], 10, "bee reward")
	assert_eq(bee["life_loss"], 2, "bee leak cost")
	return true

func test_scaled_health_floors_and_clamps_to_one() -> bool:
	assert_eq(Enemies.scaled_health(&"slime", 1.0), 5, "unmodified")
	assert_eq(Enemies.scaled_health(&"slime", 1.5), 7, "7.5 floors to 7")
	assert_eq(Enemies.scaled_health(&"slime", 0.0), 1, "never below one")
	return true

func test_scaled_speed_is_unrounded_and_clamps_to_one() -> bool:
	assert_almost_eq(Enemies.scaled_speed(&"ogre", 1.05), 63.0, 0.001, "unrounded")
	assert_almost_eq(Enemies.scaled_speed(&"ogre", 0.0), 1.0, 0.001, "never below one")
	return true

func test_tower_stats_match_the_phaser_build() -> bool:
	var expected := {
		&"basic":  {"cost": 20,  "cost_escalation": 10, "range": 100.0, "fire_rate": 1000.0, "damage": 4,  "base_splash_radius": 0.0,  "base_limit": 8},
		&"fast":   {"cost": 50,  "cost_escalation": 15, "range": 80.0,  "fire_rate": 500.0,  "damage": 2,  "base_splash_radius": 0.0,  "base_limit": 8},
		&"mortar": {"cost": 70,  "cost_escalation": 35, "range": 120.0, "fire_rate": 2000.0, "damage": 5,  "base_splash_radius": 55.0, "base_limit": 5},
		&"long":   {"cost": 100, "cost_escalation": 50, "range": 150.0, "fire_rate": 1500.0, "damage": 15, "base_splash_radius": 0.0,  "base_limit": 5},
	}
	for kind in expected.keys():
		var def: Dictionary = Towers.DEFS[kind]
		for field in expected[kind].keys():
			assert_eq(def[field], expected[kind][field], "%s.%s" % [kind, field])
	return true

func test_only_the_mortar_has_splash_and_arcing_shots() -> bool:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		var is_mortar := kind == &"mortar"
		assert_eq(def["base_splash_radius"] > 0.0, is_mortar, "%s splash" % kind)
		assert_eq(def["projectile_arcs"], is_mortar, "%s arcing" % kind)
	return true

func test_no_base_tower_has_pierce_or_detection() -> bool:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		assert_eq(def["pierce"], 0, "%s pierce is earned, not given" % kind)
		assert_false(def["detection"], "%s detection is earned, not given" % kind)
	return true

func test_economy_constants() -> bool:
	assert_eq(Economy.STARTING_LIVES, 20, "twenty lives")
	assert_eq(Economy.SELL_REFUND_FRACTION, 0.5, "half back on sale")
	return true

func test_first_map_definition() -> bool:
	var m := Maps.get_def(Maps.FIRST)
	assert_eq(m["label"], "The Pass", "map label")
	assert_eq(m["cols"], 23, "columns")
	assert_eq(m["rows"], 14, "rows")
	assert_eq(m["tower_budget"], 16, "tower budget")
	assert_eq(m["starting_gold"], 100, "starting gold")
	return true
