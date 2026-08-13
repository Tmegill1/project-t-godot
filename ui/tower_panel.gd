class_name TowerPanel
extends Control

## Build panel: one button per Towers.KINDS, each showing that kind's
## current escalated asking price and disabled when the board's gold can't
## afford it. Calls board.select_tower_kind() directly on press; emits
## nothing of its own. Every button carries a custom_minimum_size of at
## least 44x44 (touch-first requirement).

const MIN_TAP_SIZE := Vector2(120, 56)
const TOWER_SHEET := preload("res://assets/towers.png")
const SHEET_COLUMNS := 5
const FRAME_SIZE := 96
const ICON_PX := 40

var _board: GameBoard
var _buttons := {}

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_refresh)
	board.tower_placed.connect(_on_tower_placed)

	var container: VBoxContainer = $Buttons
	for child in container.get_children():
		child.queue_free()

	for kind in Towers.KINDS:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.toggle_mode = true
		button.icon = icon_for(kind)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", ICON_PX)
		# Icon left, text beside it, rather than the default centred stack.
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_selected.bind(kind))
		container.add_child(button)
		_buttons[kind] = button

	_refresh(board.get_gold())

## That kind's sprite, cut from the shared tower sheet on the same 96px grid
## the placed tower uses, so the button shows the thing you are buying.
static func icon_for(kind: StringName) -> AtlasTexture:
	var frame: int = Towers.DEFS[kind]["upgrade_frames"][0]
	var atlas := AtlasTexture.new()
	atlas.atlas = TOWER_SHEET
	atlas.region = Rect2(
		(frame % SHEET_COLUMNS) * FRAME_SIZE,
		(frame / SHEET_COLUMNS) * FRAME_SIZE,
		FRAME_SIZE, FRAME_SIZE)
	return atlas

## Placing consumes the board's selection, so the button must not stay lit.
func _on_tower_placed(_kind: StringName) -> void:
	clear_selection()
	_refresh(_board.get_gold())

func clear_selection() -> void:
	for k in _buttons:
		_buttons[k].button_pressed = false

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
