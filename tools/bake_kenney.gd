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

const CORNER_TOL_SQ := 900.0
const FRACTION_TOL_SQ := 4000.0
const SNOW_TOL_SQ := 2600.0
const MAX_LOBE_FRACTION := 0.25

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var tiles := _load_all()
	for biome in BIOMES:
		_bake_biome(biome, tiles)
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
	print("bake_kenney: %s %s" % [biome, table])
