class_name MainMenu
extends Control

## Entry point of the game (`run/main_scene`). Play loads the game scene
## fresh; Quit is hidden on Web builds where it would do nothing useful.

@onready var _play: Button = $Panel/Play
@onready var _quit: Button = $Panel/Quit
@onready var _stamp: Label = $BuildStampLabel

func _ready() -> void:
	# Which build this is, dimmed in the corner. A diagnostic, not a feature:
	# a cached index.pck is indistinguishable from a fresh one otherwise, and
	# working out which version a browser was running previously meant
	# downloading the pack and parsing it in a headless engine.
	_stamp.text = BuildStamp.label()
	_play.pressed.connect(func():
		begin_new_run()
		get_tree().change_scene_to_file("res://game/game.tscn"))
	_quit.pressed.connect(func(): get_tree().quit())
	# Quit is meaningless in a browser build.
	_quit.visible = OS.get_name() != "Web"

## Clears anything a previous run left behind. "Play" must always mean the
## first map, however the last run ended.
static func begin_new_run() -> void:
	GameBoard.pending_map = &""
