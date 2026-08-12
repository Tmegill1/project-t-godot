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

func _find_buildable_tile(b: GameBoard) -> Vector2i:
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == Tiles.BUILDABLE:
				return Vector2i(c, r)
	return Vector2i(-1, -1)

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
		var button: Button = p._buttons[kind]
		assert_eq(button.text, "%s\n%d gold" % [def["label"], price], "%s button shows its base price" % kind)
	p.free(); b.free()
	return true

func test_min_tap_size_constant_matches_the_brief() -> bool:
	assert_eq(TowerPanel.MIN_TAP_SIZE, Vector2(120, 48), "MIN_TAP_SIZE matches the brief's literal dimensions")
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
	var tile := _find_buildable_tile(b)
	var base_price := EconomySim.tower_price(&"basic", 0)
	var escalated_price := EconomySim.tower_price(&"basic", 1)
	assert_true(escalated_price > base_price, "precondition: the second basic costs strictly more than the first")

	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)  # emits tower_placed and gold_changed for real

	var button: Button = p._buttons[&"basic"]
	assert_eq(button.text, "%s\n%d gold" % [Towers.DEFS[&"basic"]["label"], escalated_price],
		"after one basic is placed the button shows the escalated price, not the base price")
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
