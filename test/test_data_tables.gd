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

## Fields the previous version left unasserted: cosmetic and progression data
## that has zero effect on damage math but everything to do with which
## sprite gets drawn (Task 17/18 read sprite_frame, upgrade_frames and
## texture_key directly). Expected values are taken from
## reference/project-t/td-browser/src/game/data/towers.ts, not read back out
## of data/towers.gd, so a wrong table value would fail this test rather
## than being silently re-pinned as "correct".
func test_tower_cosmetic_and_progression_fields_match_the_phaser_build() -> bool:
	var expected := {
		&"basic": {
			"label": "Basic", "color": Color8(0x00, 0x66, 0xff), "size": 0.8,
			"sprite_frame": 8, "upgrade_frames": [8, 9, 11, 17],
			"limit_bonus_map2": 2, "projectile_speed": 500.0,
		},
		&"fast": {
			"label": "Fast", "color": Color8(0x00, 0xff, 0x00), "size": 0.75,
			"sprite_frame": 1, "upgrade_frames": [1, 0, 7, 16],
			"limit_bonus_map2": 2, "projectile_speed": 500.0,
		},
		&"mortar": {
			"label": "Mortar", "color": Color8(0xb0, 0x7a, 0x3a), "size": 0.85,
			"sprite_frame": 5, "upgrade_frames": [5, 6, 12, 13],
			"limit_bonus_map2": 2, "projectile_speed": 350.0,
		},
		&"long": {
			"label": "Long Range", "color": Color8(0xff, 0x66, 0x00), "size": 0.85,
			"sprite_frame": 2, "upgrade_frames": [2, 10, 18, 19],
			"limit_bonus_map2": 2, "projectile_speed": 500.0,
		},
	}
	for kind in expected.keys():
		var def: Dictionary = Towers.DEFS[kind]
		for field in expected[kind].keys():
			assert_eq(def[field], expected[kind][field], "%s.%s" % [kind, field])
	return true

## label, texture_key, sprite_scale and flip_horizontally pick which sprite
## sheet an enemy uses and how it is drawn (Task 17 reads texture_key
## directly). Only ogre's sprite_scale/flip_horizontally were asserted
## before; this covers every field, for every kind, against
## reference/project-t/td-browser/src/game/data/enemies.ts.
func test_enemy_cosmetic_fields_match_the_phaser_build() -> bool:
	var expected := {
		&"slime": {"label": "Slime", "texture_key": "slime", "sprite_scale": 0.7, "flip_horizontally": false},
		&"ogre":  {"label": "Ogre",  "texture_key": "ogre",  "sprite_scale": 1.2, "flip_horizontally": true},
		&"bee":   {"label": "Bee",   "texture_key": "bee",   "sprite_scale": 0.7, "flip_horizontally": false},
	}
	for kind in expected.keys():
		var def: Dictionary = Enemies.DEFS[kind]
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

# pixel_size() went untested while nothing called it. TowerPanel now anchors
# its left edge to the value this returns, so a wrong answer here is a
# visible gap (or an overlap) between the map and the build panel rather
# than a dormant arithmetic bug. Both components are checked: multiplying by
# the wrong axis' count would still produce a plausible-looking number.
func test_map_pixel_size_multiplies_both_axes_by_tile_size() -> bool:
	var m := Maps.get_def(Maps.FIRST)
	var size := Maps.pixel_size(Maps.FIRST)
	assert_eq(size.x, int(m["cols"]) * int(m["tile_size"]), "width is cols * tile_size")
	assert_eq(size.y, int(m["rows"]) * int(m["tile_size"]), "height is rows * tile_size")
	assert_eq(size, Vector2i(1104, 672), "the first map is 1104x672 px at 23x14 tiles of 48")
	return true
