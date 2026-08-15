class_name Hud
extends CanvasLayer

## HUD strip: gold, lives, wave, the Start button and a transient message
## line. Purely a view over GameBoard's signals and accessors - it decides
## nothing about gold, lives, wave progression or placement rules; that is
## the board's job. StartButton carries a custom_minimum_size of at least
## 44x44 (touch-first requirement; see task-20-21-amendments.md amendment 3).
##
## Sell used to live here too. It moved to ui/tower_inspector.gd, beside the
## upgrade tiers whose cost its refund is half of - a sell price that counts
## upgrades means nothing next to the wave counter.
##
## The speed toggle lives here rather than on the board because it is an engine
## setting, not a game rule: nothing in sim/ may reference Engine at all, and
## the harness has its own tick size. What the board owns is the simulation;
## what this owns is how fast the player watches it.

const MESSAGE_SECONDS := 2.0

## What the fast-play button multiplies time by.
##
## Engine.time_scale DOUBLES the delta passed to _physics_process on 4.7.1 - it
## does not raise the tick rate - so at 2x every enemy takes steps twice the
## size. That is the shape that soft-locked waves 19 and 20 before the waypoint
## clamp landed; test_harness.gd sweeps all twenty waves at twice the tick size
## to hold it, and this constant is the number that sweep assumes.
const FAST_TIME_SCALE := 2.0

## Horizontal inset of the Top bar from the viewport edges. The bar anchors
## edge to edge, so without this its first and last children sit flush on the
## screen border with the tilemap showing through behind them. Mirrors the
## 12px separation the bar already puts between its own items. The scene file
## carries the literal (offset_left/offset_right on Top); this names it and
## test_hud.gd pins both against each other.
const EDGE_INSET := 12.0

@onready var _gold: Label = $Top/GoldLabel
@onready var _lives: Label = $Top/LivesLabel
@onready var _wave: Label = $Top/WaveLabel
@onready var _start: Button = $Top/StartButton
@onready var _speed: Button = $Top/SpeedButton
@onready var _message: Label = $Top/Message

var _board: GameBoard
var _message_timer := 0.0
var _fast := false

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.lives_changed.connect(_on_lives_changed)
	board.wave_changed.connect(_on_wave_changed)
	board.wave_state_changed.connect(_on_wave_state_changed)
	board.placement_rejected.connect(_show_message)
	_start.pressed.connect(board.start_next_wave)
	_speed.pressed.connect(_toggle_speed)

	# Engine.time_scale is global and outlives reload_current_scene(), so a run
	# that ended at 2x would hand the next one double speed behind a button
	# reading 1x. Binding a HUD is the start of a run; reset it here.
	_fast = false
	_apply_speed()

	_on_gold_changed(board.get_gold())
	_on_lives_changed(board.get_lives())
	_on_wave_changed(board.get_wave(), Waves.MAX_WAVES)
	_message.text = ""

func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message.text = ""

func _on_gold_changed(gold: int) -> void:
	_gold.text = "Gold %d" % gold

func _on_lives_changed(lives: int) -> void:
	_lives.text = "Lives %d" % lives

func _on_wave_changed(wave: int, max_waves: int) -> void:
	_wave.text = "Wave %d / %d" % [wave, max_waves]

func _on_wave_state_changed(active: bool) -> void:
	_start.disabled = active
	_start.text = "In progress" if active else "Start wave"

func _toggle_speed() -> void:
	_fast = not _fast
	_apply_speed()

func _apply_speed() -> void:
	Engine.time_scale = FAST_TIME_SCALE if _fast else 1.0
	_speed.text = "Speed 2x" if _fast else "Speed 1x"

func _show_message(text: String) -> void:
	_message.text = text
	_message_timer = MESSAGE_SECONDS
