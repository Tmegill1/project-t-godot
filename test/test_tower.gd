extends TestCase

# Tower's @onready fields (_sprite, _range_indicator) only resolve on
# NOTIFICATION_READY, which add_child() does NOT deliver in this harness
# (test/run_tests.gd runs entirely inside SceneTree._initialize(), before
# the tree's own root has entered the tree - confirmed empirically by
# Task 17, now the project-wide pattern). notification(NOTIFICATION_READY)
# is the only variant that resolves them. See test_enemy.gd for the same
# pattern with the same reasoning.
func _ready_tower() -> Tower:
	var t: Tower = load("res://game/tower.tscn").instantiate()
	t.notification(Node.NOTIFICATION_READY)
	return t

func _candidate(id: int, pos: Vector2, extra := {}) -> Dictionary:
	var c := {"id": id, "position": pos, "health": 5.0, "path_index": 0,
		"alive": true, "dying": false, "node": null}
	c.merge(extra, true)
	return c

# --------------------------------------------------------------------------
# setup() - atlas region per kind
# --------------------------------------------------------------------------

# One tower per kind, each asserting the exact atlas region computed from
# upgrade_frames[0]. Exercises the atlas arithmetic (%, /, * FRAME_SIZE) and
# pins that `frame / SHEET_COLUMNS` stays an integer division (frame is
# declared int; amendment 1 - do not "fix" this to floor()/int()). A
# preceding precondition assertion locks in the (col, row) this test
# expects, independent of the arithmetic under test, so a bad expectation
# in the test itself can't quietly agree with a broken implementation.
func test_setup_atlas_region_for_each_tower_kind() -> bool:
	Grid.set_active(23, 14)
	var expectations := [
		{"kind": &"basic", "col": 3, "row": 1},
		{"kind": &"fast", "col": 1, "row": 0},
		{"kind": &"mortar", "col": 0, "row": 1},
		{"kind": &"long", "col": 2, "row": 0},
	]
	for entry in expectations:
		var kind: StringName = entry["kind"]
		var frame: int = Towers.DEFS[kind]["upgrade_frames"][0]
		assert_eq(frame % Tower.SHEET_COLUMNS, entry["col"], "%s upgrade_frames[0]=%d column precondition" % [kind, frame])
		assert_eq(frame / Tower.SHEET_COLUMNS, entry["row"], "%s upgrade_frames[0]=%d row precondition" % [kind, frame])

		var t := _ready_tower()
		t.setup(kind, 0, 0, 0)
		var region: Rect2 = (t._sprite.texture as AtlasTexture).region
		var expected := Rect2(entry["col"] * Tower.FRAME_SIZE, entry["row"] * Tower.FRAME_SIZE,
			Tower.FRAME_SIZE, Tower.FRAME_SIZE)
		assert_eq(region, expected, "%s atlas region resolves from upgrade_frames[0]=%d" % [kind, frame])
		t.free()
	return true

# Checked as scale.x * the atlas region's own width, not a raw scale factor:
# a raw-scale assertion would pass even if FRAME_SIZE were wrong (scale is
# derived FROM FRAME_SIZE, so comparing scale alone can't catch a FRAME_SIZE
# mutation that cancels out). Multiplying back by the region width is what
# actually pins the on-screen size.
func test_setup_sprite_display_size_equals_tile_size_times_def_size() -> bool:
	Grid.set_active(23, 14)
	for kind in Towers.KINDS:
		var t := _ready_tower()
		t.setup(kind, 0, 0, 0)
		var region: Rect2 = (t._sprite.texture as AtlasTexture).region
		var displayed_width: float = t._sprite.scale.x * region.size.x
		var displayed_height: float = t._sprite.scale.y * region.size.y
		var expected: float = Tiles.TILE_SIZE * float(Towers.DEFS[kind]["size"])
		assert_almost_eq(displayed_width, expected, 0.001, "%s displayed width is TILE_SIZE * size" % kind)
		assert_almost_eq(displayed_height, expected, 0.001, "%s displayed height is TILE_SIZE * size" % kind)
		t.free()
	return true

# --------------------------------------------------------------------------
# setup() - position, stored properties, range indicator initial state
# --------------------------------------------------------------------------

func test_setup_positions_tower_at_tile_centre_and_stores_properties() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"long", 5, 7, 100)
	assert_eq(t.position, Grid.tile_to_world_center(5, 7), "tower sits at the tile centre, not the tile's corner")
	assert_eq(t.grid_col, 5, "grid_col stored")
	assert_eq(t.grid_row, 7, "grid_row stored")
	assert_eq(t.price_paid, 100, "price_paid stored")
	assert_eq(t.kind, &"long", "kind stored")
	t.free()
	return true

# Amendment 5: Grid holds active dimensions as static state. A distinct
# tile_size (64, not the default 48) proves setup() genuinely reads Grid's
# active state rather than a hardcoded TILE_SIZE baked into this test.
func test_setup_position_reflects_grids_active_tile_size_not_a_hardcoded_one() -> bool:
	Grid.set_active(10, 10, 64)
	var t := _ready_tower()
	t.setup(&"basic", 2, 1, 0)
	assert_eq(t.position, Vector2(2 * 64 + 32, 1 * 64 + 32), "position uses the active tile_size, not a hardcoded 48")
	t.free()
	Grid.set_active(23, 14)  # restore the default so later tests aren't order-dependent
	return true

func test_setup_initializes_range_indicator_from_the_def_and_hides_it() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"mortar", 0, 0, 0)
	assert_eq(t._range_indicator.radius, Towers.DEFS[&"mortar"]["range"], "range indicator radius comes from the def's range")
	assert_eq(t._range_indicator.tint, Towers.DEFS[&"mortar"]["color"], "range indicator tint comes from the def's color")
	assert_false(t._range_indicator.visible, "range indicator starts hidden")
	t.free()
	return true

# --------------------------------------------------------------------------
# to_targeting_dict()
# --------------------------------------------------------------------------

func test_to_targeting_dict_reports_def_range_default_priority_and_detection() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"mortar", 1, 1, 0)
	var d := t.to_targeting_dict()
	assert_eq(d.keys().size(), 4, "exactly the documented keys, no more, no fewer")
	assert_eq(d["position"], t.position, "position matches the tower's own position")
	assert_eq(d["range"], Towers.DEFS[&"mortar"]["range"], "range comes from the def, not a hardcoded value")
	assert_eq(d["priority"], Targeting.DEFAULT_PRIORITY, "priority defaults to closest")
	assert_eq(d["detection"], Towers.DEFS[&"mortar"]["detection"], "detection matches the def")
	t.free()
	return true

# --------------------------------------------------------------------------
# tick()
# --------------------------------------------------------------------------

# Mortar (not basic) deliberately: mortar's base_splash_radius (55.0) and
# fire_rate (2000.0) are both non-zero/non-default, so a mutation that drops
# or zeroes either field in the emitted signal is actually caught - basic's
# splash is 0.0, which would let a "always emit splash 0" mutant hide.
func test_tick_fires_once_when_a_candidate_is_in_range_and_resets_cooldown() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"mortar", 0, 0, 0)  # damage 5, pierce 0, splash 55.0, fire_rate 2000.0

	var target_node := Node2D.new()
	var captured := {"count": 0, "target": null, "source": {}, "splash": -1.0}
	t.wants_to_fire.connect(func(tn, src, sp):
		captured["count"] += 1
		captured["target"] = tn
		captured["source"] = src
		captured["splash"] = sp)

	var candidates := [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})]
	t.tick(16.0, candidates)

	assert_eq(captured["count"], 1, "wants_to_fire fires exactly once")
	assert_true(captured["target"] == target_node, "fires at the selected candidate's node")
	# Asserted key by key rather than as one dictionary equality: the source
	# gained gold and slow fields when upgrades landed, and a whole-dictionary
	# comparison would have to be rewritten again for every field added after.
	# The unupgraded values here are still exactly the table's.
	assert_eq(captured["source"]["damage"], 5, "source carries the def's damage")
	assert_eq(captured["source"]["pierce"], 0, "source carries the def's pierce")
	assert_almost_eq(captured["source"]["gold_multiplier"], 1.0, 0.0001, "an unupgraded tower pays plain gold")
	assert_eq(captured["source"]["bonus_gold_per_kill"], 0, "and no flat bonus")
	assert_almost_eq(captured["source"]["slow_factor"], 1.0, 0.0001, "and slows nothing")
	assert_almost_eq(captured["source"]["slow_duration_ms"], 0.0, 0.0001, "for no time at all")
	assert_eq(captured["splash"], 55.0, "splash carries the def's base_splash_radius")
	assert_eq(t._cooldown, 2000.0, "cooldown resets to fire_rate after firing")

	t.free()
	target_node.free()
	return true

func test_tick_does_not_fire_again_while_cooling_down() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"basic", 0, 0, 0)  # fire_rate 1000.0
	var target_node := Node2D.new()
	var count := {"n": 0}
	t.wants_to_fire.connect(func(_a, _b, _c): count["n"] += 1)

	var candidates := [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})]
	t.tick(16.0, candidates)
	assert_eq(count["n"], 1, "first tick fires")

	t.tick(16.0, candidates)
	assert_eq(count["n"], 1, "second tick, still well within the 1000ms cooldown, does not fire again")

	t.free()
	target_node.free()
	return true

# Isolates the `>` in `if _cooldown > 0.0: return` from `>=`: a cooldown
# that lands exactly on zero must still fire this tick.
func test_tick_fires_when_cooldown_decrements_to_exactly_zero() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"basic", 0, 0, 0)
	t._cooldown = 16.0  # decrementing by delta_ms=16.0 lands exactly at 0.0
	var target_node := Node2D.new()
	var count := {"n": 0}
	t.wants_to_fire.connect(func(_a, _b, _c): count["n"] += 1)

	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])

	assert_eq(count["n"], 1, "a cooldown that reaches exactly zero still fires (> 0.0, not >= 0.0)")

	t.free()
	target_node.free()
	return true

func test_tick_with_no_candidates_emits_nothing_and_does_not_reset_cooldown() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"basic", 0, 0, 0)
	var count := {"n": 0}
	t.wants_to_fire.connect(func(_a, _b, _c): count["n"] += 1)

	t.tick(16.0, [])

	assert_eq(count["n"], 0, "no candidates - no signal")
	assert_eq(t._cooldown, -16.0, "cooldown was decremented by delta_ms but not reset to fire_rate")

	t.free()
	return true

func test_tick_with_a_candidate_out_of_range_emits_nothing() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"basic", 0, 0, 0)  # range 100.0
	var target_node := Node2D.new()
	var count := {"n": 0}
	t.wants_to_fire.connect(func(_a, _b, _c): count["n"] += 1)

	var candidates := [_candidate(1, t.position + Vector2(500, 0), {"node": target_node})]
	t.tick(16.0, candidates)
	assert_eq(count["n"], 0, "a candidate beyond range is never selected, so nothing fires")

	t.free()
	target_node.free()
	return true

# --------------------------------------------------------------------------
# set_range_visible() / get_def()
# --------------------------------------------------------------------------

func test_set_range_visible_toggles_the_indicator() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"basic", 0, 0, 0)
	assert_false(t._range_indicator.visible, "starts hidden after setup")

	t.set_range_visible(true)
	assert_true(t._range_indicator.visible, "visible after set_range_visible(true)")

	t.set_range_visible(false)
	assert_false(t._range_indicator.visible, "hidden again after set_range_visible(false)")

	t.free()
	return true

func test_get_def_returns_the_towers_resolved_def() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(&"fast", 0, 0, 0)
	assert_eq(t.get_def(), Towers.DEFS[&"fast"], "get_def exposes the def setup() resolved for this kind")
	t.free()
	return true

# --------------------------------------------------------------------------
# ClickArea is inert for combat (the architectural rule this task exists to
# enforce): tick() must select and fire identically whether or not the
# click area is even capable of detecting anything.
# --------------------------------------------------------------------------

func test_click_area_matches_the_briefs_scene_tree_and_never_affects_targeting() -> bool:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	var click_area: Area2D = t.get_node("ClickArea")
	assert_true(click_area is Area2D, "ClickArea exists and is an Area2D")
	var shape_node: CollisionShape2D = click_area.get_node("CollisionShape2D")
	var shape: RectangleShape2D = shape_node.shape
	assert_eq(shape.size, Vector2(48, 48), "the click shape is 48x48 per the brief's scene tree")

	click_area.monitoring = false
	click_area.monitorable = false
	t.setup(&"basic", 0, 0, 0)
	var target_node := Node2D.new()
	var count := {"n": 0}
	t.wants_to_fire.connect(func(_a, _b, _c): count["n"] += 1)
	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])
	assert_eq(count["n"], 1, "targeting fires normally even with the click area fully disabled - tick() never reads it")

	t.free()
	target_node.free()
	return true

# --------------------------------------------------------------------------
# constants
# --------------------------------------------------------------------------

# A script-level const on a class_name script is directly readable as
# ClassName.CONST_NAME with no tree, node, or draw pass involved (same
# technique test_enemy.gd and test_map_renderer.gd use).
func test_sheet_columns_and_frame_size_constants_match_the_brief() -> bool:
	assert_eq(Tower.SHEET_COLUMNS, 5, "SHEET_COLUMNS")
	assert_eq(Tower.FRAME_SIZE, 96, "FRAME_SIZE")
	return true

# --------------------------------------------------------------------------
# frame_region — the single copy of the sheet's geometry.
#
# The atlas arithmetic used to be written out twice: here in Tower.setup and
# again in ui/tower_panel.gd's icon_for. An earlier pass unified the constants
# (SHEET_COLUMNS, FRAME_SIZE) but left both sites computing the Rect2, which
# is the same duplication one layer down. Tower.frame_region is now the only
# copy; both call sites' results stay pinned where they already were
# (test_setup_atlas_region_for_each_tower_kind above, and test_tower_panel.gd's
# test_icon_for_cuts_each_kinds_own_frame_from_the_tower_sheet).
# --------------------------------------------------------------------------

# Static, so it needs no tree, no node and no @onready resolution.
func test_frame_region_walks_the_sheet_row_major() -> bool:
	assert_eq(Tower.frame_region(0), Rect2(0, 0, 96, 96), "frame 0 is the top-left cell")
	assert_eq(Tower.frame_region(4), Rect2(4 * 96, 0, 96, 96), "frame 4 is the last cell of row 0")
	assert_eq(Tower.frame_region(5), Rect2(0, 96, 96, 96), "frame 5 wraps to the start of row 1")
	assert_eq(Tower.frame_region(12), Rect2(2 * 96, 2 * 96, 96, 96), "frame 12 is row 2, column 2")
	return true

# `frame / SHEET_COLUMNS` must stay integer division. Both operands are ints
# so GDScript floors it; if either ever became a float the row would come out
# fractional and every icon would sample a sliver of two rows. Frame 7 is the
# cheapest witness: 7 / 5 is 1 as ints and 1.4 as floats.
func test_frame_region_row_uses_integer_division() -> bool:
	assert_eq(Tower.frame_region(7), Rect2(2 * 96, 1 * 96, 96, 96),
		"frame 7 is row 1 column 2, not row 1.4")
	return true

# The invariant the extraction exists to protect: what the build panel shows
# you before you buy is cut from the same cell as the tower you get.
func test_the_build_panel_icon_and_the_placed_tower_share_one_region() -> bool:
	for kind in Towers.KINDS:
		var frame: int = Towers.DEFS[kind]["upgrade_frames"][0]
		assert_eq(TowerPanel.icon_for(kind).region, Tower.frame_region(frame),
			"%s: the panel icon and the placed tower cut the same cell" % kind)
	return true

# --------------------------------------------------------------------------
# upgrades
#
# The tower caches resolved stats rather than resolving per tick, so every
# path that changes tiers has to refresh the cache. These tests exist mostly
# to catch a refresh that was forgotten.
# --------------------------------------------------------------------------

# _ready_tower() deliberately stops short of setup() - its callers pick their
# own kind and tile. Everything below needs a tower that has been through
# setup(), and Grid must be active first because setup() positions through
# Grid.tile_to_world_center.
func _setup_tower(kind: StringName) -> Tower:
	Grid.set_active(23, 14)
	var t := _ready_tower()
	t.setup(kind, 0, 0, EconomySim.tower_price(kind, 0))
	return t

func test_setup_starts_a_tower_with_no_tiers() -> bool:
	var t := _setup_tower(&"basic")
	assert_eq(t.tiers[&"sustained"], 0, "sustained starts at zero")
	assert_eq(t.tiers[&"burst"], 0, "burst starts at zero")
	t.free()
	return true

func test_get_stats_returns_base_stats_before_any_upgrade() -> bool:
	var t := _setup_tower(&"mortar")
	var def: Dictionary = Towers.DEFS[&"mortar"]
	assert_almost_eq(t.get_stats()["damage"], float(def["damage"]), 0.0001, "unupgraded damage is the table's")
	assert_almost_eq(t.get_stats()["fire_rate"], float(def["fire_rate"]), 0.0001, "and its fire rate")
	assert_almost_eq(t.get_stats()["range"], float(def["range"]), 0.0001, "and its range")
	assert_almost_eq(t.get_stats()["splash_radius"], float(def["base_splash_radius"]), 0.0001, "and its splash")
	assert_eq(t.get_stats()["pierce"], int(def["pierce"]), "and its pierce")
	assert_false(bool(t.get_stats()["detection"]), "and it cannot see phased enemies")
	t.free()
	return true

func test_apply_upgrade_advances_the_branch_and_refreshes_the_stats() -> bool:
	var t := _setup_tower(&"basic")
	var before: float = t.get_stats()["fire_rate"]
	t.apply_upgrade(&"sustained")
	assert_eq(t.tiers[&"sustained"], 1, "branch advanced")
	assert_eq(t.tiers[&"burst"], 0, "the other branch is untouched")
	assert_true(t.get_stats()["fire_rate"] < before,
		"the cached stats were refreshed, not left stale")
	assert_almost_eq(t.get_stats()["fire_rate"], 800.0, 0.0001, "1000 * 0.8, resolved not guessed")
	t.free()
	return true

func test_apply_upgrade_accumulates_into_price_paid() -> bool:
	var t := _setup_tower(&"basic")
	var placed := t.price_paid
	t.apply_upgrade(&"sustained")
	assert_eq(t.price_paid, placed + 30,
		"price_paid means everything sunk in, so sell_refund keeps its meaning")
	t.free()
	return true

# Each tier costs its own price, not the first one's. Buying twice must charge
# 30 then 60 - a cost read from the wrong tier is invisible on a single buy.
func test_apply_upgrade_charges_the_cost_of_the_tier_being_bought() -> bool:
	var t := _setup_tower(&"basic")
	var placed := t.price_paid
	t.apply_upgrade(&"sustained")
	t.apply_upgrade(&"sustained")
	assert_eq(t.price_paid, placed + 30 + 60, "tier 1 then tier 2, not tier 1 twice")
	assert_eq(t.tiers[&"sustained"], 2, "and the branch advanced twice")
	t.free()
	return true

func test_to_targeting_dict_reports_upgraded_range_and_detection() -> bool:
	var t := _setup_tower(&"basic")
	t.apply_upgrade(&"burst")
	t.apply_upgrade(&"burst")
	t.apply_upgrade(&"burst")  # Spotter grants detection
	assert_true(t.to_targeting_dict()["detection"], "detection comes from resolved stats")
	assert_almost_eq(t.to_targeting_dict()["range"], 100.0, 0.0001, "range is untouched until tier 4")
	t.apply_upgrade(&"burst")  # Executioner extends range by a quarter
	assert_almost_eq(t.to_targeting_dict()["range"], 125.0, 0.0001, "100 * 1.25, resolved not the table's")
	t.free()
	return true

func test_upgrading_advances_the_sprite_frame() -> bool:
	var t := _setup_tower(&"basic")
	var frames: Array = Towers.DEFS[&"basic"]["upgrade_frames"]
	assert_eq((t._sprite.texture as AtlasTexture).region, Tower.frame_region(int(frames[0])),
		"an unupgraded tower shows the first frame")
	t.apply_upgrade(&"sustained")
	var atlas := t._sprite.texture as AtlasTexture
	assert_eq(atlas.region, Tower.frame_region(int(frames[1])), "one tier in shows the second frame")
	assert_true(atlas.atlas == Tower.TOWER_SHEET, "and still points at the tower sheet, not a blank texture")
	t.free()
	return true

# The range ring is derived state too, and it is the one piece of feedback a
# player gets that a range upgrade landed.
func test_upgrading_range_grows_the_range_indicator() -> bool:
	var t := _setup_tower(&"basic")
	assert_almost_eq(t._range_indicator.radius, 100.0, 0.0001, "starts at the table's range")
	for i in range(4):
		t.apply_upgrade(&"burst")
	assert_almost_eq(t._range_indicator.radius, 125.0, 0.0001, "the ring grew with the resolved range")
	t.free()
	return true

# The shot's payload is where slow and gold reach the rest of the game.
func test_tick_source_carries_the_resolved_slow_and_gold_effects() -> bool:
	var t := _setup_tower(&"fast")
	for i in range(4):
		t.apply_upgrade(&"sustained")  # Suppression: Deep Freeze slows to 45% for 2.5s
	var target_node := Node2D.new()
	var captured := {"source": {}}
	t.wants_to_fire.connect(func(_tn, src, _sp): captured["source"] = src)
	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])

	assert_almost_eq(captured["source"]["slow_factor"], 0.45, 0.0001, "the strongest slow travels with the shot")
	assert_almost_eq(captured["source"]["slow_duration_ms"], 2500.0, 0.0001, "with the duration that won")
	assert_almost_eq(captured["source"]["gold_multiplier"], 1.0, 0.0001, "and no gold effect from this branch")

	var g := _setup_tower(&"fast")
	for i in range(4):
		g.apply_upgrade(&"burst")  # Bounty Hunter: War Profiteer doubles gold, plus 2
	var g_captured := {"source": {}}
	g.wants_to_fire.connect(func(_tn, src, _sp): g_captured["source"] = src)
	g.tick(16.0, [_candidate(1, g.position + Vector2(10, 0), {"node": target_node})])

	assert_almost_eq(g_captured["source"]["gold_multiplier"], 2.0, 0.0001, "the strongest multiplier travels with the shot")
	assert_eq(g_captured["source"]["bonus_gold_per_kill"], 2, "and the flat bonus with it")
	assert_almost_eq(g_captured["source"]["slow_factor"], 1.0, 0.0001, "and this branch slows nothing")

	t.free()
	g.free()
	target_node.free()
	return true

# Splash is resolved too, not read from the table - a Fragmentation basic must
# actually splash.
func test_tick_splash_comes_from_the_resolved_stats() -> bool:
	var t := _setup_tower(&"basic")
	for i in range(3):
		t.apply_upgrade(&"sustained")  # Fragmentation: 45px splash
	var target_node := Node2D.new()
	var captured := {"splash": -1.0}
	t.wants_to_fire.connect(func(_tn, _src, sp): captured["splash"] = sp)
	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])
	assert_almost_eq(captured["splash"], 45.0, 0.0001, "the upgrade's splash radius, not the table's zero")
	t.free()
	target_node.free()
	return true

# The board instantiates a Tower under a node that never entered a live tree,
# so the tower's own @onready fields are unresolved and setup() aborts at the
# first line that touches one (see the header of test_game_board.gd). Every
# rules field setup() assigns BEFORE that line still lands, and Task 8's
# upgrade path depends on tiers and the resolved stats being among them.
# This test deliberately skips notification(NOTIFICATION_READY) to reproduce
# that state, so it PRINTS A SCRIPT ERROR when it passes.
func test_setup_lands_tiers_and_stats_even_when_the_sprite_half_aborts() -> bool:
	Grid.set_active(23, 14)
	var t: Tower = load("res://game/tower.tscn").instantiate()
	t.setup(&"basic", 0, 0, 20)

	assert_true(t._sprite == null, "precondition: this tower's @onready fields really are unresolved")
	assert_eq(t.tiers[&"sustained"], 0, "tiers landed before the aborting line")
	assert_eq(t.tiers[&"burst"], 0, "both branches of them")
	assert_almost_eq(t.get_stats()["range"], 100.0, 0.0001, "and so did the resolved stats")
	t.free()
	return true

# An illegal buy - here the cross-path rule locking a branch at tier 2 - must
# cost nothing. upgrade_cost still returns a real price for that tier (it only
# zeroes at MAX_TIER), so charging before checking would take 145 gold for a
# tier the tower never receives. Prints the "Illegal upgrade" error that
# with_upgrade pushes; that noise is the point of the call.
func test_apply_upgrade_charges_nothing_for_a_buy_the_cross_path_rule_forbids() -> bool:
	var t := _setup_tower(&"basic")
	for i in range(3):
		t.apply_upgrade(&"sustained")
	t.apply_upgrade(&"burst")
	t.apply_upgrade(&"burst")
	var committed := t.price_paid
	assert_eq(committed, 20 + 30 + 60 + 130 + 30 + 65, "precondition: placement plus five legal tiers")

	t.apply_upgrade(&"burst")  # tier 3 while sustained sits at 3 - forbidden

	assert_eq(t.price_paid, committed, "an illegal buy costs nothing")
	assert_eq(t.tiers[&"burst"], 2, "and the branch does not advance")
	t.free()
	return true

# The rest of the payload has to come from the resolved stats too, and an
# unupgraded tower cannot prove it - its resolved values equal the table's.
# Basic sustained tier 1 changes the fire rate, long burst tier 3 the pierce,
# and both change damage.
func test_tick_fires_at_the_upgraded_rate_and_damage() -> bool:
	var t := _setup_tower(&"basic")
	t.apply_upgrade(&"sustained")   # Quick Loader: fires 20% faster
	t.apply_upgrade(&"burst")       # Heavy Rounds: damage up 40%
	var target_node := Node2D.new()
	var captured := {"source": {}}
	t.wants_to_fire.connect(func(_tn, src, _sp): captured["source"] = src)
	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])

	assert_almost_eq(t._cooldown, 800.0, 0.0001, "the cooldown is the resolved fire rate, not the table's 1000")
	assert_almost_eq(captured["source"]["damage"], 6.0, 0.0001, "round(4 * 1.4), not the table's 4")
	t.free()
	target_node.free()
	return true

func test_tick_carries_the_upgraded_pierce() -> bool:
	var t := _setup_tower(&"long")
	for i in range(3):
		t.apply_upgrade(&"burst")   # Tungsten Core: +5 pierce
	var target_node := Node2D.new()
	var captured := {"source": {}}
	t.wants_to_fire.connect(func(_tn, src, _sp): captured["source"] = src)
	t.tick(16.0, [_candidate(1, t.position + Vector2(10, 0), {"node": target_node})])

	assert_eq(captured["source"]["pierce"], 5, "pierce comes from the resolved stats, not the table's zero")
	t.free()
	target_node.free()
	return true
