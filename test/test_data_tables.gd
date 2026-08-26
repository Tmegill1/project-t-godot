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
	assert_eq(ogre["sprite_px"], 58.0, "ogre draws taller than the others")
	assert_false(ogre["flip_horizontally"], "ogre artwork faces the same way as the others on this sheet")

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
		# label, sprite_frame and upgrade_frames DIVERGE from the reference for
		# these two kinds, deliberately - see the swap tests at the bottom of
		# this file. Every other field here is still Phaser parity.
		&"fast": {
			"label": "Magic", "color": Color8(0x00, 0xff, 0x00), "size": 0.75,
			"sprite_frame": 5, "upgrade_frames": [5, 6, 12, 13],
			"limit_bonus_map2": 2, "projectile_speed": 500.0,
		},
		&"mortar": {
			"label": "Mortar", "color": Color8(0xb0, 0x7a, 0x3a), "size": 0.85,
			"sprite_frame": 1, "upgrade_frames": [1, 0, 7, 16],
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

## NOT a Phaser-parity test, unlike its neighbours - which is why it no longer
## carries that name. label still matches the reference, but variant_count and
## sprite_px have no Phaser counterpart at all: they were introduced by this
## port when the enemy art became per-spawn illustrated variants.
##
## label, walk_frames, death_frames, sprite_px and flip_horizontally pick which
## sprite directory an enemy draws from and how it is sized/mirrored.
## walk_frames and death_frames replaced variant_count when the art went from
## per-spawn variants back to drawn animation - the bat's seven is its eighth
## walk frame coming off the sheet as an orphaned wing (see data/enemies.gd's
## own doc comment); every
## kind's flip_horizontally is false because all three kinds' art on this
## sheet faces right, including the ogre, which faced left on the old sheet.
## stride_px joined the same table for a different reason - not sizing or
## mirroring, but how far each kind travels per run cycle - and is pinned
## here for the same reason as its neighbours: nothing else in the suite
## would notice a value silently drifting back to 0.0 or to another kind's
## number.
func test_enemy_cosmetic_fields_are_the_ones_this_port_draws_from() -> bool:
	var expected := {
		&"slime": {"label": "Slime", "walk_frames": 8, "death_frames": 4, "sprite_px": 34.0, "stride_px": 30.0, "flip_horizontally": false},
		&"ogre":  {"label": "Ogre",  "walk_frames": 8, "death_frames": 4, "sprite_px": 58.0, "stride_px": 46.0, "flip_horizontally": false},
		&"bee":   {"label": "Bee",   "walk_frames": 7, "death_frames": 4, "sprite_px": 28.0, "stride_px": 32.0, "flip_horizontally": false},
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

func test_every_map_names_a_biome_that_exists() -> bool:
	for name in Maps.DEFS:
		var def: Dictionary = Maps.DEFS[name]
		assert_true(def.has("biome"), "%s names a biome" % name)
		assert_true(Biomes.KINDS.has(def["biome"]),
			"%s's biome %s is registered" % [name, def["biome"]])
	return true

func test_the_first_map_is_the_forest() -> bool:
	assert_eq(Maps.get_def(Maps.FIRST)["biome"], &"forest",
		"The Pass is a forest map")
	return true

# --------------------------------------------------------------------------
# The map registry (spec 2026-08-24-slice-0-design.md section 6)
# --------------------------------------------------------------------------

func test_every_map_is_registered_with_its_dimensions() -> bool:
	assert_eq(int(Maps.DEFS[&"map2"]["cols"]), 26, "The Fork's columns")
	assert_eq(int(Maps.DEFS[&"map2"]["rows"]), 17, "The Fork's rows")
	assert_eq(int(Maps.DEFS[&"map3"]["cols"]), 28, "The Coils' columns")
	assert_eq(int(Maps.DEFS[&"map3"]["rows"]), 16, "The Coils' rows")
	return true

# The registry and the builder are two statements of one fact, and this is
# what stops them drifting.
func test_the_registry_dimensions_match_what_the_builders_produce() -> bool:
	for name in [&"demoMap", &"map2", &"map3"]:
		var tiles := Maps.build_tiles(name)
		var d: Dictionary = Maps.DEFS[name]
		assert_eq(tiles.size(), int(d["rows"]), "%s rows agree" % name)
		assert_eq(tiles[0].size(), int(d["cols"]), "%s cols agree" % name)
	return true

func test_each_map_draws_in_its_own_biome() -> bool:
	assert_eq(Maps.DEFS[&"demoMap"]["biome"], &"forest", "The Pass is forest")
	assert_eq(Maps.DEFS[&"map2"]["biome"], &"ice", "The Fork is ice")
	assert_eq(Maps.DEFS[&"map3"]["biome"], &"desert", "The Coils is desert")
	return true

func test_every_biome_a_map_names_actually_exists() -> bool:
	for name in Maps.DEFS:
		var biome: StringName = Maps.DEFS[name]["biome"]
		assert_true(Biomes.DEFS.has(biome), "%s names a real biome" % name)
	return true

func test_the_maps_chain_and_the_last_one_terminates() -> bool:
	assert_eq(Maps.DEFS[&"demoMap"]["next"], &"map2", "The Pass leads to The Fork")
	assert_eq(Maps.DEFS[&"map2"]["next"], &"map3", "The Fork leads to The Coils")
	assert_eq(Maps.DEFS[&"map3"]["next"], &"", "and The Coils is the last")
	return true

func test_budgets_and_starting_gold_are_ported() -> bool:
	assert_eq(int(Maps.DEFS[&"map2"]["tower_budget"]), 20, "The Fork's budget")
	assert_eq(int(Maps.DEFS[&"map2"]["starting_gold"]), 250,
		"and its opening gold, doubled waves needing a doubled opening")
	assert_eq(int(Maps.DEFS[&"map3"]["tower_budget"]), 18,
		"The Coils is wider but its folds double up, so it needs fewer towers")
	assert_eq(int(Maps.DEFS[&"map3"]["starting_gold"]), 200, "and its opening gold")
	return true

# Every map must be reachable by build_tiles, or the registry advertises a
# board the game cannot load.
func test_every_registered_map_can_actually_be_built() -> bool:
	for name in Maps.DEFS:
		var tiles := Maps.build_tiles(name)
		assert_true(tiles.size() > 0, "%s builds to a real grid" % name)
	return true

# --------------------------------------------------------------------------
# Tower art swap and the Magic rename
# (spec 2026-08-25-roster-resistance-and-bosses-design.md section 8)
# --------------------------------------------------------------------------
#
# A DELIBERATE DIVERGENCE from the Phaser reference, and the fourth this port
# carries. Measured on assets/towers.png by cropping the frames: the ones Fast
# pointed at draw a CANNON and the ones Mortar pointed at draw CRYSTALS. They
# were simply on the wrong towers, upstream included. A parity test would
# faithfully preserve the mistake, so these assertions replace parity for
# these two fields.

func test_the_magic_tower_wears_the_crystal_frames() -> bool:
	assert_eq(Towers.DEFS[&"fast"]["upgrade_frames"], [5, 6, 12, 13],
		"Magic wears what Mortar used to")
	assert_eq(int(Towers.DEFS[&"fast"]["sprite_frame"]), 5, "and its base frame")
	return true

func test_the_mortar_tower_wears_the_cannon_frames() -> bool:
	assert_eq(Towers.DEFS[&"mortar"]["upgrade_frames"], [1, 0, 7, 16],
		"Mortar wears what Fast used to")
	assert_eq(int(Towers.DEFS[&"mortar"]["sprite_frame"]), 1, "and its base frame")
	return true

func test_the_fast_tower_is_labelled_magic() -> bool:
	assert_eq(Towers.DEFS[&"fast"]["label"], "Magic",
		"renamed for the crystals it now wears")
	return true

# The key is the join to the upgrade table, the fire-fast audio event and the
# sprite lookup. Renaming the label is one word; renaming the key is five files.
func test_the_fast_key_survives_the_rename() -> bool:
	assert_true(Towers.DEFS.has(&"fast"), "the key is unchanged")
	assert_true(Upgrades.DEFS.has(&"fast"), "so the upgrade table still joins")
	assert_true(Towers.KINDS.has(&"fast"), "and so does KINDS")
	return true

# Art and a name only. Nothing about how either tower PLAYS moves.
func test_swapping_the_art_moved_no_stats() -> bool:
	assert_eq(int(Towers.DEFS[&"fast"]["cost"]), 50, "Magic still costs 50")
	assert_eq(float(Towers.DEFS[&"fast"]["fire_rate"]), 500.0, "and still fires every 500ms")
	assert_eq(float(Towers.DEFS[&"fast"]["range"]), 80.0, "and still reaches 80")
	assert_eq(float(Towers.DEFS[&"fast"]["base_splash_radius"]), 0.0, "and still does not splash")
	assert_eq(float(Towers.DEFS[&"mortar"]["base_splash_radius"]), 55.0, "Mortar still splashes")
	assert_eq(float(Towers.DEFS[&"mortar"]["fire_rate"]), 2000.0, "and still fires every 2000ms")
	assert_eq(int(Towers.DEFS[&"mortar"]["cost"]), 70, "and still costs 70")
	return true

# --------------------------------------------------------------------------
# Build stamp
# --------------------------------------------------------------------------

# The committed template must always read as a local build. If CI's generated
# version were ever committed by accident, this fails and says so.
func test_the_committed_build_stamp_is_the_dev_template() -> bool:
	assert_eq(BuildStamp.SHA, "dev",
		"the committed template is unstamped; CI overwrites it at export")
	return true

func test_an_unstamped_build_says_so() -> bool:
	assert_eq(BuildStamp.label(), "dev build", "a local run identifies itself")
	return true

# The workflow generates this file wholesale, so the names and types it writes
# have to keep matching what the game reads.
func test_the_stamp_exposes_the_fields_the_workflow_writes() -> bool:
	assert_true(BuildStamp.SHA is String, "SHA is a String")
	assert_true(BuildStamp.BUILT_AT is String, "BUILT_AT is a String")
	assert_true(BuildStamp.label() is String, "label() returns a String")
	return true
