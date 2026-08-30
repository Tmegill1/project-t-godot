extends CanvasLayer

## The pause menu: Continue, Restart, Quit.
##
## Declares no class_name, matching GameOver and Victory - Game holds all three
## only as an untyped `scene.instantiate()` result.
##
## PROCESS_MODE_WHEN_PAUSED is set on the scene's root, and it is load-bearing:
## this menu is what pauses the tree, so without it the menu's own buttons stop
## responding the instant it appears.
##
## `restart_map` and `restart_difficulty` are set by the caller before this node
## enters the tree (see game/game.gd), so they are already in place by the time
## anything reads them - the same ordering game_over's wave_reached relies on.

var restart_map: StringName = &""
var restart_difficulty: StringName = &""

@onready var _continue: Button = $Panel/Continue
@onready var _restart: Button = $Panel/Restart
@onready var _quit: Button = $Panel/Quit

func _ready() -> void:
	_continue.pressed.connect(_on_continue)
	_restart.pressed.connect(_on_restart)
	_quit.pressed.connect(_on_quit)

## Puts the run back where it was and reloads.
##
## Split from the button handler so it can be tested without a live tree, and
## because the ordering is the whole point: GameBoard._ready CONSUMES
## pending_map and pending_difficulty and clears both, and _map_name falls back
## to Maps.FIRST. A plain reload_current_scene() therefore restarts on The Pass
## at Normal wherever the player actually was. Both statics have to be put back
## before the reload, not after.
func stage_restart() -> void:
	GameBoard.pending_map = restart_map
	GameBoard.pending_difficulty = restart_difficulty

## Lifts the pause before leaving.
##
## `paused` is global tree state and outlives a scene change, exactly as
## Engine.time_scale does - the hazard Hud.bind() documents. A Quit that left it
## set would hand the main menu a frozen tree.
func stage_quit() -> void:
	_unpause()

## Whether anything this menu does could leave the tree paused behind it. It
## cannot: every exit lifts the pause first.
func leaves_tree_paused() -> bool:
	return false

func _on_continue() -> void:
	_unpause()
	queue_free()

func _on_restart() -> void:
	stage_restart()
	_unpause()
	get_tree().reload_current_scene()

func _on_quit() -> void:
	stage_quit()
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

## Guarded because every node this harness builds is outside the tree, where
## get_tree() returns null - the same guard Hud._audio() documents.
func _unpause() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
