extends Node2D

## Top-level scene: composes GameBoard, Hud and TowerPanel, and swaps in the
## game-over or victory screen when the board reports the run has ended. It
## owns no gameplay rules of its own - it only wires the board's signals to
## the end screens.

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

@onready var _board: GameBoard = $GameBoard
@onready var _hud: Hud = $Hud
@onready var _panel: TowerPanel = $Hud/TowerPanel
@onready var _inspector: TowerInspector = $Hud/TowerPanel/TowerInspector

func _ready() -> void:
	_hud.bind(_board)
	_panel.bind(_board)
	_inspector.bind(_board)
	_board.game_over.connect(_on_game_over)
	_board.victory.connect(_on_victory)

func _on_game_over() -> void:
	_show_end_screen(GAME_OVER_SCENE)

func _on_victory() -> void:
	_show_end_screen(VICTORY_SCENE)

func _show_end_screen(scene: PackedScene) -> void:
	var screen := scene.instantiate()
	screen.wave_reached = _board.get_wave()
	# The victory screen needs to know where it is to know where to go next.
	# Set before add_child, so it is in place by the time _ready reads it -
	# the same ordering wave_reached already relies on.
	if screen.has_method("set_completed_map") or "completed_map" in screen:
		screen.completed_map = _board.get_map_name()
	add_child(screen)
