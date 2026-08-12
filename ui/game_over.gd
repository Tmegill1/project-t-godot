extends CanvasLayer

## Defeat screen: shown by Game when GameBoard's lives reach zero. Purely
## presentational - `wave_reached` is set by the caller before this node
## enters the tree (see game/game.gd), so it is already in place by the
## time _ready() reads it.

var wave_reached := 0

@onready var _summary: Label = $Panel/Summary
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/MainMenu

func _ready() -> void:
	_summary.text = "You held until wave %d of %d." % [wave_reached, Waves.MAX_WAVES]
	_retry.pressed.connect(func(): get_tree().reload_current_scene())
	_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
