extends TestCase

# Hud's @onready fields (_gold, _lives, _wave, _start, _message) only
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

# Sell moved out of the HUD into ui/tower_inspector.tscn, beside the tiers
# its refund is half of; test_tower_inspector.gd owns its wiring now. The test
# that used to live here pressed h._sell and asserted the board sold.

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

func test_the_start_button_meets_the_44x44_minimum_tap_target() -> bool:
	var h := _ready_hud()
	assert_true(h._start.custom_minimum_size.x >= 44.0 and h._start.custom_minimum_size.y >= 44.0,
		"StartButton has at least a 44x44 tap target")
	h.free()
	return true

# Sell is gone from this bar. Asserted rather than assumed, so a reinstated
# copy here - two Sell buttons, one of them quoting nothing about upgrades -
# fails loudly.
func test_the_hud_no_longer_carries_a_sell_button() -> bool:
	var h := _ready_hud()
	assert_true(h.get_node_or_null("Top/SellButton") == null,
		"Sell belongs to the tower inspector now")
	h.free()
	return true

# --------------------------------------------------------------------------
# top bar inset
# --------------------------------------------------------------------------

# Top anchors across the full viewport width, so with both horizontal offsets
# left at 0 its first child begins at viewport x=0: "Gold N" is drawn hard
# against the screen edge, over the tilemap, with no backing panel behind it.
# Nothing is truncated - the glyph is whole - but at web-export scale it reads
# as cut off, which is what sent us looking for a clipping bug that was really
# a missing inset.
#
# The computed label rect cannot be asserted here. Containers only lay out
# their children once inside a live tree, which this harness never provides
# (see the header note), so GoldLabel's position stays at its unlaid-out
# default no matter what the offsets say. Pin the offsets that drive the
# layout instead.
#
# Both sides are pinned deliberately: Message is the right-most child and
# expands to fill, so a regression that dropped only offset_right would push
# it back onto the right edge while a left-only assertion stayed green.
func test_top_bar_is_inset_from_both_viewport_edges() -> bool:
	var h := _ready_hud()
	var top: Control = h.get_node("Top")
	assert_eq(top.offset_left, Hud.EDGE_INSET, "Top bar starts EDGE_INSET in from the left viewport edge")
	assert_eq(top.offset_right, -Hud.EDGE_INSET, "Top bar stops EDGE_INSET short of the right viewport edge")
	h.free()
	return true

# Pins the constant itself. Without this, editing EDGE_INSET and the scene
# together would keep the test above green while silently changing the layout
# - the "constant pinned from one side only" failure this suite has hit before.
func test_edge_inset_constant_is_twelve_pixels() -> bool:
	assert_eq(Hud.EDGE_INSET, 12.0, "EDGE_INSET matches the 12px separation already used between HUD items")
	return true

# --------------------------------------------------------------------------
# speed toggle
#
# Engine.time_scale is global and survives reload_current_scene(), so a run
# that ended at 2x would otherwise hand the next run double speed with a
# button reading 1x. Every test below restores it, for the same reason: the
# whole suite shares one process.
# --------------------------------------------------------------------------

func test_bind_starts_a_run_at_normal_speed_even_if_the_last_one_ended_fast() -> bool:
	Engine.time_scale = Hud.FAST_TIME_SCALE
	var h := _ready_hud()
	var b := _ready_board()

	h.bind(b)

	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "a fresh run starts at normal speed")
	assert_true(h._speed.text.contains("1x"), "and the button says so: %s" % h._speed.text)
	Engine.time_scale = 1.0
	h.free(); b.free()
	return true

func test_pressing_speed_toggles_between_normal_and_double() -> bool:
	var h := _ready_hud()
	var b := _ready_board()
	h.bind(b)

	h._speed.pressed.emit()
	assert_almost_eq(Engine.time_scale, Hud.FAST_TIME_SCALE, 0.0001, "the game runs faster")
	assert_true(h._speed.text.contains("1.5x"), "and the button says so: %s" % h._speed.text)

	h._speed.pressed.emit()
	assert_almost_eq(Engine.time_scale, 1.0, 0.0001, "and back to normal")
	assert_true(h._speed.text.contains("1x"), "and says that too: %s" % h._speed.text)

	Engine.time_scale = 1.0
	h.free(); b.free()
	return true

# 1.5x, chosen by the owner over 2x, which played too fast. The harness sweep
# in test_harness.gd runs at DOUBLE the tick size deliberately - a bound above
# what the button applies - so this constant has headroom rather than sitting
# exactly on the tested edge. Raising it past 2.0 would leave that cover.
func test_the_fast_speed_is_the_one_the_termination_sweep_covers() -> bool:
	assert_almost_eq(Hud.FAST_TIME_SCALE, 1.5, 0.0001, "1.5x, not 2x")
	assert_true(Hud.FAST_TIME_SCALE > 1.0, "and it is actually faster than normal")
	assert_true(Hud.FAST_TIME_SCALE <= 2.0,
		"and no faster than the step size test_harness.gd sweeps for termination")
	return true

# The label is derived from the number rather than written beside it, so the
# two cannot drift: a speed change that forgot the text would show the old
# multiplier on a button that applies the new one.
func test_the_speed_label_is_derived_from_the_multiplier() -> bool:
	var h := _ready_hud()
	assert_eq(h._speed_label(1.0), "Speed 1x", "a whole number loses its decimal")
	assert_eq(h._speed_label(1.5), "Speed 1.5x", "a fractional one keeps it")
	assert_eq(h._speed_label(2.0), "Speed 2x", "and 2.0 does not read as 2.0x")
	h.free()
	return true

func test_the_speed_button_meets_the_44x44_minimum_tap_target() -> bool:
	var h := _ready_hud()
	assert_true(h._speed.custom_minimum_size.x >= 44.0 and h._speed.custom_minimum_size.y >= 44.0,
		"SpeedButton has at least a 44x44 tap target")
	h.free()
	return true
