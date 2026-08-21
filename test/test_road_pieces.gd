extends TestCase

# Gates for the road pieces. Each piece is named by the connection mask it is
# drawn for, and this file re-derives that mask from the committed pixels -
# so the naming is proved rather than trusted, the same way the Kenney blend
# table was.
#
# Bit order is N=1, E=2, S=4, W=8, and it is load-bearing: MapRenderer builds
# the same mask from a cell's orthogonal neighbours and looks the piece up by
# it. A transposed bit order produces a plausible-looking but wrong road.
#
# Mask 5 (north-south straight) has no source piece on the sheet and is
# COMPOSED from the cross - see tools/bake_sheet.gd. It is gated here like any
# other piece precisely because it is manufactured.

const _BIOMES := ["forest", "desert", "ice"]
const _MASKS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

func _road(biome: String, mask: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/%s/road_%02d.png" % [biome, mask])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

## Where each biome's road and surround should have landed after the bake's
## recolouring. Only the grass row holds road pieces on this sheet, so desert
## and ice are recoloured from it - which is exactly why this test cannot use
## a "road is warmer" heuristic: desert's road AND its surround are both warm,
## and the road is the darker of the two.
const _PALETTES := {
	"forest": {"surround": Vector3(58, 69, 16), "road": Vector3(168, 119, 55)},
	"desert": {"surround": Vector3(170, 123, 62), "road": Vector3(105, 76, 42)},
	"ice": {"surround": Vector3(91, 145, 190), "road": Vector3(200, 220, 235)},
}

## Whether the middle of the given edge is road rather than surround, decided
## by which of that biome's two palettes the sampled material is nearer to.
func _edge_is_road(img: Image, biome: String, edge: String) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var inset := maxi(6, mini(w, h) / 5)
	var centre := {
		"N": Vector2i(w / 2, inset), "S": Vector2i(w / 2, h - inset),
		"W": Vector2i(inset, h / 2), "E": Vector2i(w - inset, h / 2),
	}[edge] as Vector2i
	var acc := Vector3.ZERO
	var n := 0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := img.get_pixel(
				clampi(centre.x + dx, 0, w - 1), clampi(centre.y + dy, 0, h - 1))
			if c.a > 0.5:
				acc += Vector3(c.r, c.g, c.b) * 255.0
				n += 1
	if n == 0:
		return false
	var mean := acc / float(n)
	var palette: Dictionary = _PALETTES[biome]
	return mean.distance_squared_to(palette["road"]) \
		< mean.distance_squared_to(palette["surround"])

func test_every_biome_ships_every_road_piece() -> bool:
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _road(biome, mask)
			assert_true(img != null, "%s/road_%02d.png decodes" % [biome, mask])
	return true

func test_each_piece_connects_exactly_where_its_name_says() -> bool:
	var bits := {"N": 1, "E": 2, "S": 4, "W": 8}
	for biome in _BIOMES:
		for mask in _MASKS:
			if mask == 0 or mask == 15:
				continue  # no arms and all arms: the edge probe cannot separate them
			var img := _road(biome, mask)
			assert_true(img != null, "%s/road_%02d.png decodes" % [biome, mask])
			if img == null:
				continue
			var derived := 0
			for edge in bits:
				if _edge_is_road(img, biome, edge):
					derived |= int(bits[edge])
			assert_eq(derived, mask,
				"%s/road_%02d connects %d - the piece and its name disagree"
					% [biome, mask, derived])
	return true

func test_the_composed_straight_is_road_north_south_and_surround_east_west() -> bool:
	# Mask 5 is manufactured, so it gets its own assertion rather than only
	# riding on the generic one above.
	for biome in _BIOMES:
		var img := _road(biome, 5)
		assert_true(img != null, "%s/road_05.png decodes" % biome)
		if img == null:
			continue
		assert_true(_edge_is_road(img, biome, "N"), "%s straight is road at the north edge" % biome)
		assert_true(_edge_is_road(img, biome, "S"), "%s straight is road at the south edge" % biome)
		assert_false(_edge_is_road(img, biome, "E"), "%s straight is surround at the east edge" % biome)
		assert_false(_edge_is_road(img, biome, "W"), "%s straight is surround at the west edge" % biome)
	return true

func test_road_pieces_have_no_unkeyed_background_left() -> bool:
	# Not "no dark pixels". The pieces' own outlines and painted shadows are
	# legitimately dark, and forest keeps them unshifted because its palette is
	# identity - so a brightness rule fails every forest piece while passing the
	# recoloured biomes, which is a property of the recolour, not of the key.
	# What must not survive is the SHEET BACKGROUND: an opaque pixel within the
	# key's own tolerance of (9, 22, 28) means the key never ran.
	var background := Vector3(9.0, 22.0, 28.0)
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _road(biome, mask)
			assert_true(img != null, "%s/road_%02d.png decodes" % [biome, mask])
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
				"%s/road_%02d has %d unkeyed background pixels" % [biome, mask, survivors])
	return true
