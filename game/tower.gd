class_name Tower
extends Node2D

## Tower view: owns a sprite and a tap-pickable Area2D, asks sim/targeting.gd
## who to shoot each tick, and asks the board to spawn a projectile by
## signal. Decides nothing about combat itself - Targeting.select does.
## ClickArea exists solely so a tap can pick this tower; it must never
## participate in targeting or hit resolution - combat is distance
## arithmetic, never physics.

signal wants_to_fire(target_node: Node2D, source: Dictionary, splash: float)

const TOWER_SHEET := preload("res://assets/towers.png")
const SHEET_COLUMNS := 5
const FRAME_SIZE := 96

## Where a frame index sits on the shared tower sheet, row-major across
## SHEET_COLUMNS. One PNG gets one description of its geometry: the build
## panel's button icons come through here too (ui/tower_panel.gd's icon_for),
## so a re-pack of towers.png is a one-line change rather than two that can
## disagree. Integer division on the row is intentional.
static func frame_region(frame: int) -> Rect2:
	return Rect2(
		(frame % SHEET_COLUMNS) * FRAME_SIZE,
		(frame / SHEET_COLUMNS) * FRAME_SIZE,
		FRAME_SIZE, FRAME_SIZE)

var kind: StringName
## Placement price plus every upgrade bought since, so sell_refund keeps its
## meaning as "half of everything sunk into this tower".
var price_paid := 0
var grid_col := 0
var grid_row := 0
## Purchased tier per branch. Empty until setup() runs.
var tiers := {}

var _def := {}
## Live stats resolved from tiers. Resolved on change rather than per tick:
## tick() runs for every tower every physics frame, and resolution walks both
## branches' tiers.
var _stats := {}
var _cooldown := 0.0
var _priority: StringName = Targeting.DEFAULT_PRIORITY
var _range_visible := false

@onready var _sprite: Sprite2D = $Sprite
@onready var _range_indicator: Node2D = $RangeIndicator

func setup(tower_kind: StringName, col: int, row: int, paid: int) -> void:
	kind = tower_kind
	grid_col = col
	grid_row = row
	price_paid = paid
	_def = Towers.DEFS[kind]
	# Rules state before anything visual. The board instantiates a tower under
	# a node that never entered a live tree, so in the test harness the
	# tower's own @onready fields are unresolved and this function aborts at
	# the first line that touches one - everything assigned before that line
	# still lands (see test_game_board.gd's header), and the upgrade path
	# needs tiers and the resolved stats to be among them.
	tiers = UpgradesSim.empty_tiers()
	_stats = UpgradesSim.resolve_tower_stats(kind, tiers)
	position = Grid.tile_to_world_center(col, row)

	var target_px := Tiles.TILE_SIZE * float(_def["size"])
	_sprite.scale = Vector2.ONE * (target_px / FRAME_SIZE)

	_range_indicator.tint = _def["color"]
	_range_indicator.visible = false
	_refresh_visuals()

func set_range_visible(is_visible: bool) -> void:
	_range_visible = is_visible
	_range_indicator.visible = is_visible
	_range_indicator.queue_redraw()

## Buys the next tier on a branch and refreshes everything derived from it.
## The board gates on UpgradesSim.can_upgrade and affordability before calling.
##
## Charges only if the buy actually happened: an illegal one (a stale button,
## a branch the cross-path rule has locked) still has a non-zero cost to read,
## so charging first would take gold for a tier the tower never receives.
func apply_upgrade(branch: StringName) -> void:
	var current := int(tiers.get(branch, 0))
	var next := UpgradesSim.with_upgrade(tiers, branch)
	if int(next.get(branch, 0)) == current:
		return
	price_paid += UpgradesSim.upgrade_cost(kind, branch, current)
	tiers = next
	_stats = UpgradesSim.resolve_tower_stats(kind, tiers)
	_refresh_visuals()

## This tower's live stats after upgrades.
func get_stats() -> Dictionary:
	return _stats

## Sprite frame and range ring, both derived from the tiers.
func _refresh_visuals() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = TOWER_SHEET
	atlas.region = frame_region(UpgradesSim.sprite_frame_for(kind, tiers))
	_sprite.texture = atlas
	_range_indicator.radius = float(_stats["range"])
	_range_indicator.queue_redraw()

func to_targeting_dict() -> Dictionary:
	return {
		"position": position, "range": float(_stats["range"]),
		"priority": _priority, "detection": bool(_stats["detection"]),
	}

## Called by the board each physics tick with the current enemy candidates.
func tick(delta_ms: float, candidates: Array) -> void:
	_cooldown -= delta_ms
	if _cooldown > 0.0:
		return
	var target = Targeting.select(to_targeting_dict(), candidates)
	if target == null:
		return
	_cooldown = float(_stats["fire_rate"])
	wants_to_fire.emit(target["node"],
		{
			"damage": _stats["damage"],
			"pierce": _stats["pierce"],
			"gold_multiplier": _stats["gold_multiplier"],
			"bonus_gold_per_kill": _stats["bonus_gold_per_kill"],
			"slow_factor": _stats["slow_factor"],
			"slow_duration_ms": _stats["slow_duration_ms"],
		},
		float(_stats["splash_radius"]))

func get_def() -> Dictionary:
	return _def
