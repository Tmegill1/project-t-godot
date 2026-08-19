extends TestCase

# Props are free-standing sprites, so each needs a transparent margin all
# round - an opaque edge means the subject is clipped.
#
# The tight-bbox gate is the one that matters for gameplay.
# MapRenderer.prop_footprints() derives a tower-blocking radius from the
# texture's full dimensions, so transparent padding becomes invisible wall.
# Kenney's raw tile130 fills 48% of its 128x128 canvas: untrimmed it would
# block over twice the area it draws. The bake trims to the alpha bbox and
# pads back exactly 1px, which is what makes "radius from displayed size" true
# rather than merely conservative. See spec section 6.

const _BIOMES := ["forest", "ice", "desert"]
const _SLOTS := ["tree", "stone", "spike", "fire"]
const _MARGIN_ALPHA_MAX := 8

# After a 1px pad, the subject must fill everything else. Allowing a little
# slack for antialiasing at the extremes rather than demanding exactly 1px.
const _MAX_TRANSPARENT_BORDER := 3

func _prop_image(biome: String, slot: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes("res://assets/kenney/%s/%s.png" % [biome, slot])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_every_prop_keeps_a_transparent_margin_on_all_four_edges() -> bool:
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
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
				"%s/%s edge peak alpha %d is a transparent margin" % [biome, slot, peak])
	return true

func test_every_prop_is_trimmed_tight_so_its_footprint_is_honest() -> bool:
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			var w := img.get_width()
			var h := img.get_height()
			var min_x := w
			var min_y := h
			var max_x := -1
			var max_y := -1
			for y in h:
				for x in w:
					if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
						min_x = mini(min_x, x)
						min_y = mini(min_y, y)
						max_x = maxi(max_x, x)
						max_y = maxi(max_y, y)
			assert_true(max_x >= 0, "%s/%s has visible pixels" % [biome, slot])
			if max_x < 0:
				continue
			assert_true(min_x <= _MAX_TRANSPARENT_BORDER,
				"%s/%s left border %d is tight" % [biome, slot, min_x])
			assert_true(min_y <= _MAX_TRANSPARENT_BORDER,
				"%s/%s top border %d is tight" % [biome, slot, min_y])
			assert_true(w - 1 - max_x <= _MAX_TRANSPARENT_BORDER,
				"%s/%s right border %d is tight" % [biome, slot, w - 1 - max_x])
			assert_true(h - 1 - max_y <= _MAX_TRANSPARENT_BORDER,
				"%s/%s bottom border %d is tight" % [biome, slot, h - 1 - max_y])
	return true

func test_trimming_actually_shrank_the_source_canvas() -> bool:
	# This is the only test in the suite that can catch a clipped,
	# non-free-standing source tile being chosen for PROPS. The margin and
	# tight-trim tests above cannot: _trim_and_pad's 1px pad manufactures a
	# clean transparent border around ANY crop, including one taken from art
	# that ran off the edge of its 128x128 canvas. A bush sliced off at the
	# canvas edge and padded with 1px of transparency still passes both those
	# gates, and renders with hard-cut edges. Every one of the 12 sources is
	# free-standing with genuine margin to trim, so a correct bake shrinks
	# all 12 below 128px in both dimensions; anything less means a bake that
	# forgot to trim, or a PROPS entry pointing at a tiling fill instead of a
	# sprite.
	var shrunk := 0
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			if img.get_width() < 128 or img.get_height() < 128:
				shrunk += 1
	assert_eq(shrunk, _BIOMES.size() * _SLOTS.size(), "every prop was trimmed below 128px")
	return true
