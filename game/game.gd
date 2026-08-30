extends Node2D

## Top-level scene: composes GameBoard, Hud and TowerPanel, and swaps in the
## game-over or victory screen when the board reports the run has ended. It
## owns no gameplay rules of its own - it only wires the board's signals to
## the end screens.

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")
const PAUSE_MENU_SCENE := preload("res://ui/pause_menu.tscn")

@onready var _board: GameBoard = $GameBoard
@onready var _hud: Hud = $Hud
@onready var _panel: TowerPanel = $Hud/TowerPanel
@onready var _inspector: TowerInspector = $Hud/TowerPanel/TowerInspector

## The open pause menu, or null. Held so a second Escape cannot stack a second
## copy on top of the first - the menu frees itself on Continue, so this goes
## invalid rather than stale.
var _paused_menu: CanvasLayer = null

func _ready() -> void:
	_hud.bind(_board)
	_panel.bind(_board)
	_inspector.bind(_board)
	_board.game_over.connect(_on_game_over)
	_board.victory.connect(_on_victory)
	_board.pause_requested.connect(_on_pause_requested)

func _on_game_over() -> void:
	_show_end_screen(GAME_OVER_SCENE)

func _on_victory() -> void:
	_show_end_screen(VICTORY_SCENE)

## Escape reached the board with nothing left to cancel.
##
## The menu carries the run's map and difficulty so Restart can put them back:
## GameBoard._ready consumes both statics and clears them, so a plain reload
## would restart on the first map at Normal. Set before add_child, so they are
## in place by the time _ready runs - the same ordering wave_reached relies on.
##
## get_tree().paused rather than a flag of the board's own, because it is the
## one that stops _physics_process - which is what drives the wave clock, the
## prep timer and every enemy. The menu itself runs when paused; its scene sets
## that, or its own buttons would go dead the moment it appeared.
func _on_pause_requested() -> void:
	if _paused_menu != null and is_instance_valid(_paused_menu):
		return
	var menu := PAUSE_MENU_SCENE.instantiate()
	menu.restart_map = _board.get_map_name()
	menu.restart_difficulty = _board.get_difficulty()
	add_child(menu)
	_paused_menu = menu
	get_tree().paused = true

func _show_end_screen(scene: PackedScene) -> void:
	var screen := scene.instantiate()
	screen.wave_reached = _board.get_wave()
	# Retry replays THIS run, not the first map at Normal - see game_over.gd.
	if "retry_map" in screen:
		screen.retry_map = _board.get_map_name()
		screen.retry_difficulty = _board.get_difficulty()
	# The victory screen needs to know where it is to know where to go next.
	# Set before add_child, so it is in place by the time _ready reads it -
	# the same ordering wave_reached already relies on.
	if screen.has_method("set_completed_map") or "completed_map" in screen:
		screen.completed_map = _board.get_map_name()
	add_child(screen)
