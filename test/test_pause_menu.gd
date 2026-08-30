extends TestCase

# The pause menu declares no class_name, matching GameOver and Victory - Game
# holds all three only as an untyped `scene.instantiate()` result. Its
# @onready fields resolve on NOTIFICATION_READY, which add_child() does not
# deliver in this harness, so every test fires that notification by hand (see
# test_end_screens.gd's header for the full finding).
#
# `restart_map` and `restart_difficulty` are set by the caller BEFORE the
# notification, exactly as game.gd sets them - the same ordering game_over's
# wave_reached already relies on, and the defect amendment 1 warns about.

func _ready_menu(map: StringName, tier: StringName):
	var menu = load("res://ui/pause_menu.tscn").instantiate()
	menu.restart_map = map
	menu.restart_difficulty = tier
	menu.notification(Node.NOTIFICATION_READY)
	return menu

func test_the_menu_offers_continue_restart_and_quit() -> bool:
	var menu = _ready_menu(&"map2", Difficulty.HARD)
	assert_eq(menu._continue.text, "Continue", "the first way out is back into the run")
	assert_eq(menu._restart.text, "Restart", "the second starts this run again")
	assert_eq(menu._quit.text, "Quit", "the third leaves for the menu")
	menu.free()
	return true

# THE reason Restart is not just reload_current_scene(). GameBoard._ready
# consumes pending_map and pending_difficulty and clears both, and _map_name
# falls back to Maps.FIRST - so a plain reload restarts on The Pass at Normal
# wherever the player actually was. Both statics have to be put back first.
func test_restart_keeps_the_runs_map_and_difficulty() -> bool:
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
	var menu = _ready_menu(&"map3", Difficulty.NIGHTMARE)

	menu.stage_restart()

	assert_eq(GameBoard.pending_map, &"map3", "the same map is restarted")
	assert_eq(GameBoard.pending_difficulty, Difficulty.NIGHTMARE,
		"at the same difficulty")
	assert_eq(GameBoard.active_difficulty(), Difficulty.NIGHTMARE,
		"and the board would read it back")
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
	menu.free()
	return true

# Paused is global tree state and outlives a scene change, exactly as
# Engine.time_scale does - the hazard Hud.bind() documents. A Quit that left it
# set would hand the main menu a frozen tree.
func test_leaving_the_menu_never_leaves_the_tree_paused() -> bool:
	var menu = _ready_menu(&"demoMap", Difficulty.NORMAL)
	assert_true(menu.has_method("stage_quit"), "quit is its own step, so it can be tested")
	assert_false(menu.leaves_tree_paused(), "nothing this menu does leaves the tree paused")
	menu.free()
	return true
