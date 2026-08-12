class_name TowerPanel
extends Control

## Build panel: one button per Towers.KINDS, each showing that kind's
## current escalated asking price and disabled when the board's gold can't
## afford it. Calls board.select_tower_kind() directly on press; emits
## nothing of its own. Every button carries a custom_minimum_size of at
## least 44x44 (touch-first requirement).

const MIN_TAP_SIZE := Vector2(120, 48)

var _board: GameBoard
var _buttons := {}

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_refresh)
	board.tower_placed.connect(func(_kind): _refresh(board.get_gold()))

	var container: VBoxContainer = $Buttons
	for child in container.get_children():
		child.queue_free()

	for kind in Towers.KINDS:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.toggle_mode = true
		button.pressed.connect(_on_selected.bind(kind))
		container.add_child(button)
		_buttons[kind] = button

	_refresh(board.get_gold())

func _on_selected(kind: StringName) -> void:
	_board.select_tower_kind(kind)
	for k in _buttons:
		_buttons[k].button_pressed = (k == kind)

func _refresh(gold: int) -> void:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		# The board owns the authoritative count; the panel shows the base
		# price plus escalation is applied on placement, so display the
		# current asking price by asking the board.
		var price := EconomySim.tower_price(kind, _board.get_tower_count(kind))
		var button: Button = _buttons[kind]
		button.text = "%s\n%d gold" % [def["label"], price]
		button.disabled = not EconomySim.can_afford(gold, price)
