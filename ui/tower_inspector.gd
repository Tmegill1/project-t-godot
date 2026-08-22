class_name TowerInspector
extends Control

## Selected-tower view: what each branch has bought, what the next tier on each
## costs, and Sell. Decides nothing - legality comes from UpgradesSim,
## affordability and the purchase itself from the board.
##
## Sell lives here rather than in the HUD strip because the refund it quotes is
## half of everything sunk into THIS tower, upgrades included, which only means
## anything beside the tiers that produced it.
##
## The rows are built ONCE and rewritten in place; nothing here frees a node
## after _ready(). An earlier version rebuilt them on every change, which broke
## the moment a row was actually pressed: Godot locks an object while it is
## emitting, refuses to free it ("Object is locked and can't be freed"), and
## aborts the enclosing call - so pressing an upgrade bought the tier and then
## left the panel showing the tier it had just bought. The node set never
## varies (one header, one row per branch, Sell), so there is nothing a rebuild
## could do that rewriting cannot.

const MIN_TAP_SIZE := Vector2(120, 56)

## Three type sizes, largest for the tower's own name. Godot's built-in font
## has no bold face, so the hierarchy has to come from size, colour and case -
## a kicker that labels the panel, the tower name as the thing you selected,
## and the branch counters as detail under it.
const KICKER_FONT_SIZE := 11
const NAME_FONT_SIZE := 20
const COUNTER_FONT_SIZE := 14
const KICKER_COLOR := Color(0.62, 0.66, 0.62)
const NAME_COLOR := Color(0.94, 0.96, 0.94)

## Green means one thing only: you can press this row right now - the tier is
## legal AND you can afford it. A row you cannot afford keeps the default look
## rather than a second colour, so the player learns one rule instead of two.
const BUYABLE_COLOR := Color(0.13, 0.42, 0.18)
const BUYABLE_CORNER_RADIUS := 4

var _board: GameBoard
var _tower: Tower = null
var _rows := {}
var _counters := {}
var _kicker: Label = null
var _name: Label = null
var _sell: Button = null
var _priority: Button = null

@onready var _rows_root: VBoxContainer = $Rows

func _ready() -> void:
	_build_rows()
	_refresh()

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.tower_upgraded.connect(_on_tower_upgraded)
	board.tower_selected.connect(show_tower)
	board.tower_deselected.connect(clear)

func has_tower() -> bool:
	return _tower != null and is_instance_valid(_tower)

## The rows currently on display, keyed by branch. Empty when no tower is
## shown - the nodes persist, but they are not a view of anything.
func branch_rows() -> Dictionary:
	return _rows if has_tower() else {}

func sell_row() -> Button:
	return _sell if has_tower() else null

func priority_row() -> Button:
	return _priority

func show_tower(tower: Tower) -> void:
	_tower = tower
	_refresh()

func clear() -> void:
	_tower = null
	_refresh()

## Affordability moved, but nothing else did - re-gate rather than rewrite.
##
## The reference records this exact bug in a comment: its panel was drawn once
## on selection, so a tower selected while broke stayed greyed out after a wave
## paid out until the player reselected it.
func _on_gold_changed(_gold: int) -> void:
	_refresh_gating()

func _on_tower_upgraded(_branch: StringName) -> void:
	_refresh()

func _build_rows() -> void:
	# Every header line is its own Label so each can carry its own size and
	# colour. Wrapping stays on for all of them: a Label reports the width of
	# its longest line as its MINIMUM size, and a VBoxContainer is at least as
	# wide as its widest child, so one long line makes the whole column
	# overflow the 140px sidebar. It grew 37px out over the map before this was
	# measured.
	_kicker = _header_label(KICKER_FONT_SIZE, KICKER_COLOR)
	_kicker.text = "UPGRADES:"
	_name = _header_label(NAME_FONT_SIZE, NAME_COLOR)
	for branch in Upgrades.BRANCHES:
		_counters[branch] = _header_label(COUNTER_FONT_SIZE, NAME_COLOR)

	for branch in Upgrades.BRANCHES:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.clip_text = true
		button.pressed.connect(_on_branch_pressed.bind(branch))
		_rows_root.add_child(button)
		_rows[branch] = button

	# One cycling button rather than one per priority. Five side-by-side
	# controls would report a minimum width the 140px sidebar cannot hold -
	# the failure this panel's header documents - and Targeting.next_priority
	# already exists for exactly this control.
	_priority = Button.new()
	_priority.custom_minimum_size = MIN_TAP_SIZE
	_priority.clip_text = true
	_priority.pressed.connect(_on_priority_pressed)
	_rows_root.add_child(_priority)

	_sell = Button.new()
	_sell.custom_minimum_size = MIN_TAP_SIZE
	_sell.clip_text = true
	_sell.pressed.connect(_on_sell_pressed)
	_rows_root.add_child(_sell)

func _header_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	_rows_root.add_child(label)
	return label

func _refresh() -> void:
	_rows_root.visible = has_tower()
	if not has_tower():
		return

	_name.text = String(Towers.DEFS[_tower.kind]["label"])
	for branch in Upgrades.BRANCHES:
		_counters[branch].text = "%s %d/%d" % [
			Upgrades.DEFS[_tower.kind][branch]["label"],
			int(_tower.tiers[branch]), UpgradesSim.MAX_TIER,
		]
	_priority.text = "Target: %s" % Targeting.LABELS[_tower.get_priority()]
	_sell.text = "Sell  %d gold" % EconomySim.sell_refund(_tower.price_paid)
	_refresh_gating()

func _refresh_gating() -> void:
	if not has_tower():
		return
	for branch in _rows:
		var tier := int(_tower.tiers[branch])
		var button: Button = _rows[branch]
		var definition: Dictionary = Upgrades.DEFS[_tower.kind][branch]
		if not UpgradesSim.can_upgrade(_tower.tiers, branch):
			# Which of the two, not "maxed or locked": they mean opposite
			# things to a player deciding what to do next, and the combined
			# phrase was measured being clipped to "maxed or lock" anyway.
			var reason := "maxed" if tier >= UpgradesSim.MAX_TIER else "locked"
			button.text = "%s\n%s" % [definition["label"], reason]
			button.tooltip_text = definition["summary"]
			button.disabled = true
			_set_buyable(button, false)
			continue
		var next: Dictionary = definition["tiers"][tier]
		var price := UpgradesSim.upgrade_cost(_tower.kind, branch, tier)
		# Three short lines, not one long one. The sidebar is 140px wide at the
		# design ratio and a Button does not wrap its text: "Quick Loader —
		# 30g" on one line was measured overflowing it. The tier's description
		# is the tooltip for the same reason.
		button.text = "%s\n%s\n%d gold" % [definition["label"], next["label"], price]
		button.tooltip_text = String(next["description"])
		var affordable := EconomySim.can_afford(_board.get_gold(), price)
		button.disabled = not affordable
		_set_buyable(button, affordable)

## Picks a row out in green, or puts it back to the theme's own look. Applied
## to `hover` as well as `normal` so the highlight does not vanish under the
## cursor, which would read as the row going dead the moment you reach for it.
func _set_buyable(button: Button, buyable: bool) -> void:
	if not buyable:
		button.remove_theme_stylebox_override(&"normal")
		button.remove_theme_stylebox_override(&"hover")
		return
	var box := StyleBoxFlat.new()
	box.bg_color = BUYABLE_COLOR
	box.set_corner_radius_all(BUYABLE_CORNER_RADIUS)
	button.add_theme_stylebox_override(&"normal", box)
	var hovered := box.duplicate()
	hovered.bg_color = BUYABLE_COLOR.lightened(0.12)
	button.add_theme_stylebox_override(&"hover", hovered)

func _on_branch_pressed(branch: StringName) -> void:
	_board.upgrade_selected_tower(branch)

func _on_sell_pressed() -> void:
	_board.sell_selected_tower()

## Asks the board to cycle, then re-reads the tower. The panel never advances
## the priority itself - the board owns what happens to a selected tower.
func _on_priority_pressed() -> void:
	_board.cycle_selected_tower_priority()
	_refresh()
