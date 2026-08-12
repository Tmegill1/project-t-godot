extends TestCase

# Hud's @onready fields (_gold, _lives, _wave, _start, _sell, _message) only
# resolve on NOTIFICATION_READY, which add_child() does NOT deliver in this
# harness (test/run_tests.gd runs entirely inside SceneTree._initialize(),
# before the tree's own root has entered a tree - Task 17's finding,
# reconfirmed for Task 20 in task-20-21-amendments.md). Hud defines no
# _ready() override of its own, so notification(NOTIFICATION_READY) here is
# purely the engine's default @onready resolution.
#
# Consequence: nodes are never inside the tree, so get_tree() returns null.
# Hud._process reads no get_tree() state, so it is safe to call directly as
# an ordinary method (per the amendments' guidance) instead of needing a
# live tree to drive it via idle frames.

func _ready_hud() -> Hud:
	var h: Hud = load("res://ui/hud.tscn").instantiate()
	h.notification(Node.NOTIFICATION_READY)
	return h

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

func test_bind_populates_initial_labels_from_the_boards_state() -> bool:
	var h := _ready_hud()
	var b := _ready_board()

	h.bind(b)

	var expected_gold := int(Maps.get_def(Maps.FIRST)["starting_gold"])
	assert_eq(h._gold.text, "Gold %d" % expected_gold, "gold label seeded from board.get_gold()")
	assert_eq(h._lives.text, "Lives %d" % Economy.STARTING_LIVES, "lives label seeded from board.get_lives()")
	assert_eq(h._wave.text, "Wave 0 / %d" % Waves.MAX_WAVES, "wave label seeded from board.get_wave()/MAX_WAVES")
	assert_eq(h._message.text, "", "message starts empty")
	h.free(); b.free()
	return true

func test_bind_wires_start_button_to_board_start_next_wave() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)
	assert_false(b.is_wave_active(), "precondition: no wave active yet")

	h._start.pressed.emit()

	assert_true(b.is_wave_active(), "pressing Start invoked board.start_next_wave through bind()'s connection")
	assert_eq(b.get_wave(), 1, "the board actually advanced to wave 1")
	h.free(); b.free()
	return true

# SCRIPT ERROR noise from this test's placement/selection flow is expected
# per test_game_board.gd's documented pattern: Tower's own @onready fields
# (_sprite, _range_indicator) never resolve here because the tower is
# add_child()'d under a board that itself never entered a live tree, so
# set_range_visible() aborts partway through - but every board-owned field
# it needs (kind, price_paid, grid_col/grid_row, the _counts map) is set
# before that crash point, so the assertions below are unaffected.
func test_bind_wires_sell_button_to_board_sell_selected_tower() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	b._gold = 1000
	var tile := _find_buildable_tile(b)
	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)
	b._handle_tap(Grid.tile_to_world_center(tile.x, tile.y))  # selects the placed tower
	assert_true(b._selected_tower != null, "precondition: a tower is selected")
	h.bind(b)

	h._sell.pressed.emit()

	assert_eq(b.get_tower_count(&"basic"), 0, "pressing Sell invoked board.sell_selected_tower and it sold")
	h.free(); b.free()
	return true

func test_bind_connects_gold_changed_to_the_label() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)

	b.gold_changed.emit(42)

	assert_eq(h._gold.text, "Gold 42", "board.gold_changed drives the label through bind()'s connection")
	h.free(); b.free()
	return true

# bind() also seeds the lives label once from board.get_lives() before any
# signal fires, so a test that only checks the post-bind() label (as
# test_bind_populates_initial_labels_from_the_boards_state does) cannot
# distinguish a working lives_changed connection from a missing one - the
# seed call alone would already make that assertion pass. Emitting the
# signal a second time, to a different value, isolates the connection.
func test_bind_connects_lives_changed_to_the_label() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)

	b.lives_changed.emit(9)

	assert_eq(h._lives.text, "Lives 9", "board.lives_changed drives the label through bind()'s connection")
	h.free(); b.free()
	return true

# Same reasoning as the lives_changed test above, for wave_changed.
func test_bind_connects_wave_changed_to_the_label() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)

	b.wave_changed.emit(6, Waves.MAX_WAVES)

	assert_eq(h._wave.text, "Wave 6 / %d" % Waves.MAX_WAVES, "board.wave_changed drives the label through bind()'s connection")
	h.free(); b.free()
	return true

# Isolates bind()'s explicit `_message.text = ""` from the label's own
# scene-file default (also ""): without a pre-existing non-empty value,
# removing that line would go unnoticed since the label already reads empty.
func test_bind_clears_any_pre_existing_message_text() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h._message.text = "leftover"

	h.bind(b)

	assert_eq(h._message.text, "", "bind() clears any pre-existing message text")
	h.free(); b.free()
	return true

func test_bind_connects_placement_rejected_to_show_message() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)

	b.placement_rejected.emit("nope")

	assert_eq(h._message.text, "nope", "board.placement_rejected shows the message through bind()'s connection")
	assert_eq(h._message_timer, Hud.MESSAGE_SECONDS, "the message timer starts counting down")
	h.free(); b.free()
	return true

# --------------------------------------------------------------------------
# label formats
# --------------------------------------------------------------------------

func test_on_gold_changed_formats_gold_percent_d() -> bool:
	var h := _ready_hud()
	h._on_gold_changed(7)
	assert_eq(h._gold.text, "Gold 7", "matches the 'Gold %d' format")
	h.free()
	return true

func test_on_lives_changed_formats_lives_percent_d() -> bool:
	var h := _ready_hud()
	h._on_lives_changed(3)
	assert_eq(h._lives.text, "Lives 3", "matches the 'Lives %d' format")
	h.free()
	return true

func test_on_wave_changed_formats_wave_percent_d_slash_percent_d() -> bool:
	var h := _ready_hud()
	h._on_wave_changed(4, 20)
	assert_eq(h._wave.text, "Wave 4 / 20", "matches the 'Wave %d / %d' format")
	h.free()
	return true

# --------------------------------------------------------------------------
# _on_wave_state_changed()
# --------------------------------------------------------------------------

func test_bind_connects_wave_state_changed_to_the_handler() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)
	assert_false(h._start.disabled, "precondition: Start begins enabled")

	b.wave_state_changed.emit(true)

	assert_true(h._start.disabled, "board.wave_state_changed drives the handler through bind()'s connection")
	assert_eq(h._start.text, "In progress", "and the handler's own text swap runs too")
	h.free(); b.free()
	return true

func test_wave_state_changed_true_disables_start_and_shows_in_progress() -> bool:
	var h := _ready_hud()
	h._on_wave_state_changed(true)
	assert_true(h._start.disabled, "Start is disabled while a wave is active")
	assert_eq(h._start.text, "In progress", "text swaps to 'In progress'")
	h.free()
	return true

func test_wave_state_changed_false_enables_start_and_shows_start_wave() -> bool:
	var h := _ready_hud()
	h._on_wave_state_changed(true)
	h._on_wave_state_changed(false)
	assert_false(h._start.disabled, "Start is re-enabled once the wave ends")
	assert_eq(h._start.text, "Start wave", "text swaps back to 'Start wave'")
	h.free()
	return true

# --------------------------------------------------------------------------
# messages / _process
# --------------------------------------------------------------------------

func test_show_message_sets_text_and_starts_the_timer() -> bool:
	var h := _ready_hud()
	h._show_message("Not enough gold — that costs 20.")
	assert_eq(h._message.text, "Not enough gold — that costs 20.", "message text is set verbatim")
	assert_eq(h._message_timer, Hud.MESSAGE_SECONDS, "timer starts at MESSAGE_SECONDS")
	h.free()
	return true

func test_process_counts_down_and_clears_the_message_once_it_reaches_zero() -> bool:
	var h := _ready_hud()
	h._show_message("temporary")

	h._process(1.0)
	assert_eq(h._message.text, "temporary", "message still shown before MESSAGE_SECONDS have elapsed")
	assert_almost_eq(h._message_timer, Hud.MESSAGE_SECONDS - 1.0, 0.0001, "timer decremented by delta")

	h._process(1.0)
	assert_eq(h._message.text, "", "message cleared once the timer reaches exactly zero")
	h.free()
	return true

# Isolates the `<= 0.0` guard from `< 0.0`: with no message pending the
# timer starts at exactly 0.0, and _process must treat that as "nothing to
# do" rather than driving the timer negative or touching the label.
func test_process_is_a_no_op_when_no_message_is_pending() -> bool:
	var h := _ready_hud()
	h._process(5.0)
	assert_eq(h._message.text, "", "still empty; nothing to clear")
	assert_eq(h._message_timer, 0.0, "the idle timer is untouched, not driven negative")
	h.free()
	return true

# --------------------------------------------------------------------------
# touch targets (amendment 3)
# --------------------------------------------------------------------------

func test_message_seconds_constant_is_two_seconds() -> bool:
	assert_eq(Hud.MESSAGE_SECONDS, 2.0, "MESSAGE_SECONDS matches the brief's literal 2.0 seconds")
	return true

func test_start_and_sell_buttons_meet_the_44x44_minimum_tap_target() -> bool:
	var h := _ready_hud()
	assert_true(h._start.custom_minimum_size.x >= 44.0 and h._start.custom_minimum_size.y >= 44.0,
		"StartButton has at least a 44x44 tap target")
	assert_true(h._sell.custom_minimum_size.x >= 44.0 and h._sell.custom_minimum_size.y >= 44.0,
		"SellButton has at least a 44x44 tap target")
	h.free()
	return true
