class_name RangeIndicator
extends Node2D

## Purely visual range circle a tower shows while selected. Never consulted
## for targeting or hit resolution - Targeting.select owns range decisions;
## this only draws what the tower tells it to.

const _FILL_ALPHA := 0.12
const _RING_ALPHA := 0.6

var radius := 0.0
var tint := Color.WHITE

func _draw() -> void:
	if not visible or radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius, Color(tint.r, tint.g, tint.b, _FILL_ALPHA))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, _RING_ALPHA), 1.5)
