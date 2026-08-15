extends CanvasLayer

## Victory screen: shown by Game when the final wave is cleared. Its copy
## deliberately reads as a win, not "You held until wave %d of %d." - on this
## screen `wave_reached` is always Waves.MAX_WAVES, and that line would read
## as though the player fell short at the last wave (see
## task-20-21-amendments.md, Task 21 amendment 2).

var wave_reached := 0

@onready var _summary: Label = $Panel/Summary
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/MainMenu

func _ready() -> void:
	_summary.text = "You cleared all %d waves." % Waves.MAX_WAVES
	_retry.pressed.connect(func(): get_tree().reload_current_scene())
	_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
