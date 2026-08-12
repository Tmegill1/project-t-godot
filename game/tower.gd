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

var kind: StringName
var price_paid := 0
var grid_col := 0
var grid_row := 0

var _def := {}
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
	position = Grid.tile_to_world_center(col, row)

	var frame: int = _def["upgrade_frames"][0]
	var atlas := AtlasTexture.new()
	atlas.atlas = TOWER_SHEET
	atlas.region = Rect2(
		(frame % SHEET_COLUMNS) * FRAME_SIZE,
		(frame / SHEET_COLUMNS) * FRAME_SIZE,
		FRAME_SIZE, FRAME_SIZE)
	_sprite.texture = atlas
	var target_px := Tiles.TILE_SIZE * float(_def["size"])
	_sprite.scale = Vector2.ONE * (target_px / FRAME_SIZE)

	_range_indicator.radius = float(_def["range"])
	_range_indicator.tint = _def["color"]
	_range_indicator.visible = false

func set_range_visible(is_visible: bool) -> void:
	_range_visible = is_visible
	_range_indicator.visible = is_visible
	_range_indicator.queue_redraw()

func to_targeting_dict() -> Dictionary:
	return {
		"position": position, "range": float(_def["range"]),
		"priority": _priority, "detection": bool(_def["detection"]),
	}

## Called by the board each physics tick with the current enemy candidates.
func tick(delta_ms: float, candidates: Array) -> void:
	_cooldown -= delta_ms
	if _cooldown > 0.0:
		return
	var target = Targeting.select(to_targeting_dict(), candidates)
	if target == null:
		return
	_cooldown = float(_def["fire_rate"])
	wants_to_fire.emit(target["node"],
		{"damage": _def["damage"], "pierce": _def["pierce"]},
		float(_def["base_splash_radius"]))

func get_def() -> Dictionary:
	return _def
