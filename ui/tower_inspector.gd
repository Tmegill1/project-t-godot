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

var _board: GameBoard
var _tower: Tower = null
var _rows := {}
var _header: Label = null
var _sell: Button = null

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
	_header = Label.new()
	# One branch per line, and wrapping on. A Label reports the width of its
	# longest line as its MINIMUM size, and a VBoxContainer is at least as wide
	# as its widest child - so a single long header line makes the whole column
	# overflow the 140px sidebar. It grew 37px out over the map before this was
	# measured.
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows_root.add_child(_header)

	for branch in Upgrades.BRANCHES:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.clip_text = true
		button.pressed.connect(_on_branch_pressed.bind(branch))
		_rows_root.add_child(button)
		_rows[branch] = button

	_sell = Button.new()
	_sell.custom_minimum_size = MIN_TAP_SIZE
	_sell.clip_text = true
	_sell.pressed.connect(_on_sell_pressed)
	_rows_root.add_child(_sell)

func _refresh() -> void:
	_rows_root.visible = has_tower()
	if not has_tower():
		return

	_header.text = "%s\n%s %d/%d\n%s %d/%d" % [
		Towers.DEFS[_tower.kind]["label"],
		Upgrades.DEFS[_tower.kind][&"sustained"]["label"],
		int(_tower.tiers[&"sustained"]), UpgradesSim.MAX_TIER,
		Upgrades.DEFS[_tower.kind][&"burst"]["label"],
		int(_tower.tiers[&"burst"]), UpgradesSim.MAX_TIER,
	]
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
			continue
		var next: Dictionary = definition["tiers"][tier]
		var price := UpgradesSim.upgrade_cost(_tower.kind, branch, tier)
		# Three short lines, not one long one. The sidebar is 140px wide at the
		# design ratio and a Button does not wrap its text: "Quick Loader —
		# 30g" on one line was measured overflowing it. The tier's description
		# is the tooltip for the same reason.
		button.text = "%s\n%s\n%d gold" % [definition["label"], next["label"], price]
		button.tooltip_text = String(next["description"])
		button.disabled = not EconomySim.can_afford(_board.get_gold(), price)

func _on_branch_pressed(branch: StringName) -> void:
	_board.upgrade_selected_tower(branch)

func _on_sell_pressed() -> void:
	_board.sell_selected_tower()
