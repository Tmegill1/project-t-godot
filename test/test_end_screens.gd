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
