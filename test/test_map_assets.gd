extends TestCase

# Acceptance gates for the pre-sliced map atlas: assets/map/*.png, cut out of
# the reference sprite sheet by tools/slice_atlas.gd.
#
# Task 15 shipped six of its eight tiles wrong - artwork running straight off
# a rect edge, neighbouring props bleeding in, and a transparent strip down the
# ground textures that drew a dark seam at every tile boundary on the board.
# Three separate passes inspected those tiles by eye and reported them clean.
# The point of this file is that nobody has to be believed about it again: the
# properties below are re-derived from the committed PNGs on every suite run.
#
# GATE 1 - PROP TILES are drawn as free-standing sprites, so the outermost row
# and column on all four edges must be an effectively transparent margin
# (max alpha <= _MARGIN_ALPHA_MAX). An opaque edge means one of exactly two
# defects: the rect clips the subject, or a neighbouring prop bled in.
#
# GATE 2 - GROUND TILES are seamless textures drawn edge-to-edge across every
# tile of the board, so every pixel must be opaque; a single transparent
# column repeats as a visible seam 322 times across the map. "Opaque" here is
# >= 249 rather than == 255 because 255 is not available: the largest fully
# opaque (alpha == 255) square anywhere in the 1024x1536 source sheet is 6x6
# px, so no 64x64 window with min alpha 255 exists to be cut. 249 is the best
# minimum achievable over any 64x64 window in either swatch, and both shipped
# tiles hit exactly that.
#
# _EDGE_PIXEL_BUDGET covers the five edges that the source sheet makes
# impossible to cut cleanly (the castle is packed against neighbouring rocks on
# one side and clipped by the sheet's own border on the other; the campfire's
# neighbour dips into the only rows that clear its flame; the cave keeps one
# antialiased pixel of its own rock wall). Those edges are not exempted - they
# are held to a budget on how many pixels of the edge may be opaque, and each
# budget sits far below what the corresponding broken tile used to measure, so
# a regression still turns this red. tools/slice_atlas.gd carries the
# measurement behind every entry.
#
# If one of these goes red: re-cut the rect in tools/slice_atlas.gd. Do not
# raise a budget to make the test pass - a budget is a record of a limit in the
# artwork, not a tolerance for a worse crop.

const _MAP_DIR := "res://assets/map/"

const _PROP_TILES := ["tree", "stone", "castle", "cave", "spike", "fire"]
const _GROUND_TILES := ["grass", "path"]
const _EDGE_NAMES := ["left", "right", "top", "bottom"]

const _MARGIN_ALPHA_MAX := 8
const _GROUND_ALPHA_MIN := 249

# tile -> edge -> how many pixels of that edge may be opaque.
# Measured on the committed tiles at the time of writing:
#   castle left   37 of 305   right 34 of 305
#   cave   right   1 of 216
#   fire   top    11 of 141   right  5 of  92
# For contrast, the broken tiles this replaced measured castle left 68 / right
# 116 of 302, and fire left 39 / right 40 of 89.
const _EDGE_PIXEL_BUDGET := {
	"castle": {"left": 45, "right": 40},
	"cave": {"right": 2},
	"fire": {"top": 15, "right": 8},
}

# Reads the committed PNG bytes rather than the imported Texture2D, so the
# gates measure the file that is in git rather than whatever .godot/imported
# happens to hold. (The two were verified identical after a fresh
# `godot --headless --import`; reading the file drops the dependency on that.)
# Returns null if the file is missing or is not a decodable PNG - every caller
# asserts on the result, per the helper-crash gap documented in run_tests.gd.
func _tile_image(tile: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(_MAP_DIR + tile + ".png")
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

# For each edge: the highest alpha found in that outermost row/column, how many
# of its pixels are above the transparent-margin threshold, and how long it is.
func _edge_profile(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var samples := {"left": [], "right": [], "top": [], "bottom": []}
	for y in h:
		samples["left"].append(_alpha8(img, 0, y))
		samples["right"].append(_alpha8(img, w - 1, y))
	for x in w:
		samples["top"].append(_alpha8(img, x, 0))
		samples["bottom"].append(_alpha8(img, x, h - 1))

	var profile := {}
	for edge in samples:
		var alphas: Array = samples[edge]
		var peak := 0
		var opaque := 0
		for sample in alphas:
			var alpha: int = sample
			peak = maxi(peak, alpha)
			if alpha > _MARGIN_ALPHA_MAX:
				opaque += 1
		profile[edge] = {"max": peak, "opaque": opaque, "length": alphas.size()}
	return profile

func test_prop_tiles_keep_a_transparent_margin_on_every_unbudgeted_edge() -> bool:
	for tile in _PROP_TILES:
		var name: String = tile
		var img := _tile_image(name)
		assert_true(img != null, "%s.png loads as a decodable PNG" % name)
		if img == null:
			continue
		var profile := _edge_profile(img)
		var budgets: Dictionary = _EDGE_PIXEL_BUDGET.get(name, {})
		for edge in _EDGE_NAMES:
			var edge_name: String = edge
			if budgets.has(edge_name):
				continue
			var peak: int = profile[edge_name]["max"]
			assert_true(peak <= _MARGIN_ALPHA_MAX,
				("%s.png: %s edge must be a transparent margin, max alpha %d (limit %d). " +
				"An opaque edge means the rect clips the subject or a neighbouring prop " +
				"bled in - fix the rect in tools/slice_atlas.gd.") % [name, edge_name, peak, _MARGIN_ALPHA_MAX])
	return true

func test_budgeted_prop_edges_stay_inside_their_documented_pixel_budget() -> bool:
	for tile in _EDGE_PIXEL_BUDGET:
		var name: String = tile
		var img := _tile_image(name)
		assert_true(img != null, "%s.png loads as a decodable PNG" % name)
		if img == null:
			continue
		var profile := _edge_profile(img)
		var budgets: Dictionary = _EDGE_PIXEL_BUDGET[name]
		for edge in budgets:
			var edge_name: String = edge
			var budget: int = budgets[edge_name]
			var opaque: int = profile[edge_name]["opaque"]
			var length: int = profile[edge_name]["length"]
			assert_true(opaque <= budget,
				("%s.png: %s edge has %d of %d pixels opaque, budget %d. This edge cannot be " +
				"cut clean (see tools/slice_atlas.gd) but it has got worse - re-cut the rect " +
				"rather than raising the budget.") % [name, edge_name, opaque, length, budget])
	return true

# A budget silently disables the strict margin check for whichever edge it
# names, so a typo in the table would be a hole in gate 1 that nothing else
# reports. This pins the table to real tile and edge names.
func test_the_edge_budget_table_only_names_real_prop_tiles_and_edges() -> bool:
	for tile in _EDGE_PIXEL_BUDGET:
		var name: String = tile
		assert_true(name in _PROP_TILES, "edge budget names a real prop tile: %s" % name)
		var budgets: Dictionary = _EDGE_PIXEL_BUDGET[name]
		for edge in budgets:
			var edge_name: String = edge
			assert_true(edge_name in _EDGE_NAMES, "%s edge budget names a real edge: %s" % [name, edge_name])
	return true

func test_ground_tiles_are_opaque_across_their_whole_area() -> bool:
	for tile in _GROUND_TILES:
		var name: String = tile
		var img := _tile_image(name)
		assert_true(img != null, "%s.png loads as a decodable PNG" % name)
		if img == null:
			continue
		var lowest := 255
		var lowest_at := Vector2i.ZERO
		for y in img.get_height():
			for x in img.get_width():
				var alpha := _alpha8(img, x, y)
				if alpha < lowest:
					lowest = alpha
					lowest_at = Vector2i(x, y)
		assert_true(lowest >= _GROUND_ALPHA_MIN,
			("%s.png is drawn edge-to-edge over the whole board, so every pixel must be " +
			"opaque: lowest alpha %d at %s (floor %d). Anything less draws a seam at every " +
			"tile boundary - move the rect into the interior of the swatch.") % [name, lowest, lowest_at, _GROUND_ALPHA_MIN])
	return true

# Ties the committed PNGs back to the rects that are supposed to have produced
# them. The gates above cannot tell a correct crop from a differently-placed
# one that happens to have clean edges; this catches a rect edited in
# slice_atlas.gd without re-running it, and a PNG replaced without updating the
# rect. It reads the slicer's own FRAMES table rather than restating it.
func test_every_tile_is_the_size_of_the_slicer_rect_that_produced_it() -> bool:
	var slicer: GDScript = load("res://tools/slice_atlas.gd")
	var usable := slicer != null and slicer.can_instantiate()
	assert_true(usable, "tools/slice_atlas.gd loads and parses")
	if not usable:
		return true

	var frames: Array = slicer.get_script_constant_map().get("FRAMES", [])
	assert_eq(frames.size(), _PROP_TILES.size() + _GROUND_TILES.size(),
		"the slicer declares exactly one rect per shipped tile")

	var seen: Array[String] = []
	for frame in frames:
		var entry: Dictionary = frame
		var name: String = entry["name"]
		var rect: Rect2i = entry["rect"]
		seen.append(name)
		var img := _tile_image(name)
		assert_true(img != null, "%s.png loads as a decodable PNG" % name)
		if img == null:
			continue
		assert_eq(Vector2i(img.get_width(), img.get_height()), rect.size,
			"%s.png is the size of its slicer rect - re-run tools/slice_atlas.gd if the rect moved" % name)

	for tile in _PROP_TILES + _GROUND_TILES:
		var name: String = tile
		assert_true(name in seen, "the slicer still produces %s.png" % name)
	return true

# GATE 5 - MIPMAPS. Unlike everything above, this one deliberately inspects the
# *imported* Texture2D rather than the committed PNG bytes: mipmap generation is
# an import setting (mipmaps/generate in the .import sidecar), so it has no
# representation in the source file at all and reading the PNG cannot see it.
#
# Every one of these tiles is minified on screen, several of them hard:
# stone.png is 216px wide drawn into 48px (22%), tree.png 165px tall into 48px
# (29%), castle.png 305px into 144px (47%). Minifying that far with no mipmap
# chain means each output pixel samples a handful of source texels out of the
# dozens it covers, so which texels win depends on subpixel position - the
# classic shimmer/aliasing on detailed downscaled art. The mipmap chain is what
# gives the sampler a correctly pre-averaged level to read instead.
#
# The chain is only half the fix: map_renderer.gd must also select a filter that
# actually samples it (TEXTURE_FILTER_LINEAR_WITH_MIPMAPS), which
# test_map_renderer.gd pins. Generating mipmaps nobody reads changes nothing on
# screen, so neither test is sufficient alone.
#
# If this goes red after an asset is re-cut: set mipmaps/generate=true in that
# tile's .import and re-run `godot --headless --import`. Do not delete the gate.
func test_every_map_tile_is_imported_with_a_mipmap_chain() -> bool:
	for tile in _PROP_TILES + _GROUND_TILES:
		var name: String = tile
		var tex: Texture2D = load(_MAP_DIR + name + ".png")
		assert_true(tex != null, "%s.png imports to a Texture2D" % name)
		if tex == null:
			continue
		var img: Image = tex.get_image()
		assert_true(img != null, "%s.png's imported texture exposes its image" % name)
		if img == null:
			continue
		assert_true(img.has_mipmaps(),
			("%s.png is minified on the board (%dx%d source) and needs a mipmap chain to " +
			"downscale without aliasing - set mipmaps/generate=true in its .import and " +
			"re-run `godot --headless --import`.") % [name, img.get_width(), img.get_height()])
	return true
