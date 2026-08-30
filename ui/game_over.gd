extends CanvasLayer

## Defeat screen: shown by Game when GameBoard's lives reach zero. Purely
## presentational - `wave_reached` is set by the caller before this node
## enters the tree (see game/game.gd), so it is already in place by the
## time _ready() reads it.

var wave_reached := 0

## The map and tier the lost run was played at, so Retry replays THAT run.
##
## Without them Retry lost both: GameBoard._ready consumes pending_map and
## pending_difficulty and clears them, and _map_name falls back to Maps.FIRST,
## so dying on The Fork on Nightmare used to retry on The Pass on Normal. Set
## by game.gd before this node enters the tree, alongside wave_reached.
var retry_map: StringName = &""
var retry_difficulty: StringName = &""

@onready var _summary: Label = $Panel/Summary
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/MainMenu

func _ready() -> void:
	_summary.text = "You held until wave %d of %d." % [wave_reached, Waves.MAX_WAVES]
	_retry.pressed.connect(func():
		stage_retry()
		get_tree().reload_current_scene())
	_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/main_menu.tscn"))

## Puts the lost run's map and tier back before the reload consumes them.
## Split from the button so it can be tested without a live tree.
func stage_retry() -> void:
	GameBoard.pending_map = retry_map
	GameBoard.pending_difficulty = retry_difficulty
