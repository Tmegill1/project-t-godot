class_name TowerInspector
extends Control

## Selected-tower view: what each branch has bought, what the next tier on it
## costs, and Sell. Decides nothing - legality comes from UpgradesSim,
## affordability and the purchase itself from the board.
##
## Sell lives here rather than in the HUD strip because the refund it quotes
## is half of everything sunk into THIS tower, upgrades included, which only
## means anything beside the tiers that produced it.

const MIN_TAP_SIZE := Vector2(120, 56)

var _board: GameBoard
var _tower: Tower = null
var _rows := {}
var _sell: Button = null

@onready var _rows_root: VBoxContainer = $Rows

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.tower_upgraded.connect(_on_tower_upgraded)
	board.tower_selected.connect(show_tower)
	board.tower_deselected.connect(clear)

func has_tower() -> bool:
	return _tower != null and is_instance_valid(_tower)

## The per-branch buttons, keyed by branch. Empty when nothing is shown.
func branch_rows() -> Dictionary:
	return _rows

func sell_row() -> Button:
	return _sell

func show_tower(tower: Tower) -> void:
	_tower = tower
	_rebuild()

func clear() -> void:
	_tower = null
	_rebuild()

## Affordability moved, but nothing else did - re-gate rather than redraw.
##
## The reference records this exact bug in a comment: its panel was drawn once
## on selection, so a tower selected while broke stayed greyed out after a wave
## paid out until the player reselected it.
func _on_gold_changed(_gold: int) -> void:
	_refresh_gating()

func _on_tower_upgraded(_branch: StringName) -> void:
	_rebuild()

func _rebuild() -> void:
	# free(), not queue_free() - same reasoning as ui/tower_panel.gd's bind():
	# queue_free() only unparents once a frame processes, which never happens
	# inside a synchronous test method, so the old rows would still be present
	# alongside the new ones. These rows are owned exclusively by this
	# container, so an immediate free() is safe.
	for child in _rows_root.get_children():
		child.free()
	_rows.clear()
	_sell = null
	if not has_tower():
		return

	var header := Label.new()
	header.text = "%s\n%s %d/%d   %s %d/%d" % [
		Towers.DEFS[_tower.kind]["label"],
		Upgrades.DEFS[_tower.kind][&"sustained"]["label"],
		int(_tower.tiers[&"sustained"]), UpgradesSim.MAX_TIER,
		Upgrades.DEFS[_tower.kind][&"burst"]["label"],
		int(_tower.tiers[&"burst"]), UpgradesSim.MAX_TIER,
	]
	_rows_root.add_child(header)

	for branch in Upgrades.BRANCHES:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.clip_text = true
		button.pressed.connect(_on_branch_pressed.bind(branch))
		_rows_root.add_child(button)
		_rows[branch] = button

	_sell = Button.new()
	_sell.custom_minimum_size = MIN_TAP_SIZE
	_sell.text = "Sell  %dg" % EconomySim.sell_refund(_tower.price_paid)
	_sell.pressed.connect(_board.sell_selected_tower)
	_rows_root.add_child(_sell)

	_refresh_gating()

func _refresh_gating() -> void:
	if not has_tower():
		return
	for branch in _rows:
		var tier := int(_tower.tiers[branch])
		var button: Button = _rows[branch]
		var definition: Dictionary = Upgrades.DEFS[_tower.kind][branch]
		if not UpgradesSim.can_upgrade(_tower.tiers, branch):
			button.text = "%s\nmaxed or locked" % definition["label"]
			button.tooltip_text = definition["summary"]
			button.disabled = true
			continue
		var next: Dictionary = definition["tiers"][tier]
		var price := UpgradesSim.upgrade_cost(_tower.kind, branch, tier)
		# The description is the tooltip, not a third line: the sidebar is
		# 140px wide at the design ratio and a Button does not wrap its text,
		# so a sentence on the face of it would simply be cut off.
		button.text = "%s\n%s — %dg" % [definition["label"], next["label"], price]
		button.tooltip_text = String(next["description"])
		button.disabled = not EconomySim.can_afford(_board.get_gold(), price)

func _on_branch_pressed(branch: StringName) -> void:
	_board.upgrade_selected_tower(branch)
