extends TestCase

# The goal and spawn markers, composed from pack pieces because Kenney ships
# neither a castle nor a cave. They are drawn 3 tiles wide by
# MapRenderer._draw_endpoints and are shared across biomes.
#
# Unlike the old assets/map/castle.png and cave.png, these are composed on a
# clear canvas rather than cut out of a packed sheet, so there is no
# neighbouring artwork to bleed in and no _EDGE_PIXEL_BUDGET. Every edge is
# held to a clean transparent margin. If one of these goes red, fix the
# composition in tools/bake_kenney.gd - do not add a budget.

const _ENDPOINTS := ["castle", "cave"]
const _MARGIN_ALPHA_MAX := 8

func _endpoint_image(name: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes("res://assets/kenney/%s.png" % name)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_both_endpoints_decode_and_carry_visible_art() -> bool:
	for name in _ENDPOINTS:
		var img := _endpoint_image(name)
		assert_true(img != null, "%s.png decodes" % name)
		if img == null:
			continue
		var opaque := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
					opaque += 1
		assert_true(opaque > 0, "%s.png is not blank" % name)
	return true

func test_both_endpoints_keep_a_clean_transparent_margin() -> bool:
	for name in _ENDPOINTS:
		var img := _endpoint_image(name)
		assert_true(img != null, "%s.png decodes" % name)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var peak := 0
		for y in h:
			peak = maxi(peak, maxi(_alpha8(img, 0, y), _alpha8(img, w - 1, y)))
		for x in w:
			peak = maxi(peak, maxi(_alpha8(img, x, 0), _alpha8(img, x, h - 1)))
		assert_true(peak <= _MARGIN_ALPHA_MAX,
			"%s.png edge peak alpha %d is a transparent margin" % [name, peak])
	return true

func test_the_two_endpoints_are_visually_distinct() -> bool:
	# A composition bug that wrote the same pieces twice would leave the player
	# unable to tell the spawn from the goal.
	var castle := _endpoint_image("castle")
	var cave := _endpoint_image("cave")
	assert_true(castle != null, "castle.png decodes")
	assert_true(cave != null, "cave.png decodes")
	if castle == null or cave == null:
		return true
	var differs := castle.get_width() != cave.get_width() \
		or castle.get_height() != cave.get_height()
	if not differs:
		for y in range(0, castle.get_height(), 4):
			for x in range(0, castle.get_width(), 4):
				if castle.get_pixel(x, y) != cave.get_pixel(x, y):
					differs = true
					break
			if differs:
				break
	assert_true(differs, "castle and cave are different images")
	return true
