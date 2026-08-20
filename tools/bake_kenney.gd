extends SceneTree

# Bakes Kenney's CC0 Tower Defense (Top-Down) pack into assets/kenney/.
#
#   godot --headless --script tools/bake_kenney.gd
#   godot --headless --import        # regenerate the .import sidecars
#   git checkout -- project.godot    # drop the blank line reimport writes
#
# Source: https://kenney.nl/assets/tower-defense-top-down (CC0), extracted to
# reference/kenney-td/ which is gitignored. The 3.2MB archive is not committed;
# the extracted subset this writes into assets/ is.
#
# ============================================================================
# TWO THINGS THAT WILL BITE YOU - READ BEFORE CHANGING ANY INDEX
# ============================================================================
# 1. The tilesheet's packing order is NOT this numbering. 70 of the 299 tiles
#    differ, starting at 15 and including the whole 130-137 prop range. Every
#    index here indexes towerDefense_tileNNN.png. Reading an index off a
#    tilesheet contact sheet gives the wrong tile.
#
# 2. Each terrain pairing appears TWICE in the pack: once with the road drawn
#    as a small overlay lobe on a ground base, and once with the roles
#    reversed. Both classify identically by corner colour. Picking by corner
#    alone yields a self-consistent table that tiles WRONGLY - mismatched wave
#    phases at concave corners, and road flooding ground it must not touch.
#    _select_family separates them by measuring the road-pixel fraction of the
#    single-corner masks: ~0.04 in the family we want, ~0.46 in the other.
#    Index position is not a usable rule - for grass/dirt the correct family is
#    the higher indices, for sand/stone the lower.
#
# test/test_blend_tiles.gd re-derives both properties from the committed PNGs,
# so neither claim has to be believed.
# ============================================================================

const SRC := "res://reference/kenney-td/PNG/Retina/towerDefense_tile%03d.png"
const OUT := "res://assets/kenney"
const TILE_PX := 128

# Measured off the pack by clustering every solid, fully opaque tile.
const GRASS := Vector3(45.0, 202.0, 111.0)
const SAND := Vector3(229.0, 213.0, 179.0)
const DIRT := Vector3(187.0, 128.0, 68.0)
const STONE := Vector3(136.0, 162.0, 164.0)
const SNOW := Vector3(236.0, 242.0, 248.0)

const TERRAINS := {
	&"grass": GRASS, &"sand": SAND, &"dirt": DIRT, &"stone": STONE,
}

# ground, road, and whether the sand family is recoloured to snow.
const BIOMES := {
	&"forest": {"ground": &"grass", "road": &"dirt", "snow": false},
	&"desert": {"ground": &"sand", "road": &"dirt", "snow": false},
	&"ice": {"ground": &"sand", "road": &"stone", "snow": true},
}

const MASKS := [0, 1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15]
const SINGLE_CORNER := [1, 2, 4, 8]

# Prop source tiles, in individual-PNG indices. tree/stone/spike/fire are the
# slot names MapRenderer's scatter rules already use; the biome only changes
# which tile sits behind each one.
# tile130 and tile133 are the pack's tiling foliage FILLS, not free-standing
# sprites: their art runs edge-to-edge with fully opaque pixels touching all
# four sides of the 128x128 canvas, so no alpha floor can ever trim them.
# They must never appear as a value below. Do not "restore" tile130 for a
# bigger-looking forest tree - it cannot be cropped to a footprint that
# matches what it draws (see test_prop_assets.gd's trim-shrank-canvas test).
const PROPS := {
	&"forest": {&"tree": 132, &"stone": 136, &"spike": 131, &"fire": 296},
	&"ice": {&"tree": 181, &"stone": 135, &"spike": 183, &"fire": 297},
	&"desert": {&"tree": 134, &"stone": 137, &"spike": 135, &"fire": 295},
}

const PROP_ALPHA_FLOOR := 8.0 / 255.0

const CORNER_TOL_SQ := 900.0
const FRACTION_TOL_SQ := 4000.0
const SNOW_TOL_SQ := 2600.0
const MAX_LOBE_FRACTION := 0.25

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var tiles := _load_all()
	for biome in BIOMES:
		_bake_biome(biome, tiles)
	for name in ENDPOINTS:
		_compose_endpoint(ENDPOINTS[name], tiles).save_png("%s/%s.png" % [OUT, name])
	_bake_tower_atlas(tiles)
	_copy_licence()
	print("bake_kenney: done")
	quit()

func _load_all() -> Dictionary:
	var out := {}
	for n in range(1, 300):
		var img := Image.load_from_file(SRC % n)
		if img != null:
			out[n] = img
	return out

func _copy_licence() -> void:
	var text := FileAccess.get_file_as_string("res://reference/kenney-td/License.txt")
	var f := FileAccess.open(OUT + "/License.txt", FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _rgb(img: Image, x: int, y: int) -> Vector3:
	var c := img.get_pixel(x, y)
	return Vector3(c.r, c.g, c.b) * 255.0

func _is_opaque(img: Image) -> bool:
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).a < 1.0:
				return false
	return true

func _classify(sample: Vector3, tol_sq: float) -> StringName:
	var best := &""
	var best_d := INF
	for name in TERRAINS:
		var d: float = sample.distance_squared_to(TERRAINS[name])
		if d < best_d:
			best_d = d
			best = name
	return best if best_d <= tol_sq else &""

# The four corner terrains, or [] if any corner is not a known terrain.
func _corners(img: Image) -> Array:
	var offsets := [Vector2i(3, 3), Vector2i(115, 3), Vector2i(3, 115), Vector2i(115, 115)]
	var out: Array = []
	for o in offsets:
		var off: Vector2i = o
		var acc := Vector3.ZERO
		for dy in 10:
			for dx in 10:
				acc += _rgb(img, off.x + dx, off.y + dy)
		var kind := _classify(acc / 100.0, CORNER_TOL_SQ)
		if kind == &"":
			return []
		out.append(kind)
	return out

func _road_fraction(img: Image, road: StringName) -> float:
	var hits := 0
	var total := 0
	for y in range(0, TILE_PX, 2):
		for x in range(0, TILE_PX, 2):
			total += 1
			if _classify(_rgb(img, x, y), FRACTION_TOL_SQ) == road:
				hits += 1
	return float(hits) / float(total)

func _luma_variance(img: Image) -> float:
	var vals: Array[float] = []
	for y in range(0, TILE_PX, 4):
		for x in range(0, TILE_PX, 4):
			var c := _rgb(img, x, y)
			vals.append((c.x + c.y + c.z) / 3.0)
	var mean := 0.0
	for v in vals:
		mean += v
	mean /= float(vals.size())
	var acc := 0.0
	for v in vals:
		acc += (v - mean) * (v - mean)
	return acc / float(vals.size())

# mask -> [candidate tile numbers], for one ground/road pairing.
func _candidates(tiles: Dictionary, ground: StringName, road: StringName) -> Dictionary:
	var bits := [1, 2, 4, 8]
	var out := {}
	for n in tiles:
		var img: Image = tiles[n]
		if not _is_opaque(img):
			continue
		var corners := _corners(img)
		if corners.is_empty():
			continue
		var mask := 0
		var ok := true
		for i in 4:
			var kind: StringName = corners[i]
			if kind == road:
				mask |= int(bits[i])
			elif kind != ground:
				ok = false
				break
		if ok:
			out.get_or_add(mask, []).append(n)
	return out

# mask -> tile number. See the header: the anchors come from measurement, the
# rest from proximity to those anchors.
func _select_family(tiles: Dictionary, cand: Dictionary, road: StringName) -> Dictionary:
	var anchors: Array[int] = []
	for mask in SINGLE_CORNER:
		for n in cand.get(mask, []):
			if _road_fraction(tiles[n], road) < MAX_LOBE_FRACTION:
				anchors.append(int(n))
				break
	assert(anchors.size() == SINGLE_CORNER.size(), "every single-corner mask needs an anchor")
	var centre := 0.0
	for a in anchors:
		centre += float(a)
	centre /= float(anchors.size())

	var table := {}
	for mask in MASKS:
		var options: Array = cand.get(mask, [])
		assert(not options.is_empty(), "mask %d has no candidate" % mask)
		if mask == 0 or mask == 15:
			# Solid tiles: take the plainest, so the blends carry the detail.
			var best: int = int(options[0])
			for n in options:
				if _luma_variance(tiles[n]) < _luma_variance(tiles[best]):
					best = int(n)
			table[mask] = best
		else:
			var best: int = int(options[0])
			for n in options:
				if absf(float(n) - centre) < absf(float(best) - centre):
					best = int(n)
			table[mask] = best
	return table

func _snowify(img: Image) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			var s := Vector3(c.r, c.g, c.b) * 255.0
			if s.distance_squared_to(SAND) < SNOW_TOL_SQ:
				var shifted := SNOW + (s - SAND)
				out.set_pixel(x, y, Color(
					clampf(shifted.x / 255.0, 0.0, 1.0),
					clampf(shifted.y / 255.0, 0.0, 1.0),
					clampf(shifted.z / 255.0, 0.0, 1.0), c.a))
	return out

## Crops to the alpha bounding box, then pads 1px of transparency back.
##
## Both halves are load-bearing. The crop is what makes prop_footprints()
## honest - it derives a blocking radius from the texture's full size, so
## transparent padding becomes invisible wall (tile130 fills 48% of its canvas,
## which would block over twice the area it draws). The 1px pad is what keeps
## test_prop_assets.gd's margin gate satisfiable: a bare bbox crop has opaque
## edge pixels by construction.
func _trim_and_pad(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > PROP_ALPHA_FLOOR:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	assert(max_x >= 0, "prop has no visible pixels")
	var box := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	var out := Image.create_empty(box.size.x + 2, box.size.y + 2, false, img.get_format())
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, box, Vector2i(1, 1))
	return out

# Endpoint compositions. The pack ships no castle and no cave, so each is
# assembled from pieces on a clear 256x256 canvas: {tile, offset, scale}.
# Composing rather than cutting is why these need no edge budget - there is no
# neighbouring artwork on the canvas to bleed in.
#
# THESE OFFSETS WERE VALIDATED BY EYE, NOT DERIVED. An earlier set placed the
# pieces so they did not touch: three floating shapes that passed every
# assertion in test_endpoint_assets.gd (which can only see margins and
# non-blankness) and read as scattered debris. If you change a number here,
# re-render and LOOK at it. The suite cannot see composition.
#
# The castle interlocks deliberately: the two bastions (229) sit on the same
# bottom line as the wide base (228), and the tower (226) is dropped far
# enough to overlap the base rather than hover above it.
const ENDPOINT_CANVAS := 256

const ENDPOINTS := {
	"castle": {
		"pieces": [
			{"tile": 229, "at": Vector2i(28, 138), "px": 86},
			{"tile": 229, "at": Vector2i(142, 138), "px": 86},
			{"tile": 228, "at": Vector2i(58, 96), "px": 140},
			{"tile": 226, "at": Vector2i(70, 36), "px": 116},
		],
	},
	# The cave is a painted opening with boulders arched around it. The pack
	# has no cave and no dark shape to borrow, so the mouth is drawn: without
	# it the three rocks read as a rock pile, not somewhere enemies come from.
	"cave": {
		"mouth": Rect2i(76, 94, 104, 98),
		"mouth_colour": Color8(34, 41, 48),
		"pieces": [
			{"tile": 136, "at": Vector2i(0, 84), "px": 122},
			{"tile": 137, "at": Vector2i(138, 86), "px": 114},
			{"tile": 135, "at": Vector2i(84, 40), "px": 100},
		],
	},
}

## Fills an ellipse inscribed in `box`. Godot's Image has no primitive for
## this, and the cave needs one solid dark shape the pack cannot supply.
func _fill_ellipse(img: Image, box: Rect2i, colour: Color) -> void:
	var rx := float(box.size.x) / 2.0
	var ry := float(box.size.y) / 2.0
	var cx := float(box.position.x) + rx
	var cy := float(box.position.y) + ry
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var nx := (float(x) + 0.5 - cx) / rx
			var ny := (float(y) + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, colour)

func _compose_endpoint(spec: Dictionary, tiles: Dictionary) -> Image:
	var canvas := Image.create_empty(
		ENDPOINT_CANVAS, ENDPOINT_CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	# Mouth first: the boulders are drawn over it so they frame the opening.
	if spec.has("mouth"):
		_fill_ellipse(canvas, spec["mouth"], spec["mouth_colour"])
	for piece in spec["pieces"]:
		var p: Dictionary = piece
		var src: Image = tiles[p["tile"]].duplicate()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(p["px"], p["px"], Image.INTERPOLATE_LANCZOS)
		canvas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), p["at"])
	return _trim_and_pad(canvas)

func _bake_biome(biome: StringName, tiles: Dictionary) -> void:
	var def: Dictionary = BIOMES[biome]
	var dir := "%s/%s" % [OUT, biome]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var cand := _candidates(tiles, def["ground"], def["road"])
	var table := _select_family(tiles, cand, def["road"])
	for mask in MASKS:
		var img: Image = tiles[table[mask]]
		if def["snow"]:
			img = _snowify(img)
		img.save_png("%s/blend_%02d.png" % [dir, mask])
	for slot in PROPS[biome]:
		# .duplicate() first, like the endpoint and atlas bakes - this runs
		# three times (once per biome) over a PROPS table with tiles shared
		# across biomes (e.g. tile 135 is both ice's stone and desert's
		# spike), so mutating tiles[...] in place here, unlike its neighbours,
		# would be the one bake path where an in-place .convert() could
		# outlive the biome that made it.
		var prop: Image = tiles[PROPS[biome][slot]].duplicate()
		prop.convert(Image.FORMAT_RGBA8)
		prop = _trim_and_pad(prop)
		prop.save_png("%s/%s.png" % [dir, slot])
	print("bake_kenney: %s %s" % [biome, table])

# The tower atlas, rebuilt at the geometry game/tower.gd already assumes:
# 5 columns of 96px frames, row-major, 20 frames.
#
# Each frame is a platform tile with a turret composited on top. The frame
# numbers are dictated by data/towers.gd's sprite_frame/upgrade_frames, which
# do NOT change - that is the point of rebaking at the same geometry. Frames
# 3, 4, 14 and 15 are unreferenced and stay blank.
const ATLAS_COLUMNS := 5
const ATLAS_FRAME := 96
const ATLAS_ROWS := 4

# frame -> {base tile, turret tile}.
#
# Grouped by tower kind below, because the frame NUMBERS are dictated by
# data/towers.gd's sprite_frame/upgrade_frames (which do not change - that is
# the point of rebaking at the same geometry) and read as scrambled. What
# matters is that each kind's four tiers escalate visibly:
#
#   basic  f8  f9  f11 f17 : small turret -> small turret -> twin rockets ->
#                            twin rockets on a fortified base
#   fast   f1  f0  f7  f16 : bare mount -> small turret -> rocket -> big rocket
#   mortar f5  f6  f12 f13 : big rocket -> twin -> quad -> red siege form
#   long   f2  f10 f18 f19 : rocket -> bigger -> biggest -> green siege form
#
# The base escalates with the tier too (227, 227, 228, 229), so a maxed tower
# reads as fortified even where its turret is shared with a lower tier of
# another kind. THIS MAPPING WAS VALIDATED BY RENDERING IT AND LOOKING. An
# earlier version gave mortar four near-identical twin-rocket tiers and sent
# basic from a green mass at tier 3 to a tiny rocket at tier 4; every
# assertion in test_tower_atlas.gd passed on it, because the suite can only
# see that a frame is non-empty and has clean margins.
const ATLAS_FRAMES := {
	# basic
	8: {"base": 227, "turret": 245}, 9: {"base": 227, "turret": 246},
	11: {"base": 228, "turret": 204}, 17: {"base": 229, "turret": 205},
	# fast
	1: {"base": 227, "turret": 203}, 0: {"base": 227, "turret": 248},
	7: {"base": 228, "turret": 251}, 16: {"base": 229, "turret": 252},
	# mortar
	5: {"base": 227, "turret": 206}, 6: {"base": 227, "turret": 204},
	12: {"base": 228, "turret": 205}, 13: {"base": 229, "turret": 250},
	# long
	2: {"base": 227, "turret": 251}, 10: {"base": 227, "turret": 252},
	18: {"base": 228, "turret": 206}, 19: {"base": 229, "turret": 249},
}

const ATLAS_BASE_PX := 84
const ATLAS_TURRET_PX := 64

func _bake_tower_atlas(tiles: Dictionary) -> void:
	var sheet := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for frame in ATLAS_FRAMES:
		var spec: Dictionary = ATLAS_FRAMES[frame]
		var ox: int = (int(frame) % ATLAS_COLUMNS) * ATLAS_FRAME
		var oy: int = (int(frame) / ATLAS_COLUMNS) * ATLAS_FRAME
		# Both pieces are centred in the 96px frame, not inset by a shared
		# margin constant - the inset falls out of (ATLAS_FRAME - piece) / 2
		# and differs per piece: 6px for the 84px base, 16px for the 64px
		# turret. The smaller of the two, the base's 6px, is what keeps art
		# off the frame edge - an AtlasTexture sampling a frame would
		# otherwise pull in the neighbouring frame's pixels - and it is that
		# same 6px that test_tower_atlas.gd's transparent-margin assertion
		# depends on.
		var base: Image = tiles[spec["base"]].duplicate()
		base.convert(Image.FORMAT_RGBA8)
		base.resize(ATLAS_BASE_PX, ATLAS_BASE_PX, Image.INTERPOLATE_LANCZOS)
		var base_at := Vector2i(ox + (ATLAS_FRAME - ATLAS_BASE_PX) / 2,
			oy + (ATLAS_FRAME - ATLAS_BASE_PX) / 2)
		sheet.blend_rect(base, Rect2i(Vector2i.ZERO, base.get_size()), base_at)

		var turret: Image = tiles[spec["turret"]].duplicate()
		turret.convert(Image.FORMAT_RGBA8)
		turret.resize(ATLAS_TURRET_PX, ATLAS_TURRET_PX, Image.INTERPOLATE_LANCZOS)
		var turret_at := Vector2i(ox + (ATLAS_FRAME - ATLAS_TURRET_PX) / 2,
			oy + (ATLAS_FRAME - ATLAS_TURRET_PX) / 2)
		sheet.blend_rect(turret, Rect2i(Vector2i.ZERO, turret.get_size()), turret_at)
	sheet.save_png("res://assets/towers.png")
