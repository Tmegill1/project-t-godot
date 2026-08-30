class_name MortarExplosion
extends Sprite2D

## The mortar's impact blast: a six-frame explosion played where its shell
## lands, sized to the blast it actually did.
##
## MORTAR ONLY, and named for it deliberately. Splash is not the same thing as
## artillery - Basic reaches 45px of splash at its Fragmentation tier and 75px
## at Saturation, and Long Range reaches 55px at Shellburst - so a "spawn this
## whenever splash > 0" rule would draw a shell burst over a crystal bolt and
## an arrow. The board gates this on the firing tower's kind for that reason;
## see GameBoard._on_projectile_hit.
##
## If another tower kind ever earns its own impact art, it gets its own scene
## rather than a generalisation of this one. A shared "ImpactEffect" would
## have to choose a texture at runtime, and the kind -> art join is exactly
## the sort of thing this project keeps in a table rather than in a branch.

## The sheet is 768x128: six 128px frames laid out horizontally. FRAME_SIZE is
## the frame's own width, which is what the scale below divides into a
## requested diameter - not the width of the whole sheet.
const FRAME_COUNT := 6
const FRAME_DURATION := 0.07
const FRAME_SIZE := 128.0

var _elapsed := 0.0

## Sizes the blast to the radius that actually did the damage, so an upgraded
## mortar visibly covers more ground. The mortar's splash grows 55 -> 70 -> 95
## -> 130 across its tiers, and the explosion grows with it.
func setup(splash_radius: float) -> void:
	frame = 0
	_elapsed = 0.0
	var diameter := maxf(1.0, splash_radius * 2.0)
	scale = Vector2.ONE * diameter / FRAME_SIZE

func _physics_process(delta: float) -> void:
	_elapsed += delta
	var next_frame := int(_elapsed / FRAME_DURATION)
	if next_frame >= FRAME_COUNT:
		queue_free()
		return
	frame = next_frame
