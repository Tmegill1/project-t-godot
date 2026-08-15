extends Control

## Entry point of the game (`run/main_scene`). Play loads the game scene
## fresh; Quit is hidden on Web builds where it would do nothing useful.

@onready var _play: Button = $Panel/Play
@onready var _quit: Button = $Panel/Quit

func _ready() -> void:
	_play.pressed.connect(func(): get_tree().change_scene_to_file("res://game/game.tscn"))
	_quit.pressed.connect(func(): get_tree().quit())
	# Quit is meaningless in a browser build.
	_quit.visible = OS.get_name() != "Web"
