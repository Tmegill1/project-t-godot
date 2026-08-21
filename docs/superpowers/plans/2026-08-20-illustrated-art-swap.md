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

**How the sheet lays the towers out**, all measured against the vendored `sheet.png` (1536 × 1024):

The tower band is divided into four panels by vertical rules that are opaque at *every* row of the band — at x = 8–10, 429–430, 862–864, 1233–1235 and 1526–1527. The four panels between them are Archer, Cannon, Mage and Barracks. Each panel stacks four row runs: a horizontal rule at y = 8–10, the panel heading ("TOWER 1 – ARCHER TOWER") at y = 19–34, the per-level captions ("LVL 1" … "LVL 4") at y = 46–60, and the tower art at y = 63–211.

Those vertical rules are why the tower band must not include the caption rows and why no crop can be cleaned up after the fact: a rule is opaque at every row, so inside any crop that touches one, no row is ever fully transparent and no row-based separator search can find the gap under the caption.

The captions are what makes the levels separable. Each "LVL n" is centred over its tower, and the caption row segments cleanly into exactly four runs in every panel — while the tower art does not, because the Mage and Barracks towers touch. Cutting each panel at the midpoints between consecutive caption centres, bounded by the panel's own rules, puts exactly one tower in each cell:

| Kind | Type | Caption centres | Cell boundaries |
|---|---|---|---|
| `basic` | Archer | 58.5, 158, 257, 359.5 | 11, 108, 208, 308, 428 |
| `fast` | Cannon | 489, 593, 695, 798.5 | 431, 541, 644, 747, 861 |
| `mortar` | Mage | 917.5, 1010, 1098, 1187 | 865, 964, 1054, 1142, 1232 |
| `long` | Barracks | 1275, 1344, 1413, 1489.5 | 1236, 1310, 1378, 1451, 1524 |

**The sixteen levels share one scale factor.** Fitting each sprite to the frame on its own longest dimension erases the thing this swap is for: a level that grows taller faster than it grows wider absorbs the extra height into a smaller scale and comes out *smaller* on screen than the level below it. Measured trimmed extents rise from 79×108 (Archer L1) to 97×139 (Archer L4) and the per-kind fit factors land between 0.60 and 0.66 — the sheet already draws every tower at one world scale, so a single factor derived from the largest of the sixteen is both simpler and truer to the art. With it, the sampled opaque-pixel count rises across every kind: basic 498 → 817, fast 549 → 896, mortar 503 → 757, long 441 → 582.

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
	#
	# First against last, not each against the one before it: a level's
	# silhouette can widen and shorten between two steps (the Mage's crystals
	# spread further at L3 than they do at L4) without the level being any
	# less of an upgrade.
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

func test_no_referenced_frame_carries_a_detached_fragment() -> bool:
	# The gate for everything the cut can drag in with the tower: the "LVL 4"
	# caption printed above it, or a sliver of the neighbouring level. Both
	# arrive separated from the tower by a band of transparency, so a frame
	# whose content spans an empty row or column has caught something.
	#
	# Every tower on the sheet is solid between its extremes - measured, not
	# assumed: all sixteen come out with zero interior empty rows and zero
	# interior empty columns. The flags and floating crystals stay attached to
	# their poles and rings.
	#
	# Full stride, not every other pixel: a one-row gap is exactly what a
	# caption leaves behind, and a stride of two can step over it.
	var img := _atlas()
	assert_true(img != null, "towers.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			var n := int(frame)
			var ox := (n % _COLUMNS) * _FRAME
			var oy := (n / _COLUMNS) * _FRAME
			var rows := []
			var cols := []
			rows.resize(_FRAME)
			cols.resize(_FRAME)
			rows.fill(false)
			cols.fill(false)
			for y in _FRAME:
				for x in _FRAME:
					if img.get_pixel(ox + x, oy + y).a > 8.0 / 255.0:
						rows[y] = true
						cols[x] = true
			assert_eq(_interior_gaps(rows), 0,
				"%s frame %d spans no empty row" % [kind, n])
			assert_eq(_interior_gaps(cols), 0,
				"%s frame %d spans no empty column" % [kind, n])
	return true

## Empty entries lying between the first and last true entry.
func _interior_gaps(occupied: Array) -> int:
	var first := -1
	var last := -1
	for i in occupied.size():
		if bool(occupied[i]):
			if first < 0:
				first = i
			last = i
	if first < 0:
		return 0
	var gaps := 0
	for i in range(first, last + 1):
		if not bool(occupied[i]):
			gaps += 1
	return gaps
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — `test_a_kind_s_levels_grow_across_its_upgrade_frames` fails against the Kenney atlas, whose frames do not grow monotonically (`basic` 544 vs 617, `fast` 544 vs 633, `long` 613 vs 617; `mortar` passes it by coincidence). The other four tests pass against the Kenney atlas, which is the point of them — they are the geometry contract this bake must not break.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
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
	return _trim(_isolate_centre(_key(region)))

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

Render `assets/towers.png` at 3× with frame numbers overlaid and look at it. **Composite it over an opaque background rather than dropping the alpha channel** — an RGBA-to-RGB conversion that discards alpha paints every anti-aliased edge pixel at full strength, and the atlas comes out looking like it is covered in coloured speckle that is not in the file.

Confirm frames 3, 4, 14 and 15 are empty, and that each kind's four frames hold that tower type's four levels in order:

| Kind | Sheet type | Frames, L1 → L4 |
|---|---|---|
| `basic` | Archer | 8, 9, 11, 17 |
| `fast` | Cannon | 1, 0, 7, 16 |
| `mortar` | Mage | 5, 6, 12, 13 |
| `long` | Barracks | 2, 10, 18, 19 |

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

| Kind | Profile | Sheet row | Band y | Content rows |
|---|---|---|---|---|
| `slime` | 100 speed, 5 hp, common early spawn | Goblin | 216–288 | 232–283 |
| `ogre` | 60 speed, 8 hp, slow and tanky | Ogre | 438–516 | 439–512 |
| `bee` | 150 speed, 3 hp, fastest and frailest | Bat | 521–586 | 529–581 |

The Goblin Shaman (293–361) and Troll (366–433) rows are extracted to `assets/art/enemies/_unused/` for the deferred enemy-variety feature. They are not referenced by any code.

**The rows are variants, not animation.** Consecutive frames differ about four times less than a real walk cycle's do, and the difference is flat across every frame lag — no periodicity, which is what a cycle would show. Each is a usable alternate look, so an enemy picks one at spawn.

**Two things about the enemy bands, both measured.** Unlike the tower band, no enemy band contains a vertical panel rule anywhere in the x range used here — the rules that broke Task 3's first two attempts stop above these rows. But the row's own LABEL ("GOBLIN", "OGRE", "BAT") runs from x 25 to about x 90, so the scan must start at **95**, not 60: at 60 the label is clipped rather than excluded and every row's first "variant" is a 21–30px fragment of text. The right-hand decor starts at x 1238 in every row, so 1228 is a correct upper bound.

**The BAT row does not fully segment, and that is expected.** Its bats overlap wing-to-wing. Gap segmentation returns six spans of widths 263, 103, 92, 338, 133 and 102 — rendered and looked at, the 263 is three bats, the 338 is four, the 133 is two, and only 103, 92 and 102 are single bats. Projecting only the lower body rows gives more spans but at irregular spacing, so it splits bodies rather than separating them; no column-profile threshold separates them either. So the bake **rejects any span wider than 1.4× its row's narrowest span**, which keeps exactly the three single bats and every span in every other row. Measured counts after the filter:

| Kind | Spans found | Kept | Trimmed sizes |
|---|---|---|---|
| `slime` | 15 | 15 | 54×50 to 69×54 |
| `ogre` | 13 | 13 | 71×67 to 80×76 |
| `bee` | 6 | 3 | 94×47, 104×41, 105×47 |
| `_unused/shaman` | 15 | 14 | 52×51 to 63×65 |
| `_unused/troll` | 13 | 13 | 70×58 to 84×66 |

Three bat variants is the honest yield of that row, and three alternate looks is real variety for the fastest enemy. The test asserts the exact measured counts rather than a floor, so a regression in the segmentation shows up as a number rather than as silently fewer sprites.

**For Task 7, which wires these up:** the bat variants are wide and short (about 105 × 45) where the goblin is 60 × 54 and the ogre 79 × 76. `data/enemies.gd`'s per-kind `sprite_scale` is tuned against the Kenney sprites and will need retuning against these.

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
const _MARGIN_ALPHA_MAX := 8

## The exact yield of each row, measured. A floor would hide the thing most
## likely to go wrong here: the bat row's sprites overlap wing-to-wing and only
## three of its thirteen bats can be cut out cleanly, so the bake drops the
## spans that hold more than one. If that filter ever stops working, slime and
## ogre gain sprites and bee gains merged ones - a floor sees neither.
const _EXPECTED_VARIANTS := {"slime": 15, "ogre": 13, "bee": 3}

## No variant may be wider than this multiple of its kind's narrowest. Two
## enemies cut into one PNG is the failure this catches, and it is invisible to
## every other assertion in this file - a merged sprite is free-standing, has a
## clean margin, and differs from its siblings.
const _MAX_WIDTH_RATIO := 1.4

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

func test_every_kind_ships_the_variants_its_row_yields() -> bool:
	for kind in _KINDS:
		assert_eq(_count(kind), int(_EXPECTED_VARIANTS[kind]),
			"%s ships %d variants" % [kind, int(_EXPECTED_VARIANTS[kind])])
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

func test_no_variant_holds_more_than_one_creature() -> bool:
	# The bat row's gap segmentation returns spans holding two, three and four
	# bats. They are dropped in the bake; this is the gate that says so.
	for kind in _KINDS:
		var widths := []
		for i in _count(kind):
			var img := _variant(kind, i)
			assert_true(img != null, "%s/variant_%d decodes" % [kind, i])
			if img == null:
				continue
			widths.append(img.get_width())
		assert_true(not widths.is_empty(), "%s has variants to measure" % kind)
		if widths.is_empty():
			continue
		var narrowest: int = widths[0]
		var widest: int = widths[0]
		for w in widths:
			narrowest = mini(narrowest, int(w))
			widest = maxi(widest, int(w))
		assert_true(float(widest) <= float(narrowest) * _MAX_WIDTH_RATIO,
			"%s's widest variant is %d against a narrowest of %d" % [kind, widest, narrowest])
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
Expected: FAIL — `assets/art/enemies/` does not exist, so every count is 0.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
## kind -> the sheet row it is cut from. The three existing kinds keep their
## stats and wave schedules; only the art changes. Shaman and Troll are cut to
## _unused for the deferred enemy-variety feature and referenced by no code.
##
## MEASURED: each band's content occupies rows 232..283, 439..512, 529..581,
## 294..357 and 369..432 respectively, so every band holds its row with margin.
## Unlike the tower band these carry no vertical panel rules - the rules that
## make a row's transparency unsearchable stop above these rows.
const ENEMY_ROWS := {
	&"slime": {"y0": 216, "y1": 288},
	&"ogre": {"y0": 438, "y1": 516},
	&"bee": {"y0": 521, "y1": 586},
	&"_unused/shaman": {"y0": 293, "y1": 361},
	&"_unused/troll": {"y0": 366, "y1": 433},
}

## The scan starts at 95 because the row's own label ("GOBLIN", "OGRE", "BAT")
## runs x 25..~90 - at 60 it is clipped rather than excluded and arrives as a
## 21-30px "variant" made of text. It ends at 1228 because the right-hand decor
## starts at 1238 in every row.
const ENEMY_X0 := 95
const ENEMY_X1 := 1228
const MIN_SPRITE_RUN := 20

## Spans wider than this multiple of the row's narrowest hold more than one
## creature and are dropped.
##
## The bat row overlaps wing-to-wing and does not segment: its six spans are
## 263, 103, 92, 338, 133 and 102 wide, and rendering them shows three bats,
## one, one, four, two and one. No projection threshold separates them, and
## projecting the lower body rows splits bodies rather than dividing them. So
## the row yields the three bats that stand alone and the rest are left on the
## sheet. Every span in every other row passes this filter.
const MAX_SPAN_RATIO := 1.4

## Whether a pixel belongs to a sprite rather than the sheet background.
func _is_content(sheet: Image, x: int, y: int) -> bool:
	var c := sheet.get_pixel(x, y)
	return Vector3(c.r, c.g, c.b).distance_squared_to(BACKGROUND / 255.0) * 65025.0 \
		> KEY_TOLERANCE_SQ

## Splits a horizontal band into sprite spans on gaps in its column
## projection, then drops the spans that hold more than one creature.
##
## Projection works here and flood fill does not: a tight fill fragments a
## sprite because its dark outlines sit near the background, and a loose one
## merges neighbours.
func _row_sprites(sheet: Image, y0: int, y1: int, x0: int, x1: int) -> Array:
	var present := []
	for x in range(x0, x1):
		var any := false
		for y in range(y0, y1):
			if _is_content(sheet, x, y):
				any = true
				break
		present.append(any)
	var found := []
	var start := -1
	for i in present.size():
		if present[i] and start < 0:
			start = i
		elif not present[i] and start >= 0:
			if i - start >= MIN_SPRITE_RUN:
				found.append(Vector2i(x0 + start, x0 + i))
			start = -1
	if start >= 0 and present.size() - start >= MIN_SPRITE_RUN:
		found.append(Vector2i(x0 + start, x0 + present.size()))
	if found.is_empty():
		return found
	var narrowest: int = found[0].y - found[0].x
	for span in found:
		narrowest = mini(narrowest, span.y - span.x)
	var out := []
	for span in found:
		if float(span.y - span.x) <= float(narrowest) * MAX_SPAN_RATIO:
			out.append(span)
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

Expected: PASS. The bake should print 15 slime, 13 ogre, 3 bee, 14 shaman and 13 troll variants.

Confirm `assets/towers.png` and everything already under `assets/art/` came out byte-identical: `git status --porcelain -- assets/towers.png assets/art/ground assets/art/roads` must be empty.

- [ ] **Step 5: Look at the variants**

Contact-sheet every variant of every kind, including `_unused`, and look at it. Composite over an opaque background rather than dropping alpha — an RGBA→RGB conversion paints anti-aliased edge pixels at full strength and produces convincing false speckle.

Confirm every PNG holds exactly one creature, cleanly cut, with nothing of a neighbour attached and no fragment of the row's label. The bat row is where a defect would land: it should ship three bats and no pair.

- [ ] **Step 6: Commit**

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
- Consumes: `_key`, `_trim` from Task 1, `_tower_sprite` from Task 3.
- Produces: four props per biome plus two shared endpoints, all trimmed with a 1px pad.

**The four prop slot names do not change** — `tree`, `stone`, `spike`, `fire` — because `MapRenderer`'s scatter rules are written in those terms and none of those rules change. Props come from the EXTRAS / DECOR column at `x 1237–1524`, `y 216–740`.

**The decor column is segmented by connected components, not by rows.** An earlier version of this task scanned for horizontal bands of content and split each with `_row_sprites`. Measured, that returns **four** things for the whole column: the two words of the "EXTRAS / DECOR" heading, one 283×411 blob holding every decor sprite at once, and the rule below them. The column's objects are staggered, so no row inside it is ever empty and no band scan can divide them. `_row_sprites` is also wrong here for a second reason — Task 4 gave it a filter that drops any span wider than 1.4× its row's narrowest, which is right for a row of same-sized enemies and destroys a column whose objects run from a 35×31 skull to a 96×61 boulder cluster.

Connected-component labelling divides it exactly: 42 raw components, 29 of them above the size floor, and every one is a single decor object. The 13 below the floor are the heading's letters. Each sprite is cut from **its own component's mask**, not its bounding rectangle — a neighbouring object that overlaps the rectangle would otherwise ride along, which is the same defect the tower cells hit in Task 3.

**The 29 components in reading order**, which is what `PROP_SLOTS` and the endpoint tables index:

| | | | | |
|---|---|---|---|---|
| 0 signpost | 1 pine | 2 flat stump | 3 leafy tree | 4 banner |
| 5 crates | 6 rock pair | 7 fallen log | 8 boulder cluster | 9 mossy stump |
| 10 bush | 11 stone spire | 12 mushrooms | 13 grey rock | 14 berry plant |
| 15 handcart | 16 planks | 17 barrel | 18 white flowers | 19 campfire |
| 20 mossy stump | 21 spike fence | 22 wooden cross | 23 skull and crossbones | 24 orange flowers |
| 25 rock outcrop | 26 mossy stump | 27 stump | 28 small skull | |

**Endpoints are composed**, as the Kenney ones were, because the sheet ships no castle and no cave. Keeping flat vector markers on an illustrated board is the style clash this swap exists to avoid.

The castle is the **Barracks tower's top level** with banners and crates flanking it. The decor column ships nothing castle-like, and the sheet's own keep is the right marker for the player's base — it is already in the atlas at frame 19, and `_tower_sprite(sheet, &"long", 3)` cuts it again here.

The cave is a dark ellipse with three rocks around its **rim**, leaving the middle dark. That is the arrangement the Kenney cave used and it is the only one that reads: rocks stacked *over* the mouth make a rock pile, and a mouth wider than the rocks makes a black blob. Both were tried and rendered before this one was chosen.

- [ ] **Step 1: Write the failing test**

Rewrite `test/test_prop_assets.gd`:

```gdscript
extends TestCase

# Props are free-standing sprites, so each needs a transparent margin all
# round - an opaque edge means the subject is clipped.
#
# The tight-bbox gate is the one that matters for gameplay.
# MapRenderer.prop_footprints() derives a tower-blocking radius from the
# texture's full dimensions, so transparent padding becomes invisible wall.
# The bake cuts each prop from its own connected component and pads back
# exactly 1px, which is what makes "radius from displayed size" true rather
# than merely conservative. See spec section 6.

const _BIOMES := ["forest", "ice", "desert"]
const _SLOTS := ["tree", "stone", "spike", "fire"]
const _ENDPOINTS := ["castle", "cave"]
const _MARGIN_ALPHA_MAX := 8

# After a 1px pad, the subject must fill everything else. Allowing a little
# slack for antialiasing at the extremes rather than demanding exactly 1px.
const _MAX_TRANSPARENT_BORDER := 3

# No free-standing object fills its own bounding box. Measured, the twelve
# props run from 0.35 to 0.62 opaque; a tiling fill or a crop taken from the
# middle of a larger drawing would sit near 1.0. This is the gate that
# replaces the Kenney-era "trimming shrank the 128px canvas" check, which
# only meant anything when every source shared one canvas size.
const _MAX_FILL := 0.85

func _image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _prop_image(biome: String, slot: String) -> Image:
	return _image("res://assets/art/%s/%s.png" % [biome, slot])

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

func test_every_prop_is_a_sprite_rather_than_a_slab_of_fill() -> bool:
	# The gate that catches a slot pointed at a tiling texture or at a crop
	# taken from the middle of a larger drawing. Both pass the margin and
	# tight-trim gates - the 1px pad manufactures a clean border around any
	# crop at all.
	for biome in _BIOMES:
		for slot in _SLOTS:
			var img := _prop_image(biome, slot)
			assert_true(img != null, "%s/%s.png decodes" % [biome, slot])
			if img == null:
				continue
			var opaque := 0
			for y in img.get_height():
				for x in img.get_width():
					if _alpha8(img, x, y) > _MARGIN_ALPHA_MAX:
						opaque += 1
			var fill := float(opaque) / float(img.get_width() * img.get_height())
			assert_true(fill <= _MAX_FILL,
				"%s/%s is %.2f opaque" % [biome, slot, fill])
	return true

func test_a_biome_s_four_slots_are_four_different_sprites() -> bool:
	# An index typo in PROP_SLOTS that points two slots at the same decor
	# piece is otherwise invisible: the duplicate passes every gate above.
	#
	# Compared as raw bytes, not as a digest of a decoded string: a PNG hits a
	# zero byte inside its first header field, and PackedByteArray's
	# string conversions stop there - every PNG in the project hashes to the
	# same thing that way. PackedByteArray compares by value, so Array.has is
	# the whole comparison.
	for biome in _BIOMES:
		var seen := []
		for slot in _SLOTS:
			var bytes := FileAccess.get_file_as_bytes(
				"res://assets/art/%s/%s.png" % [biome, slot])
			assert_false(bytes.is_empty(), "%s/%s.png exists" % [biome, slot])
			if bytes.is_empty():
				continue
			assert_false(seen.has(bytes),
				"%s's %s is not a copy of another slot" % [biome, slot])
			seen.append(bytes)
	return true

func test_both_endpoints_decode_and_keep_a_clear_margin() -> bool:
	for name in _ENDPOINTS:
		var img := _image("res://assets/art/%s.png" % name)
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
		assert_true(peak <= _MARGIN_ALPHA_MAX, "%s.png edge peak %d" % [name, peak])
	return true

func test_the_cave_keeps_a_dark_mouth() -> bool:
	# The cave is a dark ellipse with rocks around its rim. Rocks stacked over
	# the mouth read as a rock pile instead - and that failure is invisible to
	# every other gate here, because a rock pile is free-standing, tightly
	# trimmed and not a slab of fill. So assert the mouth is still there: a
	# tenth of the sprite is near-black.
	var img := _image("res://assets/art/cave.png")
	assert_true(img != null, "cave.png decodes")
	if img == null:
		return true
	var dark := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r < 0.12 and c.g < 0.12 and c.b < 0.14:
				dark += 1
	var share := float(dark) / float(img.get_width() * img.get_height())
	assert_true(share >= 0.10, "the cave's mouth covers %.2f of its sprite" % share)
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — nothing exists under `assets/art/<biome>/tree.png` and no endpoints. The old test read from `res://assets/kenney/<biome>/` and passed; it is the path change that turns it red.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_sheet.gd`:

```gdscript
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
	region = _key(region)
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
```

Call both from `_init` after `_bake_enemies(sheet)`, sharing one segmentation pass:

```gdscript
	var decor := _decor_sprites(sheet)
	print("bake_sheet: %d decor sprites found" % decor.size())
	_bake_props(decor)
	_bake_endpoints(sheet, decor)
```

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: PASS, and `bake_sheet: 29 decor sprites found`. A different count means the size floor or the region bounds moved and every index in `PROP_SLOTS`, `CASTLE_PIECES` and `CAVE_PIECES` is now pointing at the wrong sprite — stop and report rather than adjusting indices to match.

Confirm nothing already committed changed: `git status --porcelain -- assets/towers.png assets/art/enemies` must be empty, and the only modified files under `assets/art/forest`, `assets/art/ice` and `assets/art/desert` must be the four new prop PNGs in each.

- [ ] **Step 5: Look at what came out**

Two contact sheets, both composited over an opaque background rather than converting RGBA to RGB — dropping alpha paints anti-aliased edge pixels at full strength and produces convincing false speckle.

1. All 29 decor sprites with their indices overlaid. Confirm each is a single object and that index 3 is the leafy tree, 8 the boulder cluster, 21 the spike fence and 19 the campfire — if the numbering has shifted, everything below is wrong.
2. The twelve props at **48px**, the size `MapRenderer` draws them into, and the two endpoints at **96px**. Confirm each prop still reads at that size, that the castle reads as a keep, and that the cave reads as a dark mouth ringed by rock rather than as a rock pile or a black blob.

- [ ] **Step 6: Commit**

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

**Repoint the endpoint preloads in this task.** `game/map_renderer.gd:9-10` preloads `_CASTLE` and `_CAVE` from `res://assets/kenney/`. Task 5 wrote the replacements to `res://assets/art/`, and Task 9 deletes the Kenney directory — so leaving these would turn a `preload` into a parse error and take the whole suite down as a load failure rather than a test failure. Change both constants to `res://assets/art/castle.png` and `res://assets/art/cave.png`; `_draw_endpoints`'s body does not change.

**Interfaces:**
- Consumes: the ground and road assets from Tasks 1 and 2.
- Produces: `Biomes.ground_path(biome, index) -> String`, `Biomes.road_path(biome, mask) -> String`, and `MapRenderer.edge_mask(c, r) -> int`.

**This deletes the corner-mask lattice.** `MapRenderer._draw_ground` currently samples terrain at tile centres over a `(cols + 1) × (rows + 1)` grid offset by half a tile, and `corner_mask` supports it. Both go. The replacement draws **one sprite per tile on the tile grid** — no offset, no extra row or column.

**The mask is edges, not corners.** For each cell, which of its four orthogonal neighbours is road: `N=1, E=2, S=4, W=8`. Out of bounds is not road. `MapRenderer._is_road` already has exactly these semantics and does not change.

**All sixteen road masks exist as files, so there is no rotation.** An earlier version of this task loaded one of five base pieces and rotated it onto the cell's mask. That was written before Task 2's ruling to compose every mask from the cross, and it is not merely redundant now — it is wrong twice over:

- Rotating `{0, 3, 5, 7, 15}` reaches only twelve of the sixteen masks. The four dead ends — 1, 2, 4 and 8 — are unreachable, because a single-bit mask has no rotation from a two-, three- or four-bit one. **The demo map contains masks 2 and 8**, at the spawn and the goal, where the road enters from exactly one side. Both cells would have fallen through to the `push_error` and drawn nothing.
- The pieces are 66 × 63, not square, so a 90° rotation would not fit the cell it was drawn into.

The road piece for a cell is `road_%02d.png` for that cell's mask. Measured, the demo map uses masks 2, 3, 5, 6, 8, 9, 10 and 12.

**Ground and road tiles are STRETCHED to the tile, not aspect-fitted.** `_place` fits a source inside a square box preserving aspect and centres it in the slack — which is right for props and wrong for tiles. The road pieces are 66 × 63 and `ground_5` is 65 × 66, so aspect-fitting leaves a 2.2px transparent gap under every road tile and a hairline beside that one ground tile: seams, in the layer whose whole job is to have none. A tile is a cell of a grid and has to fill its cell exactly. The distortion is 4.7% on the roads and under 2% on the ground, and it is what the Phaser reference did for every sprite.

Props keep `_place`. `prop_footprints` derives a blocking radius from displayed size and its doc comment says in as many words that this only measures correctly because `_place` scales uniformly — so the new path must be a separate function, not a flag on that one.

- [ ] **Step 1: Write the failing tests**

In `test/test_map_renderer.gd`, delete the tests that describe the lattice — `test_ground_layer_has_one_sprite_per_lattice_point`, `test_ground_sprites_are_offset_half_a_tile_so_roads_sit_on_tile_centres`, `test_the_corner_mask_reads_road_from_the_four_surrounding_tile_centres`, `test_spawn_and_goal_tiles_count_as_road_for_the_lattice`, `test_the_demo_map_never_needs_a_diagonal_blend_tile`, `test_every_ground_sprite_uses_the_texture_its_mask_names` and `test_square_ground_tiles_take_zero_slack_from_the_tile_box` — change the four prop path constants to `res://assets/art/forest/*.png`, and add:

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
	tiles[1][2] = Tiles.BUILDABLE
	tiles[2][1] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 4, "a road neighbour to the south sets bit 4")
	tiles[2][1] = Tiles.BUILDABLE
	tiles[1][0] = Tiles.PATH
	renderer.render(tiles, Rng.new(1), &"forest")
	assert_eq(renderer.edge_mask(1, 1), 8, "a road neighbour to the west sets bit 8")
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
	assert_eq(renderer.edge_mask(1, 0), 2 | 8,
		"spawn to the west and goal to the east both count")
	renderer.free()
	return true

func test_every_road_cell_draws_the_piece_its_mask_names() -> bool:
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
		var named := int(sprite.texture.resource_path.get_file().get_basename().split("_")[1])
		assert_eq(named, renderer.edge_mask(c, r),
			"the piece at (%d, %d) is the one its mask names" % [c, r])
		checked += 1
	assert_true(checked > 0, "road cells were checked")
	renderer.free()
	return true

func test_the_demo_map_needs_the_dead_end_pieces() -> bool:
	# The reason there is no rotation. Rotating the five pieces the sheet
	# itself draws reaches twelve of the sixteen masks; the four dead ends
	# (1, 2, 4, 8) are unreachable from them, and the demo map has two - the
	# spawn and the goal, where the road enters from one side only. This test
	# fails the day someone reintroduces a rotation scheme.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var dead_ends := 0
	for r in DemoMap.GRID_ROWS:
		for c in DemoMap.GRID_COLS:
			if tiles[r][c] in Tiles.WALKABLE and renderer.edge_mask(c, r) in [1, 2, 4, 8]:
				dead_ends += 1
	assert_eq(dead_ends, 2, "the demo map's road has two dead ends")
	renderer.free()
	return true

func test_ground_and_road_tiles_fill_their_cell_exactly() -> bool:
	# Replaces test_square_ground_tiles_take_zero_slack_from_the_tile_box,
	# whose premise was that every ground source is square. The illustrated
	# road pieces are 66x63, so aspect-fitting them leaves a 2.2px transparent
	# gap under every road tile - seams, in the layer whose whole job is to
	# have none. The property worth keeping is unchanged and is stated more
	# directly here: a tile lands on its cell's origin and covers the cell.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var box := float(Tiles.TILE_SIZE)
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		var tex: Texture2D = sprite.texture
		var display := Vector2(tex.get_width(), tex.get_height()) * sprite.scale
		assert_almost_eq(display.x, box, 0.01, "a tile is exactly one cell wide")
		assert_almost_eq(display.y, box, 0.01, "a tile is exactly one cell tall")
		var c := int(round(sprite.position.x / box))
		var r := int(round(sprite.position.y / box))
		assert_eq(sprite.position, Vector2(c * box, r * box),
			"a tile lands on its cell's origin")
		checked += 1
	assert_true(checked > 0, "tiles were checked")
	renderer.free()
	return true

func test_a_non_square_tile_source_is_the_case_this_covers() -> bool:
	# The precondition the test above rests on. If every source were square,
	# stretching and aspect-fitting would be the same thing and the seam this
	# task fixes could not occur.
	var bytes := FileAccess.get_file_as_bytes("res://assets/art/forest/road_10.png")
	assert_false(bytes.is_empty(), "a road piece exists to measure")
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(bytes), OK, "the road piece decodes")
	assert_false(img.get_width() == img.get_height(),
		"the road pieces are genuinely non-square (%dx%d)"
			% [img.get_width(), img.get_height()])
	return true
```

In `test/test_biomes.gd`, replace the blend-mask test with:

```gdscript
func test_every_biome_resolves_its_ground_and_road_pieces() -> bool:
	for biome in Biomes.KINDS:
		for i in Biomes.GROUND_VARIANTS:
			assert_true(ResourceLoader.exists(Biomes.ground_path(biome, i)),
				"%s ground %d resolves" % [biome, i])
		for mask in 16:
			assert_true(ResourceLoader.exists(Biomes.road_path(biome, mask)),
				"%s road %d resolves" % [biome, mask])
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — `edge_mask`, `ground_path` and `road_path` do not exist.

- [ ] **Step 3: Rewrite the biome accessors**

In `data/biomes.gd`, point each biome's `dir` at `res://assets/art/<biome>`, delete `blend_path`, `DIAGONAL_MASKS` and `DIAGONAL_FALLBACK`, and add:

```gdscript
## Returns a path, never a loaded resource. data/ is held engine-free by
## test/test_sim_purity.gd, whose docstring explains that resource loading
## breaks the headless claim the whole harness rests on. The render layer
## loads; this module only names.
static func ground_path(biome: StringName, index: int) -> String:
	return "%s/ground_%d.png" % [DEFS[biome]["dir"], index]

static func road_path(biome: StringName, mask: int) -> String:
	return "%s/road_%02d.png" % [DEFS[biome]["dir"], mask]

## Ground variants per biome, and every one of the sixteen edge masks as a
## road piece. There is no fallback and no rotation: the bake composes all
## sixteen from the sheet's cross, so every mask a map can produce has a file
## - including the four dead ends, which no rotation of the pieces the sheet
## itself draws can reach.
const GROUND_VARIANTS := 6
const ROAD_MASKS := 16
```

Delete the `DIAGONAL_MASKS` comment block with it: it described a Kenney blob tileset that omitted the diagonal-only pairing, and neither the tileset nor the omission survives this swap.

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
##
## Ground variety is drawn from its own Rng rather than the decoration one.
## Which of the six ground cards a tile gets is cosmetic and should not move
## when the decoration seed changes; drawing from the passed rng here would
## also shift the whole decoration stream, since _draw_ground runs first.
func _draw_ground() -> void:
	var variants := Rng.new(Seeds.DEFAULT_GROUND_SEED)
	for r in _rows:
		for c in _cols:
			# load() rather than a texture from Biomes: data/ is held
			# engine-free by test_sim_purity.gd, so the render layer is where
			# a path becomes a resource. Godot's ResourceLoader caches by
			# path, so the repeated calls are dictionary hits.
			if _is_road(c, r):
				_place_tile(load(Biomes.road_path(_biome, edge_mask(c, r))), c, r)
			else:
				_place_tile(load(Biomes.ground_path(
					_biome, variants.int_range(0, Biomes.GROUND_VARIANTS - 1))), c, r)

## The four orthogonal neighbours of a cell that are road, as a bitmask.
## Bit order is fixed: N=1, E=2, S=4, W=8. Out of bounds is not road.
## Public so tests can assert the mask without inspecting sprites.
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

## Draws a ground or road tile STRETCHED to fill its cell exactly.
##
## Deliberately not _place. A tile is a cell of a grid and has to cover its
## cell; _place fits a source inside the box preserving aspect and centres it
## in the slack, which is right for a prop and opens seams here - the road
## pieces are 66x63, so aspect-fitting leaves 2.2px of transparency under
## every one of them. The distortion this trades for is 4.7% on the roads and
## under 2% on the ground.
##
## prop_footprints reads displayed size to derive a blocking radius and its
## doc comment says that only measures correctly because _place scales
## uniformly. That stays true: props still go through _place, and nothing
## drawn here is ever recorded as a prop.
func _place_tile(texture: Texture2D, col: int, row: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE)
	s.scale = Vector2(
		float(Tiles.TILE_SIZE) / float(texture.get_width()),
		float(Tiles.TILE_SIZE) / float(texture.get_height()))
	# Same reasoning as _place: this art is painted, not pixel art, and every
	# tile is minified from 66px into 48px.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = _Z_GROUND
	add_child(s)
	return s
```

`_is_road` stays exactly as it is — its semantics already match, and its doc comment ("out of bounds reads as ground") is still true. Replace only the sentence about closing the lattice.

Add to `data/seeds.gd`:

```gdscript
## Which of the six ground cards each tile gets. Separate from the decoration
## seed so ground variety does not move when decoration does.
const DEFAULT_GROUND_SEED := 20260821
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: PASS. Other tests in `test/test_map_renderer.gd` count sprites or read positions and may need their expectations updated for the new grid — that is in scope for this task. Do not weaken an assertion to make it pass; if one cannot be updated truthfully, stop and report.

- [ ] **Step 6: Look at the map**

Render the forest map and look at it: `godot --headless` cannot screenshot, so run the project through the Godot MCP (`run_project`, then `game_screenshot`) or open it directly. Confirm the road is continuous with no transparent seams between tiles, that the spawn and goal cells draw a road piece rather than nothing, and that the ground cards tile without visible gaps.

- [ ] **Step 7: Commit**

```bash
git add game/map_renderer.gd data/biomes.gd data/seeds.gd test/test_map_renderer.gd test/test_biomes.gd
git commit -m "Draw the road from an edge mask and drop the corner lattice"
```

---

### Task 7: Enemy variants, motion and death

**Files:**
- Modify: `game/enemy.gd`
- Modify: `game/enemy.tscn`
- Modify: `game/game_board.gd`
- Modify: `data/enemies.gd`
- Modify: `data/seeds.gd`
- Test: `test/test_enemy.gd`

**Interfaces:**
- Consumes: the variant sprites from Task 4.
- Produces: `Enemy` draws a `Sprite2D` rather than an `AnimatedSprite2D`; `Enemy.setup` takes an optional `Rng`; `Enemies.variant_count(kind) -> int`.

**What is removed:** `_facing`, `_set_facing`, `_play_walk`, `_build_frames`, the `FRAME_SIZE`/`FRAMES_PER_SHEET`/`WALK_FPS`/`DEATH_FPS` constants and every `_sprite.play(...)` call. `game/enemy.tscn`'s `AnimatedSprite2D` becomes a `Sprite2D`, and its `texture_filter` moves from NEAREST to LINEAR_WITH_MIPMAPS — see Step 4.

**What replaces it:** one variant chosen at spawn from a seeded `Rng`, flipped horizontally by travel direction, with a sine bob while moving. Death becomes a fade-and-shrink tween.

**`Enemy.setup` has no `Rng` today and `GameBoard` has none either.** Variant choice has to be reproducible — the whole harness rests on that — so the parameter is added with a default, matching `MapRenderer.render`'s existing shape, and the board gains a spawn `Rng` reset at each wave start. The default keeps every existing `setup(kind, path, wave)` call site working unchanged.

**`sprite_scale` becomes `sprite_px`, a displayed HEIGHT.** A fixed scale factor only made sense against Kenney's uniform 48 × 48 animation frames. The variants are not uniform — measured, the goblins run 54–69 × 50–54, the ogres 71–80 × 67–76 and the bats 94–105 × 41–47 — so a fixed factor draws the same kind at different sizes from one spawn to the next, and draws all three at the wrong absolute size. Deriving the scale from the chosen variant's height fixes both. The values below preserve today's on-screen sizes: the Kenney frame was 48px at 0.7, 1.2 and 0.7, giving 33.6, 57.6 and 33.6.

**All three kinds' art faces right**, checked at 4×, so `flip_horizontally` is `false` for all of them — including the ogre, which was `true` against the Kenney art.

**Death cannot create a tween in the test harness.** Every enemy the suite builds is outside the scene tree — `test/test_enemy.gd`'s header explains why at length — and `Node.create_tween()` requires a tree. `_die` therefore returns after emitting when it is off-tree. That is exactly today's observable behaviour: today `_die` awaits `animation_finished`, which off-tree never fires, so everything after the await already never runs in tests.

- [ ] **Step 1: Write the failing tests**

In `test/test_enemy.gd`, delete `test_die_plays_the_death_animation_for_the_enemys_current_facing` and every other test asserting `_facing`, `_sprite.animation`, or the `walk_*`/`death_*` animations. Add a seeded builder beside `_ready_enemy`, and these tests:

```gdscript
## The same enemy _ready_enemy builds, set up with a seeded Rng so the variant
## it picks is pinned rather than incidental.
func _ready_enemy_with_seed(seed_value: int) -> Enemy:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1, Rng.new(seed_value))
	return e

func test_an_enemy_draws_one_of_its_kind_s_variants() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	assert_true(sprite.texture != null, "a variant was chosen")
	assert_true(sprite.texture.resource_path.contains("/art/enemies/slime/"),
		"and it came from this kind's art directory")
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

func test_different_seeds_reach_more_than_one_variant() -> bool:
	# Otherwise "pick a variant" could be a constant and every test above
	# would still pass.
	var seen := {}
	for s in 40:
		var e := _ready_enemy_with_seed(s + 1)
		seen[e.get_node("Sprite").texture.resource_path] = true
		e.free()
	assert_true(seen.size() > 1, "%d distinct variants over 40 seeds" % seen.size())
	return true

func test_an_enemy_is_drawn_at_its_kind_s_declared_height() -> bool:
	# The scale is derived from the chosen variant rather than fixed, because
	# the variants are not a uniform size - a fixed factor would draw the same
	# kind at a different size from one spawn to the next.
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _straight_path(), 1)
		var sprite: Sprite2D = e.get_node("Sprite")
		var drawn := float(sprite.texture.get_height()) * sprite.scale.y
		assert_almost_eq(drawn, float(Enemies.DEFS[kind]["sprite_px"]), 0.01,
			"%s draws at its declared height" % kind)
		assert_almost_eq(sprite.scale.x, sprite.scale.y, 0.0001,
			"%s is scaled uniformly, not stretched" % kind)
		e.free()
	return true

func test_every_variant_of_a_kind_draws_at_the_same_height() -> bool:
	# The defect a fixed scale factor would leave: same kind, different size.
	for kind in Enemies.KINDS:
		for i in Enemies.variant_count(kind):
			var e := _ready_enemy()
			e.setup(kind, _straight_path(), 1)
			var sprite: Sprite2D = e.get_node("Sprite")
			sprite.texture = load("res://assets/art/enemies/%s/variant_%d.png" % [kind, i])
			e.apply_sprite_height()
			var drawn := float(sprite.texture.get_height()) * sprite.scale.y
			assert_almost_eq(drawn, float(Enemies.DEFS[kind]["sprite_px"]), 0.01,
				"%s variant %d draws at the declared height" % [kind, i])
			e.free()
	return true

func test_an_enemy_faces_the_way_it_travels() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
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
	assert_true(Enemy.DEATH_TWEEN_MS > 0.0, "the death tween has a duration")
	assert_true(Enemy.DEATH_TWEEN_MS < 1000.0,
		"and it is short enough not to hold a kill on screen")
	return true

func test_a_lethal_hit_off_the_tree_still_pays_and_hides_the_bar() -> bool:
	# Every enemy this suite builds is outside the scene tree (see this file's
	# header), and create_tween() requires one. _die must reach everything the
	# sim observes before it gives up on the presentation.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var captured := {"count": 0}
	e.died.connect(func(_v, _k): captured["count"] += 1)
	e.take_damage({"damage": 999.0})
	assert_eq(captured["count"], 1, "died fired on the lethal hit")
	assert_true(e.sim["dying"], "the enemy is marked dying")
	assert_false(e.sim["alive"], "and no longer alive")
	assert_false(e._health_bar.visible, "the health bar is hidden")
	e.free()
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — the scene still holds an `AnimatedSprite2D`, `setup` takes three arguments, and none of `variant_count`, `sprite_px`, `set_facing_from_travel`, `apply_sprite_height` or `DEATH_TWEEN_MS` exist.

- [ ] **Step 3: Rewrite the data tables**

In `data/enemies.gd`, replace each kind's `texture_key` and `sprite_scale` with `variant_count` and `sprite_px`, set every `flip_horizontally` to `false`, and leave every stat untouched:

```gdscript
const DEFS := {
	&"slime": {
		"label": "Slime", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "variant_count": 15, "sprite_px": 34.0,
		"flip_horizontally": false,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 60.0, "base_health": 8, "reward": 20,
		"life_loss": 5, "variant_count": 13, "sprite_px": 58.0,
		"flip_horizontally": false,
	},
	&"bee": {
		"label": "Bee", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "variant_count": 3, "sprite_px": 28.0,
		"flip_horizontally": false,
	},
}
```

Add the accessor:

```gdscript
## How many per-spawn variants this kind's art directory holds. Baked by
## tools/bake_sheet.gd; pinned by test_enemy.gd against the files on disk, so a
## re-bake that produces a different number cannot silently leave this table
## pointing at a variant that is not there.
static func variant_count(kind: StringName) -> int:
	return int(DEFS[kind]["variant_count"])
```

Document the two replaced keys where the table sits:

```gdscript
## sprite_px is a displayed HEIGHT, not a scale factor. It replaced
## sprite_scale, which only made sense against Kenney's uniform 48x48
## animation frames: the illustrated variants are not a uniform size (goblins
## 54-69 x 50-54, ogres 71-80 x 67-76, bats 94-105 x 41-47), so a fixed factor
## drew the same kind at a different size from one spawn to the next. The
## values preserve the sizes the Kenney art drew at - 33.6, 57.6 and 33.6px -
## except the bat, which is naturally wide and is given a little less height
## so it does not out-mass the tanky kind.
##
## flip_horizontally is false for all three because all three faces on this
## sheet point right. It stays in the table because it is a property of the
## ART, and the next sheet may not agree with this one.
```

Add to `data/seeds.gd`:

```gdscript
## Which variant each spawn draws. Separate from the decoration seed so enemy
## variety does not move when scenery does.
const DEFAULT_SPAWN_SEED := 20260822
```

- [ ] **Step 4: Rewrite the enemy view**

In `game/enemy.tscn`, change the `Sprite` node's type from `AnimatedSprite2D` to `Sprite2D`, and change `texture_filter` from `1` to `4`.

`1` is `TEXTURE_FILTER_NEAREST` and it was the right call for what it filtered: Kenney's enemies are 48px hand-placed pixel art, and a linear filter on pixel art smears it. These variants are painted, not pixel art, and they are minified — the ogre 79 × 76 into 58px tall, the goblin 60 × 52 into 34, the bat 100 × 44 into 28, so between 1.3× and 1.6×. `4` is `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`, matching what `MapRenderer._place` already uses for the props for the same reason. Task 10 turns mipmap generation on for the variant `.import` files; a mipmap filter reading a chain nobody generated silently falls back to the base level.

In `game/enemy.gd`, delete `_facing`, `_set_facing`, `_play_walk`, `_build_frames`, and the `FRAME_SIZE`, `FRAMES_PER_SHEET`, `WALK_FPS` and `DEATH_FPS` constants. Update the class docstring's "owns an animated sprite" to "owns a sprite". Then add:

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

var _bob_clock := 0.0
var _flip := false
```

Change `setup`'s signature to `func setup(enemy_kind: StringName, path: PackedVector2Array, wave: int, rng: Rng = null) -> void`, and replace the two `_sprite` lines at its end with:

```gdscript
	# One of this kind's variants, chosen per spawn. A wave of eight shows
	# eight subtly different creatures rather than eight identical ones. The
	# default keeps the three-argument call sites working and keeps a spawn
	# reproducible either way.
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_SPAWN_SEED)
	_sprite.texture = load("res://assets/art/enemies/%s/variant_%d.png"
		% [kind, rng.int_range(0, Enemies.variant_count(kind) - 1)])
	apply_sprite_height()
```

```gdscript
## Scales the current variant to the kind's declared displayed height.
##
## Derived per sprite rather than fixed, because the variants are not a
## uniform size - see data/enemies.gd's note on sprite_px. Uniform on both
## axes: these are creatures, and a stretched one reads as a bug.
func apply_sprite_height() -> void:
	var factor := float(Enemies.DEFS[kind]["sprite_px"]) \
		/ float(_sprite.texture.get_height())
	_sprite.scale = Vector2.ONE * factor
```

Replace `_set_facing` with:

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

In `_physics_process`, keep the existing `advanced_waypoint` guard exactly where it is — a tick that advanced a waypoint covered no distance, so its reported direction comes from a sub-pixel delta and would make the sprite jitter — and drive the bob outside it:

```gdscript
	if not result["advanced_waypoint"]:
		set_facing_from_travel(bool(result["moving_left"]))

	_bob_clock += delta
	_sprite.position.y = -absf(sin(_bob_clock * BOB_HZ * TAU)) * BOB_PIXELS
```

Rewrite `_die` so everything the sim observes happens exactly where it happens now, and only the despawn changes:

```gdscript
func _die(source: Dictionary) -> void:
	sim["dying"] = true
	sim["alive"] = false
	# Emitted before the presentation, unchanged: economy timing must not move
	# because the death animation became a tween.
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
	_health_bar.visible = false
	# Every enemy the test harness builds is outside the scene tree (see the
	# header of test/test_enemy.gd) and create_tween() requires one. This is
	# not a new limitation: today's `await _sprite.animation_finished` never
	# resolves off-tree either, so nothing past this point has ever run in a
	# test. Returning says so instead of parking a coroutine forever.
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 0.6, DEATH_TWEEN_MS / 1000.0)
	tween.tween_property(self, "modulate:a", 0.0, DEATH_TWEEN_MS / 1000.0)
	await tween.finished
	queue_free()
```

- [ ] **Step 5: Give the board a spawn Rng**

In `game/game_board.gd`, add the field and reset it where `_spawned` is reset at wave start:

```gdscript
## Which variant each spawn draws. Reset per wave so replaying a wave shows
## the same creatures, and separate from every other random system so enemy
## variety does not move when they do.
var _spawn_rng := Rng.new(Seeds.DEFAULT_SPAWN_SEED)
```

```gdscript
	_spawn_rng = Rng.new(Seeds.DEFAULT_SPAWN_SEED)
```

and pass it in `_spawn`:

```gdscript
	enemy.setup(kind, _paths[0], _wave, _spawn_rng)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: PASS. `test/test_harness.gd` and the wave tests must stay green — the sim never knew about animations, so nothing there should move. `test/test_game_board.gd` deals a lethal hit to an off-tree enemy; that path is covered by `_die`'s tree guard.

- [ ] **Step 7: Look at a wave**

Run the project and watch a wave. Confirm the enemies face the way they travel, that a wave shows visibly different creatures rather than one repeated, that the bob reads as motion rather than vibration, and that a kill fades out rather than vanishing. Note the on-screen sizes against each other — `sprite_px` is the one value here chosen to preserve a previous look rather than measured from the art, and this is where it gets judged.

- [ ] **Step 8: Commit**

```bash
git add game/enemy.gd game/enemy.tscn game/game_board.gd data/enemies.gd data/seeds.gd test/test_enemy.gd
git commit -m "Draw enemies as per-spawn variants with procedural motion"
```

---

### Task 8: Close the tile seams

**Files:**
- Modify: `tools/bake_sheet.gd`
- Modify: `assets/art/<biome>/road_*.png` (all 48, re-baked)
- Modify: `game/map_renderer.gd`
- Test: `test/test_road_pieces.gd`
- Test: `test/test_map_renderer.gd`

**Interfaces:**
- Consumes: the road pieces from Task 2 and `_place_tile` from Task 6.
- Produces: road pieces with no black slot in their interior, and a ground layer with no black gutter between cells.

**This task exists because the board was rendered and looked at.** Composing the demo map from the committed tiles at the size the game draws them shows two separate defects, neither of which any existing gate can see, and both of which dominate the board's main surface.

**Defect one: every tile is drawn with its card border, so the map reads as a grid of cards separated by black gutters.** The sheet's terrain tiles are cards with a painted dark scalloped edge. `_trim` keeps that edge and adds a 1px transparent pad, and `_place_tile` draws the whole texture into the cell — so every cell boundary carries the two adjacent borders back to back. Measured across all 66 ground and road PNGs in all three biomes, probing inward from each edge at six positions per tile and counting the run of near-black pixels: the border, including the pad, is **at most 5px** of a 66px tile. The spec called for the tiles to be "scaled to slightly overfill each cell" for exactly this reason; overfilling helps the ground but cannot help the road, because a road tile's leading border is then drawn over its neighbour's road. Cropping the border away removes it in both cases.

**Defect two: every composed road piece has black slots cut into its interior.** `_patch_arm` fills an absent arm by copying an adjacent corner of the cross — and that corner region includes the card's outer border along its own outer edges. Copying it into the middle of the tile carries a near-black stripe into the interior. It is visible in every composed mask, and tiled up it reads as a black bar across the road at every cell boundary. The function's own doc comment says the patch is "mirrored so the grass edging runs the right way", and the code does not mirror — it clamps. Mirroring is the fix, because it makes the arm continue the corner from the corner's INNER edge outward, and never reaches the outer border at all.

Both were prototyped against the real sheet and rendered before this task was written.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_road_pieces.gd`:

```gdscript
func test_no_composed_piece_carries_a_black_slot_in_its_interior() -> bool:
	# _patch_arm used to fill an absent arm by copying an adjacent corner of
	# the cross, and that corner carries the card's own outer border on its
	# outer edges - so the copy dragged a near-black stripe into the middle of
	# the tile. Tiled up it read as a bar across the road at every cell
	# boundary. Nothing else in this file could see it: the piece still had
	# the right mask, the right palette and a clean margin.
	#
	# The interior is everything more than BORDER from an edge. The card's own
	# border lives outside that and is left alone.
	const _BORDER := 6
	const _DARK := 45.0 / 255.0
	for biome in Biomes.KINDS:
		for mask in 16:
			var bytes := FileAccess.get_file_as_bytes(
				"res://assets/art/%s/road_%02d.png" % [biome, mask])
			assert_false(bytes.is_empty(), "%s road %d exists" % [biome, mask])
			if bytes.is_empty():
				continue
			var img := Image.new()
			assert_eq(img.load_png_from_buffer(bytes), OK,
				"%s road %d decodes" % [biome, mask])
			var dark := 0
			for y in range(_BORDER, img.get_height() - _BORDER):
				for x in range(_BORDER, img.get_width() - _BORDER):
					var c := img.get_pixel(x, y)
					if c.a > 0.5 and c.r < _DARK and c.g < _DARK and c.b < _DARK:
						dark += 1
			assert_eq(dark, 0,
				"%s road %d has %d near-black interior pixels" % [biome, mask, dark])
	return true
```

Add to `test/test_map_renderer.gd`:

```gdscript
func test_tiles_are_drawn_without_their_card_border() -> bool:
	# The sheet's terrain tiles are cards with a painted dark edge. Drawn
	# whole, every cell boundary carries two of those edges back to back and
	# the map reads as a grid of cards in black gutters. The renderer draws
	# the interior of each tile instead.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != -1:
			continue
		var sprite: Sprite2D = child
		assert_true(sprite.region_enabled, "a tile is drawn from a region")
		var tex: Texture2D = sprite.texture
		assert_eq(sprite.region_rect,
			Rect2(MapRenderer.TILE_BLEED, MapRenderer.TILE_BLEED,
				tex.get_width() - MapRenderer.TILE_BLEED * 2.0,
				tex.get_height() - MapRenderer.TILE_BLEED * 2.0),
			"the region is the tile's interior")
		checked += 1
	assert_true(checked > 0, "tiles were checked")
	renderer.free()
	return true

func test_the_bleed_is_wide_enough_for_the_widest_card_border() -> bool:
	# Measured: probing inward from each edge of all 66 ground and road PNGs
	# in all three biomes, the run of near-black pixels - the card's border
	# plus _trim's 1px pad - never exceeds 5. A bleed under that leaves a dark
	# line; far over it eats art. This pins the measurement rather than the
	# taste.
	var worst := 0
	for biome in Biomes.KINDS:
		for i in Biomes.GROUND_VARIANTS:
			worst = maxi(worst, _border_run(Biomes.ground_path(biome, i)))
		for mask in 16:
			worst = maxi(worst, _border_run(Biomes.road_path(biome, mask)))
	assert_true(worst > 0, "the tiles do have a card border to crop")
	assert_true(MapRenderer.TILE_BLEED > worst,
		"the bleed %d clears the widest border %d" % [MapRenderer.TILE_BLEED, worst])
	assert_true(MapRenderer.TILE_BLEED <= worst + 3,
		"the bleed %d does not eat art beyond the border %d"
			% [MapRenderer.TILE_BLEED, worst])
	return true

## Longest run of near-black pixels reaching in from any edge of a tile.
func _border_run(path: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return 0
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return 0
	var w := img.get_width()
	var h := img.get_height()
	var worst := 0
	for probe in [w / 4, w / 2, 3 * w / 4]:
		worst = maxi(worst, _run_from(img, probe, 0, 0, 1))
		worst = maxi(worst, _run_from(img, probe, h - 1, 0, -1))
	for probe in [h / 4, h / 2, 3 * h / 4]:
		worst = maxi(worst, _run_from(img, 0, probe, 1, 0))
		worst = maxi(worst, _run_from(img, w - 1, probe, -1, 0))
	return worst

func _run_from(img: Image, x: int, y: int, dx: int, dy: int) -> int:
	var n := 0
	while x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		var c := img.get_pixel(x, y)
		var lum := (c.r + c.g + c.b) / 3.0 * c.a
		if lum >= 45.0 / 255.0:
			break
		n += 1
		x += dx
		y += dy
	return n
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — the road pieces carry interior black slots, and `MapRenderer.TILE_BLEED` does not exist.

- [ ] **Step 3: Mirror the arm patch**

In `tools/bake_sheet.gd`, add the constant and rewrite `_patch_arm`, and pass each call its mirror axis:

```gdscript
## How far the card's painted border reaches in from a tile's edge.
##
## MEASURED across all 66 ground and road PNGs in all three biomes, probing
## inward from each edge at six positions per tile: the run of near-black
## pixels, including _trim's 1px pad, never exceeds 5.
const CARD_BORDER := 5
```

```gdscript
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
```

In `_compose_road`, mirror across the axis that runs from the corner into the arm — horizontally for the north and south arms, which sit beside their corner, and vertically for the west and east arms, which sit below theirs:

```gdscript
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
```

- [ ] **Step 4: Re-bake and confirm only the roads moved**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
git status --porcelain
```

Only `assets/art/<biome>/road_*.png` may appear. The ground tiles, the tower atlas, the enemy variants, the props and the endpoints all come out byte-identical — nothing but `_patch_arm` changed. If anything else is modified, stop and report.

- [ ] **Step 5: Crop the card border at draw time**

In `game/map_renderer.gd`, add the constant and take the region in `_place_tile`:

```gdscript
## How much of each tile's edge is the card's painted border rather than
## terrain, and is therefore not drawn.
##
## The sheet's terrain tiles are cards with a dark scalloped edge and a drop
## shadow. Drawn whole, every cell boundary carries two of those edges back to
## back and the board reads as a grid of cards in black gutters - the single
## most visible thing about the first map rendered from this art. The spec
## called for tiles "scaled to slightly overfill each cell" to close them,
## which works for the ground and cannot work for the road: a road tile's
## leading border is then drawn over its neighbour's road instead of over its
## grass. Cropping removes it in both cases.
##
## MEASURED at 5 - the widest near-black run reaching in from any edge across
## all 66 ground and road PNGs in all three biomes - plus one.
const TILE_BLEED := 6
```

```gdscript
func _place_tile(texture: Texture2D, col: int, row: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	# The card's border is cropped rather than drawn - see TILE_BLEED.
	s.region_enabled = true
	s.region_rect = Rect2(TILE_BLEED, TILE_BLEED,
		texture.get_width() - TILE_BLEED * 2.0,
		texture.get_height() - TILE_BLEED * 2.0)
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE)
	s.scale = Vector2(
		float(Tiles.TILE_SIZE) / s.region_rect.size.x,
		float(Tiles.TILE_SIZE) / s.region_rect.size.y)
	# Same reasoning as _place: this art is painted, not pixel art, and every
	# tile is minified from 66px into 48px.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = _Z_GROUND
	add_child(s)
	return s
```

`test_ground_and_road_tiles_fill_their_cell_exactly` from Task 6 measures displayed size as `texture size × scale`. With a region that is no longer the whole texture, it must measure `region_rect.size × scale`. Update it; the property it asserts is unchanged.

- [ ] **Step 6: Clear the two loose ends Task 6's review left**

Both are one-liners in files this task is already changing.

`Biomes.ROAD_MASKS := 16` is unused — nothing reads it, and `tools/bake_sheet.gd`'s own `ROAD_MASKS` array is a different thing with the same name. Delete the constant and fold what it documented into `road_path`'s comment, which is where a reader looking for "how many masks are there" actually arrives.

`MapRenderer._place`'s docstring still ends by claiming a square source's zero slack "is what keeps the ground layer flush and seam-free". That stopped being true when the ground moved to `_place_tile` — and Task 6 deleted the test that verified it, for the same reason. Cut that sentence; `_place` is the prop path now, and its remaining paragraphs about uniform scaling and centring are still correct and still load-bearing for `prop_footprints`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: PASS.

- [ ] **Step 8: Look at the board**

Render the forest, ice and desert maps and look at all three. Confirm the ground reads as one continuous surface rather than a grid of cards, that the road runs unbroken through every straight, corner and junction with no dark bar at a cell boundary, and that nothing at the map edge is clipped oddly by the crop.

- [ ] **Step 9: Commit**

```bash
git add tools/bake_sheet.gd assets/art data/biomes.gd game/map_renderer.gd test/test_road_pieces.gd test/test_map_renderer.gd
git commit -m "Crop the card border and stop the arm patch dragging it inward"
```

---

### Task 9: Retune the no-build corridor

**Files:**
- Modify: `sim/placement.gd`
- Test: `test/test_road_width.gd`

**Interfaces:**
- Consumes: the road pieces from Task 8 and `MapRenderer.TILE_BLEED` from Task 8.
- Produces: `Placement.PATH_HALF_WIDTH` measured against the new road.

`PATH_HALF_WIDTH` moved 26 → 14 during the Kenney swap because that road drew only 23px wide. **It goes down again, not up.** An earlier version of this task claimed these cells are full-tile dirt so the road returns to roughly 48px. That is false: the sheet's cross has arms about a third of its cell, so the drawn road is narrower than the Kenney one it replaces, not wider. Measured on the committed `road_05` in all three biomes, classifying each pixel to the nearer of the surround and road palettes and taking the longest contiguous run per row, the road is 22 source px of 66 — identically in forest, desert and ice, which is expected since they are one composition recoloured.

**The conversion to world pixels is not the naïve one.** Task 8 crops `TILE_BLEED` from every edge before scaling, so a source pixel is worth `TILE_SIZE / (source_width - TILE_BLEED * 2)` world pixels, not `TILE_SIZE / source_width`. Deriving it any other way understates the road by about 12%.

**Measure, do not guess.** `test/test_road_width.gd` already derives the drawn road width from a committed tile and asserts the constant tracks it with two bounds — never narrower than the road's half-width, never more than 4px beyond it. Both bounds stay.

- [ ] **Step 1: Repoint the measurement**

Rewrite `test/test_road_width.gd` to measure `res://assets/art/forest/road_05.png`, the north-south straight, as the longest contiguous run per row of pixels nearer the road palette than the surround palette — a single hardcoded dirt RGB with a tolerance does not survive this art, which is painted and textured rather than flat. Take the median run across the rows, convert with Task 8's crop in the divisor, and keep both bounds. Keep `test_min_tower_spacing_was_not_disturbed` exactly as it is.

`test_path_half_width_is_the_value_the_spec_amendment_names` hardcodes 14.0 and has to move to the new value with everything else — it is the test that pins the constant against a careless sweep, so it stays, holding the new number.

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

### Task 10: Retire the Kenney art

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

`test_asset_import.gd` gated `mipmaps/generate=true` on `assets/kenney/**`, and its own docstring ends "Do not delete this gate." **Re-home it onto the illustrated art rather than dropping it** — losing it is exactly how the mipmap defect happened last time, and it has already happened again: every `.import` sidecar written for `assets/art/**` and `assets/towers.png` currently says `mipmaps/generate=false`, so `MapRenderer`'s mipmap filter has been reading a chain nobody generated and silently falling back to the base level ever since Task 1.

- [ ] **Step 3: Generate the mipmaps that are actually wanted, and only those**

The re-homed gate is not a blanket sweep over `assets/art/**`. Which files want a chain follows from how hard each is minified and whether it is region-sampled, both measured:

| Asset | Source → drawn | Minification | Chain? |
|---|---|---|---|
| props (`<biome>/{tree,stone,spike,fire}.png`) | up to 96 × 61 → 48 box | up to 1.83× | **yes** |
| endpoints (`castle.png`, `cave.png`) | ~220² → 144 box | ~1.49× | **yes** |
| enemy variants (`enemies/<kind>/variant_N.png`) | up to 105 × 47 → 28–58 tall | 1.3–1.6× | **yes** |
| ground and road tiles | 66 → 54 region → 48 cell | 1.125× | **no** |
| `assets/towers.png` | region-sampled atlas | — | **no** |

The tiles are excluded for two reasons, and either alone would be enough. They are barely minified — Task 8 crops the card border, so 54 source pixels land in 48. And they are **region-sampled**: Task 8 set `region_enabled` on every tile sprite, and a mip level averages across the region's boundary, which for these tiles means averaging the card's dark border back into the terrain — reintroducing by hand the seam Task 8 exists to remove. `assets/towers.png` is excluded for the same region-sampling reason and its exclusion was already load-bearing; carry `test_asset_import.gd`'s paragraph on it across verbatim.

So, in `game/map_renderer.gd`, `_place_tile`'s filter drops from `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` to `TEXTURE_FILTER_LINEAR`, with a comment saying why the tile path differs from `_place`'s. `_place` keeps the mipmap filter — that is the prop and endpoint path, and those do get a chain.

Set `mipmaps/generate=true` in the `.import` sidecars for the three included groups, re-run `godot --headless --import`, and `git checkout -- project.godot`. Then write `test/test_art_import.gd` to pin exactly that split: every included file has `mipmaps/generate=true`, every excluded one has `false`. A gate that only checks the `true` side lets a later sweep turn the tiles on and nothing would catch it.

- [ ] **Step 4: Run the suite**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. The check count drops with the deleted files and rises with the re-homed gate; report the new number.

- [ ] **Step 5: Credit and document**

Update `README.md`'s art section and `CONTINUE.md` §0 to describe the illustrated sheet, where it is vendored, and that `tools/bake_sheet.gd` regenerates everything. Record the two facts a future reader needs: the road is an **edge** mask (not the corner mask the previous art used), and the sheet has no alpha so extraction keys a background colour.

- [ ] **Step 6: Screenshot all three biomes and a wave**

Run the game, capture the forest map, then re-render under `&"ice"` and `&"desert"` at runtime through the Godot MCP rather than editing `Maps.DEFS`:

```gdscript
var board = get_tree().current_scene.get_node("GameBoard")
board.get_node("MapRenderer").render(board._tiles, null, &"ice")
```

Check each for: road pieces meeting without visible mismatch at corners and junctions, no leftover navy fringing on any sprite, towers reading clearly against the ground, and the tile grid reading as intended rather than as a defect. Then start a wave and confirm enemies show visible variety and die with a visible fade rather than vanishing.

- [ ] **Step 7: Commit**

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
