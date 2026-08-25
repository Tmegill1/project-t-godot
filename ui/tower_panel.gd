class_name TowerPanel
extends Control

## Build panel: one button per Towers.KINDS, each showing that kind's
## current escalated asking price and disabled when the board's gold can't
## afford it. Calls board.select_tower_kind() directly on press; emits
## nothing of its own. Every button carries a custom_minimum_size of at
## least 44x44 (touch-first requirement).

const MIN_TAP_SIZE := Vector2(120, 56)
const ICON_PX := 40

var _board: GameBoard
var _buttons := {}

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_refresh)
	board.tower_placed.connect(_on_tower_placed)
	board.tower_sold.connect(_on_tower_sold)

	# Butt the panel's left edge against the map's right edge; the scene
	# anchors the other three sides to the viewport. The map is a fixed pixel
	# size but the viewport is not - window/stretch/aspect="expand" hands the
	# surplus width of any window wider than the 1244x672 design box to the
	# viewport - so a fixed-width panel pinned right leaves that surplus as
	# bare background between the two. Absorbing it here means the panel is
	# 140px at the design ratio, wider on a wider screen, and never narrower.
	# Asked of the board rather than read from Maps.FIRST so a later map of
	# different dimensions still lines up.
	offset_left = float(Maps.pixel_size(board.get_map_name()).x)

	var container: VBoxContainer = $Buttons
	# free(), not queue_free(). queue_free() only unparents a node once a frame
	# actually processes, which never happens inside a single synchronous test
	# method (no await allowed) — the previous bind()'s buttons would still be
	# in get_children() alongside the new ones, doubling the count on any
	# re-bind observed synchronously. Same engine behaviour, same conclusion,
	# as game/map_renderer.gd's render(); these two used to disagree. The
	# buttons are owned exclusively by this container (the only other reference
	# is _buttons, rebuilt below), so an immediate free() is safe.
	for child in container.get_children():
		child.free()
	_buttons.clear()

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

## That kind's sprite, cut from the shared tower sheet on the same grid the
## placed tower uses, so the button shows the thing you are buying.
##
## The sheet AND the region arithmetic come from Tower rather than being
## re-declared here: they are one description of one PNG, and a second copy
## would drift the day someone re-packs towers.png. An earlier pass unified
## only the constants and left both sites computing the Rect2 themselves,
## which is the same duplication one layer down — Tower.frame_region closes it.
static func icon_for(kind: StringName) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = Tower.TOWER_SHEET
	atlas.region = Tower.frame_region(Towers.DEFS[kind]["upgrade_frames"][0])
	return atlas

## Selling frees a slot, so both the count and the asking price move.
##
## Connected explicitly rather than left to ride on gold_changed, which a sale
## also emits: the panel cares about the sale, and depending on a coincidence
## of emission order is how the count goes stale the day a refund is ever made
## free.
func _on_tower_sold(_kind: StringName) -> void:
	_refresh(_board.get_gold())

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
		var owned := _board.get_tower_count(kind)
		var limit := EconomySim.tower_limit(kind, _board.get_map_name())
		var price := EconomySim.tower_price(kind, owned)
		var button: Button = _buttons[kind]
		# Name on its own line, the two numbers grouped on the second. Putting
		# the count beside the name instead pushed "Long Range 0/5" past the
		# 140px button and squeezed its icon to zero width - visible only in a
		# screenshot, since the icon was still set and the button still
		# measured 140x56.
		button.text = "%s\n%d/%d · %d gold" % [def["label"], owned, limit, price]
		# Two independent reasons a kind can be unbuildable. The limit is
		# checked as well as the price because a maxed kind stays unbuildable
		# however rich the player gets, and a button that looks affordable but
		# is refused on tap is worse than one that reads as spent.
		button.disabled = owned >= limit or not EconomySim.can_afford(gold, price)
