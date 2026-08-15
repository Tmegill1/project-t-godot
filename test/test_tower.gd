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
	assert_eq(captured["source"], {"damage": 5, "pierce": 0}, "source carries the def's damage and pierce")
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
