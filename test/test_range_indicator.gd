extends TestCase

# _draw()'s draw_circle/draw_arc calls cannot be exercised in this headless,
# frameless harness: Godot rejects draw_* calls made outside an actual
# NOTIFICATION_DRAW pass with a low-level engine error, not a GDScript
# exception, and there is no public API to introspect a CanvasItem's queued
# draw commands (confirmed by probing RangeIndicator.new()._draw() directly
# before writing this file). What IS checkable, following the same
# technique test_tower.gd/test_projectile.gd use for their own constants:
# the alpha values _draw() would pass to draw_circle/draw_arc are plain
# script-level consts on a class_name script, directly readable with no
# tree, node, or draw pass.
func test_fill_and_ring_alpha_constants_match_the_brief() -> bool:
	assert_eq(RangeIndicator._FILL_ALPHA, 0.12, "the range circle's fill alpha")
	assert_eq(RangeIndicator._RING_ALPHA, 0.6, "the range circle's ring alpha")
	return true
