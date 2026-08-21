extends TestCase

# Acceptance gates for the ground tiles cut from the illustrated sheet.
#
# The sheet has NO alpha channel - every sprite sits on an opaque navy
# background at (9, 22, 28) - so extraction keys that colour out. Sprite
# outlines sit close to it, which makes the key threshold a real tunable
# rather than a formality: too tight eats outlines, too loose leaves a dark
# halo that shows as fringing once the tile is drawn over another.
#
# The margin gate below is also what catches a misaligned extraction. Rows are
# cut on a fixed pitch of 67 from a per-row origin; if an origin is off by a
# few pixels the crop carries a sliver of its neighbour, which shows up as
# opaque pixels on an edge that should be clear.

const _BIOMES := ["forest", "desert", "ice"]
const _TILES_PER_ROW := 6
const _MARGIN_ALPHA_MAX := 8

func _ground(biome: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/%s/ground_%d.png" % [biome, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_every_biome_ships_six_ground_tiles() -> bool:
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
	return true

func test_ground_tiles_have_no_unkeyed_background_left() -> bool:
	# Not "no dark pixels" - the tiles' own outlines and painted shadows are
	# legitimately dark, and an earlier version of this gate failed every tile
	# for having them. What must not survive is the SHEET BACKGROUND: an opaque
	# pixel sitting within the key's own tolerance of (9, 22, 28) means the key
	# never ran, or ran against the wrong colour.
	var background := Vector3(9.0, 22.0, 28.0)
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
			if img == null:
				continue
			var survivors := 0
			for y in range(0, img.get_height(), 2):
				for x in range(0, img.get_width(), 2):
					var c := img.get_pixel(x, y)
					if c.a <= 0.5:
						continue
					if (Vector3(c.r, c.g, c.b) * 255.0).distance_squared_to(background) <= 250.0:
						survivors += 1
			assert_eq(survivors, 0,
				"%s/ground_%d has %d unkeyed background pixels" % [biome, i, survivors])
	return true

func test_ground_tiles_keep_a_clear_margin_so_no_neighbour_bled_in() -> bool:
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
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
				"%s/ground_%d edge peak %d - a neighbour bled in or the origin is off"
					% [biome, i, peak])
	return true

func test_the_three_biomes_are_visibly_different_ground() -> bool:
	# Guards a descriptor copy-paste that points two biomes at one sheet row.
	var means := {}
	for biome in _BIOMES:
		var img := _ground(biome, 0)
		assert_true(img != null, "%s/ground_0.png decodes" % biome)
		if img == null:
			continue
		var acc := Vector3.ZERO
		var n := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					acc += Vector3(c.r, c.g, c.b)
					n += 1
		means[biome] = acc / maxf(1.0, float(n))
	# Green DOMINANCE, not absolute green: desert's sand is bright enough that
	# its mean green exceeds forest's darker olive, so comparing the channel
	# directly is false. What separates them is green relative to red.
	assert_true(means["forest"].y - means["forest"].x > means["desert"].y - means["desert"].x,
		"forest is greener relative to red than desert")
	assert_true(means["ice"].z > means["desert"].z, "ice is bluer than desert")
	return true
