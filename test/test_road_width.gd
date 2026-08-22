extends TestCase

# Ties sim/placement.gd's no-build corridor to the width the illustrated road
# actually draws.
#
# The Kenney-era version of this test read the road off one blend tile using
# a single hardcoded dirt RGB and a tolerance. That does not survive this
# art: the illustrated road is painted and textured, so there is no single
# "road colour" a tolerance band can safely bracket. Instead every pixel is
# classified to the NEARER of two material palettes - road and surround -
# read directly from tools/bake_sheet.gd's ROAD_PALETTES, the same table the
# bake itself recolours desert and ice against, so this test can never invent
# a value the bake disagrees with.
#
# Measured off the committed res://assets/art/forest/road_05.png, the
# composed north-south straight (bit order N=1,E=2,S=4,W=8 - see
# tools/bake_sheet.gd's ROAD_MASKS and _compose_road). For every row, the
# longest contiguous run of road-classified pixels is the road's drawn width
# at that row; the MEDIAN run across all rows is what PATH_HALF_WIDTH is
# tuned to. Median rather than mean or max: _compose_road leaves the cross's
# central hub untouched when it masks off the absent E/W arms, so a handful
# of rows near the tile's vertical centre read far wider than the through
# road actually is - the median shrugs those off where a mean or a max would
# not.
#
# A source pixel is not a world pixel: MapRenderer crops TILE_BLEED off every
# edge of the tile before stretching what remains to fill one TILE_SIZE cell
# (see MapRenderer._place_tile), so the conversion divides by the CROPPED
# width, not the raw source width - using the raw width understates the
# road by about 12%.

const BakeSheet := preload("res://tools/bake_sheet.gd")

func _forest_road_straight() -> Image:
	var bytes := FileAccess.get_file_as_bytes("res://assets/art/forest/road_05.png")
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

# The longest run, per row, of pixels nearer `road` than `surround`. Ties
# (equidistant) count as surround, matching "nearer to the road palette"
# read literally.
func _road_runs(img: Image, surround: Color, road: Color) -> Array[int]:
	var surround_v := Vector3(surround.r, surround.g, surround.b) * 255.0
	var road_v := Vector3(road.r, road.g, road.b) * 255.0
	var runs: Array[int] = []
	for y in img.get_height():
		var run := 0
		var best := 0
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var sample := Vector3(c.r, c.g, c.b) * 255.0
			if sample.distance_squared_to(road_v) < sample.distance_squared_to(surround_v):
				run += 1
				best = maxi(best, run)
			else:
				run = 0
		runs.append(best)
	return runs

func _median(values: Array[int]) -> float:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var n := sorted_values.size()
	if n % 2 == 1:
		return float(sorted_values[n / 2])
	return float(sorted_values[n / 2 - 1] + sorted_values[n / 2]) / 2.0

func test_the_no_build_corridor_matches_the_road_the_art_draws() -> bool:
	var img := _forest_road_straight()
	assert_true(img != null, "assets/art/forest/road_05.png decodes")
	if img == null:
		return true

	var palette: Dictionary = BakeSheet.ROAD_PALETTES[&"forest"]
	var runs := _road_runs(img, palette["surround"], palette["road"])
	var drawn_source_px := _median(runs)

	# Task 8's crop: a source pixel is worth TILE_SIZE / (source_width -
	# TILE_BLEED * 2) world pixels, not the naive TILE_SIZE / source_width -
	# see the file header.
	var px_to_world := float(Tiles.TILE_SIZE) \
		/ (float(img.get_width()) - MapRenderer.TILE_BLEED * 2.0)
	var drawn_world := drawn_source_px * px_to_world
	assert_true(drawn_world > 8.0, "the road draws something, measured %f world px" % drawn_world)
	var half_road := drawn_world / 2.0

	# Two bounds, not an equality: PATH_HALF_WIDTH is half the drawn road plus
	# a deliberate margin, so pinning it to `half_road` with a tolerance wide
	# enough to contain the margin also accepts values BELOW the road's own
	# half-width - a no-build corridor narrower than the road it guards, which
	# would let towers be built on painted road. The lower bound is the real
	# invariant; the upper bound keeps the margin from growing into a wall.
	assert_true(Placement.PATH_HALF_WIDTH >= half_road,
		"PATH_HALF_WIDTH %f is never narrower than the drawn road's half-width %f"
			% [Placement.PATH_HALF_WIDTH, half_road])
	assert_true(Placement.PATH_HALF_WIDTH <= half_road + 4.0,
		"PATH_HALF_WIDTH %f stays within a small margin of the drawn road's half-width %f"
			% [Placement.PATH_HALF_WIDTH, half_road])
	return true

func test_path_half_width_is_the_value_the_spec_amendment_names() -> bool:
	# Pins the constant against a careless sweep, independent of whether the
	# measurement above still passes. 11 is the illustrated road's measured
	# half-width (8.89 world px) rounded to the nearest pixel plus the
	# constant's standing 2px margin - see sim/placement.gd's doc comment.
	assert_almost_eq(Placement.PATH_HALF_WIDTH, 11.0, 0.001,
		"PATH_HALF_WIDTH is 11 after the illustrated art swap")
	return true

func test_min_tower_spacing_was_not_disturbed() -> bool:
	# Tower art keeps its footprint, so the spacing tuned against it still
	# holds. Guards against a well-meant sweep retuning both constants.
	assert_almost_eq(Placement.MIN_TOWER_SPACING, 44.0, 0.001,
		"MIN_TOWER_SPACING is unchanged at 44")
	return true
