extends TestCase

# Acceptance gates for the baked ground tiles under assets/kenney/<biome>/.
#
# Two independent properties are checked, and the second is the one that
# matters most. Corner classification alone passes for BOTH of the pack's two
# tile families - the one that draws the road as a small overlay lobe, and the
# one that draws it as the base with a ground lobe. They classify identically
# by corner colour and tile completely differently. The road-fraction gate is
# what separates them; without it a plausible-looking table renders mismatched
# wave phases at every concave corner. See spec section 7.2.

const _BIOMES := ["forest", "ice", "desert"]
const _MASKS := [0, 1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15]
const _SINGLE_CORNER := [1, 2, 4, 8]

# Ground/road terrain per biome, as the RGB the bake writes. Ice's ground is
# the recoloured snow, which is why it is not sand.
const _TERRAIN := {
	"forest": {"ground": Vector3(45, 202, 111), "road": Vector3(187, 128, 68)},
	"desert": {"ground": Vector3(229, 213, 179), "road": Vector3(187, 128, 68)},
	"ice": {"ground": Vector3(236, 242, 248), "road": Vector3(136, 162, 164)},
}

const _CORNER_TOL_SQ := 3000.0
const _FRACTION_TOL_SQ := 4000.0
const _MAX_SINGLE_CORNER_ROAD_FRACTION := 0.25

func _blend_image(biome: String, mask: int) -> Image:
	var path := "res://assets/kenney/%s/blend_%02d.png" % [biome, mask]
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _rgb(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(c.r, c.g, c.b) * 255.0

# Which of the biome's two terrains a colour is nearer to, or "" if neither is
# within tolerance.
func _nearest(sample: Vector3, biome: String, tol_sq: float) -> String:
	var t: Dictionary = _TERRAIN[biome]
	var dg: float = sample.distance_squared_to(t["ground"])
	var dr: float = sample.distance_squared_to(t["road"])
	if minf(dg, dr) > tol_sq:
		return ""
	return "road" if dr < dg else "ground"

func test_every_biome_ships_every_mask_the_pack_supplies() -> bool:
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _blend_image(biome, mask)
			assert_true(img != null, "%s/blend_%02d.png decodes" % [biome, mask])
	return true

func test_the_two_diagonal_masks_are_deliberately_absent() -> bool:
	# The pack has no diagonal-only tiles in any pairing. Baking one would mean
	# it came from somewhere it should not have. Biomes.blend_texture is what
	# resolves the gap at runtime (Task 2), not a file on disk.
	for biome in _BIOMES:
		for mask in [6, 9]:
			var path := "res://assets/kenney/%s/blend_%02d.png" % [biome, mask]
			assert_false(FileAccess.file_exists(path),
				"%s/blend_%02d.png must not exist" % [biome, mask])
	return true

func test_blend_tiles_are_square_and_fully_opaque() -> bool:
	# Ground draws edge to edge across the board; one transparent pixel repeats
	# as a seam at every tile boundary.
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _blend_image(biome, mask)
			assert_true(img != null, "%s/blend_%02d.png decodes" % [biome, mask])
			if img == null:
				continue
			assert_eq(img.get_width(), 128, "%s/blend_%02d width" % [biome, mask])
			assert_eq(img.get_height(), 128, "%s/blend_%02d height" % [biome, mask])
			var min_alpha := 255
			for y in range(0, 128, 4):
				for x in range(0, 128, 4):
					min_alpha = mini(min_alpha, int(round(img.get_pixel(x, y).a * 255.0)))
			assert_eq(min_alpha, 255, "%s/blend_%02d is fully opaque" % [biome, mask])
	return true

func test_each_tiles_four_corners_match_the_mask_in_its_filename() -> bool:
	# Re-derives the property the bake claims, from the committed bytes.
	var offsets := [Vector2i(3, 3), Vector2i(115, 3), Vector2i(3, 115), Vector2i(115, 115)]
	var bits := [1, 2, 4, 8]
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _blend_image(biome, mask)
			assert_true(img != null, "%s/blend_%02d.png decodes" % [biome, mask])
			if img == null:
				continue
			for i in 4:
				var o: Vector2i = offsets[i]
				var acc := Vector3.ZERO
				for dy in 10:
					for dx in 10:
						acc += _rgb(img, o.x + dx, o.y + dy)
				var kind := _nearest(acc / 100.0, biome, _CORNER_TOL_SQ)
				var expected := "road" if (mask & int(bits[i])) != 0 else "ground"
				assert_eq(kind, expected,
					"%s/blend_%02d corner %d is %s" % [biome, mask, i, expected])
	return true

func test_single_corner_tiles_draw_the_road_as_a_small_lobe() -> bool:
	# THE FAMILY GATE. A single-corner tile from the correct family measures
	# about 0.04; the wrong family measures about 0.46. Anything near a half
	# means the bake picked the inverted family and the map will not tile.
	for biome in _BIOMES:
		for mask in _SINGLE_CORNER:
			var img := _blend_image(biome, mask)
			assert_true(img != null, "%s/blend_%02d.png decodes" % [biome, mask])
			if img == null:
				continue
			var road := 0
			var total := 0
			for y in range(0, 128, 2):
				for x in range(0, 128, 2):
					total += 1
					if _nearest(_rgb(img, x, y), biome, _FRACTION_TOL_SQ) == "road":
						road += 1
			var fraction := float(road) / float(total)
			assert_true(fraction < _MAX_SINGLE_CORNER_ROAD_FRACTION,
				"%s/blend_%02d road fraction %f is a small lobe" % [biome, mask, fraction])
	return true

func test_ice_ground_was_recoloured_and_is_not_the_packs_sand() -> bool:
	# A silently skipped recolour would leave ice looking like desert.
	var img := _blend_image("ice", 0)
	assert_true(img != null, "ice/blend_00.png decodes")
	if img == null:
		return true
	var sample := _rgb(img, 64, 64)
	assert_true(sample.distance_squared_to(Vector3(229, 213, 179)) > 400.0,
		"ice ground is not the pack's sand, measured %v" % sample)
	assert_true(sample.distance_squared_to(Vector3(236, 242, 248)) < 400.0,
		"ice ground is snow, measured %v" % sample)
	return true
