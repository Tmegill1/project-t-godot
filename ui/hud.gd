class_name Hud
extends CanvasLayer

## HUD strip: gold, lives, wave, Start/Sell buttons and a transient message
## line. Purely a view over GameBoard's signals and accessors - it decides
## nothing about gold, lives, wave progression or placement rules; that is
## the board's job. StartButton and SellButton in the scene each carry a
## custom_minimum_size of at least 44x44 (touch-first requirement; see
## task-20-21-amendments.md amendment 3).

const MESSAGE_SECONDS := 2.0

@onready var _gold: Label = $Top/GoldLabel
@onready var _lives: Label = $Top/LivesLabel
@onready var _wave: Label = $Top/WaveLabel
@onready var _start: Button = $Top/StartButton
@onready var _sell: Button = $Top/SellButton
@onready var _message: Label = $Top/Message

var _board: GameBoard
var _message_timer := 0.0

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.lives_changed.connect(_on_lives_changed)
	board.wave_changed.connect(_on_wave_changed)
	board.wave_state_changed.connect(_on_wave_state_changed)
	board.placement_rejected.connect(_show_message)
	_start.pressed.connect(board.start_next_wave)
	_sell.pressed.connect(board.sell_selected_tower)

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

func _show_message(text: String) -> void:
	_message.text = text
	_message_timer = MESSAGE_SECONDS
