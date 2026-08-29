extends TestCase

# TowerPanel declares no @onready fields of its own - bind() looks up its
# Buttons container inline via `$Buttons`, which resolves through the
# ordinary node tree built by instantiate() and needs no NOTIFICATION_READY
# (unlike an @onready field, which only resolves on that notification - see
# game/tower.gd / test_tower.gd for the contrasting case). notification()
# is still fired below for consistency with the project-wide pattern; it is
# harmless here since TowerPanel defines no _ready() override.

func _ready_panel() -> TowerPanel:
	var p: TowerPanel = load("res://ui/tower_panel.tscn").instantiate()
	p.notification(Node.NOTIFICATION_READY)
	return p

func _ready_board() -> GameBoard:
	var b: GameBoard = load("res://game/game_board.tscn").instantiate()
	b.notification(Node.NOTIFICATION_READY)
	return b

## The first world position the board will actually accept, found the same
## way test_game_board.gd's _find_placeable_positions does: by asking the
## real rule rather than reimplementing it.
func _find_placeable_position(b: GameBoard) -> Vector2:
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(b._map_name)))
	var radius := Placement.tower_radius(&"basic")
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			var pos := Grid.tile_to_world_center(c, r)
			var verdict := Placement.can_place(
				pos, radius, b._map_renderer.prop_footprints(), b._tower_positions(), b._paths, bounds)
			if verdict["ok"]:
				return pos
	return Vector2.ZERO

# --------------------------------------------------------------------------
# bind()
# --------------------------------------------------------------------------

func test_bind_creates_one_button_per_kind_with_base_price_and_label() -> bool:
	var p := _ready_panel()
	var b := _ready_board()

	p.bind(b)

	assert_eq(p._buttons.size(), Towers.KINDS.size(), "one button per Towers.KINDS entry")
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		var price := EconomySim.tower_price(kind, 0)
		var limit := EconomySim.tower_limit(kind, b.get_map_name())
		var button: Button = p._buttons[kind]
		assert_eq(button.text, "%s\n0/%d · %d gold" % [def["label"], limit, price],
			"%s button shows its base price and an empty count" % kind)
	p.free(); b.free()
	return true

# --------------------------------------------------------------------------
# panel geometry
# --------------------------------------------------------------------------

# The map is 1104px wide and the panel was a fixed 140px pinned to the right
# edge of a 1244px design viewport, so the two tiled exactly and nothing
# showed between them. That only holds at the design aspect ratio.
# window/stretch/aspect="expand" gives every surplus pixel of a wider window
# to viewport width; the map keeps its fixed pixel size and the panel kept
# its fixed width, so the surplus opened as bare engine background between
# them - 114 viewport px of it at 1920x950.
#
# Anchoring the panel's left edge to the map's right edge and its right edge
# to the viewport closes that at every width: the panel absorbs whatever
# expand hands out instead of ignoring it. The panel can never be squeezed
# below its original 140px either, because viewport width never drops under
# the 1244 design width - a window narrower in aspect than the design box
# grows viewport height instead, leaving width at exactly 1244.
#
# Asserted as anchors and offsets, not a computed rect: containers only lay
# out inside a live tree, which this harness never provides (see the header
# note), so size stays at its unlaid-out default here.
func test_panel_spans_from_the_maps_right_edge_to_the_viewport_edge() -> bool:
	var p := _ready_panel()
	var b := _ready_board()

	p.bind(b)

	assert_eq(p.anchor_left, 0.0, "left edge is measured from the viewport's left, not its right")
	assert_eq(p.offset_left, float(Maps.pixel_size(b.get_map_name()).x),
		"panel starts exactly where the map ends, leaving nothing between them")
	assert_eq(p.anchor_right, 1.0, "right edge tracks the viewport's right edge")
	assert_eq(p.offset_right, 0.0, "and sits flush against it, so no gap can open at any width")
	assert_eq(p.anchor_bottom, 1.0, "runs down to the viewport's bottom edge")
	assert_eq(p.offset_bottom, 0.0, "flush with it")
	p.free(); b.free()
	return true

# Checked on the composed game.tscn, not on a standalone tower_panel.tscn:
# the panel's vertical placement was an *instance override* in game.tscn
# (offset_top = 52), so a test that instantiates the panel scene by itself
# reads the panel's own 0 and passes no matter what game.tscn says - it
# cannot see the override that actually renders. Asserting here on the
# composed tree is the only way this catches a reintroduced offset.
#
# instantiate() alone, with no NOTIFICATION_READY: building the node tree
# applies every scene-file and instance-override property, which is all this
# needs, and skipping the notification avoids running Game._ready()'s whole
# bind() chain for a layout assertion.
func test_composed_game_scene_leaves_no_bare_strip_above_the_panel() -> bool:
	# Explicitly typed: load() is untyped, so `:=` cannot infer from
	# .instantiate() and hard-fails to parse on 4.7.1 - same inference gap
	# game/map_renderer.gd documents for its array-literal loop variable.
	var game: Node = load("res://game/game.tscn").instantiate()
	var panel: Control = game.get_node("Hud/TowerPanel")
	assert_eq(panel.offset_top, 0.0,
		"panel runs to the top of the viewport, so no bare background shows beside the map's top rows")
	game.free()
	return true

# game.gd binds the inspector through $Hud/TowerPanel/TowerInspector, a path
# no other test walks: the inspector's own suite instantiates its scene
# directly. Without this, renaming or moving the node would leave the game
# unable to bind it and nothing would fail until someone ran it.
func test_composed_game_scene_carries_the_tower_inspector_in_the_sidebar() -> bool:
	var game: Node = load("res://game/game.tscn").instantiate()
	var inspector = game.get_node_or_null("Hud/TowerPanel/TowerInspector")
	assert_true(inspector != null, "the sidebar carries an inspector where game.gd looks for it")
	assert_true(inspector is TowerInspector, "and it is the inspector, not some other Control")
	# Deliberately the SAME offset as the Buttons container, not below it: the
	# two share one column and are shown one at a time. See
	# test_the_build_palette_and_the_inspector_are_never_both_showing. Stacking
	# them is what pushed Sell off the bottom of the screen.
	var buttons: Control = game.get_node("Hud/TowerPanel/Buttons")
	assert_eq(inspector.offset_top, buttons.offset_top,
		"inspector starts level with the palette it replaces, below the HUD bar")
	game.free()
	return true

# The panel's Control spans the full viewport height so its background covers
# the whole column beside the map - closing the strip that was otherwise left
# bare between the map's right edge and the top of the screen. The buttons
# themselves still have to start below the HUD bar, which is 44px tall
# (hud.tscn's Top offset_bottom) plus an 8px breather, so that inset moves to
# the Buttons container rather than the panel.
#
# The panel is added to Hud after Top, so it draws over the HUD strip in this
# column. Nothing is lost to that: Message is the only HUD item that could
# reach this far, it starts after the Start button (earlier than it used to,
# now that Sell has moved into the tower inspector), and the longest string
# the board emits ("You cannot build any more of that tower.") runs out well
# before the map's 1104px right edge.
func test_buttons_container_clears_the_hud_bar() -> bool:
	var p := _ready_panel()
	var buttons: Control = p.get_node("Buttons")
	assert_eq(buttons.offset_top, 52.0, "buttons start below the 44px HUD bar plus an 8px gap")
	p.free()
	return true

# The panel asks the board which map is loaded rather than assuming
# Maps.FIRST, so this pins the accessor it depends on. Without it, a second
# map of a different width would silently lay the panel out against the
# first map's edge.
func test_get_map_name_returns_the_map_the_board_loaded() -> bool:
	var b := _ready_board()
	assert_eq(b.get_map_name(), Maps.FIRST, "board reports the map it built its tiles from")
	b.free()
	return true

func test_min_tap_size_constant_matches_the_brief() -> bool:
	# Grew from 48 to 56 when the tower icon was added beside the label, so the
	# artwork and two text lines both fit. Still well above the 44x44 floor.
	assert_eq(TowerPanel.MIN_TAP_SIZE, Vector2(120, 56), "MIN_TAP_SIZE leaves room for the icon")
	assert_true(TowerPanel.MIN_TAP_SIZE.x >= 44.0 and TowerPanel.MIN_TAP_SIZE.y >= 44.0,
		"MIN_TAP_SIZE still satisfies the touch-first 44x44 floor")
	return true

# --------------------------------------------------------------------------
# Tower icons
# --------------------------------------------------------------------------

func test_icon_for_cuts_each_kinds_own_frame_from_the_tower_sheet() -> bool:
	# The same 96px grid and upgrade_frames[0] the placed tower uses, so the
	# button shows the thing you are actually buying. Frames: basic 8 -> (3,1),
	# fast 5 -> (0,1), mortar 1 -> (1,0), long 2 -> (2,0). Fast and mortar are
	# swapped from the reference - see data/towers.gd's header.
	var expected := {
		&"basic": Rect2(3 * 96, 1 * 96, 96, 96),
		&"fast": Rect2(0 * 96, 1 * 96, 96, 96),
		&"mortar": Rect2(1 * 96, 0 * 96, 96, 96),
		&"long": Rect2(2 * 96, 0 * 96, 96, 96),
	}
	for kind in Towers.KINDS:
		var icon := TowerPanel.icon_for(kind)
		assert_eq(icon.region, expected[kind], "%s icon region matches its upgrade_frames[0]" % kind)
		assert_eq(icon.atlas, Tower.TOWER_SHEET, "%s icon is cut from the same sheet the placed tower uses" % kind)
	return true

func test_every_button_carries_its_kinds_icon() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)

	for kind in Towers.KINDS:
		var button: Button = p._buttons[kind]
		assert_true(button.icon != null, "%s button has an icon" % kind)
		assert_eq(button.icon.region, TowerPanel.icon_for(kind).region,
			"%s button's icon is that kind's own frame, not another kind's" % kind)
	p.free(); b.free()
	return true

# --------------------------------------------------------------------------
# Selection clears on placement
# --------------------------------------------------------------------------

func test_placing_a_tower_untoggles_every_button() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	b._gold = 1000
	p.bind(b)

	p._on_selected(&"basic")
	assert_true(p._buttons[&"basic"].button_pressed, "precondition: the basic button is lit after selecting it")

	var pos := _find_placeable_position(b)
	b._try_place(pos)

	for kind in Towers.KINDS:
		assert_false(p._buttons[kind].button_pressed,
			"%s button is no longer lit once a tower has been placed" % kind)
	p.free(); b.free()
	return true

func test_bind_creates_buttons_that_meet_the_minimum_tap_target() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)

	for kind in Towers.KINDS:
		var button: Button = p._buttons[kind]
		assert_true(button.custom_minimum_size.x >= 44.0 and button.custom_minimum_size.y >= 44.0,
			"%s button meets the 44x44 minimum tap target" % kind)
	p.free(); b.free()
	return true

# --------------------------------------------------------------------------
# _refresh() - escalated pricing and affordability
# --------------------------------------------------------------------------

# Places a real basic tower through the board's own _try_place() so
# tower_placed fires for real, exercising bind()'s lambda connection rather
# than calling _refresh() directly - this is the amendment 5 "current
# escalated price, not the base price" pin.
func test_refresh_shows_the_current_escalated_price_after_a_placement_of_that_kind() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	b._gold = 1000
	p.bind(b)
	var pos := _find_placeable_position(b)
	var base_price := EconomySim.tower_price(&"basic", 0)
	var escalated_price := EconomySim.tower_price(&"basic", 1)
	assert_true(escalated_price > base_price, "precondition: the second basic costs strictly more than the first")

	b.select_tower_kind(&"basic")
	b._try_place(pos)  # emits tower_placed and gold_changed for real

	var button: Button = p._buttons[&"basic"]
	var limit := EconomySim.tower_limit(&"basic", b.get_map_name())
	assert_eq(button.text, "%s\n1/%d · %d gold" % [Towers.DEFS[&"basic"]["label"], limit, escalated_price],
		"after one basic is placed the button shows the escalated price and a count of one")
	p.free(); b.free()
	return true

# Isolates can_afford's `>=` boundary directly (EconomySim.can_afford is
# pinned elsewhere; this is TowerPanel's own wiring of it to `disabled`).
func test_button_is_disabled_exactly_when_the_gold_cannot_afford_the_price() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)
	var price := EconomySim.tower_price(&"long", 0)

	p._refresh(price - 1)
	assert_true(p._buttons[&"long"].disabled, "one gold short of the price - disabled")

	p._refresh(price)
	assert_false(p._buttons[&"long"].disabled, "exactly enough gold - enabled (can_afford is >=, not >)")

	p._refresh(price + 1)
	assert_false(p._buttons[&"long"].disabled, "more than enough gold - enabled")
	p.free(); b.free()
	return true

# _try_place() always emits gold_changed immediately before tower_placed, so
# a test that places a real tower cannot tell which of the two connections
# is doing the refreshing. This isolates tower_placed by mutating _gold
# directly (no signal) and then emitting only tower_placed.
func test_tower_placed_signal_alone_drives_refresh() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)  # initial refresh runs against the board's starting gold
	assert_false(p._buttons[&"basic"].disabled, "precondition: affordable at the starting gold")

	b._gold = 0  # bypasses gold_changed - no signal fires from this alone
	b.tower_placed.emit(&"basic")

	assert_true(p._buttons[&"basic"].disabled,
		"tower_placed alone (with no accompanying gold_changed) still triggers a refresh reflecting the board's current gold")
	p.free(); b.free()
	return true

func test_gold_changed_signal_drives_refresh() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)
	var price := EconomySim.tower_price(&"mortar", 0)
	assert_true(price > 0, "precondition: mortar has a positive price")

	b._gold = 0
	b.gold_changed.emit(0)
	assert_true(p._buttons[&"mortar"].disabled, "after gold_changed(0) the panel disables what it can no longer afford")

	b._gold = 100000
	b.gold_changed.emit(100000)
	assert_false(p._buttons[&"mortar"].disabled, "gold_changed re-enables once affordable again")
	p.free(); b.free()
	return true

# --------------------------------------------------------------------------
# _on_selected()
# --------------------------------------------------------------------------

func test_on_selected_calls_board_select_tower_kind() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)

	p._on_selected(&"fast")

	assert_eq(b._selected_kind, &"fast", "selecting a kind calls board.select_tower_kind with that kind")
	p.free(); b.free()
	return true

func test_on_selected_leaves_exactly_one_button_toggled_on() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)

	p._on_selected(&"mortar")
	var pressed_count := 0
	for kind in Towers.KINDS:
		if p._buttons[kind].button_pressed:
			pressed_count += 1
			assert_eq(kind, &"mortar", "the pressed button is the one just selected")
	assert_eq(pressed_count, 1, "exactly one button is toggled on")

	p._on_selected(&"basic")
	pressed_count = 0
	for kind in Towers.KINDS:
		if p._buttons[kind].button_pressed:
			pressed_count += 1
			assert_eq(kind, &"basic", "switching selection moves the toggle to the newly selected button")
	assert_eq(pressed_count, 1, "still exactly one button toggled on after switching kinds")
	p.free(); b.free()
	return true

func test_pressing_a_build_button_selects_its_kind_through_the_wired_signal() -> bool:
	var p := _ready_panel()
	var b := _ready_board()
	p.bind(b)

	var button: Button = p._buttons[&"long"]
	button.pressed.emit()

	assert_eq(b._selected_kind, &"long", "pressing the button itself (not calling _on_selected directly) selects that kind")
	assert_true(button.button_pressed, "the pressed button is toggled on")
	p.free(); b.free()
	return true

# --------------------------------------------------------------------------
# Per-kind counts against the limit (spec section 5)
# --------------------------------------------------------------------------

func test_each_button_shows_the_count_against_the_limit() -> bool:
	var board := _ready_board()
	var panel := _ready_panel()
	panel.bind(board)
	var text: String = panel._buttons[&"basic"].text
	assert_true(text.contains("0/8"), "no basics built, eight allowed")
	panel.free()
	board.free()
	return true

func test_the_count_rises_when_a_tower_is_placed() -> bool:
	var board := _ready_board()
	var panel := _ready_panel()
	panel.bind(board)
	board.select_tower_kind(&"basic")
	board._try_place(_find_placeable_position(board))
	assert_true(panel._buttons[&"basic"].text.contains("1/8"),
		"the panel followed the placement")
	panel.free()
	board.free()
	return true

# A kind at its limit is unbuildable however much gold the player holds, so
# the button must be disabled for that reason and not only for price.
func test_a_kind_at_its_limit_is_disabled_even_when_affordable() -> bool:
	var board := _ready_board()
	var panel := _ready_panel()
	board.set_gold_for_test(100000)
	board.set_tower_count_for_test(&"long", EconomySim.tower_limit(&"long", board.get_map_name()))
	panel.bind(board)
	assert_true(panel._buttons[&"long"].disabled,
		"maxed out, so unbuildable regardless of gold")
	panel.free()
	board.free()
	return true

# --------------------------------------------------------------------------
# The sidebar has to FIT
# --------------------------------------------------------------------------

# Sell used to render 38px below the bottom edge of the viewport. It was
# built, wired, and covered - test_tower_inspector.gd presses it and asserts
# the board sells - and still no player could reach it, because the inspector
# sat at a hardcoded offset_top of 320 and grew 390px into a column only 672
# tall. Every test asked "does this button work"; none asked "is it on the
# screen", so the suite stayed green while the feature was gone.
#
# Two rules close it. Both are asserted here rather than in the inspector's
# own suite, because neither is visible from a panel instantiated alone - the
# height that matters comes from the map, and the exclusivity is the panel's
# behaviour.

## Bottom edge the inspector's last row reaches, without needing a layout
## frame - a harness that forbids await never gets one.
##
## Sums the CHILDREN's minimum sizes rather than asking the container for its
## combined minimum. rows.get_combined_minimum_size() returns (0, 0) here: a
## Container reports zero until it has been laid out inside a live tree, and
## a hidden one reports zero regardless. The first version of this test used
## it and computed offset_top + 0, which is under any viewport - it passed
## with the inspector back at the broken offset of 320. Summing the children
## is measured against the real rendered layout in the commit message: 414px
## of minimums against 390px actually drawn, so this over-estimates slightly,
## which is the safe direction for a fit check.
func _inspector_content_height(panel: TowerPanel) -> float:
	var inspector: TowerInspector = panel.get_node("TowerInspector")
	var rows: VBoxContainer = inspector.get_node("Rows")
	var total := 0.0
	for child in rows.get_children():
		total += (child as Control).get_combined_minimum_size().y
	total += float(rows.get_theme_constant(&"separation")) * float(rows.get_child_count() - 1)
	return inspector.offset_top + total

## The shortest shipped map, which is the binding constraint: the viewport is
## exactly the map's pixel height (GameBoard.required_content_size), so the
## sidebar has to fit the smallest one, not the one that happens to load first.
func _shortest_map_height() -> int:
	var shortest := 1 << 30
	for name in Maps.DEFS:
		shortest = mini(shortest, Maps.pixel_size(name).y)
	return shortest

func test_the_selected_tower_inspector_fits_inside_the_shortest_map() -> bool:
	var board := _ready_board()
	var panel := _ready_panel()
	panel.bind(board)
	var inspector: TowerInspector = panel.get_node("TowerInspector")
	inspector.notification(Node.NOTIFICATION_READY)
	# bind() as well as ready(): game.gd binds the inspector separately from
	# the panel, and an unbound inspector leaves every row's text empty, so
	# the buttons report the bare 56px tap minimum instead of the 69px three
	# lines of tier text actually need. Measuring the empty panel is measuring
	# the wrong thing.
	inspector.bind(board)

	var viewport_height := _shortest_map_height()
	var worst := 0.0
	var worst_kind := &""
	for kind in Towers.KINDS:
		board.set_gold_for_test(999999)
		board.select_tower_kind(kind)
		board._try_place(_find_placeable_position(board))
		var tower: Tower = board._towers_root.get_child(board._towers_root.get_child_count() - 1)
		inspector.show_tower(tower)
		var height := _inspector_content_height(panel)
		if height > worst:
			worst = height
			worst_kind = kind

	assert_true(worst <= float(viewport_height),
		"the whole inspector is on screen: worst kind %s needs %d px of the %d px the shortest map gives"
			% [worst_kind, int(worst), viewport_height])
	panel.free()
	board.free()
	return true

# The palette and the inspector are the same 140px column in two states.
# Stacked they needed 924px of 672, which is what pushed Sell off the bottom;
# side by side is not an option at this width. If a later change makes them
# both visible, the column overflows again and the test above stops being
# enough on its own - so the exclusivity is pinned directly.
func test_the_build_palette_and_the_inspector_are_never_both_showing() -> bool:
	var board := _ready_board()
	var panel := _ready_panel()
	panel.bind(board)
	var buttons: Control = panel.get_node("Buttons")

	assert_true(buttons.visible, "the palette is what the column shows with nothing selected")

	board.set_gold_for_test(999999)
	board.select_tower_kind(&"basic")
	board._try_place(_find_placeable_position(board))
	var tower: Tower = board._towers_root.get_child(0)
	board._select_tower(tower)
	assert_true(not buttons.visible, "selecting a tower hands the column to the inspector")

	board._deselect_tower()
	assert_true(buttons.visible, "and deselecting hands it back, so the player can build again")
	panel.free()
	board.free()
	return true
