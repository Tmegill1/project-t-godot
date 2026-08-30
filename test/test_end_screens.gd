extends TestCase

# GameOver and Victory declare no class_name (see game/game.gd - Game holds
# them only as an untyped `scene.instantiate()` result), so they are loaded
# and held here as untyped values too. Their `wave_reached` field is a plain
# script var read by _ready(), which only resolves _summary/_retry/_menu on
# NOTIFICATION_READY (same harness constraint as Hud/TowerPanel - see
# task-20-21-amendments.md). Setting wave_reached *before* firing that
# notification mirrors game.gd's own order (instantiate, set
# screen.wave_reached, then add_child, which is what actually fires
# _ready()) - see amendment 1. Reversing that order is the specific defect
# amendment 1 warns against, so a couple of these tests pin the order too.

func _instantiate(path: String):
	return load(path).instantiate()

# --------------------------------------------------------------------------
# GameOver
# --------------------------------------------------------------------------

func test_game_over_summary_reports_the_wave_reached_out_of_max_waves() -> bool:
	var screen = _instantiate("res://ui/game_over.tscn")
	screen.wave_reached = 7
	screen.notification(Node.NOTIFICATION_READY)

	assert_eq(screen._summary.text, "You held until wave 7 of %d." % Waves.MAX_WAVES,
		"game over summary matches 'You held until wave %d of %d.'")
	screen.free()
	return true

func test_game_over_summary_reflects_wave_reached_set_before_ready_fires() -> bool:
	var screen = _instantiate("res://ui/game_over.tscn")
	screen.wave_reached = 13  # set before notification(), exactly as game.gd orders it
	screen.notification(Node.NOTIFICATION_READY)

	assert_eq(screen._summary.text, "You held until wave 13 of %d." % Waves.MAX_WAVES,
		"_ready() reads the wave_reached value already in place, not a stale default")
	screen.free()
	return true

func test_game_over_summary_defaults_to_wave_zero_when_unset() -> bool:
	var screen = _instantiate("res://ui/game_over.tscn")
	screen.notification(Node.NOTIFICATION_READY)

	assert_eq(screen._summary.text, "You held until wave 0 of %d." % Waves.MAX_WAVES,
		"wave_reached's own default (0) is used if the caller never sets it")
	screen.free()
	return true

# --------------------------------------------------------------------------
# Victory
# --------------------------------------------------------------------------

# The core of amendment 2: victory must NOT reuse game over's "You held
# until wave %d of %d." line, which on a win reads as though the player fell
# short at the last wave.
func test_victory_summary_does_not_reuse_the_defeat_copy() -> bool:
	var screen = _instantiate("res://ui/victory.tscn")
	screen.wave_reached = Waves.MAX_WAVES
	screen.notification(Node.NOTIFICATION_READY)

	assert_true(not screen._summary.text.begins_with("You held until"),
		"victory copy must not read as a defeat line")
	screen.free()
	return true

func test_victory_summary_reports_all_waves_cleared() -> bool:
	var screen = _instantiate("res://ui/victory.tscn")
	screen.wave_reached = Waves.MAX_WAVES
	screen.notification(Node.NOTIFICATION_READY)

	assert_eq(screen._summary.text, "You cleared all %d waves." % Waves.MAX_WAVES,
		"victory summary matches 'You cleared all %d waves.'")
	screen.free()
	return true

# --------------------------------------------------------------------------
# Shared shape: both screens expose the same wiring points
# --------------------------------------------------------------------------

func test_game_over_exposes_retry_and_main_menu_buttons() -> bool:
	var screen = _instantiate("res://ui/game_over.tscn")
	screen.notification(Node.NOTIFICATION_READY)

	assert_true(screen._retry is Button, "game over exposes a Retry button")
	assert_true(screen._menu is Button, "game over exposes a MainMenu button")
	screen.free()
	return true

func test_victory_exposes_retry_and_main_menu_buttons() -> bool:
	var screen = _instantiate("res://ui/victory.tscn")
	screen.notification(Node.NOTIFICATION_READY)

	assert_true(screen._retry is Button, "victory exposes a Retry button")
	assert_true(screen._menu is Button, "victory exposes a MainMenu button")
	screen.free()
	return true

# --------------------------------------------------------------------------
# Map progression on victory
# --------------------------------------------------------------------------
#
# data/maps.gd has carried a `next` field since the core slice and NOTHING
# read it: winning offered Retry and Main Menu only, so The Fork and The Coils
# were unreachable in play however complete their data was. The table test
# that asserts the chain passes on the data alone, which is exactly how this
# stayed invisible.

func test_a_fresh_board_loads_the_first_map() -> bool:
	GameBoard.pending_map = &""
	var b := _ready_board()
	assert_eq(b.get_map_name(), Maps.FIRST, "no pending map means map one")
	b.free()
	return true

func test_a_pending_map_is_what_the_board_loads() -> bool:
	GameBoard.pending_map = &"map2"
	var b := _ready_board()
	assert_eq(b.get_map_name(), &"map2", "the board honoured the pending map")
	b.free()
	GameBoard.pending_map = &""
	return true

# Static state that outlives a scene reload is the whole mechanism, so it has
# to be cleared deliberately or every later run inherits the last one's map.
func test_loading_a_pending_map_consumes_it() -> bool:
	GameBoard.pending_map = &"map2"
	var first := _ready_board()
	var second := _ready_board()
	assert_eq(first.get_map_name(), &"map2", "the first board took it")
	assert_eq(second.get_map_name(), Maps.FIRST, "the second did not inherit it")
	first.free(); second.free()
	GameBoard.pending_map = &""
	return true

func test_victory_offers_the_next_map_when_there_is_one() -> bool:
	var v: CanvasLayer = _ready_victory(&"demoMap")
	assert_true(v.next_map_button().visible, "The Pass leads somewhere")
	assert_true(v.next_map_button().text.contains("The Fork"),
		"and the button names where")
	v.free()
	return true

func test_victory_hides_the_next_map_button_on_the_last_map() -> bool:
	var v: CanvasLayer = _ready_victory(&"map3")
	assert_false(v.next_map_button().visible,
		"The Coils is the last map, so there is nowhere to go")
	v.free()
	return true

func test_pressing_next_map_queues_that_map() -> bool:
	GameBoard.pending_map = &""
	var v: CanvasLayer = _ready_victory(&"demoMap")
	v.queue_next_map()
	assert_eq(GameBoard.pending_map, &"map2", "the next run loads The Fork")
	v.free()
	GameBoard.pending_map = &""
	return true

# Starting a fresh game from the menu must not drop the player onto whatever
# map the previous session happened to end on.
func test_starting_a_new_game_clears_any_pending_map() -> bool:
	GameBoard.pending_map = &"map3"
	MainMenu.begin_new_run()
	assert_eq(GameBoard.pending_map, &"", "a new run starts at the beginning")
	return true

func _ready_victory(completed_map: StringName) -> CanvasLayer:
	var v: CanvasLayer = load("res://ui/victory.tscn").instantiate()
	v.completed_map = completed_map
	v.notification(Node.NOTIFICATION_READY)
	return v

func _ready_board() -> GameBoard:
	var b: GameBoard = load("res://game/game_board.tscn").instantiate()
	b.notification(Node.NOTIFICATION_READY)
	return b

# The tier is chosen per run, so a new game must not inherit the last one's.
func test_starting_a_new_game_clears_any_pending_difficulty() -> bool:
	GameBoard.pending_difficulty = Difficulty.NIGHTMARE
	MainMenu.begin_new_run()
	assert_eq(GameBoard.pending_difficulty, &"", "a new run starts unset")
	assert_eq(GameBoard.active_difficulty(), Difficulty.NORMAL,
		"and an unset tier reads as Normal")
	return true

## The whole selector is wired in _ready, so a broken node path would ship an
## unusable menu that nothing else in the suite could see.
func test_the_menu_offers_every_tier_and_starts_on_normal() -> bool:
	var m: MainMenu = load("res://ui/main_menu.tscn").instantiate()
	m.notification(Node.NOTIFICATION_READY)
	var row: Control = m.get_node("Panel/Difficulty")
	assert_eq(row.get_child_count(), Difficulty.ORDER.size(), "one button per tier")

	var labels: Array[String] = []
	var pressed := 0
	for child in row.get_children():
		var button: Button = child
		labels.append(button.text)
		if button.button_pressed:
			pressed += 1
	for tier in Difficulty.ORDER:
		assert_true(labels.has(Difficulty.label(tier)), "%s is offered" % tier)
	assert_eq(pressed, 1, "exactly one tier is selected")
	assert_true((row.get_child(0) as Button).button_pressed,
		"and a fresh menu starts on Normal")
	m.free()
	return true

# Retry has to replay the run that was lost, not the first map at Normal.
#
# GameBoard._ready consumes pending_map and pending_difficulty and clears both,
# and _map_name falls back to Maps.FIRST - so before this, dying on The Fork on
# Nightmare retried on The Pass on Normal. The bug predates the pause menu; it
# was found while building Restart, which needs the same three lines.
func test_retry_replays_the_run_that_was_lost() -> bool:
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
	var screen = _instantiate("res://ui/game_over.tscn")
	screen.wave_reached = 12
	screen.retry_map = &"map2"
	screen.retry_difficulty = Difficulty.NIGHTMARE
	screen.notification(Node.NOTIFICATION_READY)

	screen.stage_retry()

	assert_eq(GameBoard.pending_map, &"map2", "the same map is retried")
	assert_eq(GameBoard.pending_difficulty, Difficulty.NIGHTMARE, "at the same tier")
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
	screen.free()
	return true
