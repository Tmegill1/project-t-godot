class_name MainMenu
extends Control

## Entry point of the game (`run/main_scene`). Play loads the game scene
## fresh; Quit is hidden on Web builds where it would do nothing useful.

@onready var _play: Button = $Panel/Play
@onready var _quit: Button = $Panel/Quit
@onready var _stamp: Label = $BuildStampLabel

## Plain toggle buttons and the existing theme - no art, per the standing
## asset rule. A row rather than a dropdown because three choices shown at
## once is the whole readout, and this game is touch-first.
@onready var _tier_buttons := {
	Difficulty.NORMAL: $Panel/Difficulty/Normal,
	Difficulty.HARD: $Panel/Difficulty/Hard,
	Difficulty.NIGHTMARE: $Panel/Difficulty/Nightmare,
}

var _chosen: StringName = Difficulty.NORMAL

func _ready() -> void:
	# Which build this is, dimmed in the corner. A diagnostic, not a feature:
	# a cached index.pck is indistinguishable from a fresh one otherwise, and
	# working out which version a browser was running previously meant
	# downloading the pack and parsing it in a headless engine.
	_stamp.text = BuildStamp.label()
	for tier in _tier_buttons:
		var button: Button = _tier_buttons[tier]
		button.text = Difficulty.label(tier)
		button.pressed.connect(_choose.bind(tier))
	_choose(Difficulty.NORMAL)

	_play.pressed.connect(func():
		# begin_new_run clears the tier along with the map, so the choice is
		# set after it rather than before.
		begin_new_run()
		GameBoard.pending_difficulty = _chosen
		get_tree().change_scene_to_file("res://game/game.tscn"))
	_quit.pressed.connect(func(): get_tree().quit())
	# Quit is meaningless in a browser build.
	_quit.visible = OS.get_name() != "Web"

## Difficulty is chosen per run and deliberately NOT persisted: there is no
## settings file in this project, and update.md records that Slice 3 owns
## saving. Inventing one here would hand Slice 3 a versioning problem early.
func _choose(tier: StringName) -> void:
	_chosen = tier
	for other in _tier_buttons:
		_tier_buttons[other].button_pressed = (other == tier)

## Clears anything a previous run left behind. "Play" must always mean the
## first map at the tier just chosen, however the last run ended.
static func begin_new_run() -> void:
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
