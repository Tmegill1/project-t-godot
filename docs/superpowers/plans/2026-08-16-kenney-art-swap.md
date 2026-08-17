# Kenney Art Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every non-enemy asset with Kenney's CC0 *Tower Defense (Top-Down)* art and add a biome layer so a map declares itself forest, ice or desert.

**Architecture:** A headless GDScript bake tool turns the vendored pack into committed PNGs under `assets/kenney/`, one directory per biome with an identical file layout. `data/biomes.gd` is a three-entry table that resolves textures from that layout. `MapRenderer` draws its ground layer from a corner-mask lattice sampled at tile centres instead of one flat texture per tile. The tower atlas keeps its exact existing geometry so no tower code changes at all.

**Tech Stack:** Godot 4.7.1.stable, GDScript, `Image`/`FileAccess` for the bake, the project's own `TestCase`/`run_tests.gd` harness.

**Spec:** `docs/superpowers/specs/2026-08-16-kenney-art-swap-design.md`

## Global Constraints

- Godot 4.7.1.stable. `class_name` does not resolve until `godot --headless --import` has run once.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. See `test/case.gd`.
- A test that records zero assertions fails the run. So does a suite file with zero test methods.
- Prefer flat `test_*` bodies over helper delegation; where a helper is unavoidable, assert on its result (see the known gap in `test/run_tests.gd`).
- **Asset-gate tests** (those measuring pixels) read committed PNG bytes via `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`, never the imported `Texture2D`, so they gate the file that is in git. **Renderer tests** keep comparing `Texture2D.resource_path`, which is the existing convention documented in `test/test_map_renderer.gd`'s header.
- Every task ends on a green suite. A task that knowingly commits a failing test is not done.
- `Tiles.TILE_SIZE` stays **48**. `MIN_TOWER_SPACING` stays **44**.
- `PATH_HALF_WIDTH` moves **26 → 14** (Task 9 only).
- Enemies are untouched: `assets/enemies/**`, `game/enemy.tscn`, `game/enemy.gd`, `data/enemies.gd`.
- No rule in `sim/` changes except the one constant in Task 9.
- Every tile index in this plan is an **individual-PNG index** (`towerDefense_tileNNN.png`). The tilesheet's packing order differs on 70 of 299 tiles — never cross-check against it.
- Corner mask bit order is fixed: **TL=1, TR=2, BL=4, BR=8**, bit set means road.
- Source art lives at `reference/kenney-td/` (gitignored, already extracted). Retina set is `reference/kenney-td/PNG/Retina/towerDefense_tileNNN.png`, 128×128.
- After any new/changed `.import`, run `godot --headless --import`, then `git checkout -- project.godot` to drop the stray `[autoload]` blank line that reimport writes.
- Run the suite with: `godot --headless --quit --script test/run_tests.gd`

---

### Task 1: Bake the ground blend tiles

**Files:**
- Create: `tools/bake_kenney.gd`
- Create: `assets/kenney/forest/blend_NN.png`, `assets/kenney/ice/blend_NN.png`, `assets/kenney/desert/blend_NN.png` (14 each)
- Create: `assets/kenney/License.txt`
- Test: `test/test_blend_tiles.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: 42 committed PNGs at `res://assets/kenney/<biome>/blend_%02d.png` for masks `0,1,2,3,4,5,7,8,10,11,12,13,14,15`. Masks 6 and 9 are deliberately absent. Biome directory names are exactly `forest`, `ice`, `desert`.

- [ ] **Step 1: Write the failing test**

Create `test/test_blend_tiles.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — every `_blend_image` returns null because `assets/kenney/` does not exist yet.

- [ ] **Step 3: Write the bake tool**

Create `tools/bake_kenney.gd`:

```gdscript
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
	var out := img.duplicate()
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
```

- [ ] **Step 4: Run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
```

Expected: prints one `bake_kenney: <biome> {...}` line per biome, and `assets/kenney/<biome>/` each hold 14 PNGs. Verify the printed forest table matches the spec's §7.2 row (`0:119, 1:117, 2:115, 3:116, 4:71, 5:94, 7:72, 8:69, 10:92, 11:73, 12:70, 13:95, 14:96, 15:50`). A mismatch means the family selection drifted — stop and diagnose rather than adjusting the test.

- [ ] **Step 5: Run test to verify it passes**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, `test_blend_tiles.gd` green.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_kenney.gd assets/kenney test/test_blend_tiles.gd
git commit -m "Bake the Kenney ground blend tiles for three biomes"
```

---

### Task 2: The biome table

**Files:**
- Create: `data/biomes.gd`
- Test: `test/test_biomes.gd`

**Interfaces:**
- Consumes: the `assets/kenney/<biome>/` layout from Task 1.
- Produces:
  - `Biomes.KINDS: Array[StringName]` — `[&"forest", &"ice", &"desert"]`
  - `Biomes.FIRST: StringName` — `&"forest"`
  - `Biomes.get_def(biome: StringName) -> Dictionary` — keys `label`, `dir`
  - `Biomes.blend_texture(biome: StringName, mask: int) -> Texture2D`
  - `Biomes.prop_texture(biome: StringName, slot: StringName) -> Texture2D` — slots `&"tree"`, `&"stone"`, `&"spike"`, `&"fire"`
  - `Biomes.DIAGONAL_MASKS: Array[int]` — `[6, 9]`
  - `Biomes.DIAGONAL_FALLBACK: int` — `15`

- [ ] **Step 1: Write the failing test**

Create `test/test_biomes.gd`:

```gdscript
extends TestCase

# The biome table is three directories with an identical file layout, so most
# of what could go wrong is a path that does not resolve. These check that,
# plus the one piece of real logic: the diagonal-mask fallback.

func test_the_three_biomes_are_exactly_forest_ice_and_desert() -> bool:
	assert_eq(Biomes.KINDS.size(), 3, "three biomes")
	assert_true(Biomes.KINDS.has(&"forest"), "forest exists")
	assert_true(Biomes.KINDS.has(&"ice"), "ice exists")
	assert_true(Biomes.KINDS.has(&"desert"), "desert exists")
	assert_eq(Biomes.FIRST, &"forest", "forest is the first biome")
	return true

func test_every_biome_resolves_every_blend_mask_the_pack_supplies() -> bool:
	for biome in Biomes.KINDS:
		for mask in [0, 1, 2, 3, 4, 5, 7, 8, 10, 11, 12, 13, 14, 15]:
			var tex := Biomes.blend_texture(biome, mask)
			assert_true(tex != null, "%s mask %d resolves" % [biome, mask])
	return true

func test_the_diagonal_masks_fall_back_to_the_full_road_tile() -> bool:
	# The pack ships no diagonal-only tile in any pairing. 15 connects both
	# diagonals rather than neither, which is the safer resolution.
	for biome in Biomes.KINDS:
		var full := Biomes.blend_texture(biome, 15)
		for mask in Biomes.DIAGONAL_MASKS:
			assert_eq(Biomes.blend_texture(biome, mask), full,
				"%s mask %d falls back to 15" % [biome, mask])
	return true

func test_each_biome_uses_its_own_directory() -> bool:
	# Guards a copy-paste that points two biomes at one directory, which would
	# silently render ice as forest.
	var seen := {}
	for biome in Biomes.KINDS:
		var dir: String = Biomes.get_def(biome)["dir"]
		assert_false(seen.has(dir), "%s has its own directory" % biome)
		seen[dir] = true
	return true

func test_every_biome_carries_a_human_readable_label() -> bool:
	for biome in Biomes.KINDS:
		var label: String = Biomes.get_def(biome)["label"]
		assert_false(label.is_empty(), "%s has a label" % biome)
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — the script does not compile, `Biomes` is not a known identifier.

- [ ] **Step 3: Write the implementation**

Create `data/biomes.gd`:

```gdscript
class_name Biomes

## Which art a map is drawn with. Three entries, each one directory that the
## bake tool (tools/bake_kenney.gd) guarantees holds an identical file layout:
## blend_NN.png per corner mask, plus tree/stone/spike/fire.
##
## The prop slot names are the ones MapRenderer's scatter rules already use.
## Only the texture behind each name is per-biome; none of the placement rules
## are.

const FIRST := &"forest"

const DEFS := {
	&"forest": {"label": "Forest", "dir": "res://assets/kenney/forest"},
	&"ice": {"label": "Ice", "dir": "res://assets/kenney/ice"},
	&"desert": {"label": "Desert", "dir": "res://assets/kenney/desert"},
}

const KINDS: Array[StringName] = [&"forest", &"ice", &"desert"]

const PROP_SLOTS: Array[StringName] = [&"tree", &"stone", &"spike", &"fire"]

## The pack ships no diagonal-only blend tile in any pairing - the connection
## is genuinely ambiguous, so blob tilesets omit it. 15 (full road) is the
## substitution: it connects both diagonals rather than neither. The demo map
## produces neither mask, and test_map_renderer.gd asserts that stays true, so
## this is a safety net rather than a live path.
const DIAGONAL_MASKS: Array[int] = [6, 9]
const DIAGONAL_FALLBACK := 15

static func get_def(biome: StringName) -> Dictionary:
	return DEFS[biome]

static func blend_texture(biome: StringName, mask: int) -> Texture2D:
	var resolved := DIAGONAL_FALLBACK if mask in DIAGONAL_MASKS else mask
	return load("%s/blend_%02d.png" % [DEFS[biome]["dir"], resolved])

static func prop_texture(biome: StringName, slot: StringName) -> Texture2D:
	return load("%s/%s.png" % [DEFS[biome]["dir"], slot])
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, whole suite green. `prop_texture` exists but is deliberately **not** exercised here — Task 3 is what bakes the props, and it adds the test that resolves all four slots. Asserting them now would commit a knowingly-red suite.

- [ ] **Step 5: Commit**

```bash
git add data/biomes.gd test/test_biomes.gd
git commit -m "Add the biome table and its diagonal-mask fallback"
```

---

### Task 3: Bake the props

**Files:**
- Modify: `tools/bake_kenney.gd` (add prop baking to `_bake_biome`)
- Create: `assets/kenney/<biome>/{tree,stone,spike,fire}.png`
- Test: `test/test_prop_assets.gd`
- Test: `test/test_biomes.gd` (add the prop-slot test, which belongs to this task because this is the task that satisfies it)

**Interfaces:**
- Consumes: `BIOMES` and the image loading from Task 1.
- Produces: four PNGs per biome, each trimmed to its alpha bounding box and padded by exactly 1px of transparency on all four sides.

Source tiles, in individual-PNG indices:

| biome | tree | stone | spike | fire |
|---|---|---|---|---|
| forest | 130 | 136 | 132 | 296 |
| ice | 181 | 135 | 183 | 297 |
| desert | 134 | 137 | 131 | 295 |

- [ ] **Step 1: Write the failing test**

Create `test/test_prop_assets.gd`:

```gdscript
extends TestCase

# Props are free-standing sprites, so each needs a transparent margin all
# round - an opaque edge means the subject is clipped.
#
# The tight-bbox gate is the one that matters for gameplay.
# MapRenderer.prop_footprints() derives a tower-blocking radius from the
# texture's full dimensions, so transparent padding becomes invisible wall.
# Kenney's raw tile130 fills 48% of its 128x128 canvas: untrimmed it would
# block over twice the area it draws. The bake trims to the alpha bbox and
# pads back exactly 1px, which is what makes "radius from displayed size" true
# rather than merely conservative. See spec section 6.

const _BIOMES := ["forest", "ice", "desert"]
const _SLOTS := ["tree", "stone", "spike", "fire"]
const _MARGIN_ALPHA_MAX := 8

# After a 1px pad, the subject must fill everything else. Allowing a little
# slack for antialiasing at the extremes rather than demanding exactly 1px.
const _MAX_TRANSPARENT_BORDER := 3

func _prop_image(biome: String, slot: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes("res://assets/kenney/%s/%s.png" % [biome, slot])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_every_prop_keeps_a_transparent_margin_on_all_four_edges() -> bool:
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
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
				"%s/%s edge peak alpha %d is a transparent margin" % [biome, slot, peak])
	return true

func test_every_prop_is_trimmed_tight_so_its_footprint_is_honest() -> bool:
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			var w := img.get_width()
			var h := img.get_height()
			var min_x := w
			var min_y := h
			var max_x := -1
			var max_y := -1
			for y in h:
				for x in w:
					if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
						min_x = mini(min_x, x)
						min_y = mini(min_y, y)
						max_x = maxi(max_x, x)
						max_y = maxi(max_y, y)
			assert_true(max_x >= 0, "%s/%s has visible pixels" % [biome, slot])
			if max_x < 0:
				continue
			assert_true(min_x <= _MAX_TRANSPARENT_BORDER,
				"%s/%s left border %d is tight" % [biome, slot, min_x])
			assert_true(min_y <= _MAX_TRANSPARENT_BORDER,
				"%s/%s top border %d is tight" % [biome, slot, min_y])
			assert_true(w - 1 - max_x <= _MAX_TRANSPARENT_BORDER,
				"%s/%s right border %d is tight" % [biome, slot, w - 1 - max_x])
			assert_true(h - 1 - max_y <= _MAX_TRANSPARENT_BORDER,
				"%s/%s bottom border %d is tight" % [biome, slot, h - 1 - max_y])
	return true

func test_trimming_actually_shrank_the_source_canvas() -> bool:
	# A bake that forgot to trim would emit 128x128 for everything and still
	# pass the margin gate. This is what catches that.
	var shrunk := 0
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			if img.get_width() < 128 or img.get_height() < 128:
				shrunk += 1
	assert_eq(shrunk, _BIOMES.size() * _SLOTS.size(), "every prop was trimmed below 128px")
	return true
```

And add to `test/test_biomes.gd` — this assertion lives here rather than in Task 2 because Task 3 is what makes it true, and a task must not commit a knowingly-red suite:

```gdscript
func test_every_biome_resolves_all_four_prop_slots() -> bool:
	for biome in Biomes.KINDS:
		for slot in Biomes.PROP_SLOTS:
			var tex := Biomes.prop_texture(biome, slot)
			assert_true(tex != null, "%s %s resolves" % [biome, slot])
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `_prop_image` returns null for every slot.

- [ ] **Step 3: Add prop baking to the tool**

In `tools/bake_kenney.gd`, add the source table beside `BIOMES`:

```gdscript
# Prop source tiles, in individual-PNG indices. tree/stone/spike/fire are the
# slot names MapRenderer's scatter rules already use; the biome only changes
# which tile sits behind each one.
const PROPS := {
	&"forest": {&"tree": 130, &"stone": 136, &"spike": 132, &"fire": 296},
	&"ice": {&"tree": 181, &"stone": 135, &"spike": 183, &"fire": 297},
	&"desert": {&"tree": 134, &"stone": 137, &"spike": 131, &"fire": 295},
}

const PROP_ALPHA_FLOOR := 8.0 / 255.0
```

Add the trim helper:

```gdscript
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
```

Then, at the end of `_bake_biome`, after the blend loop:

```gdscript
	for slot in PROPS[biome]:
		var prop: Image = tiles[PROPS[biome][slot]]
		prop.convert(Image.FORMAT_RGBA8)
		prop = _trim_and_pad(prop)
		prop.save_png("%s/%s.png" % [dir, slot])
```

- [ ] **Step 4: Re-run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
```

Expected: each `assets/kenney/<biome>/` now holds 14 blend PNGs plus `tree.png`, `stone.png`, `spike.png`, `fire.png`, all smaller than 128×128.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS — `test_prop_assets.gd` green, and `test_biomes.gd`'s prop-slot test now green too.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_kenney.gd assets/kenney test/test_prop_assets.gd
git commit -m "Bake trimmed per-biome props so footprints match the art"
```

---

### Task 4: Bake the endpoints

**Files:**
- Modify: `tools/bake_kenney.gd`
- Create: `assets/kenney/castle.png`, `assets/kenney/cave.png`
- Test: `test/test_endpoint_assets.gd`

**Interfaces:**
- Consumes: image loading and `_trim_and_pad` from Tasks 1 and 3.
- Produces: two shared (not per-biome) PNGs at `res://assets/kenney/castle.png` and `res://assets/kenney/cave.png`.

The pack has no castle and no cave. `castle` is composed from structure tiles **226** (turret base), **229** (shield block) and **249** (green base); `cave` from boulders **135**, **136** and **137**. Both are composed on a 256×256 canvas and trimmed, so `_draw_endpoints()`'s 3-tile scaling is unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/test_endpoint_assets.gd`:

```gdscript
extends TestCase

# The goal and spawn markers, composed from pack pieces because Kenney ships
# neither a castle nor a cave. They are drawn 3 tiles wide by
# MapRenderer._draw_endpoints and are shared across biomes.
#
# Unlike the old assets/map/castle.png and cave.png, these are composed on a
# clear canvas rather than cut out of a packed sheet, so there is no
# neighbouring artwork to bleed in and no _EDGE_PIXEL_BUDGET. Every edge is
# held to a clean transparent margin. If one of these goes red, fix the
# composition in tools/bake_kenney.gd - do not add a budget.

const _ENDPOINTS := ["castle", "cave"]
const _MARGIN_ALPHA_MAX := 8

func _endpoint_image(name: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes("res://assets/kenney/%s.png" % name)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_both_endpoints_decode_and_carry_visible_art() -> bool:
	for name in _ENDPOINTS:
		var img := _endpoint_image(name)
		assert_true(img != null, "%s.png decodes" % name)
		if img == null:
			continue
		var opaque := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
					opaque += 1
		assert_true(opaque > 0, "%s.png is not blank" % name)
	return true

func test_both_endpoints_keep_a_clean_transparent_margin() -> bool:
	for name in _ENDPOINTS:
		var img := _endpoint_image(name)
		assert_true(img != null, "%s.png decodes" % name)
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
			"%s.png edge peak alpha %d is a transparent margin" % [name, peak])
	return true

func test_the_two_endpoints_are_visually_distinct() -> bool:
	# A composition bug that wrote the same pieces twice would leave the player
	# unable to tell the spawn from the goal.
	var castle := _endpoint_image("castle")
	var cave := _endpoint_image("cave")
	assert_true(castle != null, "castle.png decodes")
	assert_true(cave != null, "cave.png decodes")
	if castle == null or cave == null:
		return true
	var differs := castle.get_width() != cave.get_width() \
		or castle.get_height() != cave.get_height()
	if not differs:
		for y in range(0, castle.get_height(), 4):
			for x in range(0, castle.get_width(), 4):
				if castle.get_pixel(x, y) != cave.get_pixel(x, y):
					differs = true
					break
			if differs:
				break
	assert_true(differs, "castle and cave are different images")
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — both `_endpoint_image` calls return null.

- [ ] **Step 3: Add endpoint composition to the tool**

Add to `tools/bake_kenney.gd`:

```gdscript
# Endpoint compositions. The pack ships no castle and no cave, so each is
# assembled from pieces on a clear 256x256 canvas: {tile, offset, scale}.
# Composing rather than cutting is why these need no edge budget - there is no
# neighbouring artwork on the canvas to bleed in.
const ENDPOINT_CANVAS := 256

const ENDPOINTS := {
	"castle": [
		{"tile": 229, "at": Vector2i(64, 96), "px": 128},
		{"tile": 226, "at": Vector2i(32, 32), "px": 96},
		{"tile": 249, "at": Vector2i(128, 32), "px": 96},
	],
	"cave": [
		{"tile": 137, "at": Vector2i(16, 80), "px": 112},
		{"tile": 135, "at": Vector2i(112, 64), "px": 128},
		{"tile": 136, "at": Vector2i(72, 128), "px": 104},
	],
}

func _compose_endpoint(pieces: Array, tiles: Dictionary) -> Image:
	var canvas := Image.create_empty(
		ENDPOINT_CANVAS, ENDPOINT_CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	for piece in pieces:
		var spec: Dictionary = piece
		var src: Image = tiles[spec["tile"]].duplicate()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(spec["px"], spec["px"], Image.INTERPOLATE_LANCZOS)
		canvas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), spec["at"])
	return _trim_and_pad(canvas)
```

Call it from `_init`, after the biome loop and before `_copy_licence()`:

```gdscript
	for name in ENDPOINTS:
		_compose_endpoint(ENDPOINTS[name], tiles).save_png("%s/%s.png" % [OUT, name])
```

- [ ] **Step 4: Re-run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
```

Expected: `assets/kenney/castle.png` and `assets/kenney/cave.png` exist and are visibly different shapes.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, `test_endpoint_assets.gd` green.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_kenney.gd assets/kenney test/test_endpoint_assets.gd
git commit -m "Compose the goal and spawn markers from Kenney pieces"
```

---

### Task 5: Bake the tower atlas

**Files:**
- Modify: `tools/bake_kenney.gd`
- Modify: `assets/towers.png` (overwritten in place)
- Test: `test/test_tower_atlas.gd`

**Interfaces:**
- Consumes: image loading from Task 1.
- Produces: `res://assets/towers.png`, 480×384, 5 columns × 4 rows of 96px frames, indexed row-major.

**Nothing in `game/tower.gd`, `data/towers.gd`, `sim/upgrades.gd` or `ui/tower_panel.gd` changes.** The atlas keeps its exact existing geometry so the whole tower stack gets a pure file swap. Frames referenced by `data/towers.gd` are `0,1,2,5,6,7,8,9,10,11,12,13,16,17,18,19`; frames `3,4,14,15` are unreferenced and are left blank.

- [ ] **Step 1: Write the failing test**

Create `test/test_tower_atlas.gd`:

```gdscript
extends TestCase

# assets/towers.png is consumed through Tower.frame_region on a 5-column grid
# of 96px frames, by both the placed tower and the build panel's button icons.
# This file pins the geometry that arithmetic assumes, and checks that every
# frame data/towers.gd actually names carries art.
#
# Frames 3, 4, 14 and 15 are unreferenced by any tower kind and are
# deliberately blank - asserting they are empty is what keeps a future re-bake
# from quietly relying on them without adding them to a tower's upgrade path.

const _ATLAS := "res://assets/towers.png"
const _COLUMNS := 5
const _FRAME := 96
const _UNUSED_FRAMES := [3, 4, 14, 15]

func _atlas_image() -> Image:
	var bytes := FileAccess.get_file_as_bytes(_ATLAS)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _opaque_pixels(img: Image, frame: int) -> int:
	var ox := (frame % _COLUMNS) * _FRAME
	var oy := (frame / _COLUMNS) * _FRAME
	var count := 0
	for y in range(0, _FRAME, 2):
		for x in range(0, _FRAME, 2):
			if img.get_pixel(ox + x, oy + y).a > 8.0 / 255.0:
				count += 1
	return count

func test_the_atlas_keeps_the_geometry_tower_gd_assumes() -> bool:
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	assert_eq(img.get_width(), _COLUMNS * _FRAME, "atlas width is 5 frames")
	assert_eq(img.get_height(), 4 * _FRAME, "atlas height is 4 frames")
	assert_eq(Tower.SHEET_COLUMNS, _COLUMNS, "Tower.SHEET_COLUMNS still 5")
	assert_eq(Tower.FRAME_SIZE, _FRAME, "Tower.FRAME_SIZE still 96")
	return true

func test_every_frame_a_tower_kind_names_carries_art() -> bool:
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.get_def(kind)
		for frame in def["upgrade_frames"]:
			var n: int = frame
			assert_true(_opaque_pixels(img, n) > 0,
				"%s frame %d carries art" % [kind, n])
		var base: int = def["sprite_frame"]
		assert_true(_opaque_pixels(img, base) > 0,
			"%s base frame %d carries art" % [kind, base])
	return true

func test_the_unreferenced_frames_are_blank() -> bool:
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for frame in _UNUSED_FRAMES:
		var n: int = frame
		assert_eq(_opaque_pixels(img, n), 0, "unused frame %d is blank" % n)
	return true

func test_every_referenced_frame_keeps_a_transparent_margin() -> bool:
	# Art running to a frame edge bleeds into the neighbouring frame when the
	# AtlasTexture samples it.
	var img := _atlas_image()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n: int = frame
			var ox := (n % _COLUMNS) * _FRAME
			var oy := (n / _COLUMNS) * _FRAME
			var peak := 0.0
			for i in _FRAME:
				peak = maxf(peak, img.get_pixel(ox + i, oy).a)
				peak = maxf(peak, img.get_pixel(ox + i, oy + _FRAME - 1).a)
				peak = maxf(peak, img.get_pixel(ox, oy + i).a)
				peak = maxf(peak, img.get_pixel(ox + _FRAME - 1, oy + i).a)
			assert_true(peak <= 8.0 / 255.0,
				"%s frame %d keeps a transparent margin" % [kind, n])
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — the committed `assets/towers.png` is the old reference sheet, so the geometry and per-frame assertions do not hold.

- [ ] **Step 3: Add atlas composition to the tool**

Add to `tools/bake_kenney.gd`:

```gdscript
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

# frame -> {platform tile, turret tile}. Tier order per kind reads as a bigger
# and more numerous weapon; see data/towers.gd for which kind owns which.
const ATLAS_FRAMES := {
	0: {"base": 227, "turret": 245}, 1: {"base": 227, "turret": 203},
	2: {"base": 227, "turret": 206}, 5: {"base": 228, "turret": 204},
	6: {"base": 228, "turret": 205}, 7: {"base": 227, "turret": 246},
	8: {"base": 227, "turret": 247}, 9: {"base": 227, "turret": 248},
	10: {"base": 228, "turret": 206}, 11: {"base": 228, "turret": 249},
	12: {"base": 229, "turret": 204}, 13: {"base": 229, "turret": 205},
	16: {"base": 228, "turret": 250}, 17: {"base": 228, "turret": 251},
	18: {"base": 229, "turret": 252}, 19: {"base": 229, "turret": 250},
}

const ATLAS_BASE_PX := 84
const ATLAS_TURRET_PX := 64
const ATLAS_MARGIN := 4

func _bake_tower_atlas(tiles: Dictionary) -> void:
	var sheet := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for frame in ATLAS_FRAMES:
		var spec: Dictionary = ATLAS_FRAMES[frame]
		var ox: int = (int(frame) % ATLAS_COLUMNS) * ATLAS_FRAME
		var oy: int = (int(frame) / ATLAS_COLUMNS) * ATLAS_FRAME
		# Both pieces are inset by ATLAS_MARGIN so no frame's art touches an
		# edge - an AtlasTexture sampling a frame would otherwise pull in the
		# neighbouring frame's pixels.
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
```

Call it from `_init`, after the endpoint loop:

```gdscript
	_bake_tower_atlas(tiles)
```

- [ ] **Step 4: Re-run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
```

Expected: `assets/towers.png` is 480×384.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, `test_tower_atlas.gd` green. If a referenced frame's margin assertion fails, reduce `ATLAS_BASE_PX` — do not raise the test's threshold.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_kenney.gd assets/towers.png test/test_tower_atlas.gd
git commit -m "Rebake the tower atlas at its existing geometry"
```

---

### Task 6: Render the ground from a corner-mask lattice

**Files:**
- Modify: `game/map_renderer.gd` (`_draw_ground`, the preload block, `render`)
- Modify: `test/test_map_renderer.gd` (ground-layer assertions, the `_GRASS_PATH`/`_PATH_PATH` constants at lines 15-16, and `test_square_ground_tiles_still_land_exactly_on_their_tile_origin`)

**Two things in the existing test file that the ground change invalidates.**
`test/test_map_renderer.gd:9-16` declares eight hardcoded `res://assets/map/*.png`
constants, and 12 of its 19 tests key off them. This task owns the two ground
ones — delete `_GRASS_PATH` and `_PATH_PATH`, since a blended ground layer has
no single grass or path texture to name. The six prop and endpoint constants
stay; Tasks 7 and 8 own those.

`test_square_ground_tiles_still_land_exactly_on_their_tile_origin` (line 577)
asserts ground sprites land on their tile origin with zero slack. The lattice
moves every ground sprite half a tile up and left, so its premise is now false.
Rewrite it as the half-tile assertion below rather than deleting it — the
property it was protecting (a square source gets zero slack from `_place`, so
the ground layer stays seam-free) is still true and still worth pinning; only
the expected origin moved.

**Interfaces:**
- Consumes: `Biomes.blend_texture` from Task 2.
- Produces: `MapRenderer.render(tiles: Array, rng: Rng = null, biome: StringName = Biomes.FIRST)`. Ground layer is `(cols + 1) * (rows + 1)` sprites at `(c * 48 - 24, r * 48 - 24)`, `z_index == _Z_GROUND`.
- Produces: `MapRenderer.corner_mask(c: int, r: int) -> int` — public so tests can assert the lattice without reaching into rendering.

- [ ] **Step 1: Write the failing test**

Replace `test_ground_layer_has_one_sprite_per_tile_with_the_right_texture` in `test/test_map_renderer.gd` with these, and keep every other test in that file as-is:

```gdscript
func test_ground_layer_has_one_sprite_per_lattice_point() -> bool:
	# The lattice samples terrain at tile CENTRES, so a sprite spans the square
	# between four adjacent centres and the grid gains one row and column.
	# See spec section 7.1 for why the alternatives were rejected.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var ground := 0
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == -1:
			ground += 1
	var expected := (DemoMap.GRID_COLS + 1) * (DemoMap.GRID_ROWS + 1)
	assert_eq(ground, expected, "one ground sprite per lattice point")
	renderer.free()
	return true

func test_ground_sprites_are_offset_half_a_tile_so_roads_sit_on_tile_centres() -> bool:
	# If the lattice is anchored anywhere else the road draws half a tile off
	# the world-space route PathFinder emits and enemies walk beside it.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var half := Tiles.TILE_SIZE / 2
	var found := false
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == -1:
			var sprite: Sprite2D = child
			if sprite.position == Vector2(3 * Tiles.TILE_SIZE - half, 5 * Tiles.TILE_SIZE - half):
				found = true
			# posmod, not %: the c == 0 column sits at -24, and GDScript's %
			# keeps the sign, so a plain modulo returns -24 and fails here.
			assert_eq(posmod(int(sprite.position.x), Tiles.TILE_SIZE), half,
				"ground sprite x is on the half-tile lattice")
	assert_true(found, "the lattice point at (3, 5) was drawn")
	renderer.free()
	return true

func test_square_ground_tiles_take_zero_slack_from_the_tile_box() -> bool:
	# Replaces test_square_ground_tiles_still_land_exactly_on_their_tile_origin,
	# whose premise the half-tile lattice offset invalidates. The property
	# worth keeping is unchanged: _place splits leftover slack to centre a
	# sprite, and a SQUARE source has none, which is what keeps the ground
	# layer flush and seam-free. Only the origin it lands on moved.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var half := Tiles.TILE_SIZE / 2
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		var tex: Texture2D = sprite.texture
		assert_eq(tex.get_width(), tex.get_height(), "a ground tile is square")
		var c := int((sprite.position.x + half) / Tiles.TILE_SIZE)
		var r := int((sprite.position.y + half) / Tiles.TILE_SIZE)
		assert_eq(sprite.position,
			Vector2(c * Tiles.TILE_SIZE - half, r * Tiles.TILE_SIZE - half),
			"ground sprite takes zero slack, landing on its lattice point")
		checked += 1
	assert_true(checked > 0, "ground sprites were checked")
	renderer.free()
	return true

func test_the_corner_mask_reads_road_from_the_four_surrounding_tile_centres() -> bool:
	# Bit order is fixed and load-bearing: TL=1, TR=2, BL=4, BR=8.
	var renderer := MapRenderer.new()
	var tiles: Array = []
	for r in 3:
		var row: Array = []
		for c in 3:
			row.append(Tiles.BUILDABLE)
		tiles.append(row)
	tiles[1][1] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	# Lattice point (1, 1) has tile (1, 1) as its BOTTOM-RIGHT corner.
	assert_eq(renderer.corner_mask(1, 1), 8, "road at bottom-right sets bit 8")
	assert_eq(renderer.corner_mask(2, 1), 4, "road at bottom-left sets bit 4")
	assert_eq(renderer.corner_mask(1, 2), 2, "road at top-right sets bit 2")
	assert_eq(renderer.corner_mask(2, 2), 1, "road at top-left sets bit 1")
	assert_eq(renderer.corner_mask(0, 0), 0, "no road nearby is mask 0")
	renderer.free()
	return true

func test_spawn_and_goal_tiles_count_as_road_for_the_lattice() -> bool:
	# Tiles.WALKABLE is PATH, SPAWN and GOAL. The old _draw_ground drew the
	# path texture on all three, and the road must not break at the endpoints.
	var renderer := MapRenderer.new()
	var tiles: Array = []
	for r in 2:
		var row: Array = []
		for c in 2:
			row.append(Tiles.BUILDABLE)
		tiles.append(row)
	tiles[0][0] = Tiles.SPAWN
	tiles[1][1] = Tiles.GOAL
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.corner_mask(1, 1), 1 | 8, "spawn and goal both read as road")
	renderer.free()
	return true

func test_the_demo_map_never_needs_a_diagonal_blend_tile() -> bool:
	# The pack ships no diagonal-only tile. Biomes.blend_texture substitutes
	# mask 15, and this asserts that substitution stays a safety net rather
	# than something the shipped map actually depends on.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var diagonal := 0
	for r in range(DemoMap.GRID_ROWS + 1):
		for c in range(DemoMap.GRID_COLS + 1):
			if renderer.corner_mask(c, r) in Biomes.DIAGONAL_MASKS:
				diagonal += 1
	assert_eq(diagonal, 0, "the demo map produces no diagonal corner cases")
	renderer.free()
	return true

func test_every_ground_sprite_uses_the_texture_its_mask_names() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var half := Tiles.TILE_SIZE / 2
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		var c := int((sprite.position.x + half) / Tiles.TILE_SIZE)
		var r := int((sprite.position.y + half) / Tiles.TILE_SIZE)
		var expected := Biomes.blend_texture(&"forest", renderer.corner_mask(c, r))
		assert_eq(sprite.texture.resource_path, expected.resource_path,
			"lattice point (%d, %d) uses its mask's texture" % [c, r])
		checked += 1
	assert_true(checked > 0, "ground sprites were checked")
	renderer.free()
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `render` takes no biome argument and `corner_mask` does not exist.

- [ ] **Step 3: Rewrite the ground layer**

In `game/map_renderer.gd`, delete **only** the `_GRASS` and `_PATH` preloads.

**Leave `_TREE`, `_STONE`, `_SPIKE`, `_FIRE`, `_CASTLE`, `_CAVE` and
`_PROP_TEXTURES` exactly where they are** — Tasks 7 and 8 replace them.
Deleting them here leaves `_draw_endpoints`, `_scatter_decoration` and
`_draw_blocked` referencing undefined identifiers, which is a **parse error**,
not a test failure: `map_renderer.gd` would fail to compile and take the whole
suite down as a load error. The old `assets/map/*.png` survive until Task 10,
so those preloads still resolve.

Then add a biome field:

```gdscript
var _biome: StringName = Biomes.FIRST
```

Change the signature and the ground call in `render`:

```gdscript
func render(tiles: Array, rng: Rng = null, biome: StringName = Biomes.FIRST) -> void:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DECORATION_SEED)
	_biome = biome
	_tiles = tiles
	...
```

Replace `_draw_ground` with:

```gdscript
## Ground is drawn from a corner-mask lattice sampled at TILE CENTRES: each
## sprite spans the square between four adjacent centres, so the grid is
## (cols + 1) x (rows + 1) and every sprite sits half a tile up and left of its
## lattice point.
##
## Anchoring anywhere else moves the road off the world-space route PathFinder
## emits - enemies follow tile centres, so the road has to be centred on them.
## The half-tile overhang this produces falls outside the viewport on the left,
## top and bottom, and under TowerPanel's 95%-opaque background on the right.
##
## Two alternatives were measured and rejected (spec section 7.1): sampling at
## grid intersections draws a 70px road but floods the one-tile buildable strip
## between the row-8 and row-10 legs, and a half-tile lattice minifies the
## blend detail into a straight-edged bar.
func _draw_ground() -> void:
	var half := Tiles.TILE_SIZE / 2
	for r in range(_rows + 1):
		for c in range(_cols + 1):
			var texture := Biomes.blend_texture(_biome, corner_mask(c, r))
			_place(texture, c, r, Tiles.TILE_SIZE, _Z_GROUND,
				Vector2(-half, -half))

## The four tiles surrounding lattice point (c, r), as a bitmask.
## Bit order is fixed: TL=1, TR=2, BL=4, BR=8, set means road.
## Public so tests can assert the lattice without inspecting sprites.
func corner_mask(c: int, r: int) -> int:
	var mask := 0
	if _is_road(c - 1, r - 1):
		mask |= 1
	if _is_road(c, r - 1):
		mask |= 2
	if _is_road(c - 1, r):
		mask |= 4
	if _is_road(c, r):
		mask |= 8
	return mask

## Out of bounds reads as ground, which is what closes the lattice at the map
## edge without a special case.
func _is_road(c: int, r: int) -> bool:
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return false
	return _tiles[r][c] in Tiles.WALKABLE
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: `test_map_renderer.gd`'s ground tests PASS. Decoration, endpoint and blocked-tile tests in that file will still fail — they reference the deleted preloads and are fixed in Tasks 7 and 8.

- [ ] **Step 5: Commit**

```bash
git add game/map_renderer.gd test/test_map_renderer.gd
git commit -m "Draw the ground from a corner-mask lattice"
```

---

### Task 7: Per-biome props and an honest footprint set

**Files:**
- Modify: `game/map_renderer.gd` (`_scatter_decoration`, `_draw_blocked`, `_place`, `prop_footprints`, and now the `_TREE`/`_STONE`/`_SPIKE`/`_FIRE`/`_PROP_TEXTURES` declarations Task 6 deliberately left in place)
- Modify: `test/test_map_renderer.gd` (the four prop path constants, and every test that keys off them)

**The prop path constants are this task's job.** `test/test_map_renderer.gd:9-12`
declares `_SPIKE_PATH`, `_FIRE_PATH`, `_STONE_PATH` and `_TREE_PATH` as
`res://assets/map/*.png`, and the scatter tests (spike counts, the fire cap, the
stone/tree split across seeds, the exclusion zone), the aspect-ratio test, the
mipmap-filter test and both footprint tests all match on them. Repoint all four
at the forest biome — `res://assets/kenney/forest/spike.png` and so on — since
every one of those tests renders with the default biome. **Their logic does not
change**; only the four string values do.

**Interfaces:**
- Consumes: `Biomes.prop_texture` from Task 2, `corner_mask` from Task 6.
- Produces: `prop_footprints()` unchanged in signature — still `Array` of `{"pos": Vector2, "radius": float}`.

**None of the scatter rules change.** Spike count, the fire cap, the walkable-adjacency test and the blocked-tile stone/tree split all keep their existing behaviour and their existing tests.

- [ ] **Step 1: Write the failing test**

Add to `test/test_map_renderer.gd`:

```gdscript
func test_props_come_from_the_biome_being_rendered() -> bool:
	var forest := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	forest.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var forest_paths := {}
	for child in forest.get_children():
		if child is Sprite2D and child.z_index == 1:
			forest_paths[child.texture.resource_path] = true
	forest.free()

	var ice := MapRenderer.new()
	ice.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"ice")
	var shared := 0
	for child in ice.get_children():
		if child is Sprite2D and child.z_index == 1:
			if forest_paths.has(child.texture.resource_path):
				shared += 1
	ice.free()
	# The endpoints are shared across biomes; the props are not.
	assert_true(shared <= 2, "ice props are not forest props (%d shared)" % shared)
	return true

func test_prop_footprints_cover_only_the_props() -> bool:
	# Endpoints are excluded on purpose - they are drawn 3 tiles wide and a
	# footprint from one would sterilise the ground around spawn and goal.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var footprints := renderer.prop_footprints()
	assert_true(footprints.size() > 0, "the demo map scatters props")
	for entry in footprints:
		var f: Dictionary = entry
		var radius: float = f["radius"]
		assert_true(radius > 0.0, "a footprint has a positive radius")
		# A prop is fitted into one 48px tile, so no footprint may exceed half
		# of it. A radius above 24 means an endpoint leaked in - those are
		# drawn 3 tiles wide and would carry a 72px radius, sterilising the
		# ground around spawn and goal.
		assert_true(radius <= float(Tiles.TILE_SIZE) / 2.0,
			"footprint radius %f fits inside one tile" % radius)
	renderer.free()
	return true

func test_every_prop_sprite_contributes_exactly_one_footprint() -> bool:
	# Guards the set-membership swap: a prop that fails to register produces no
	# blocking circle at all and towers build straight through it, which no
	# other assertion here would notice.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var props := 0
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == 1 \
				and not child.texture.resource_path.ends_with("castle.png") \
				and not child.texture.resource_path.ends_with("cave.png"):
			props += 1
	assert_eq(renderer.prop_footprints().size(), props,
		"one footprint per prop sprite, endpoints excluded")
	renderer.free()
	return true

func test_a_props_blocking_radius_is_half_the_tile_box_it_is_fitted_into() -> bool:
	# _place normalises every prop's LONGEST axis to exactly TILE_SIZE, so the
	# radius prop_footprints derives is always TILE_SIZE / 2 whatever the
	# source dimensions are. That is precisely why trimming has to happen at
	# bake time and cannot be compensated for here: the radius does not move,
	# so the ART has to grow to fill it. tile130 untrimmed draws its subject at
	# ~23px inside this same 24px radius - a blocking circle over twice the
	# area of the visible art. test_prop_assets.gd's tight-bbox gate is what
	# holds the other half of this bargain.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var footprints := renderer.prop_footprints()
	assert_true(footprints.size() > 0, "the demo map scatters props")
	for entry in footprints:
		var f: Dictionary = entry
		assert_almost_eq(f["radius"], float(Tiles.TILE_SIZE) / 2.0, 0.001,
			"footprint radius is half the tile box")
	renderer.free()
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `map_renderer.gd` does not compile; `_SPIKE`, `_FIRE`, `_TREE`, `_STONE` and `_PROP_TEXTURES` were deleted in Task 6.

- [ ] **Step 3: Track props in a set and resolve them per biome**

In `game/map_renderer.gd`, add the set beside `_decorations`:

```gdscript
## Sprites that count as solid props, recorded as they are created.
##
## This replaces the old _PROP_TEXTURES const array of preloads, which could
## not express a per-biome prop set. Recording at creation is also strictly
## more robust than comparing textures after the fact - two biomes could
## legitimately share a texture without both being props.
var _prop_sprites := {}
```

Clear it in `render` alongside `_decorations.clear()`:

```gdscript
	_decorations.clear()
	_prop_sprites.clear()
```

Add a prop-placing wrapper next to `_place`:

```gdscript
## Places a prop and records it as one, so prop_footprints can find it.
func _place_prop(slot: StringName, col: int, row: int) -> Sprite2D:
	var sprite := _place(Biomes.prop_texture(_biome, slot), col, row,
		Tiles.TILE_SIZE, _Z_OVERLAY)
	_prop_sprites[sprite] = true
	return sprite
```

Rewrite `prop_footprints`'s filter to read the set — the radius arithmetic and the doc comment about over-covering stay exactly as they are:

```gdscript
	for child in get_children():
		if not (child is Sprite2D):
			continue
		var sprite: Sprite2D = child
		if not _prop_sprites.has(sprite):
			continue
```

Swap the four placement call sites to `_place_prop`:

```gdscript
	# in _scatter_decoration, the spike loop:
	_decorations[t] = _place_prop(&"spike", t.x, t.y)
	# in _scatter_decoration, the fire loop:
	_decorations[t] = _place_prop(&"fire", t.x, t.y)
	# in _draw_blocked:
	_place_prop(&"stone" if stones.has(t) else &"tree", t.x, t.y)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS for every test in `test_map_renderer.gd` except the endpoint one, which Task 8 fixes. `test_placement.gd` stays green — its footprint inputs are constructed by hand, not read from the renderer.

- [ ] **Step 5: Commit**

```bash
git add game/map_renderer.gd test/test_map_renderer.gd
git commit -m "Resolve props per biome and track them for footprints"
```

---

### Task 8: Endpoints and wiring the biome through

**Files:**
- Modify: `game/map_renderer.gd` (`_draw_endpoints`)
- Modify: `data/maps.gd` (add `biome` to `demoMap`)
- Modify: `game/game_board.gd` (`_ready` passes the biome)
- Modify: `test/test_map_renderer.gd` (the `_CAVE_PATH`/`_CASTLE_PATH` constants at lines 13-14, and the endpoint test)
- Modify: `test/test_data_tables.gd` (map def gains a key)

**The last two path constants are this task's job.** `_CAVE_PATH` and
`_CASTLE_PATH` at `test/test_map_renderer.gd:13-14` still point at
`res://assets/map/`. Repoint them to `res://assets/kenney/cave.png` and
`res://assets/kenney/castle.png` — note these are **not** under a biome
directory, because the endpoints are shared across biomes. After this task no
`res://assets/map/` string remains in the file, which is what lets Task 10
delete that directory.

**Interfaces:**
- Consumes: `assets/kenney/castle.png` and `cave.png` from Task 4, `Biomes` from Task 2.
- Produces: `Maps.DEFS[&"demoMap"]["biome"] == &"forest"`. `GameBoard` renders with that biome.

- [ ] **Step 1: Write the failing test**

Update the endpoint test in `test/test_map_renderer.gd` to reference the new paths, and add to `test/test_data_tables.gd`:

```gdscript
func test_every_map_names_a_biome_that_exists() -> bool:
	for name in Maps.DEFS:
		var def: Dictionary = Maps.DEFS[name]
		assert_true(def.has("biome"), "%s names a biome" % name)
		assert_true(Biomes.KINDS.has(def["biome"]),
			"%s's biome %s is registered" % [name, def["biome"]])
	return true

func test_the_first_map_is_the_forest() -> bool:
	assert_eq(Maps.get_def(Maps.FIRST)["biome"], &"forest",
		"The Pass is a forest map")
	return true
```

And in `test/test_map_renderer.gd`, replace the texture paths asserted by `test_endpoints_are_placed_and_scaled_correctly` with `res://assets/kenney/cave.png` and `res://assets/kenney/castle.png`, keeping its position and scale assertions unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `Maps.DEFS[&"demoMap"]` has no `biome` key, and the endpoint sprites still carry no texture because `_draw_endpoints` references deleted preloads.

- [ ] **Step 3: Wire it through**

In `game/map_renderer.gd`, add the two endpoint preloads back — they are shared across biomes, so they stay constants:

```gdscript
## Shared across every biome: the goal and spawn markers are player landmarks,
## not scenery, and are the same object whatever the map is made of.
const _CASTLE := preload("res://assets/kenney/castle.png")
const _CAVE := preload("res://assets/kenney/cave.png")
```

`_draw_endpoints` keeps its body exactly as it is — the offset, the 3-tile scale and `_Z_OVERLAY` are unchanged, and it already refers to `_CAVE` and `_CASTLE`.

In `data/maps.gd`:

```gdscript
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		"tower_budget": 16, "starting_gold": 100,
		"biome": &"forest",
		"next": &"map2",
	},
```

In `game/game_board.gd`'s `_ready`, pass the biome:

```gdscript
	_map_renderer.render(_tiles, null, def["biome"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS — the whole suite green except the road-width test, which Task 9 adds.

- [ ] **Step 5: Commit**

```bash
git add game/map_renderer.gd data/maps.gd game/game_board.gd test/
git commit -m "Point the endpoints at the composed markers and wire the biome through"
```

---

### Task 9: Retune the no-build corridor to the drawn road

**Files:**
- Modify: `sim/placement.gd` (`PATH_HALF_WIDTH`)
- Test: `test/test_road_width.gd`

**Interfaces:**
- Consumes: the rendered ground layer from Task 6.
- Produces: `Placement.PATH_HALF_WIDTH == 14.0`.

This is the spec §3 amendment. The Kenney road draws 23px wide; a 26px half-width would refuse placement across a 14px band of open-looking ground on each side of it. Same principle as Task 3's prop trimming — art and collision must agree — arriving from the road side.

- [ ] **Step 1: Write the failing test**

Create `test/test_road_width.gd`:

```gdscript
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
	assert_almost_eq(Placement.PATH_HALF_WIDTH, drawn / 2.0, 6.0,
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `PATH_HALF_WIDTH` is still 26.0.

- [ ] **Step 3: Retune the constant**

In `sim/placement.gd`, change the constant and replace its comment:

```gdscript
## Half the width of the corridor towers may not be built in, measured from the
## path centreline.
##
## Tied to what the art draws, not to the tile size. The Kenney road lands at
## about 23px wide (Kenney draws ~3-tile corridors; this map's roads are one
## tile, so only the blend lobes carry it), which puts the honest half-width at
## 14 rather than the 26 the old 48px reference road justified. Leaving it at
## 26 would refuse placement across a 14px band of open-looking ground on each
## side of the road - the same invisible-wall defect that untrimmed prop
## footprints cause, arriving from the road side.
##
## test/test_road_width.gd re-measures the road off the committed blend tiles
## and fails if this drifts away from it.
const PATH_HALF_WIDTH := 14.0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, whole suite green.

- [ ] **Step 5: Commit**

```bash
git add sim/placement.gd test/test_road_width.gd
git commit -m "Retune the no-build corridor to the road the art draws"
```

---

### Task 10: Retire the old art and verify by eye

**Files:**
- Delete: `assets/map/*.png`, `assets/map/*.png.import`, `tools/slice_atlas.gd`, `tools/slice_atlas.gd.uid`
- Rewrite: `test/test_map_assets.gd`
- Modify: `README.md`, `CONTINUE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no references to `res://assets/map/` anywhere in the tree.

- [ ] **Step 1: Confirm nothing still references the old assets**

```bash
grep -rn "assets/map/" --include="*.gd" --include="*.tscn" . | grep -v "^./reference/"
grep -rn "slice_atlas" --include="*.gd" --include="*.md" . | grep -v "^./reference/"
```

Expected: matches only in `test/test_map_assets.gd`, `tools/slice_atlas.gd` and docs. Any match in `game/`, `data/`, `sim/` or `ui/` means an earlier task missed a call site — fix that before deleting anything.

- [ ] **Step 2: Delete the old art and tool**

```bash
git rm -r assets/map tools/slice_atlas.gd tools/slice_atlas.gd.uid
```

- [ ] **Step 3: Replace the old asset gate**

`test/test_map_assets.gd` gated `assets/map/`, which no longer exists. Its two gates now live in `test_blend_tiles.gd` (ground opacity), `test_prop_assets.gd` (prop margins) and `test_endpoint_assets.gd` (endpoint margins), so delete the file rather than leaving an empty suite — `run_tests.gd` fails a suite with zero test methods.

```bash
git rm test/test_map_assets.gd test/test_map_assets.gd.uid
```

The `_EDGE_PIXEL_BUDGET` exemptions are **deleted, not carried over**. They recorded flaws in the old reference sheet — a castle packed against neighbouring rocks, a campfire clipped by its neighbour. Composed and trimmed Kenney art has none of them, and per that file's own instruction a budget is a record of a limit in the artwork, not a tolerance for a worse crop.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. Record the check count — it should exceed the 5214 the branch started from.

- [ ] **Step 5: Screenshot all three biomes**

A green suite sees neither layout nor filtering. Through the Godot MCP, launch the game and capture the board, then temporarily point `Maps.DEFS[&"demoMap"]["biome"]` at `&"ice"` and `&"desert"` and capture each. Revert that edit afterwards.

Check each capture for: no seams between ground sprites, road edges reading as organic curves rather than staircases, the buildable grass strip between the row-8 and row-10 legs still visibly grass, props sitting inside their tiles, and the tower atlas frames aligned in the build panel. Also read the suite's expected stderr — this project treats it as a diagnostic channel, not noise.

- [ ] **Step 6: Credit the pack**

Add to `README.md`, and update `CONTINUE.md`'s asset section to describe `assets/kenney/` and `tools/bake_kenney.gd` instead of the retired atlas slicer:

```markdown
## Art

Map, prop, endpoint and tower art is from Kenney's
[Tower Defense (Top-Down)](https://kenney.nl/assets/tower-defense-top-down)
pack, licensed CC0. `tools/bake_kenney.gd` bakes the committed assets under
`assets/kenney/` from a copy extracted to `reference/kenney-td/`, which is
gitignored. The ice biome's ground is a recolour of the pack's sand, since the
pack ships no snow. Enemy sprites are not from this pack.
```

- [ ] **Step 7: Commit and push**

```bash
git add -A
git commit -m "Retire the reference art and credit the Kenney pack"
git push
```

---

## Notes for the executor

**The two traps, restated.** Both cost real time to find and both look fine until rendered:

1. Every tile index in this plan is an **individual-PNG index**. The tilesheet packs 70 of the 299 tiles in a different order. If you verify an index against a tilesheet contact sheet you will "correct" it into a bug.
2. `_select_family` is not optional cleverness. Corner classification alone picks a table that passes the corner test and tiles wrongly. If `test_blend_tiles.gd`'s road-fraction gate goes red, the bake picked the inverted family — fix the selection, never the threshold.

**On the road width.** 23px is not a bug to fix, it is the measured consequence of putting a pack drawn for 3-tile corridors onto 1-tile roads. It was chosen over a 70px alternative that floods buildable ground and a 36px alternative that flattens the edges. Whether 14 is the right `PATH_HALF_WIDTH` in play is a playtest question — turn the constant and re-run, per this project's convention for balance.

**Deferred to the next branch:** the map 2 and map 3 layouts, map-to-map progression, and `sim/economy.gd:42`'s `limit_bonus_map2`, which stays dormant until a second map exists to trigger it.
