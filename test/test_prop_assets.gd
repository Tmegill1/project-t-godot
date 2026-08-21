extends TestCase

# Props are free-standing sprites, so each needs a transparent margin all
# round - an opaque edge means the subject is clipped.
#
# The tight-bbox gate is the one that matters for gameplay.
# MapRenderer.prop_footprints() derives a tower-blocking radius from the
# texture's full dimensions, so transparent padding becomes invisible wall.
# The bake cuts each prop from its own connected component and pads back
# exactly 1px, which is what makes "radius from displayed size" true rather
# than merely conservative. See spec section 6.

const _BIOMES := ["forest", "ice", "desert"]
const _SLOTS := ["tree", "stone", "spike", "fire"]
const _ENDPOINTS := ["castle", "cave"]
const _MARGIN_ALPHA_MAX := 8

# After a 1px pad, the subject must fill everything else. Allowing a little
# slack for antialiasing at the extremes rather than demanding exactly 1px.
const _MAX_TRANSPARENT_BORDER := 3

# No free-standing object fills its own bounding box. Measured, the twelve
# props run from 0.35 to 0.62 opaque; a tiling fill or a crop taken from the
# middle of a larger drawing would sit near 1.0. This is the gate that
# replaces the Kenney-era "trimming shrank the 128px canvas" check, which
# only meant anything when every source shared one canvas size.
const _MAX_FILL := 0.85

func _image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _prop_image(biome: String, slot: String) -> Image:
	return _image("res://assets/art/%s/%s.png" % [biome, slot])

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

func test_every_prop_is_a_sprite_rather_than_a_slab_of_fill() -> bool:
	# The gate that catches a slot pointed at a tiling texture or at a crop
	# taken from the middle of a larger drawing. Both pass the margin and
	# tight-trim gates - the 1px pad manufactures a clean border around any
	# crop at all.
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			var opaque := 0
			for y in img.get_height():
				for x in img.get_width():
					if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
						opaque += 1
			var fill := float(opaque) / float(img.get_width() * img.get_height())
			assert_true(fill <= _MAX_FILL,
				"%s/%s is %.2f opaque" % [biome, slot, fill])
	return true

func test_a_biome_s_four_slots_are_four_different_sprites() -> bool:
	# An index typo in PROP_SLOTS that points two slots at the same decor
	# piece is otherwise invisible: the duplicate passes every gate above.
	#
	# Compared as raw bytes, not as a digest of a decoded string: a PNG hits a
	# zero byte inside its first header field, and PackedByteArray's
	# string conversions stop there - every PNG in the project hashes to the
	# same thing that way. PackedByteArray compares by value, so Array.has is
	# the whole comparison.
	for biome in _BIOMES:
		var seen := []
		for slot in _SLOTS:
			var bytes := FileAccess.get_file_as_bytes(
				"res://assets/art/%s/%s.png" % [biome, slot])
			assert_false(bytes.is_empty(), "%s/%s.png exists" % [biome, slot])
			if bytes.is_empty():
				continue
			assert_false(seen.has(bytes),
				"%s's %s is not a copy of another slot" % [biome, slot])
			seen.append(bytes)
	return true

func test_both_endpoints_decode_and_keep_a_clear_margin() -> bool:
	for name in _ENDPOINTS:
		var img := _image("res://assets/art/%s.png" % name)
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
		assert_true(peak <= _MARGIN_ALPHA_MAX, "%s.png edge peak %d" % [name, peak])
	return true

func test_the_cave_keeps_a_dark_mouth() -> bool:
	# The cave is a dark ellipse with rocks around its rim. Rocks stacked over
	# the mouth read as a rock pile instead - and that failure is invisible to
	# every other gate here, because a rock pile is free-standing, tightly
	# trimmed and not a slab of fill. So assert the mouth is still there: a
	# tenth of the sprite is near-black.
	var img := _image("res://assets/art/cave.png")
	assert_true(img != null, "cave.png decodes")
	if img == null:
		return true
	var dark := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r < 0.12 and c.g < 0.12 and c.b < 0.14:
				dark += 1
	var share := float(dark) / float(img.get_width() * img.get_height())
	assert_true(share >= 0.10, "the cave's mouth covers %.2f of its sprite" % share)
	return true
