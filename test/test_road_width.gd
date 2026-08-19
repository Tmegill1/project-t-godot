extends TestCase

# Ties sim/placement.gd's no-build corridor to the width the art actually
# draws. Kenney draws roads as ~3-tile corridors; this map's are one tile, so
# the blend lobes land at about 23px and PATH_HALF_WIDTH follows them down to
# 14 rather than staying at the 26 the 48px reference road justified.
#
# Measured off the committed blend tiles rather than hardcoded, so a re-bake
# that changes the road's drawn width turns this red instead of silently
# reintroducing an invisible wall.

const _ROAD_RGB := Vector3(187.0, 128.0, 68.0)   # forest road is dirt
const _TOL_SQ := 4000.0

func _blend_image(mask: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/kenney/forest/blend_%02d.png" % mask)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

# How far the road reaches down a full-width blend, in source pixels.
func _road_rows(img: Image) -> int:
	var rows := 0
	for y in img.get_height():
		var c := img.get_pixel(img.get_width() / 2, y)
		var s := Vector3(c.r, c.g, c.b) * 255.0
		if s.distance_squared_to(_ROAD_RGB) < _TOL_SQ:
			rows += 1
	return rows

func test_the_no_build_corridor_matches_the_road_the_art_draws() -> bool:
	# Mask 3 is road along the top two corners: half the road's width, drawn
	# into one tile. Doubling it and scaling 128px source to a 48px tile gives
	# the road's rendered width.
	var img := _blend_image(3)
	assert_true(img != null, "forest/blend_03.png decodes")
	if img == null:
		return true
	var scale := float(Tiles.TILE_SIZE) / float(img.get_height())
	var drawn := float(_road_rows(img)) * scale * 2.0
	assert_true(drawn > 12.0, "the road draws something, measured %f" % drawn)
	assert_almost_eq(Placement.PATH_HALF_WIDTH, drawn / 2.0, 3.0,
		"PATH_HALF_WIDTH tracks half the drawn road width of %f" % drawn)
	return true

func test_path_half_width_is_the_value_the_spec_amendment_names() -> bool:
	assert_almost_eq(Placement.PATH_HALF_WIDTH, 14.0, 0.001,
		"PATH_HALF_WIDTH is 14 after the art swap")
	return true

func test_min_tower_spacing_was_not_disturbed() -> bool:
	# Tower art keeps its footprint, so the spacing tuned against it still
	# holds. Guards against a well-meant sweep retuning both constants.
	assert_almost_eq(Placement.MIN_TOWER_SPACING, 44.0, 0.001,
		"MIN_TOWER_SPACING is unchanged at 44")
	return true
