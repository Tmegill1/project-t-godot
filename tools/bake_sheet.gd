extends SceneTree

# Cuts the illustrated sprite sheet into committed assets under assets/art/.
#
#   godot --headless --script tools/bake_sheet.gd
#   godot --headless --import
#   git checkout -- project.godot
#
# Reads reference/illustrated-sheet/sheet.png, which is gitignored - the
# extracted subset is what lives in git, matching how the Kenney bake worked.
#
# ============================================================================
# HOW THIS SHEET IS SEGMENTED, AND WHY NOT AUTOMATICALLY
# ============================================================================
# The sheet is a labelled reference sheet, not a packed atlas: section headers,
# row labels and a legend are baked into the pixels, and the sections are not
# on one grid. Two automatic approaches were tried and both fail:
#
#   Flood fill with a tight threshold FRAGMENTS sprites, because their dark
#   outlines sit close to the navy background. Loosening it and dilating
#   MERGES the densely packed enemy rows into blobs.
#
#   Pure projection segmentation works on the enemy rows but not on the
#   terrain rows, where adjacent tiles touch and cannot be split on a gap.
#
# So each row is cut on a measured fixed pitch from a measured origin, and the
# margin gate in the tests is what proves an origin is right: a crop that is
# off by a few pixels carries a sliver of its neighbour, which shows as opaque
# pixels on an edge that should be clear. Tune an origin until that gate
# passes; never relax the gate.
# ============================================================================

const SHEET := "res://reference/illustrated-sheet/sheet.png"
const BACKGROUND := Vector3(9.0, 22.0, 28.0)

## Squared distance from the background beyond which a pixel is kept. Measured:
## the sheet's own background varies by a few units, and sprite outlines sit
## close to it, so this is deliberately tight and the margin gate is what
## proves it is not too tight.
const KEY_TOLERANCE_SQ := 250.0

const TILE := 64
const PITCH := 67

## biome -> {row origin x, row top y}. The sheet's "grass" row is the forest
## biome. Origins are measured; pitch is uniform across all four rows.
##
## x=77 is shared by all three rows: it is the left edge of tile 0, sitting
## just past the row's own label text ("TERRAIN TILES" / "GRASS" / "DESERT" /
## "ICE"), which occupies the columns before it. y differs per row because
## each row's real content is taller than TILE=64 (67-74px, more for ice's
## crystal spikes) and starts at a different depth below its label. All five
## numbers were measured directly off the vendored sheet.png by scanning for
## background-colour columns/rows (not guessed), and test_ground_tiles.gd's
## margin gate is what proves them right: an origin off by even a few pixels
## carries a sliver of the neighbouring tile or the row's own label text into
## the crop, which the gate catches as an opaque edge pixel.
const GROUND_ROWS := {
	&"forest": {"x": 77, "y": 619},
	&"desert": {"x": 77, "y": 788},
	&"ice": {"x": 77, "y": 873},
}
const GROUND_TILES_PER_ROW := 6

func _init() -> void:
	var sheet := Image.load_from_file(SHEET)
	assert(sheet != null, "sheet.png not found - see the header for where it goes")
	sheet.convert(Image.FORMAT_RGBA8)
	_bake_ground(sheet)
	_bake_roads(sheet)
	print("bake_sheet: done")
	quit()

## Replaces the opaque navy background with transparency.
func _key(img: Image) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			var d := Vector3(c.r, c.g, c.b) * 255.0
			if d.distance_squared_to(BACKGROUND) <= KEY_TOLERANCE_SQ:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out

## Crops to the alpha bounding box, then pads 1px of transparency back.
##
## Both halves matter. The crop keeps a sprite's displayed size honest, which
## MapRenderer.prop_footprints depends on. The 1px pad is what keeps the
## margin gate satisfiable: a bare bbox crop has opaque edge pixels by
## construction.
func _trim(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 8.0 / 255.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	assert(max_x >= 0, "sprite is empty after keying - the key tolerance is too loose")
	var box := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	var out := Image.create_empty(box.size.x + 2, box.size.y + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, box, Vector2i(1, 1))
	return out

## One cell cut from the sheet, keyed and trimmed.
func _cell(sheet: Image, x: int, y: int) -> Image:
	var cell := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	cell.blit_rect(sheet, Rect2i(x, y, TILE, TILE), Vector2i.ZERO)
	return _trim(_key(cell))

func _bake_ground(sheet: Image) -> void:
	for biome in GROUND_ROWS:
		var row: Dictionary = GROUND_ROWS[biome]
		var dir := "res://assets/art/%s" % biome
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for i in GROUND_TILES_PER_ROW:
			_cell(sheet, int(row["x"]) + PITCH * i, int(row["y"])).save_png(
				"%s/ground_%d.png" % [dir, i])
		print("bake_sheet: %s ground x%d" % [biome, GROUND_TILES_PER_ROW])


## The path row. There is only ONE - the terrain block's four rows are GRASS,
## PATH, DESERT and ICE, and only PATH holds road pieces; the other three are
## ground variants. Desert and ice roads are RECOLOURED from this row.
##
## Origin follows the 85px row cadence Task 1 established: grass 619, path 704,
## desert 788, ice 873. Slot 4 is the cross, and it is the ONLY slot used.
const ROAD_ROW := {"x": 77, "y": 704}
const ROAD_CROSS_SLOT := 4

## Every road mask is composed from the cross by masking off the arms it does
## not connect.
##
## WHY NOT USE THE SHEET'S OWN PIECES: the row holds a solid plaza, two curves,
## a T and two crosses, and probing their edges at insets 10, 12 and 14 yields
## only masks {5, 7, 15} every time - BOTH curves read as 7, not as corners.
## Mask 3 is unreachable by rotating any of those, and the demo map has four
## corners, so slot classification cannot draw the map at all. The cross has
## four arms and surround material in all four corners, so mirroring a corner
## over an absent arm produces any of the sixteen masks from one source piece.
## Verified by composing all of them and looking.
const ROAD_MASKS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

## Where each biome's road and surround land after recolouring.
##
## Forest is IDENTITY - its targets equal the source materials - so the
## artist's own piece ships untouched.
##
## Desert's road is dark packed earth rather than the sheet's dirt, and that is
## not a style preference. The sheet's dirt (168, 119, 55) and its sand ground
## (170, 123, 62) are 15 units apart while the dirt's own shading spread is 18,
## so a dirt road on sand is both unclassifiable by the recolour AND invisible
## on screen. Darkening it restores 83 units of separation, matching forest's.
##
## Every pair below must stay farther apart than the source material's spread.
## If a future palette narrows that gap, the recolour cannot tell the two
## materials apart and the tile reads as one murky blob.
const ROAD_PALETTES := {
	&"forest": {"surround": Color8(58, 69, 16), "road": Color8(168, 119, 55)},
	&"desert": {"surround": Color8(170, 123, 62), "road": Color8(105, 76, 42)},
	&"ice": {"surround": Color8(91, 145, 190), "road": Color8(200, 220, 235)},
}

## The two materials in the path row, measured as the DOMINANT tone of each -
## the mean of pixels classified by green dominance, not by a warm-pixel
## filter. An earlier pair of values was 43 units low on the road because that
## filter swept in the dirt's shadow and vein texture, which is exactly the
## error that made desert unclassifiable.
const SOURCE_SURROUND := Vector3(57.8, 68.7, 15.5)
const SOURCE_ROAD := Vector3(168.5, 119.2, 55.4)

## Builds one mask by masking the cross's absent arms with adjacent corner
## material, then softening the paste seams.
##
## The mirror is what keeps the patch in the piece's own palette and edging -
## a flat fill would read as a hole. Bit order is N=1, E=2, S=4, W=8.
func _compose_road(cross: Image, mask: int) -> Image:
	var out: Image = cross.duplicate()
	# The trimmed cross is nearly but not exactly square (grass fringe trims
	# unevenly per side), so width and height each get their own third rather
	# than sharing one - a single square "arm" indexed past the shorter side.
	var w := out.get_width()
	var h := out.get_height()
	var aw := w / 3
	var ah := h / 3
	if not mask & 1:
		_patch_arm(out, cross, Rect2i(aw, 0, aw, ah), Rect2i(0, 0, aw, ah))
	if not mask & 4:
		_patch_arm(out, cross, Rect2i(aw, h - ah, aw, ah), Rect2i(0, h - ah, aw, ah))
	if not mask & 8:
		_patch_arm(out, cross, Rect2i(0, ah, aw, ah), Rect2i(0, 0, aw, ah))
	if not mask & 2:
		_patch_arm(out, cross, Rect2i(w - aw, ah, aw, ah), Rect2i(w - aw, 0, aw, ah))
	_soften_seams(out)
	return out

## Copies `from` (a corner of the cross) over `into` (an arm), mirrored so the
## grass edging runs the right way.
func _patch_arm(out: Image, cross: Image, into: Rect2i, from: Rect2i) -> void:
	for y in into.size.y:
		for x in into.size.x:
			var src := cross.get_pixel(
				from.position.x + mini(from.size.x - 1, x),
				from.position.y + mini(from.size.y - 1, y))
			out.set_pixel(into.position.x + x, into.position.y + y, src)

## Averages each pixel with its neighbours where the composition left a hard
## edge, so the pasted corners do not read as rectangles.
func _soften_seams(img: Image) -> void:
	var src: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var acc := Vector4.ZERO
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var c := src.get_pixel(x + dx, y + dy)
					acc += Vector4(c.r, c.g, c.b, c.a)
			acc /= 9.0
			var centre := src.get_pixel(x, y)
			# Only where the neighbourhood disagrees with the centre - leaves
			# flat interior material untouched.
			if Vector3(centre.r, centre.g, centre.b).distance_squared_to(
					Vector3(acc.x, acc.y, acc.z)) > 0.004:
				img.set_pixel(x, y, Color(acc.x, acc.y, acc.z, centre.a))

## Recolours both materials in ONE pass.
##
## Classification comes from the ORIGINAL pixel, never from a partially
## recoloured one: a two-pass version re-touched pixels the first pass had
## already shifted - once surround moves toward sand it can sit nearer the road
## palette - which blew ice's arms out to near-white.
func _recolour_road(img: Image, palette: Dictionary) -> Image:
	var out: Image = img.duplicate()
	var road_goal := Vector3(palette["road"].r, palette["road"].g, palette["road"].b) * 255.0
	var sur_goal := Vector3(palette["surround"].r, palette["surround"].g,
		palette["surround"].b) * 255.0
	for y in out.get_height():
		for x in out.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var v := Vector3(c.r, c.g, c.b) * 255.0
			var is_road := v.distance_squared_to(SOURCE_ROAD) \
				< v.distance_squared_to(SOURCE_SURROUND)
			var shifted := (road_goal + (v - SOURCE_ROAD)) if is_road \
				else (sur_goal + (v - SOURCE_SURROUND))
			out.set_pixel(x, y, Color(
				clampf(shifted.x / 255.0, 0.0, 1.0),
				clampf(shifted.y / 255.0, 0.0, 1.0),
				clampf(shifted.z / 255.0, 0.0, 1.0), c.a))
	return out

func _bake_roads(sheet: Image) -> void:
	var cross := _cell(sheet,
		int(ROAD_ROW["x"]) + PITCH * ROAD_CROSS_SLOT, int(ROAD_ROW["y"]))
	for biome in ROAD_PALETTES:
		var dir := "res://assets/art/%s" % biome
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for mask in ROAD_MASKS:
			var piece := _compose_road(cross, int(mask))
			_recolour_road(piece, ROAD_PALETTES[biome]).save_png(
				"%s/road_%02d.png" % [dir, int(mask)])
		print("bake_sheet: %s roads x%d" % [biome, ROAD_MASKS.size()])
