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
	_bake_tower_atlas(sheet)
	_bake_walk_frames()
	var decor := _decor_sprites(sheet)
	print("bake_sheet: %d decor sprites found" % decor.size())
	_bake_props(decor)
	_bake_endpoints(sheet, decor)
	print("bake_sheet: done")
	quit()

## Replaces the opaque navy background with transparency.
## Clears every pixel within KEY_TOLERANCE_SQ of `background` to transparent.
##
## The background is a parameter because the project keeps two sheets and they
## do not agree: the first is (9, 22, 28) and the walk-and-death sheet is
## (6.5, 21.5, 30.0). Close enough to look identical, far enough apart that
## keying one with the other's value leaves a halo.
func _key(img: Image, background: Vector3) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			var d := Vector3(c.r, c.g, c.b) * 255.0
			if d.distance_squared_to(background) <= KEY_TOLERANCE_SQ:
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
	return _trim(_key(cell, BACKGROUND))

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
##
## chroma_keep is how much of a pixel's colour offset from its source material
## survives the shift. The recolour preserves each pixel's offset so shading
## and texture come through, but an offset carries HUE as well as brightness -
## so at 1.0 the sheet's grass verge arrives in the desert as green speckles
## and in the ice as a green band down both sides of a snow road, on an
## all-blue board. Measured: at 1.0 the ice road pieces reach a green
## dominance of +41 where ice's own ground tiles never exceed +3, and the
## desert's reach +39 against a ground maximum of +25 that is cacti. Keeping
## a quarter of the offset holds the shading and drops both to 0.
##
## Forest keeps 1.0 and must: its palette is identity, so at 1.0 the shift is
## exactly the artist's own pixel and the forest pieces come out byte-for-byte
## unchanged. Any other value there would repaint art that needs no repainting.
const ROAD_PALETTES := {
	&"forest": {
		"surround": Color8(58, 69, 16), "road": Color8(168, 119, 55),
		"chroma_keep": 1.0,
	},
	&"desert": {
		"surround": Color8(170, 123, 62), "road": Color8(105, 76, 42),
		"chroma_keep": 0.25,
	},
	&"ice": {
		"surround": Color8(91, 145, 190), "road": Color8(200, 220, 235),
		"chroma_keep": 0.25,
	},
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
		_patch_arm(out, cross, Rect2i(aw, 0, aw, ah), Rect2i(0, 0, aw, ah), true, false)
	if not mask & 4:
		_patch_arm(out, cross, Rect2i(aw, h - ah, aw, ah), Rect2i(0, h - ah, aw, ah),
			true, false)
	if not mask & 8:
		_patch_arm(out, cross, Rect2i(0, ah, aw, ah), Rect2i(0, 0, aw, ah), false, true)
	if not mask & 2:
		_patch_arm(out, cross, Rect2i(w - aw, ah, aw, ah), Rect2i(w - aw, 0, aw, ah),
			false, true)
	_soften_seams(out)
	return out

## How far the card's painted border reaches in from a tile's edge.
##
## MEASURED across all 66 ground and road PNGs in all three biomes, probing
## inward from each edge at six positions per tile: the run of near-black
## pixels, including _trim's 1px pad, never exceeds 5.
const CARD_BORDER := 5

## Copies a corner of the cross over an absent arm, mirrored away from the
## corner's own outer border.
##
## The mirror is the whole point and it used to be missing - the doc said
## "mirrored" and the code clamped. Clamping walks from the corner's OUTER
## edge inward, so the first thing it copies into the tile's interior is the
## card's near-black border, and every composed piece carried a black slot
## across it. Mirroring walks from the corner's INNER edge outward instead, so
## the arm continues the corner it touches and the sampling never reaches the
## border at all. The clamp at CARD_BORDER is what guarantees that: an arm is
## a third of the tile and the corner's clean interior is a little narrower,
## so the last few columns repeat one interior column rather than running off
## the end.
func _patch_arm(out: Image, cross: Image, into: Rect2i, from: Rect2i,
		mirror_x: bool, mirror_y: bool) -> void:
	for y in into.size.y:
		for x in into.size.x:
			var sx := maxi(CARD_BORDER, from.size.x - 1 - x) if mirror_x \
				else mini(from.size.x - 1, x)
			var sy := maxi(CARD_BORDER, from.size.y - 1 - y) if mirror_y \
				else mini(from.size.y - 1, y)
			out.set_pixel(into.position.x + x, into.position.y + y,
				cross.get_pixel(from.position.x + sx, from.position.y + sy))

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
	var keep := float(palette["chroma_keep"])
	for y in out.get_height():
		for x in out.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var v := Vector3(c.r, c.g, c.b) * 255.0
			var is_road := v.distance_squared_to(SOURCE_ROAD) \
				< v.distance_squared_to(SOURCE_SURROUND)
			# The offset is split so the brightness half survives whole and
			# the colour half can be damped - see ROAD_PALETTES on chroma_keep.
			# At keep 1.0 the two halves recombine to the original offset
			# exactly, which is what keeps forest byte-identical.
			var offset := (v - SOURCE_ROAD) if is_road else (v - SOURCE_SURROUND)
			var brightness := (offset.x + offset.y + offset.z) / 3.0
			var colour := offset - Vector3.ONE * brightness
			var goal := road_goal if is_road else sur_goal
			var shifted := goal + Vector3.ONE * brightness + colour * keep
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

const ATLAS_COLUMNS := 5
const ATLAS_ROWS := 4
const ATLAS_FRAME := 96
const ATLAS_INSET := 6

## The rows the tower art occupies, below the "LVL n" captions and above the
## rule that closes the panel.
##
## MEASURED. Every tower panel's row profile is the same four runs: a rule at
## 8..10, the panel heading at 19..34, the captions at 46..60, and the art at
## 63..211. An earlier version of this pair started the band at 40 and ran 165
## rows, which swallowed the captions and left _isolate_centre to strip them.
## It cannot: the vertical rules dividing the panels (x = 8..10, 429..430,
## 862..864, 1233..1235, 1526..1527) are opaque at every row of the band, so
## in any crop that touches one, no row is ever fully transparent and the
## search for a separator under the caption never terminates anywhere useful.
## Two of the sixteen frames baked their "LVL 4" caption into the sprite.
const TOWER_BAND_Y := 63
const TOWER_BAND_H := 149

## kind -> the five x boundaries cutting its panel into four level cells.
##
## MEASURED from the captions, not read off the image. The caption row
## segments cleanly into four runs in every panel and each caption is centred
## over its tower; the tower art does not segment, because the Mage and
## Barracks towers touch. So the cuts are the midpoints between consecutive
## caption centres, bounded by the panel's own vertical rules. Two earlier
## versions of this table listed x offsets read by eye and both were wrong -
## the first by up to 19px, and both misplaced the Archer panel by about 15px.
##
## The sheet's tower types map onto the game's kinds by role: Archer is the
## cheap all-rounder, Cannon the fast one, Mage the splash one, Barracks the
## long-range one.
const TOWER_CELLS := {
	&"basic": [11, 108, 208, 308, 428],
	&"fast": [431, 541, 644, 747, 861],
	&"mortar": [865, 964, 1054, 1142, 1232],
	&"long": [1236, 1310, 1378, 1451, 1524],
}

## Clears anything separated from the cell's centre by a fully transparent
## column or row.
##
## Even cut on the caption midpoints, a cell can catch a disconnected sliver of
## its neighbour - the Cannon panel's first three levels each do. That matters
## because _trim takes the alpha bounding box of ALL content, so one stray
## sliver at the edge stretches the box and the sprite lands wrong in its
## frame. Walking out from the centre to the first empty line keeps only the
## tower this cell is about.
##
## This works here and did not before only because TOWER_BAND_Y now starts
## below the captions: the crop no longer contains a panel rule, so its rows
## can actually be empty.
func _isolate_centre(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var out: Image = img.duplicate()
	var cx := w / 2
	var cy := h / 2
	var empty_col := func(x: int) -> bool:
		for y in h:
			if img.get_pixel(x, y).a > 8.0 / 255.0:
				return false
		return true
	var empty_row := func(y: int) -> bool:
		for x in w:
			if img.get_pixel(x, y).a > 8.0 / 255.0:
				return false
		return true
	var left := 0
	for x in range(cx, -1, -1):
		if empty_col.call(x):
			left = x
			break
	var right := w - 1
	for x in range(cx, w):
		if empty_col.call(x):
			right = x
			break
	var top := 0
	for y in range(cy, -1, -1):
		if empty_row.call(y):
			top = y
			break
	var bottom := h - 1
	for y in range(cy, h):
		if empty_row.call(y):
			bottom = y
			break
	for y in h:
		for x in w:
			if x < left or x > right or y < top or y > bottom:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out

## One level cut from its panel, keyed, isolated and trimmed.
func _tower_sprite(sheet: Image, kind: StringName, level: int) -> Image:
	var cuts: Array = TOWER_CELLS[kind]
	var x: int = int(cuts[level])
	var width: int = int(cuts[level + 1]) - x
	var region := Image.create_empty(width, TOWER_BAND_H, false, Image.FORMAT_RGBA8)
	region.blit_rect(sheet, Rect2i(x, TOWER_BAND_Y, width, TOWER_BAND_H), Vector2i.ZERO)
	return _trim(_isolate_centre(_key(region, BACKGROUND)))

func _bake_tower_atlas(sheet: Image) -> void:
	# Cut all sixteen before resizing any of them: they share one scale factor,
	# so the largest has to be known first.
	var sprites := {}
	var largest := 1
	for kind in TOWER_CELLS:
		var levels: Array[Image] = []
		for level in 4:
			var sprite := _tower_sprite(sheet, kind, level)
			levels.append(sprite)
			largest = maxi(largest, maxi(sprite.get_width(), sprite.get_height()))
		sprites[kind] = levels
	# One factor across all sixteen rather than one per sprite. Fitting each
	# sprite to the frame on its own longest dimension throws away the upgrade
	# read: a level that grows taller faster than it grows wider absorbs the
	# extra height into a smaller scale and lands *smaller* than the level
	# below it. The four kinds' own fit factors land between 0.60 and 0.66 -
	# the sheet already draws every tower at one world scale.
	#
	# The inset is what keeps the largest sprite off its frame's edges; every
	# other sprite clears them by more.
	var factor := float(ATLAS_FRAME - ATLAS_INSET * 2) / float(largest)
	var out := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for kind in TOWER_CELLS:
		var frames: Array = Towers.DEFS[kind]["upgrade_frames"]
		for level in 4:
			var sprite: Image = sprites[kind][level]
			sprite.resize(maxi(1, int(sprite.get_width() * factor)),
				maxi(1, int(sprite.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			var frame: int = int(frames[level])
			var ox := (frame % ATLAS_COLUMNS) * ATLAS_FRAME
			var oy := (frame / ATLAS_COLUMNS) * ATLAS_FRAME
			var at := Vector2i(ox + (ATLAS_FRAME - sprite.get_width()) / 2,
				oy + (ATLAS_FRAME - sprite.get_height()) / 2)
			out.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), at)
	out.save_png("res://assets/towers.png")
	print("bake_sheet: tower atlas")

const WALK_SHEET := "res://reference/illustrated-sheet/walk-and-death.png"
const WALK_BACKGROUND := Vector3(6.5, 21.5, 30.0)

## kind -> the sprite band its frames are cut from. MEASURED: each creature is
## a name label above a band of twelve frames, and the bands do not touch.
##
## Frames 0-7 are the walk cycle and 8-11 the death sequence, uniformly across
## all five rows - checked by rendering every frame of every row.
const WALK_ROWS := {
	&"goblin": {"y0": 78, "y1": 164},
	&"ogre": {"y0": 593, "y1": 710},
	&"bat": {"y0": 789, "y1": 881},
	&"_unused/shaman": {"y0": 242, "y1": 351},
	&"_unused/troll": {"y0": 425, "y1": 532},
}
const WALK_FRAMES := 8
const WALK_MIN_RUN := 12

## A run wider than this multiple of its row's median holds two frames whose
## art touches, and is split rather than dropped. Three of the five rows have
## exactly one such pair.
const WALK_SPLIT_RATIO := 1.5

## A frame covering less than this fraction of its row's largest is broken art,
## not a small pose. The bat's eighth walk frame is an orphaned wing with no
## body; nothing else in any row comes near the threshold. Dropped on area
## rather than on index so a regenerated sheet cannot silently lose a good
## frame to a hard-coded skip.
const WALK_MIN_AREA_RATIO := 0.45

## The twelve frames of one row, in order, with broken art dropped.
func _walk_row_frames(sheet: Image, y0: int, y1: int) -> Array:
	var w := sheet.get_width()
	var present := []
	for x in w:
		var any := false
		for y in range(y0, y1 + 1):
			var c := sheet.get_pixel(x, y)
			if Vector3(c.r, c.g, c.b).distance_squared_to(WALK_BACKGROUND / 255.0) \
					* 65025.0 > KEY_TOLERANCE_SQ:
				any = true
				break
		present.append(any)
	var runs := []
	var start := -1
	for i in present.size():
		if present[i] and start < 0:
			start = i
		elif not present[i] and start >= 0:
			if i - start >= WALK_MIN_RUN:
				runs.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0 and present.size() - start >= WALK_MIN_RUN:
		runs.append(Vector2i(start, present.size() - 1))

	var widths := []
	for r in runs:
		widths.append(int(r.y) - int(r.x) + 1)
	widths.sort()
	var median: float = float(widths[widths.size() / 2])

	# Split a run holding two touching frames at its sparsest interior column,
	# searched between 30% and 70% of its width so the cut cannot land on an
	# edge and shave a sliver off instead of dividing the pair.
	var split := []
	for r in runs:
		var width: int = r.y - r.x + 1
		if float(width) <= median * WALK_SPLIT_RATIO:
			split.append(r)
			continue
		var best := -1
		var best_count := 1 << 30
		for k in range(int(width * 0.30), int(width * 0.70)):
			var count: int = 0
			for y in range(y0, y1 + 1):
				var c := sheet.get_pixel(r.x + k, y)
				if Vector3(c.r, c.g, c.b).distance_squared_to(WALK_BACKGROUND / 255.0) \
						* 65025.0 > KEY_TOLERANCE_SQ:
					count += 1
			if count < best_count:
				best_count = count
				best = k
		split.append(Vector2i(r.x, r.x + best - 1))
		split.append(Vector2i(r.x + best, r.y))
	split.sort_custom(func(a, b): return a.x < b.x)

	var cut := []
	var areas := []
	for r in split:
		var frame := Image.create_empty(int(r.y) - int(r.x) + 1, y1 - y0 + 1, false, Image.FORMAT_RGBA8)
		frame.blit_rect(sheet, Rect2i(int(r.x), y0, int(r.y) - int(r.x) + 1, y1 - y0 + 1), Vector2i.ZERO)
		var keyed := _trim(_key(frame, WALK_BACKGROUND))
		cut.append(keyed)
		var opaque := 0
		for y in keyed.get_height():
			for x in keyed.get_width():
				if keyed.get_pixel(x, y).a > 8.0 / 255.0:
					opaque += 1
		areas.append(opaque)
	var largest := 1
	for a in areas:
		largest = maxi(largest, int(a))
	# Each surviving frame carries the index it had BEFORE anything was
	# dropped, so the caller can tell which half lost it rather than guessing.
	# The guess this replaced assumed a dropped frame came out of the walk
	# half - true of the bat, the only row it currently applies to, and
	# silently wrong for a row that loses a death frame instead: the walk half
	# would stay whole and the rule would still lop its last frame into the
	# death sequence, making death_0 a walking pose and discarding a real
	# death frame. Nothing downstream could see that, because the counts stay
	# self-consistent.
	var out := []
	for i in cut.size():
		if float(areas[i]) >= float(largest) * WALK_MIN_AREA_RATIO:
			out.append({"index": i, "image": cut[i]})
	return out

func _bake_walk_frames() -> void:
	var sheet := Image.load_from_file(WALK_SHEET)
	if sheet == null:
		push_error("cannot load %s - see the header for where it goes" % WALK_SHEET)
		return
	# Same conversion _init does for the other sheet: it arrives RGB8 because
	# the PNG carries no alpha, and blit_rect refuses to mix formats.
	sheet.convert(Image.FORMAT_RGBA8)
	for kind in WALK_ROWS:
		var row: Dictionary = WALK_ROWS[kind]
		var dir := "res://assets/art/enemies/%s" % kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var frames := _walk_row_frames(sheet, int(row["y0"]), int(row["y1"]))
		var walk := 0
		var death := 0
		for entry in frames:
			var item: Dictionary = entry
			# Split on the frame's ORIGINAL index, so a dropped frame shortens
			# whichever half it came out of and never moves the boundary. The
			# sheet draws the walk cycle first and the death sequence after it,
			# uniformly across all five rows.
			if int(item["index"]) < WALK_FRAMES:
				(item["image"] as Image).save_png("%s/walk_%d.png" % [dir, walk])
				walk += 1
			else:
				(item["image"] as Image).save_png("%s/death_%d.png" % [dir, death])
				death += 1
		print("bake_sheet: %s %d walk, %d death" % [kind, walk, death])

const DECOR_X0 := 1237
const DECOR_X1 := 1525
const DECOR_Y0 := 216
const DECOR_Y1 := 740

## The floor a connected component has to clear to be a decor sprite rather
## than a letter of the "EXTRAS / DECOR" heading. MEASURED: the column holds 42
## components, the 29 above this floor are exactly the 29 decor objects and the
## 13 below it are exactly the heading's letters.
const DECOR_MIN_W := 18
const DECOR_MIN_H := 18
const DECOR_MIN_AREA := 250

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Which decor sprite fills which prop slot, per biome, as an index into
## _decor_sprites' reading order. The slot NAMES are fixed by MapRenderer's
## scatter rules and do not change; only what sits behind each one is
## per-biome.
##
## The indices in reading order are: 0 signpost, 1 pine, 2 flat stump, 3 leafy
## tree, 4 banner, 5 crates, 6 rock pair, 7 fallen log, 8 boulder cluster,
## 9 mossy stump, 10 bush, 11 stone spire, 12 mushrooms, 13 grey rock,
## 14 berry plant, 15 handcart, 16 planks, 17 barrel, 18 white flowers,
## 19 campfire, 20 mossy stump, 21 spike fence, 22 wooden cross, 23 skull and
## crossbones, 24 orange flowers, 25 rock outcrop, 26 mossy stump, 27 stump,
## 28 small skull. Every one of the twelve below was rendered at the 48px the
## renderer draws it into and checked by eye; the sheet has no cactus, so
## desert's tree is a dead stump and its spike is bones.
const PROP_SLOTS := {
	&"forest": {&"tree": 3, &"stone": 8, &"spike": 21, &"fire": 19},
	&"ice": {&"tree": 1, &"stone": 6, &"spike": 11, &"fire": 19},
	&"desert": {&"tree": 2, &"stone": 25, &"spike": 23, &"fire": 19},
}

const ENDPOINT_CANVAS := 256

## The keep, and the banners and crates flanking it. Pieces are placed by
## CENTRE rather than by top-left so a one-pixel change in a source's trimmed
## size does not walk the composition sideways. {decor, px, centre, flip}.
const CASTLE_KEEP_PX := 180
const CASTLE_KEEP_CENTRE := Vector2i(127, 120)
const CASTLE_PIECES := [
	{"decor": 4, "px": 70, "centre": Vector2i(36, 155), "flip": false},
	{"decor": 4, "px": 70, "centre": Vector2i(219, 155), "flip": true},
	{"decor": 5, "px": 56, "centre": Vector2i(58, 216), "flip": false},
	{"decor": 5, "px": 56, "centre": Vector2i(198, 216), "flip": true},
]

## The mouth, then three rocks around its RIM - not over it. Stacking rocks on
## top of the mouth makes a rock pile and a mouth wider than the rocks makes a
## black blob; both were composed and rendered before this arrangement.
const CAVE_MOUTH := Rect2i(50, 78, 156, 124)
const CAVE_MOUTH_COLOUR := Color8(11, 13, 17)
const CAVE_PIECES := [
	{"decor": 25, "px": 96, "centre": Vector2i(128, 80), "flip": false},
	{"decor": 13, "px": 72, "centre": Vector2i(62, 128), "flip": false},
	{"decor": 6, "px": 84, "centre": Vector2i(198, 132), "flip": true},
]

## Every decor sprite in the column, in reading order: rows top to bottom,
## sprites left to right within a row.
##
## Connected components, not a band scan. The column's objects are staggered,
## so no row inside it is ever empty - a band scan returns the whole column as
## one 283x411 blob. Each sprite is cut from its own component's MASK rather
## than its bounding rectangle, so a neighbour overlapping the rectangle does
## not ride along, and gets the same 1px transparent pad _trim gives everything
## else.
func _decor_sprites(sheet: Image) -> Array:
	var w := DECOR_X1 - DECOR_X0
	var h := DECOR_Y1 - DECOR_Y0
	var region := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	region.blit_rect(sheet, Rect2i(DECOR_X0, DECOR_Y0, w, h), Vector2i.ZERO)
	region = _key(region, BACKGROUND)
	var solid := []
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = region.get_pixel(x, y).a > 8.0 / 255.0
	var labels := PackedInt32Array()
	labels.resize(w * h)
	var found := []
	var next_label := 0
	for sy in h:
		for sx in w:
			var seed := sy * w + sx
			if not solid[seed] or labels[seed] != 0:
				continue
			next_label += 1
			labels[seed] = next_label
			var stack := [seed]
			var min_x := sx
			var max_x := sx
			var min_y := sy
			var max_y := sy
			var area := 0
			while not stack.is_empty():
				var i: int = stack.pop_back()
				area += 1
				var cy := i / w
				var cx := i % w
				min_x = mini(min_x, cx)
				max_x = maxi(max_x, cx)
				min_y = mini(min_y, cy)
				max_y = maxi(max_y, cy)
				for step in _NEIGHBOURS:
					var ny := cy + step.y
					var nx := cx + step.x
					if ny < 0 or ny >= h or nx < 0 or nx >= w:
						continue
					var j := ny * w + nx
					if solid[j] and labels[j] == 0:
						labels[j] = next_label
						stack.push_back(j)
			if max_x - min_x + 1 < DECOR_MIN_W or max_y - min_y + 1 < DECOR_MIN_H \
					or area < DECOR_MIN_AREA:
				continue
			found.append({"id": next_label, "x0": min_x, "y0": min_y,
				"x1": max_x, "y1": max_y})
	found.sort_custom(func(a, b):
		if int(a["y0"]) != int(b["y0"]):
			return int(a["y0"]) < int(b["y0"])
		return int(a["x0"]) < int(b["x0"]))
	var out := []
	for item in found:
		var bx: int = int(item["x0"])
		var by: int = int(item["y0"])
		var bw: int = int(item["x1"]) - bx + 1
		var bh: int = int(item["y1"]) - by + 1
		var id: int = int(item["id"])
		var sprite := Image.create_empty(bw + 2, bh + 2, false, Image.FORMAT_RGBA8)
		sprite.fill(Color(0, 0, 0, 0))
		for y in bh:
			for x in bw:
				if labels[(by + y) * w + bx + x] == id:
					sprite.set_pixel(x + 1, y + 1, region.get_pixel(bx + x, by + y))
		out.append(sprite)
	return out

## Scales a sprite to fit a px box preserving aspect, then blends it onto the
## canvas centred on `centre`.
func _place_piece(canvas: Image, src: Image, px: int, centre: Vector2i,
		flip: bool) -> void:
	var piece: Image = src.duplicate()
	var factor := float(px) / float(maxi(piece.get_width(), piece.get_height()))
	piece.resize(maxi(1, int(piece.get_width() * factor)),
		maxi(1, int(piece.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	if flip:
		piece.flip_x()
	canvas.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()),
		centre - piece.get_size() / 2)

func _bake_props(decor: Array) -> void:
	for biome in PROP_SLOTS:
		var dir := "res://assets/art/%s" % biome
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for slot in PROP_SLOTS[biome]:
			var index: int = int(PROP_SLOTS[biome][slot])
			assert(index < decor.size(), "decor index %d is past the column" % index)
			(decor[index] as Image).save_png("%s/%s.png" % [dir, slot])
		print("bake_sheet: %s props" % biome)

func _bake_endpoints(sheet: Image, decor: Array) -> void:
	var castle := Image.create_empty(
		ENDPOINT_CANVAS, ENDPOINT_CANVAS, false, Image.FORMAT_RGBA8)
	castle.fill(Color(0, 0, 0, 0))
	_place_piece(castle, _tower_sprite(sheet, &"long", 3), CASTLE_KEEP_PX,
		CASTLE_KEEP_CENTRE, false)
	for piece in CASTLE_PIECES:
		var spec: Dictionary = piece
		var index: int = int(spec["decor"])
		assert(index < decor.size(), "decor index %d is past the column" % index)
		_place_piece(castle, decor[index], int(spec["px"]), spec["centre"],
			bool(spec["flip"]))
	_trim(castle).save_png("res://assets/art/castle.png")

	var cave := Image.create_empty(
		ENDPOINT_CANVAS, ENDPOINT_CANVAS, false, Image.FORMAT_RGBA8)
	cave.fill(Color(0, 0, 0, 0))
	# An ellipse inscribed in CAVE_MOUTH, drawn by hand because Image has no
	# shape drawing.
	var rx := float(CAVE_MOUTH.size.x) / 2.0
	var ry := float(CAVE_MOUTH.size.y) / 2.0
	var cx := float(CAVE_MOUTH.position.x) + rx
	var cy := float(CAVE_MOUTH.position.y) + ry
	for y in CAVE_MOUTH.size.y:
		for x in CAVE_MOUTH.size.x:
			var px := float(CAVE_MOUTH.position.x + x) + 0.5
			var py := float(CAVE_MOUTH.position.y + y) + 0.5
			var dx := (px - cx) / rx
			var dy := (py - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				cave.set_pixel(CAVE_MOUTH.position.x + x, CAVE_MOUTH.position.y + y,
					CAVE_MOUTH_COLOUR)
	for piece in CAVE_PIECES:
		var spec: Dictionary = piece
		var index: int = int(spec["decor"])
		assert(index < decor.size(), "decor index %d is past the column" % index)
		_place_piece(cave, decor[index], int(spec["px"]), spec["centre"],
			bool(spec["flip"]))
	_trim(cave).save_png("res://assets/art/cave.png")
	print("bake_sheet: endpoints")
