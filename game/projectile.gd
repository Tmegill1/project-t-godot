class_name Projectile
extends Node2D

## Projectile view: homes on a target node and reports its own arrival by
## signal. The board resolves the actual hit (damage, splash, pierce) - this
## class only decides when it has arrived and what it is carrying.

signal hit(target_node: Node2D, source: Dictionary, splash: float)

const ARC_HEIGHT := 28.0
const HIT_RADIUS := 6.0

var _target: Node2D
var _source := {}
var _speed := 500.0
var _splash := 0.0
var _arcs := false
var _origin := Vector2.ZERO
var _total_distance := 1.0
# Guards _physics_process against a tick landing between add_child() and
# launch(): before launch() runs, _target is null, and without this guard
# `is_instance_valid(_target)` would be false and silently free the
# projectile before it ever got its target. Same class of bug as Enemy's
# `sim.is_empty()` guard, and for the same reason - a crash inside
# _physics_process aborts only that call frame, so this failure mode is
# silent rather than loud.
var _launched := false
var _dot_base := Vector2.ZERO

@onready var _dot: ColorRect = $Dot

func _ready() -> void:
	# Captured once, before launch() can run: the Dot's centred position
	# (Vector2(-3, -3), a ColorRect's position is its top-left corner) is the
	# zero point the arc offsets from. Assigning straight into
	# _dot.position.y (as the brief's code does) overwrites that centring
	# instead of offsetting it, so every arcing shot's dot jumps down by 3px
	# the moment it starts moving. Offsetting from a captured base fixes it.
	_dot_base = _dot.position

func launch(target: Node2D, source: Dictionary, speed: float,
		arcs: bool, splash: float) -> void:
	_target = target
	_source = source
	_speed = speed
	_arcs = arcs
	_splash = splash
	_origin = global_position
	_total_distance = maxf(1.0, _origin.distance_to(target.global_position))
	_launched = true

func _physics_process(delta: float) -> void:
	if not _launched:
		return
	if not is_instance_valid(_target):
		queue_free()
		return

	var to_target := _target.global_position - global_position
	var step := _speed * delta
	if to_target.length() <= step or to_target.length() <= HIT_RADIUS:
		hit.emit(_target, _source, _splash)
		queue_free()
		return

	global_position += to_target.normalized() * step

	# Arcing is purely how the shot is drawn. It still homes and still hits;
	# a mortar firing flat bolts read as a slow gun rather than as artillery.
	if _arcs:
		var travelled := _origin.distance_to(global_position)
		var t: float = clampf(travelled / _total_distance, 0.0, 1.0)
		_dot.position.y = _dot_base.y - sin(t * PI) * ARC_HEIGHT
