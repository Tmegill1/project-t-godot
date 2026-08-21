# Illustrated Art Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every visual asset with the illustrated sprite sheet — 16 towers, three enemy types with per-spawn variety, three environments of terrain and road, decor and endpoints.

**Architecture:** A new bake tool cuts the sheet into individual PNGs using per-section descriptors (origin, pitch, count) validated by margin gates, keying out the opaque navy background. The road drops the Kenney corner-mask lattice for a 4-bit edge mask with rotation, one sprite per tile. The biome layer, the tower atlas geometry and every rule in `sim/` survive unchanged.

**Tech Stack:** Godot 4.7.1.stable, GDScript, the project's own `TestCase`/`run_tests.gd` harness.

**Spec:** `docs/superpowers/specs/2026-08-20-illustrated-art-swap-design.md`

## Global Constraints

- Godot 4.7.1.stable. Suite: `godot --headless --quit --script test/run_tests.gd` from the repo root.
- After adding assets or a new `class_name`, run `godot --headless --import`, then `git checkout -- project.godot` — the reimport writes a stray blank line under `[autoload]` that must never be committed. Check `git status` before committing.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. A test recording zero assertions fails the run, as does a suite file with zero test methods. See `test/case.gd`.
- Prefer flat `test_*` bodies over helper delegation; where a helper is unavoidable, assert on its result.
- Asset-gate tests read committed PNG bytes via `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`, never the imported `Texture2D`. Renderer tests compare `Texture2D.resource_path`.
- Every task ends on a green suite. Baseline at the start of this plan: **6688 checks across 36 files, 0 failing**.
- A green run is deliberately noisy — it emits `push_error` from refusal paths under test. Judge pass/fail from the final summary line, not stderr.
- `data/` and `sim/` must contain no engine calls; `test/test_sim_purity.gd` enforces this recursively. Anything needing `load()` belongs in `game/`.
- `Tiles.TILE_SIZE` stays **48**. Tower atlas geometry stays **5 columns × 96px frames, 20 frames, 480×384, row-major**.
- Source sheet background is `(9, 22, 28)`; the sheet has **no alpha channel**.
- Terrain and road rows use **pitch 67**, tiles **64×64**, **6 tiles per row**.
- `Enemies.KINDS` stays `[slime, ogre, bee]` and every stat and wave schedule is unchanged — only sprites change.
- Do not edit `sim/placement.gd` except the single constant in Task 8.

---

### Task 1: Vendor the sheet and extract the terrain tiles

**Files:**
- Create: `tools/bake_sheet.gd`
- Create: `assets/art/{forest,desert,ice}/ground_N.png` (6 each)
- Test: `test/test_ground_tiles.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `res://assets/art/<biome>/ground_0.png` … `ground_5.png` for biomes `forest`, `desert`, `ice`.

The sheet's `grass` row becomes the `forest` biome, matching the existing biome names.

- [ ] **Step 1: Vendor the sheet**

```bash
mkdir -p ~/Projects/project-t-godot/reference/illustrated-sheet
cp ~/Desktop/AI_Towerdefense_sprite_sheet.png ~/Projects/project-t-godot/reference/illustrated-sheet/sheet.png
cd ~/Projects/project-t-godot && git status --short
```

Expected: nothing shown — `reference/` is already gitignored, matching how `reference/kenney-td/` is handled. The sheet is not committed; the extracted subset under `assets/art/` is.

- [ ] **Step 2: Write the failing test**

Create `test/test_ground_tiles.gd`:

```gdscript
extends TestCase

# Acceptance gates for the ground tiles cut from the illustrated sheet.
#
# The sheet has NO alpha channel - every sprite sits on an opaque navy
# background at (9, 22, 28) - so extraction keys that colour out. Sprite
# outlines sit close to it, which makes the key threshold a real tunable
# rather than a formality: too tight eats outlines, too loose leaves a dark
# halo that shows as fringing once the tile is drawn over another.
#
# The margin gate below is also what catches a misaligned extraction. Rows are
# cut on a fixed pitch of 67 from a per-row origin; if an origin is off by a
# few pixels the crop carries a sliver of its neighbour, which shows up as
# opaque pixels on an edge that should be clear.

const _BIOMES := ["forest", "desert", "ice"]
const _TILES_PER_ROW := 6
const _MARGIN_ALPHA_MAX := 8

func _ground(biome: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/%s/ground_%d.png" % [biome, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _alpha8(img: Image, x: int, y: int) -> int:
	return int(round(img.get_pixel(x, y).a * 255.0))

func test_every_biome_ships_six_ground_tiles() -> bool:
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
	return true

func test_ground_tiles_carry_no_navy_background() -> bool:
	# The key either worked or it did not. A tile still carrying sheet
	# background would draw a dark box over its neighbours.
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
			if img == null:
				continue
			var navy := 0
			for y in range(0, img.get_height(), 3):
				for x in range(0, img.get_width(), 3):
					var c := img.get_pixel(x, y)
					if c.a > 0.5 and c.r < 0.10 and c.g < 0.14 and c.b < 0.16:
						navy += 1
			assert_eq(navy, 0, "%s/ground_%d has no leftover navy" % [biome, i])
	return true

func test_ground_tiles_keep_a_clear_margin_so_no_neighbour_bled_in() -> bool:
	for biome in _BIOMES:
		for i in _TILES_PER_ROW:
			var img := _ground(biome, i)
			assert_true(img != null, "%s/ground_%d.png decodes" % [biome, i])
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
				"%s/ground_%d edge peak %d - a neighbour bled in or the origin is off"
					% [biome, i, peak])
	return true

func test_the_three_biomes_are_visibly_different_ground() -> bool:
	# Guards a descriptor copy-paste that points two biomes at one sheet row.
	var means := {}
	for biome in _BIOMES:
		var img := _ground(biome, 0)
		assert_true(img != null, "%s/ground_0.png decodes" % biome)
		if img == null:
			continue
		var acc := Vector3.ZERO
		var n := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					acc += Vector3(c.r, c.g, c.b)
					n += 1
		means[biome] = acc / maxf(1.0, float(n))
	assert_true(means["forest"].g > means["desert"].g, "forest is greener than desert")
	assert_true(means["ice"].b > means["desert"].b, "ice is bluer than desert")
	return true
```

- [ ] **Step 3: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `assets/art/` does not exist, so every `_ground` returns null.

- [ ] **Step 4: Write the bake tool**

Create `tools/bake_sheet.gd`:

```gdscript
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
const GROUND_ROWS := {
	&"forest": {"x": 131, "y": 600},
	&"desert": {"x": 111, "y": 772},
	&"ice": {"x": 131, "y": 854},
}
const GROUND_TILES_PER_ROW := 6

func _init() -> void:
	var sheet := Image.load_from_file(SHEET)
	assert(sheet != null, "sheet.png not found - see the header for where it goes")
	sheet.convert(Image.FORMAT_RGBA8)
	_bake_ground(sheet)
	print("bake_sheet: done")
	quit()

## Replaces the opaque navy background with transparency.
func _key(img: Image) -> Image:
	var out := img.duplicate()
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
```

- [ ] **Step 5: Run the bake and import**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
git status
```

Expected: `assets/art/{forest,desert,ice}/ground_0..5.png` exist.

- [ ] **Step 6: Run tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. If the margin gate fails for a row, nudge that row's `x` origin by a pixel or two and re-bake — a sliver of the neighbouring tile is the cause. Do not relax `_MARGIN_ALPHA_MAX`.

- [ ] **Step 7: Commit**

```bash
git add tools/bake_sheet.gd assets/art test/test_ground_tiles.gd
git commit -m "Cut the illustrated sheet's ground tiles for three biomes"
```

---

### Task 2: Road pieces and the composed straight

**Files:**
- Modify: `tools/bake_sheet.gd`
- Create: `assets/art/<biome>/road_<mask>.png` for masks 0, 3, 5, 7, 15
- Test: `test/test_road_pieces.gd`

**Interfaces:**
- Consumes: `_cell`, `_key`, `_trim` from Task 1.
- Produces: five road pieces per biome, each named by the connection mask it is drawn for. Bit order is **N=1, E=2, S=4, W=8**.

**The sheet ships no straight.** Its path row holds a solid tile and two cross variants (mask 15), two curves (mask 3) and a T (mask 7). A one-tile-wide road is mostly straights, and using the solid tile leaves those cells with no grass edging — visibly inconsistent where a straight meets a curve. The straight is therefore **composed from the cross**: mask its east and west arms with grass lifted from the cross's own corners, giving mask 5 (north-south).

Only the forest row has grass edging in the sheet; desert and ice rows are cut the same way from their own rows.

**Source cells**, at pitch 67 from the path row origin `x = 78, y = 697`:

| Slot | Piece | Mask |
|---|---|---|
| 0 | solid | 0 |
| 2 | curve | 3 |
| 4 | T | 7 |
| 5 | cross | 15 |

- [ ] **Step 1: Write the failing test**

Create `test/test_road_pieces.gd`:

```gdscript
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
	"forest": {"surround": Vector3(88, 101, 14), "road": Vector3(132, 103, 39)},
	"desert": {"surround": Vector3(170, 123, 62), "road": Vector3(132, 103, 39)},
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

func test_road_pieces_carry_no_navy_background() -> bool:
	for biome in _BIOMES:
		for mask in _MASKS:
			var img := _road(biome, mask)
			assert_true(img != null, "%s/road_%02d.png decodes" % [biome, mask])
			if img == null:
				continue
			var navy := 0
			for y in range(0, img.get_height(), 3):
				for x in range(0, img.get_width(), 3):
					var c := img.get_pixel(x, y)
					if c.a > 0.5 and c.r < 0.10 and c.g < 0.14 and c.b < 0.16:
						navy += 1
			assert_eq(navy, 0, "%s/road_%02d has no leftover navy" % [biome, mask])
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — no `road_*.png` exists.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
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

## Where each biome's road and surround land after recolouring. Measured off
## the committed ground tiles. Ice recolours the road too: a dirt track across
## a frozen field reads wrong.
const ROAD_PALETTES := {
	&"forest": {"surround": Color8(88, 101, 14), "road": Color8(132, 103, 39)},
	&"desert": {"surround": Color8(170, 123, 62), "road": Color8(132, 103, 39)},
	&"ice": {"surround": Color8(91, 145, 190), "road": Color8(200, 220, 235)},
}

## The two materials in the grass row, measured by clustering a solid piece.
const SOURCE_SURROUND := Vector3(53.2, 65.9, 14.4)
const SOURCE_ROAD := Vector3(131.8, 102.8, 39.0)

## Builds one mask by masking the cross's absent arms with adjacent corner
## material, then softening the paste seams.
##
## The mirror is what keeps the patch in the piece's own palette and edging -
## a flat fill would read as a hole. Bit order is N=1, E=2, S=4, W=8.
func _compose_road(cross: Image, mask: int) -> Image:
	var out: Image = cross.duplicate()
	var n := out.get_width()
	var arm := n / 3
	if not mask & 1:
		_patch_arm(out, cross, Rect2i(arm, 0, arm, arm), Rect2i(0, 0, arm, arm))
	if not mask & 4:
		_patch_arm(out, cross, Rect2i(arm, n - arm, arm, arm), Rect2i(0, n - arm, arm, arm))
	if not mask & 8:
		_patch_arm(out, cross, Rect2i(0, arm, arm, arm), Rect2i(0, 0, arm, arm))
	if not mask & 2:
		_patch_arm(out, cross, Rect2i(n - arm, arm, arm, arm), Rect2i(n - arm, 0, arm, arm))
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
```

Call it from `_init` after `_bake_ground(sheet)`:

```gdscript
	_bake_roads(sheet)
```

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: PASS. If `test_each_piece_connects_exactly_where_its_name_says` fails, the slot-to-mask table is wrong — fix `ROAD_SLOTS`, never the test's expectation.

- [ ] **Step 5: Look at the composed straight**

The composition is the one piece not drawn by an artist. Render the six forest pieces side by side and confirm the straight reads as a road with surround on both sides, and that its edges meet the curve and cross pieces without an obvious seam. If it does not, adjust `_compose_straight`'s arm width and re-bake.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_sheet.gd assets/art test/test_road_pieces.gd
git commit -m "Cut the road pieces and compose the straight the sheet lacks"
```

---

### Task 3: The tower atlas

**Files:**
- Modify: `tools/bake_sheet.gd`
- Modify: `assets/towers.png` (overwritten in place)
- Test: `test/test_tower_atlas.gd`

**Interfaces:**
- Consumes: `_key`, `_trim` from Task 1.
- Produces: `res://assets/towers.png` at the unchanged 5 × 96px, 20-frame, 480×384 geometry.

**Nothing outside the bake tool changes.** `Tower.frame_region`, `data/towers.gd`'s `sprite_frame` and `upgrade_frames`, `UpgradesSim.sprite_frame_for` and `ui/tower_panel.gd` all keep working, because the atlas keeps its geometry and its frame numbering. Each kind's four `upgrade_frames` receive that tower type's four levels in order.

**Sheet positions**, all in the tower band at `y = 40`, height 165:

| Kind | Type | Level x offsets |
|---|---|---|
| `basic` | Archer | 23, 114, 212, 309 |
| `fast` | Cannon | 439, 532, 637, 739 |
| `mortar` | Mage | 880, 966, 1052, 1140 |
| `long` | Barracks | 1247, 1318, 1389, 1460 |

- [ ] **Step 1: Write the failing test**

Replace `test/test_tower_atlas.gd`'s body with:

```gdscript
extends TestCase

# assets/towers.png is consumed through Tower.frame_region on a 5-column grid
# of 96px frames, by both the placed tower and the build panel's icons. The
# illustrated swap changes the art inside those frames and nothing else, which
# is why no tower code changed with it.
#
# Frames 3, 4, 14 and 15 are unreferenced by any tower kind and stay blank.

const _ATLAS := "res://assets/towers.png"
const _COLUMNS := 5
const _FRAME := 96
const _UNUSED_FRAMES := [3, 4, 14, 15]

func _atlas() -> Image:
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
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	assert_eq(img.get_width(), _COLUMNS * _FRAME, "atlas width is 5 frames")
	assert_eq(img.get_height(), 4 * _FRAME, "atlas height is 4 frames")
	assert_eq(Tower.SHEET_COLUMNS, _COLUMNS, "Tower.SHEET_COLUMNS still 5")
	assert_eq(Tower.FRAME_SIZE, _FRAME, "Tower.FRAME_SIZE still 96")
	return true

func test_every_frame_a_tower_kind_names_carries_art() -> bool:
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.get_def(kind)
		for frame in def["upgrade_frames"]:
			assert_true(_opaque_pixels(img, int(frame)) > 0,
				"%s frame %d carries art" % [kind, int(frame)])
	return true

func test_the_unreferenced_frames_are_blank() -> bool:
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for frame in _UNUSED_FRAMES:
		assert_eq(_opaque_pixels(img, int(frame)), 0, "unused frame %d is blank" % int(frame))
	return true

func test_a_kind_s_levels_grow_across_its_upgrade_frames() -> bool:
	# The upgrade read this swap buys: four hand-drawn states per tower, each
	# more substantial than the last. A bake that wrote the same level into
	# every frame would pass every other assertion here.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var frames: Array = Towers.get_def(kind)["upgrade_frames"]
		var first := _opaque_pixels(img, int(frames[0]))
		var last := _opaque_pixels(img, int(frames[frames.size() - 1]))
		assert_true(last > first,
			"%s's top level covers more than its first (%d vs %d)" % [kind, last, first])
	return true

func test_every_referenced_frame_keeps_a_transparent_margin() -> bool:
	# Art running to a frame edge bleeds into the neighbouring frame when the
	# AtlasTexture samples it.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n := int(frame)
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
Expected: FAIL — `test_a_kind_s_levels_grow_across_its_upgrade_frames` fails against the Kenney atlas, whose frames do not grow monotonically.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
const ATLAS_COLUMNS := 5
const ATLAS_ROWS := 4
const ATLAS_FRAME := 96
const ATLAS_INSET := 6

const TOWER_BAND_Y := 40
const TOWER_BAND_H := 165

## kind -> the four level x offsets, in level order. The sheet's tower types
## map onto the game's kinds by role: Archer is the cheap all-rounder, Cannon
## the fast one, Mage the splash one, Barracks the long-range one.
const TOWER_LEVELS := {
	&"basic": [23, 114, 212, 309],
	&"fast": [439, 532, 637, 739],
	&"mortar": [880, 966, 1052, 1140],
	&"long": [1247, 1318, 1389, 1460],
}

func _bake_tower_atlas(sheet: Image) -> void:
	var out := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for kind in TOWER_LEVELS:
		var frames: Array = Towers.DEFS[kind]["upgrade_frames"]
		var xs: Array = TOWER_LEVELS[kind]
		for level in xs.size():
			# The last level in a group has no following offset to measure
			# against, so it falls back to 96 - clamped to the sheet's right
			# edge, because the barracks group's last level starts at 1460 and
			# 1460 + 96 would read past the 1536-wide sheet.
			var width: int = 96
			if level + 1 < xs.size():
				width = int(xs[level + 1]) - int(xs[level])
			width = mini(width, sheet.get_width() - int(xs[level]))
			var region := Image.create_empty(width, TOWER_BAND_H, false, Image.FORMAT_RGBA8)
			region.blit_rect(sheet, Rect2i(int(xs[level]), TOWER_BAND_Y, width, TOWER_BAND_H),
				Vector2i.ZERO)
			var sprite := _trim(_key(region))
			# Fit inside the frame preserving aspect, inset so no art touches
			# a frame edge - an AtlasTexture sampling a frame would otherwise
			# pull in its neighbour.
			var box := ATLAS_FRAME - ATLAS_INSET * 2
			var factor := float(box) / float(maxi(sprite.get_width(), sprite.get_height()))
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
```

Call it from `_init` after `_bake_roads(sheet)`.

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: PASS.

- [ ] **Step 5: Look at the atlas**

Render `assets/towers.png` at 2× with frame numbers overlaid and confirm each kind's four frames show that tower type's four levels in ascending order, and that frames 3, 4, 14 and 15 are empty. A wrong `TOWER_LEVELS` offset shows immediately as a clipped or duplicated tower.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_sheet.gd assets/towers.png test/test_tower_atlas.gd
git commit -m "Rebake the tower atlas from the illustrated sheet's sixteen levels"
```

---

### Task 4: Enemy sprites and their per-spawn variants

**Files:**
- Modify: `tools/bake_sheet.gd`
- Create: `assets/art/enemies/<kind>/variant_N.png`
- Test: `test/test_enemy_sprites.gd`

**Interfaces:**
- Consumes: `_key`, `_trim` from Task 1.
- Produces: `res://assets/art/enemies/<kind>/variant_0.png` … for kinds `slime`, `ogre`, `bee`.

**The kinds and their stats do not change.** `data/waves.gd` schedules twenty waves by kind name, so introducing new kinds is balance work. The three existing kinds get new sprites, mapped by what each stat profile already is:

| Kind | Profile | Sheet row | Row y |
|---|---|---|---|
| `slime` | 100 speed, 5 hp, common early spawn | Goblin | 216–288 |
| `ogre` | 60 speed, 8 hp, slow and tanky | Ogre | 438–516 |
| `bee` | 150 speed, 3 hp, fastest and frailest | Bat | 521–586 |

The Goblin Shaman and Troll rows are extracted to `assets/art/enemies/_unused/` for the deferred enemy-variety feature. They are not referenced by any code.

**The rows are variants, not animation.** Consecutive frames differ about four times less than a real walk cycle's do, and the difference is flat across every frame lag — no periodicity, which is what a cycle would show. Each is a usable alternate look, so an enemy picks one at spawn.

- [ ] **Step 1: Write the failing test**

Create `test/test_enemy_sprites.gd`:

```gdscript
extends TestCase

# One directory of variants per enemy kind. The sheet's rows are NOT animation
# frames - measured, not assumed: a real walk cycle's frame-to-frame difference
# varies with lag and dips as the cycle closes, while these rows are flat
# across every lag. So they are used as per-spawn variety instead, and an
# enemy picks one when it spawns.

const _KINDS := ["slime", "ogre", "bee"]
const _MIN_VARIANTS := 4
const _MARGIN_ALPHA_MAX := 8

func _variant(kind: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/enemies/%s/variant_%d.png" % [kind, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _count(kind: String) -> int:
	var n := 0
	while FileAccess.file_exists(
			"res://assets/art/enemies/%s/variant_%d.png" % [kind, n]):
		n += 1
	return n

func test_every_kind_ships_several_variants() -> bool:
	for kind in _KINDS:
		var n := _count(kind)
		assert_true(n >= _MIN_VARIANTS,
			"%s has at least %d variants, found %d" % [kind, _MIN_VARIANTS, n])
	return true

func test_variants_are_free_standing_with_a_clear_margin() -> bool:
	for kind in _KINDS:
		for i in _count(kind):
			var img := _variant(kind, i)
			assert_true(img != null, "%s/variant_%d decodes" % [kind, i])
			if img == null:
				continue
			var w := img.get_width()
			var h := img.get_height()
			var peak := 0
			for y in h:
				peak = maxi(peak, maxi(
					int(round(img.get_pixel(0, y).a * 255.0)),
					int(round(img.get_pixel(w - 1, y).a * 255.0))))
			for x in w:
				peak = maxi(peak, maxi(
					int(round(img.get_pixel(x, 0).a * 255.0)),
					int(round(img.get_pixel(x, h - 1).a * 255.0))))
			assert_true(peak <= _MARGIN_ALPHA_MAX,
				"%s/variant_%d edge peak %d" % [kind, i, peak])
	return true

func test_variants_of_a_kind_are_actually_different() -> bool:
	# A bake that wrote the same crop N times would pass everything above and
	# defeat the entire point of per-spawn variety.
	for kind in _KINDS:
		var a := _variant(kind, 0)
		var b := _variant(kind, 1)
		assert_true(a != null and b != null, "%s has two variants to compare" % kind)
		if a == null or b == null:
			continue
		var differs := a.get_size() != b.get_size()
		if not differs:
			for y in range(0, a.get_height(), 3):
				for x in range(0, a.get_width(), 3):
					if a.get_pixel(x, y) != b.get_pixel(x, y):
						differs = true
						break
				if differs:
					break
		assert_true(differs, "%s's first two variants are not identical" % kind)
	return true

func test_the_three_kinds_are_different_creatures() -> bool:
	var sizes := {}
	for kind in _KINDS:
		var img := _variant(kind, 0)
		assert_true(img != null, "%s/variant_0 decodes" % kind)
		if img == null:
			continue
		sizes[kind] = img.get_size()
	assert_true(sizes["ogre"].y > sizes["bee"].y,
		"the ogre sprite is taller than the bat sprite")
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `assets/art/enemies/` does not exist.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
## kind -> the sheet row it is cut from. The three existing kinds keep their
## stats and wave schedules; only the art changes. Shaman and Troll are cut to
## _unused for the deferred enemy-variety feature and referenced by no code.
const ENEMY_ROWS := {
	&"slime": {"y0": 216, "y1": 288},
	&"ogre": {"y0": 438, "y1": 516},
	&"bee": {"y0": 521, "y1": 586},
	&"_unused/shaman": {"y0": 293, "y1": 361},
	&"_unused/troll": {"y0": 366, "y1": 433},
}
const ENEMY_X0 := 60
const ENEMY_X1 := 1228
const MIN_SPRITE_RUN := 20

## Whether a pixel belongs to a sprite rather than the sheet background.
func _is_content(sheet: Image, x: int, y: int) -> bool:
	var c := sheet.get_pixel(x, y)
	return Vector3(c.r, c.g, c.b).distance_squared_to(BACKGROUND / 255.0) * 65025.0 \
		> KEY_TOLERANCE_SQ

## Splits a horizontal band into sprite spans on gaps in its column
## projection.
##
## Projection works here and flood fill does not: a tight fill fragments a
## sprite because its dark outlines sit near the background, and a loose one
## merges neighbours. Verified on the enemy rows, returning 16/16/15/14 across
## four of them.
func _row_sprites(sheet: Image, y0: int, y1: int, x0: int, x1: int) -> Array:
	var present := []
	for x in range(x0, x1):
		var any := false
		for y in range(y0, y1):
			if _is_content(sheet, x, y):
				any = true
				break
		present.append(any)
	var out := []
	var start := -1
	for i in present.size():
		if present[i] and start < 0:
			start = i
		elif not present[i] and start >= 0:
			if i - start >= MIN_SPRITE_RUN:
				out.append(Vector2i(x0 + start, x0 + i))
			start = -1
	if start >= 0 and present.size() - start >= MIN_SPRITE_RUN:
		out.append(Vector2i(x0 + start, x0 + present.size()))
	return out

func _bake_enemies(sheet: Image) -> void:
	for kind in ENEMY_ROWS:
		var row: Dictionary = ENEMY_ROWS[kind]
		var dir := "res://assets/art/enemies/%s" % kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var spans := _row_sprites(sheet, int(row["y0"]), int(row["y1"]),
			ENEMY_X0, ENEMY_X1)
		for i in spans.size():
			var span: Vector2i = spans[i]
			var h: int = int(row["y1"]) - int(row["y0"])
			var cut := Image.create_empty(span.y - span.x, h, false, Image.FORMAT_RGBA8)
			cut.blit_rect(sheet, Rect2i(span.x, int(row["y0"]), span.y - span.x, h),
				Vector2i.ZERO)
			_trim(_key(cut)).save_png("%s/variant_%d.png" % [dir, i])
		print("bake_sheet: %s x%d variants" % [kind, spans.size()])
```

Call it from `_init` after `_bake_tower_atlas(sheet)`.

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: PASS. Report the variant count per kind — the goblin and ogre rows should yield well over the four-variant minimum.

- [ ] **Step 5: Commit**

```bash
git add tools/bake_sheet.gd assets/art test/test_enemy_sprites.gd
git commit -m "Cut enemy sprites as per-spawn variants for the three kinds"
```

---

### Task 5: Props and endpoints

**Files:**
- Modify: `tools/bake_sheet.gd`
- Create: `assets/art/<biome>/{tree,stone,spike,fire}.png`, `assets/art/castle.png`, `assets/art/cave.png`
- Test: `test/test_prop_assets.gd`

**Interfaces:**
- Consumes: `_key`, `_trim`, `_row_sprites` from earlier tasks.
- Produces: four props per biome plus two shared endpoints, all trimmed with a 1px pad.

**The four prop slot names do not change** — `tree`, `stone`, `spike`, `fire` — because `MapRenderer`'s scatter rules are written in those terms and none of those rules change. Props come from the Extras/Decor column at `x 1237–1524`, below the tower band.

**Endpoints are composed from decor**, as the Kenney ones were, because the sheet ships no castle or cave. Keeping flat vector markers on an illustrated board is the style clash this swap exists to avoid.

- [ ] **Step 1: Write the failing test**

Rewrite `test/test_prop_assets.gd` to read from `res://assets/art/<biome>/` instead of `res://assets/kenney/<biome>/`, keeping every existing assertion — the transparent-margin gate, the tight-trim gate, and the "trimming actually shrank the source" gate — and change `_BIOMES` to `["forest", "desert", "ice"]`. Add:

```gdscript
func test_both_endpoints_decode_and_keep_a_clear_margin() -> bool:
	for name in ["castle", "cave"]:
		var bytes := FileAccess.get_file_as_bytes("res://assets/art/%s.png" % name)
		assert_false(bytes.is_empty(), "%s.png exists" % name)
		if bytes.is_empty():
			continue
		var img := Image.new()
		assert_eq(img.load_png_from_buffer(bytes), OK, "%s.png decodes" % name)
		var w := img.get_width()
		var h := img.get_height()
		var peak := 0
		for y in h:
			peak = maxi(peak, maxi(
				int(round(img.get_pixel(0, y).a * 255.0)),
				int(round(img.get_pixel(w - 1, y).a * 255.0))))
		for x in w:
			peak = maxi(peak, maxi(
				int(round(img.get_pixel(x, 0).a * 255.0)),
				int(round(img.get_pixel(x, h - 1).a * 255.0))))
		assert_true(peak <= 8, "%s.png edge peak %d" % [name, peak])
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — nothing exists under `assets/art/<biome>/tree.png` and no endpoints.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
const DECOR_X0 := 1237
const DECOR_X1 := 1524
const DECOR_Y0 := 216
const DECOR_Y1 := 740

## Which decor sprite fills which prop slot, per biome, as an index into the
## decor column in reading order. The slot NAMES are fixed by MapRenderer's
## scatter rules and do not change; only what sits behind each one is
## per-biome.
const PROP_SLOTS := {
	&"forest": {&"tree": 0, &"stone": 5, &"spike": 2, &"fire": 9},
	&"desert": {&"tree": 3, &"stone": 6, &"spike": 4, &"fire": 9},
	&"ice": {&"tree": 1, &"stone": 7, &"spike": 8, &"fire": 9},
}

## Endpoints are composed on a clear canvas from decor indices, because the
## sheet ships no castle and no cave. {index, offset, size}.
const ENDPOINT_CANVAS := 256
const ENDPOINTS := {
	"castle": [
		{"decor": 11, "at": Vector2i(56, 92), "px": 144},
		{"decor": 12, "at": Vector2i(20, 130), "px": 96},
		{"decor": 12, "at": Vector2i(140, 130), "px": 96},
	],
	"cave": [
		{"decor": 5, "at": Vector2i(8, 84), "px": 128},
		{"decor": 6, "at": Vector2i(132, 88), "px": 120},
		{"decor": 7, "at": Vector2i(84, 40), "px": 104},
	],
}

## Every decor sprite in the column, in reading order: rows top to bottom,
## sprites left to right within a row.
##
## The column is a loose grid rather than a fixed pitch, so rows are found by
## scanning for bands that contain content and each band is then split with
## the same projection helper the enemy rows use.
func _decor_sprites(sheet: Image) -> Array:
	var out := []
	var y := DECOR_Y0
	while y < DECOR_Y1:
		var has_content := false
		for x in range(DECOR_X0, DECOR_X1):
			if _is_content(sheet, x, y):
				has_content = true
				break
		if not has_content:
			y += 1
			continue
		var y_end := y
		while y_end < DECOR_Y1:
			var any := false
			for x in range(DECOR_X0, DECOR_X1):
				if _is_content(sheet, x, y_end):
					any = true
					break
			if not any:
				break
			y_end += 1
		for span in _row_sprites(sheet, y, y_end, DECOR_X0, DECOR_X1):
			var cut := Image.create_empty(span.y - span.x, y_end - y, false,
				Image.FORMAT_RGBA8)
			cut.blit_rect(sheet, Rect2i(span.x, y, span.y - span.x, y_end - y),
				Vector2i.ZERO)
			out.append(_trim(_key(cut)))
		y = y_end + 1
	return out

func _bake_props(decor: Array) -> void:
	for biome in PROP_SLOTS:
		var dir := "res://assets/art/%s" % biome
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for slot in PROP_SLOTS[biome]:
			var index: int = int(PROP_SLOTS[biome][slot])
			assert(index < decor.size(), "decor index %d is past the column" % index)
			(decor[index] as Image).save_png("%s/%s.png" % [dir, slot])
		print("bake_sheet: %s props" % biome)

func _bake_endpoints(decor: Array) -> void:
	for name in ENDPOINTS:
		var canvas := Image.create_empty(
			ENDPOINT_CANVAS, ENDPOINT_CANVAS, false, Image.FORMAT_RGBA8)
		canvas.fill(Color(0, 0, 0, 0))
		for piece in ENDPOINTS[name]:
			var spec: Dictionary = piece
			var index: int = int(spec["decor"])
			assert(index < decor.size(), "decor index %d is past the column" % index)
			var src: Image = (decor[index] as Image).duplicate()
			src.resize(int(spec["px"]), int(spec["px"]), Image.INTERPOLATE_LANCZOS)
			canvas.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), spec["at"])
		_trim(canvas).save_png("res://assets/art/%s.png" % name)
	print("bake_sheet: endpoints")
```

Call both from `_init` after `_bake_enemies(sheet)`, sharing one segmentation pass:

```gdscript
	var decor := _decor_sprites(sheet)
	print("bake_sheet: %d decor sprites found" % decor.size())
	_bake_props(decor)
	_bake_endpoints(decor)
```

**The decor indices are the one thing here that cannot be derived.** `PROP_SLOTS` and `ENDPOINTS` name sprites by their position in the column, and only looking tells you whether index 5 is a rock or a barrel. Task 5's Step 4 prints the decor count and Step 5 is where you check the choices by eye — the gates prove each prop is a clean free-standing sprite, not that it is the *right* sprite.

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: PASS. If a `PROP_SLOTS` index lands on the wrong sprite, the gates will still pass — verify by eye which decor piece each slot got, and adjust the indices.

- [ ] **Step 5: Commit**

```bash
git add tools/bake_sheet.gd assets/art test/test_prop_assets.gd
git commit -m "Cut props per biome and compose the endpoint markers"
```

---

### Task 6: Draw the ground and road from an edge mask

**Files:**
- Modify: `game/map_renderer.gd`
- Modify: `data/biomes.gd`
- Test: `test/test_map_renderer.gd`
- Test: `test/test_biomes.gd`

**Repoint the endpoint preloads in this task.** `game/map_renderer.gd:9-10`
preloads `_CASTLE` and `_CAVE` from `res://assets/kenney/`. Task 5 wrote the
replacements to `res://assets/art/`, and Task 9 deletes the Kenney directory —
so leaving these would turn a `preload` into a parse error and take the whole
suite down as a load failure rather than a test failure. Change both constants
to `res://assets/art/castle.png` and `res://assets/art/cave.png`;
`_draw_endpoints`'s body does not change.

**Interfaces:**
- Consumes: the ground and road assets from Tasks 1 and 2.
- Produces: `Biomes.ground_path(biome, index) -> String`, `Biomes.road_path(biome, mask) -> String`, and `MapRenderer.edge_mask(c, r) -> int`.

**This deletes the corner-mask lattice.** `MapRenderer._draw_ground` currently samples terrain at tile centres over a `(cols + 1) × (rows + 1)` grid offset by half a tile, and `corner_mask` supports it. Both go. The replacement draws **one sprite per tile on the tile grid** — no offset, no extra row or column.

**The mask is edges, not corners.** For each cell, which of its four orthogonal neighbours is road: `N=1, E=2, S=4, W=8`. Out of bounds is not road.

**Rotation covers the pieces the sheet does not ship.** Only masks 0, 3, 5, 7 and 15 exist as files; the rest are those five rotated. `rotate_mask(m, k) = ((m << k) | (m >> (4 - k))) & 15`.

- [ ] **Step 1: Write the failing tests**

In `test/test_map_renderer.gd`, delete every test that references `corner_mask` or the half-tile lattice, change the four prop path constants to `res://assets/art/forest/*.png`, and add:

```gdscript
func test_the_ground_layer_has_one_sprite_per_tile() -> bool:
	# The corner lattice drew (cols+1)*(rows+1) sprites offset half a tile.
	# The edge mask draws one per tile, on the grid.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var ground := 0
	for child in renderer.get_children():
		if child is Sprite2D and child.z_index == -1:
			ground += 1
	assert_eq(ground, DemoMap.GRID_COLS * DemoMap.GRID_ROWS,
		"one ground sprite per tile")
	renderer.free()
	return true

func test_the_edge_mask_reads_the_four_orthogonal_neighbours() -> bool:
	# Bit order is fixed and load-bearing: N=1, E=2, S=4, W=8.
	var renderer := MapRenderer.new()
	var tiles: Array = []
	for r in 3:
		var row: Array = []
		for c in 3:
			row.append(Tiles.BUILDABLE)
		tiles.append(row)
	tiles[1][1] = Tiles.PATH
	tiles[0][1] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 1, "a road neighbour to the north sets bit 1")
	tiles[0][1] = Tiles.BUILDABLE
	tiles[1][2] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 2, "a road neighbour to the east sets bit 2")
	renderer.free()
	return true

func test_out_of_bounds_neighbours_are_not_road() -> bool:
	var renderer := MapRenderer.new()
	var tiles: Array = [[Tiles.PATH]]
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(0, 0), 0, "an isolated cell has no road neighbours")
	renderer.free()
	return true

func test_spawn_and_goal_count_as_road() -> bool:
	# Tiles.WALKABLE is PATH, SPAWN and GOAL; the road must not break at the
	# endpoints.
	var renderer := MapRenderer.new()
	var tiles: Array = [[Tiles.SPAWN, Tiles.PATH, Tiles.GOAL]]
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 0), 2 | 8, "spawn to the west and goal to the east both count")
	renderer.free()
	return true

func test_every_road_cell_draws_a_piece_whose_mask_matches_after_rotation() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		if not sprite.texture.resource_path.contains("road_"):
			continue
		var c := int(sprite.position.x / Tiles.TILE_SIZE)
		var r := int(sprite.position.y / Tiles.TILE_SIZE)
		var wanted := renderer.edge_mask(c, r)
		var base := int(sprite.texture.resource_path.get_file().get_basename().split("_")[1])
		var turns := int(round(sprite.rotation / (PI / 2.0))) % 4
		var rotated := ((base << turns) | (base >> (4 - turns))) & 15
		assert_eq(rotated, wanted,
			"the piece at (%d, %d) rotates onto its cell's mask" % [c, r])
		checked += 1
	assert_true(checked > 0, "road cells were checked")
	renderer.free()
	return true
```

In `test/test_biomes.gd`, replace the blend-mask test with:

```gdscript
func test_every_biome_resolves_its_ground_and_road_pieces() -> bool:
	for biome in Biomes.KINDS:
		for i in 6:
			assert_true(ResourceLoader.exists(Biomes.ground_path(biome, i)),
				"%s ground %d resolves" % [biome, i])
		for mask in [0, 3, 5, 7, 15]:
			assert_true(ResourceLoader.exists(Biomes.road_path(biome, mask)),
				"%s road %d resolves" % [biome, mask])
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `edge_mask`, `ground_path` and `road_path` do not exist.

- [ ] **Step 3: Rewrite the biome accessors**

In `data/biomes.gd`, replace `blend_path` with:

```gdscript
## Returns a path, never a loaded resource. data/ is held engine-free by
## test/test_sim_purity.gd; the render layer loads.
static func ground_path(biome: StringName, index: int) -> String:
	return "%s/ground_%d.png" % [DEFS[biome]["dir"], index]

static func road_path(biome: StringName, mask: int) -> String:
	return "%s/road_%02d.png" % [DEFS[biome]["dir"], mask]

## The five masks the sheet ships as files. Every other mask is one of these
## rotated - see MapRenderer._draw_ground.
const ROAD_BASE_MASKS: Array[int] = [0, 3, 5, 7, 15]
const GROUND_VARIANTS := 6
```

Point each biome's `dir` at `res://assets/art/<biome>`.

- [ ] **Step 4: Rewrite the ground layer**

In `game/map_renderer.gd`, delete `corner_mask` and rewrite `_draw_ground`:

```gdscript
## Ground is one sprite per tile, on the tile grid.
##
## This replaces a corner-mask lattice that sampled terrain at tile centres
## over a (cols+1) x (rows+1) grid offset half a tile. That existed because the
## previous art blended between terrains; this art does not - its cells are
## discrete cards and its road pieces are shapes. An edge mask over orthogonal
## neighbours is the simpler thing that this art actually wants.
func _draw_ground() -> void:
	for r in _rows:
		for c in _cols:
			if _is_road(c, r):
				_place_road(c, r)
			else:
				var variant := _ground_rng.int_range(0, Biomes.GROUND_VARIANTS - 1)
				_place(load(Biomes.ground_path(_biome, variant)), c, r,
					Tiles.TILE_SIZE, _Z_GROUND)

## The four orthogonal neighbours of a cell that are road, as a bitmask.
## Bit order is fixed: N=1, E=2, S=4, W=8. Out of bounds is not road.
func edge_mask(c: int, r: int) -> int:
	var mask := 0
	if _is_road(c, r - 1):
		mask |= 1
	if _is_road(c + 1, r):
		mask |= 2
	if _is_road(c, r + 1):
		mask |= 4
	if _is_road(c - 1, r):
		mask |= 8
	return mask

func _is_road(c: int, r: int) -> bool:
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return false
	return _tiles[r][c] in Tiles.WALKABLE

## Places the road piece for a cell, rotating a base piece onto its mask.
##
## The sheet ships only five of the sixteen masks; the rest are those rotated,
## which is why the piece is chosen by search rather than by table. Rotating a
## 4-bit ring is a shift with wraparound.
func _place_road(c: int, r: int) -> void:
	var wanted := edge_mask(c, r)
	for base in Biomes.ROAD_BASE_MASKS:
		for turns in 4:
			if ((base << turns) | (base >> (4 - turns))) & 15 == wanted:
				var sprite := _place(load(Biomes.road_path(_biome, base)), c, r,
					Tiles.TILE_SIZE, _Z_GROUND)
				# Rotate about the cell's centre: _place anchors top-left.
				sprite.offset = -Vector2(sprite.texture.get_width(),
					sprite.texture.get_height()) / 2.0
				sprite.position += Vector2(Tiles.TILE_SIZE, Tiles.TILE_SIZE) / 2.0
				sprite.rotation = float(turns) * PI / 2.0
				return
	# Unreachable: masks 0, 3, 5, 7 and 15 rotate onto all sixteen.
	push_error("no road piece rotates onto mask %d" % wanted)
```

Add a `_ground_rng` field seeded in `render` from the passed `Rng`, so ground variant choice is reproducible.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add game/map_renderer.gd data/biomes.gd test/test_map_renderer.gd test/test_biomes.gd
git commit -m "Draw the road from an edge mask and drop the corner lattice"
```

---

### Task 7: Enemy variants, motion and death

**Files:**
- Modify: `game/enemy.gd`
- Modify: `game/enemy.tscn`
- Modify: `data/enemies.gd`
- Test: `test/test_enemy.gd`

**Interfaces:**
- Consumes: the variant sprites from Task 4.
- Produces: `Enemy` draws a `Sprite2D` rather than an `AnimatedSprite2D`.

**What is removed:** `_facing`, `_set_facing`, the `walk_<facing>` and `death_<facing>` animations, and `_build_frames`. `game/enemy.tscn`'s `AnimatedSprite2D` becomes a `Sprite2D`, keeping `texture_filter = 1` — these sprites are still minified and want the same filtering the enemies already use.

**What replaces it:** one variant chosen at spawn from the seeded `Rng`, flipped horizontally by travel direction, with a sine bob while moving. Death becomes a fade-and-shrink tween.

**`_die` currently awaits `animation_finished` before despawning**, so despawn timing is whatever the death animation's length was. It becomes `DEATH_TWEEN_MS`, a constant this file owns. Tests pinning the old sequence change with it.

`Enemies.DEFS`'s `flip_horizontally` per-kind override survives — the new sprites also face one way by default. `texture_key` is replaced by `variant_count`, since variants live in a directory named for the kind and what the code needs from the table is how many there are to choose from.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_enemy.gd`, and delete the tests that assert `walk_*`/`death_*` animations exist:

```gdscript
func test_an_enemy_draws_one_of_its_kind_s_variants() -> bool:
	var e := _ready_enemy()
	var sprite: Sprite2D = e.get_node("Sprite")
	assert_true(sprite.texture != null, "a variant was chosen")
	assert_true(sprite.texture.resource_path.contains("/enemies/"),
		"and it came from the enemy art")
	e.free()
	return true

func test_the_variant_choice_is_reproducible_from_the_seed() -> bool:
	# Runs must stay reproducible - the whole harness depends on it.
	var a := _ready_enemy_with_seed(1234)
	var b := _ready_enemy_with_seed(1234)
	assert_eq(a.get_node("Sprite").texture.resource_path,
		b.get_node("Sprite").texture.resource_path,
		"the same seed picks the same variant")
	a.free()
	b.free()
	return true

func test_an_enemy_faces_the_way_it_travels() -> bool:
	var e := _ready_enemy()
	var sprite: Sprite2D = e.get_node("Sprite")
	e.set_facing_from_travel(true)
	var left := sprite.flip_h
	e.set_facing_from_travel(false)
	assert_true(sprite.flip_h != left, "travelling the other way flips the sprite")
	e.free()
	return true

func test_the_declared_variant_count_matches_what_was_baked() -> bool:
	# The count is hand-written in data/enemies.gd while the bake decides the
	# real number. A count that is too high makes the spawn pick a file that
	# does not exist - a crash on a path only a live wave reaches.
	for kind in Enemies.KINDS:
		var on_disk := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/variant_%d.png" % [kind, on_disk]):
			on_disk += 1
		assert_eq(Enemies.variant_count(kind), on_disk,
			"%s declares %d variants and %d are baked"
				% [kind, Enemies.variant_count(kind), on_disk])
	return true

func test_death_despawns_after_the_tween_rather_than_an_animation() -> bool:
	var e := _ready_enemy()
	assert_true(Enemy.DEATH_TWEEN_MS > 0.0, "the death tween has a duration")
	assert_true(Enemy.DEATH_TWEEN_MS < 1000.0,
		"and it is short enough not to hold a kill on screen")
	e.free()
	return true
```

`_ready_enemy_with_seed` is a new helper in this file: build an enemy the way `_ready_enemy` does but pass an `Rng` seeded with the given value.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — the scene still holds an `AnimatedSprite2D` and none of the new methods exist.

- [ ] **Step 3: Rewrite the enemy view**

In `game/enemy.tscn`, change the `Sprite` node's type from `AnimatedSprite2D` to `Sprite2D`, keeping `texture_filter = 1` — these sprites are still minified into the board and want the same filtering.

In `game/enemy.gd`, delete `_facing`, `_set_facing`, `_build_frames`, the `WALK_FPS`/`DEATH_FPS` constants and every `_sprite.play(...)` call, then add:

```gdscript
## How long a kill takes to leave the screen.
##
## Replaces awaiting the death animation, which tied despawn timing to whatever
## length the artist drew. The sheet has no death frames, so this file owns the
## duration - short enough not to hold a corpse on screen, long enough that a
## kill registers as feedback.
const DEATH_TWEEN_MS := 250.0

## How far the walk bob lifts the sprite, and how fast it cycles.
##
## The sheet's rows are variants rather than animation frames, so motion is
## synthesised: without this an enemy slides along the path like a paper
## cutout.
const BOB_PIXELS := 2.0
const BOB_HZ := 5.0

var _variant: Texture2D = null
var _bob_clock := 0.0
var _flip := false
```

In `setup`, pick the variant from the passed `Rng` so a run stays reproducible:

```gdscript
	# One of this kind's variants, chosen per spawn. A wave of eight shows
	# eight subtly different creatures rather than eight identical ones.
	var count := Enemies.variant_count(kind)
	_variant = load("res://assets/art/enemies/%s/variant_%d.png"
		% [kind, rng.int_range(0, count - 1)])
	_sprite.texture = _variant
```

Replace `_set_facing` with a flip that honours the existing per-kind override:

```gdscript
## Faces the way the enemy is travelling. Up and down both draw the side pose -
## the sheet gives one facing, so there is nothing else to draw.
func set_facing_from_travel(moving_left: bool) -> void:
	var flip := moving_left
	if Enemies.DEFS[kind]["flip_horizontally"]:
		flip = not flip
	if flip == _flip:
		return
	_flip = flip
	_sprite.flip_h = flip
```

In `_physics_process`, after movement resolves, drive the bob and the facing:

```gdscript
	set_facing_from_travel(bool(result["moving_left"]))
	_bob_clock += delta
	_sprite.position.y = -absf(sin(_bob_clock * BOB_HZ * TAU)) * BOB_PIXELS
```

Rewrite `_die` so the reward still fires exactly where it fires now — before anything visual — and only the despawn changes:

```gdscript
func _die(source: Dictionary) -> void:
	sim["dying"] = true
	sim["alive"] = false
	# Emitted before the tween, unchanged: economy timing must not move
	# because the death presentation changed.
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 0.6, DEATH_TWEEN_MS / 1000.0)
	tween.tween_property(self, "modulate:a", 0.0, DEATH_TWEEN_MS / 1000.0)
	await tween.finished
	queue_free()
```

In `data/enemies.gd`, replace each kind's `texture_key` with `variant_count`, leaving every stat untouched, and add the accessor:

```gdscript
## How many per-spawn variants this kind's art directory holds. Baked by
## tools/bake_sheet.gd; pinned by test_enemy_sprites.gd so a re-bake that
## produces fewer cannot silently narrow the variety.
static func variant_count(kind: StringName) -> int:
	return int(DEFS[kind]["variant_count"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. `test/test_harness.gd` and the wave tests must stay green — the sim never knew about animations, so nothing there should move.

- [ ] **Step 5: Commit**

```bash
git add game/enemy.gd game/enemy.tscn data/enemies.gd test/test_enemy.gd
git commit -m "Draw enemies as per-spawn variants with procedural motion"
```

---

### Task 8: Retune the no-build corridor

**Files:**
- Modify: `sim/placement.gd`
- Test: `test/test_road_width.gd`

**Interfaces:**
- Consumes: the road pieces from Task 2.
- Produces: `Placement.PATH_HALF_WIDTH` measured against the new road.

`PATH_HALF_WIDTH` moved 26 → 14 during the Kenney swap because that road drew only 23px wide. These road cells are full-tile dirt, so the visible road returns to roughly 48px and the corridor follows it back up.

**Measure, do not guess.** `test/test_road_width.gd` already derives the drawn road width from a committed tile and asserts the constant tracks it with two bounds — never narrower than the road's half-width, never more than 4px beyond it. Repoint it at `res://assets/art/forest/road_05.png` (the north-south straight), keep both bounds, and set `PATH_HALF_WIDTH` to whatever the measurement supports.

- [ ] **Step 1: Repoint the measurement**

Change `test/test_road_width.gd`'s source path to the new straight, and update `_ROAD_RGB` to the dirt colour sampled from it. Keep `test_min_tower_spacing_was_not_disturbed` exactly as it is.

- [ ] **Step 2: Run and read the failure**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL, and the message names the measured half-width. Record that number.

- [ ] **Step 3: Set the constant**

Set `PATH_HALF_WIDTH` to the measured half-width rounded to the nearest whole pixel, plus the 2px margin the constant has always carried, and rewrite its doc comment to say what it is now tied to.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add sim/placement.gd test/test_road_width.gd
git commit -m "Retune the no-build corridor to the illustrated road"
```

---

### Task 9: Retire the Kenney art

**Files:**
- Delete: `assets/kenney/`, `tools/bake_kenney.gd`, `test/test_blend_tiles.gd`, `test/test_asset_import.gd`, `test/test_endpoint_assets.gd`
- Modify: `README.md`, `CONTINUE.md`

- [ ] **Step 1: Confirm nothing references what you are deleting**

```bash
cd ~/Projects/project-t-godot
grep -rn "assets/kenney\|bake_kenney\|blend_" --include="*.gd" --include="*.tscn" . | grep -v "^./reference/" | grep -v docs/superpowers
```

Expected: matches only in the files being deleted. Any match in `game/`, `data/`, `sim/` or `ui/` means an earlier task missed a call site — fix that before deleting anything.

- [ ] **Step 2: Delete**

```bash
git rm -r assets/kenney tools/bake_kenney.gd tools/bake_kenney.gd.uid \
          test/test_blend_tiles.gd test/test_blend_tiles.gd.uid \
          test/test_asset_import.gd test/test_asset_import.gd.uid \
          test/test_endpoint_assets.gd test/test_endpoint_assets.gd.uid
```

`test_asset_import.gd` gated `mipmaps/generate=true` on `assets/kenney/**`. The illustrated assets are drawn the same way — minified into 48px cells — so **re-home that gate onto `assets/art/**` rather than dropping it**, in a new `test/test_art_import.gd`. Losing it is how the mipmap defect happened last time: a gate was deleted with its assets and nothing replaced it.

- [ ] **Step 3: Run the suite**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. The check count drops with the deleted files and rises with the re-homed gate; report the new number.

- [ ] **Step 4: Credit and document**

Update `README.md`'s art section and `CONTINUE.md` §0 to describe the illustrated sheet, where it is vendored, and that `tools/bake_sheet.gd` regenerates everything. Record the two facts a future reader needs: the road is an **edge** mask (not the corner mask the previous art used), and the sheet has no alpha so extraction keys a background colour.

- [ ] **Step 5: Screenshot all three biomes and a wave**

Run the game, capture the forest map, then re-render under `&"ice"` and `&"desert"` at runtime through the Godot MCP rather than editing `Maps.DEFS`:

```gdscript
var board = get_tree().current_scene.get_node("GameBoard")
board.get_node("MapRenderer").render(board._tiles, null, &"ice")
```

Check each for: road pieces meeting without visible mismatch at corners and junctions, no leftover navy fringing on any sprite, towers reading clearly against the ground, and the tile grid reading as intended rather than as a defect. Then start a wave and confirm enemies show visible variety and die with a visible fade rather than vanishing.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Retire the Kenney art and document the illustrated swap"
```

---

## Notes for the executor

**The riskiest thing here is extraction alignment.** Rows are cut on a fixed pitch from a measured origin, and a few pixels of drift puts a sliver of the neighbouring sprite into every crop. The margin gates are what catch it. When one goes red, move the origin — never the threshold.

**The second riskiest is the composed straight.** It is the only piece no artist drew, and Task 2 Step 5 exists because no assertion can tell you whether it reads correctly next to the pieces it must sit beside.

**The road is an edge mask now.** If you find yourself sampling corners or offsetting the grid by half a tile, you are rebuilding the thing this plan deleted.

**Deferred, deliberately:** the Goblin Shaman and Troll rows are extracted but unused, waiting on the enemy-variety feature which needs its own stats, wave schedule and balance pass. The three targeting-priority tasks in `docs/superpowers/plans/2026-08-20-turret-tracking-and-targeting.md` are unaffected by any of this and remain worth executing on their own.
