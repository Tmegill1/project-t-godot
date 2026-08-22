# Board Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The board reads as dimensional — props, towers and enemies overlap by position instead of by fixed layer, and every object is anchored to the ground by a shadow.

**Architecture:** Ground stays on its own layer below everything. Props, endpoints, towers and enemies move to a shared layer and their containers enable Y-sorting, so what is lower on screen draws in front. Props re-anchor to their base so a tall tree sorts by where it stands rather than where its canopy is — which moves the geometry `sim/placement.gd` derives its collision from, so that is pinned by a parity gate rather than trusted.

**Tech Stack:** Godot 4.7.1.stable, GDScript, the project's own `TestCase`/`run_tests.gd` harness, `tools/bake_kenney.gd` for the shadow asset.

**Spec:** `docs/superpowers/specs/2026-08-20-turret-depth-and-targeting-design.md` (package C)

**This is plan 2 of 2, and it stacks.** `docs/superpowers/plans/2026-08-20-turret-tracking-and-targeting.md` delivers packages A and B and must be complete first — Task 3 here puts shadows under towers, which assumes the split base/turret sprites that plan produces. Execute plan 1 alone to leave the graphics as they are; execute both, in order, to add depth.

## Global Constraints

- Godot 4.7.1.stable. Run the suite with `godot --headless --quit --script test/run_tests.gd` from the repo root.
- After adding assets, run `godot --headless --import`, then `git checkout -- project.godot` — the reimport writes a stray blank line under `[autoload]` that must never be committed.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. A test recording zero assertions fails the run. See `test/case.gd`.
- Prefer flat `test_*` bodies over helper delegation; where a helper is unavoidable, assert on its result.
- Every task ends on a green suite. Baseline at the start of this plan is whatever plan 1 finished on; record it before Task 1 and never let a task reduce it.
- A green run is deliberately noisy — it emits `push_error` from refusal paths under test. Judge pass/fail from the final summary line, not stderr.
- `data/` and `sim/` must contain no engine calls; `test/test_sim_purity.gd` enforces this.
- **`sim/placement.gd` is not edited by this plan.** Its contract is kept true by the parity gate in Task 1, not by changing the rule.
- Enemy art, map layouts and map progression stay out of scope.

---

### Task 1: Anchor props to their base without moving their collision

**Files:**
- Modify: `game/map_renderer.gd` (`_place_prop`, `prop_footprints`)
- Test: `test/test_map_renderer.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: prop sprites whose `position` is their **base centre-left** rather than their top-left; `prop_footprints()` returns identical values to before.

**Why this has to happen.** Godot Y-sorts by a node's `position.y`. Props are placed with `centered = false`, so `position` is the sprite's top-left — sorting on that makes a tall tree sort as though it stood where its canopy is, which is wrong in the direction that looks worst: tall props would sort behind things they should occlude.

**Why it is dangerous.** `MapRenderer.prop_footprints()` derives each blocking circle from `sprite.position`, and `sim/placement.gd` refuses tower placement against those circles. Moving the anchor moves the collision geometry unless `prop_footprints` is corrected to match. This is the third time on this codebase that art and collision have turned out to share a coupling — untrimmed prop footprints and the road-width corridor were the first two — so it is pinned rather than trusted.

**This task inverts the usual TDD order, deliberately.** The test is a *characterization* test: it asserts the footprints the renderer produces **today**, so it passes before the change and must still pass after. There is no red phase, and manufacturing one would mean asserting something false. Write it, watch it pass, make the change, watch it still pass.

The expected values below were measured off the current committed renderer.

- [ ] **Step 1: Write the characterization test**

Add to `test/test_map_renderer.gd`:

```gdscript
# --------------------------------------------------------------------------
# Collision parity across the Y-sort anchoring change.
#
# prop_footprints() derives its blocking circles from sprite.position, and
# sim/placement.gd refuses tower placement against them. Re-anchoring props to
# their base for Y-sorting moves those positions unless prop_footprints is
# corrected to match, and a silent shift would move where towers may be built
# without any other test noticing.
#
# These values were measured off the renderer BEFORE the anchoring change.
# They are expected to be identical after it. If one of these goes red, the
# anchoring and the footprint arithmetic have drifted apart - fix the
# arithmetic, never the expected values.
func test_prop_footprints_are_unchanged_by_the_sort_anchoring() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var footprints := renderer.prop_footprints()

	assert_eq(footprints.size(), 45, "the demo map scatters 45 props")

	# Every prop is fitted into one 48px tile, so every radius is half of it.
	for entry in footprints:
		var f: Dictionary = entry
		assert_almost_eq(f["radius"], 24.0, 0.001, "every footprint radius is 24")

	# An aggregate rather than 45 literals: any single prop moving in any
	# direction moves this sum, and it stays readable.
	var sum := Vector2.ZERO
	for entry in footprints:
		sum += entry["pos"]
	assert_almost_eq(sum.x, 24744.0, 0.5, "the summed footprint x is unchanged")
	assert_almost_eq(sum.y, 17208.0, 0.5, "the summed footprint y is unchanged")

	renderer.free()
	return true

func test_a_prop_sprite_sorts_by_its_base_not_its_canopy() -> bool:
	# The property the anchoring exists for: a prop's position.y - the value
	# Godot Y-sorts on - must be the bottom of its drawn art, not the top.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var checked := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or not child.texture.resource_path.contains("/forest/"):
			continue
		var sprite: Sprite2D = child
		if sprite.texture.resource_path.contains("blend_"):
			continue
		var drawn_top := sprite.position.y + sprite.offset.y * sprite.scale.y
		var drawn_bottom := drawn_top + float(sprite.texture.get_height()) * sprite.scale.y
		assert_almost_eq(sprite.position.y, drawn_bottom, 0.001,
			"the sort key is the base of the drawn art")
		checked += 1
	assert_true(checked > 0, "prop sprites were checked")
	renderer.free()
	return true
```

- [ ] **Step 2: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: `test_prop_footprints_are_unchanged_by_the_sort_anchoring` **PASSES** — it describes today's behaviour. `test_a_prop_sprite_sorts_by_its_base_not_its_canopy` **FAILS**, because `position.y` is currently the top of the art and `offset` is zero.

If the parity test fails at this step, stop: the measured values no longer match the renderer, and the change must not proceed on a baseline nobody understands.

- [ ] **Step 3: Re-anchor the props**

In `game/map_renderer.gd`, extend `_place_prop` to move the sprite's origin to its base after `_place` has positioned it:

```gdscript
## Places a prop and records it as one, so prop_footprints can find it.
##
## The sprite is then re-anchored so its `position` is the BASE of the drawn
## art rather than its top-left. Godot Y-sorts on position.y, and sorting a
## tall prop by its top-left would sort it as though it stood where its canopy
## is - behind things it should occlude. `offset` pulls the drawing back up so
## nothing moves on screen; only the origin does.
##
## prop_footprints() reads these positions, so it compensates for the same
## shift. test_prop_footprints_are_unchanged_by_the_sort_anchoring is what
## keeps the two in step.
func _place_prop(slot: StringName, col: int, row: int) -> Sprite2D:
	var texture: Texture2D = load(Biomes.prop_path(_biome, slot))
	var sprite := _place(texture, col, row, Tiles.TILE_SIZE, _Z_OVERLAY)
	var source_height := float(texture.get_height())
	sprite.position.y += source_height * sprite.scale.y
	sprite.offset.y = -source_height
	_prop_sprites[sprite] = true
	return sprite
```

Then correct `prop_footprints`. Only the `pos` line changes — the radius arithmetic and the doc comment about over-covering stay exactly as they are:

```gdscript
		var display := Vector2(tex.get_width(), tex.get_height()) * sprite.scale
		out.append({
			# position is now the base of the drawn art (see _place_prop), so
			# the centre is half a width right and half a height UP from it.
			"pos": sprite.position + Vector2(display.x / 2.0, -display.y / 2.0),
			"radius": maxf(display.x, display.y) / 2.0,
		})
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS — both new tests, and every existing scatter test unchanged. The parity test passing after the change is the whole point of this task.

- [ ] **Step 5: Commit**

```bash
git add game/map_renderer.gd test/test_map_renderer.gd
git commit -m "Anchor props to their base for sorting, holding collision still"
```

---

### Task 2: Sort the board by position

**Files:**
- Modify: `game/map_renderer.gd` (`_Z_OVERLAY`)
- Modify: `game/game_board.tscn`
- Test: `test/test_map_renderer.gd`
- Test: `test/test_game_board.gd`

**Interfaces:**
- Consumes: base-anchored props from Task 1.
- Produces: props and endpoints at `z_index == 0`; `MapRenderer`, `$Towers` and `$Enemies` all Y-sorting.

**The current layering, measured rather than assumed:** only `map_renderer.gd` sets a z-index in code — ground at −1 and props/endpoints at +1. `$Towers` and `$Enemies` have none, so they sit at the default 0. The consequence is that **props currently draw above both towers and enemies**: a tree covers a tower standing beside it, whatever their positions.

The fix is to bring props down to 0 with towers and enemies, and let position decide. Ground stays at −1, below everything, unsorted — its half-tile lattice is unaffected.

**Ten places in `test_map_renderer.gd` reference z-index, and they are selectors rather than assertions** — `if child.z_index == 1` is how those tests pick props out of the renderer's children. They become `== 0`. Ground's `== -1` selectors are untouched, and since `$Towers` and `$Enemies` are not children of `MapRenderer`, a `== 0` selector inside it still uniquely means "a prop or endpoint."

**This task carries the spec's verification gate.** §6.2 records that nested Y-sort interleaving was probed and only partially confirmed: the API exists on this build, but draw order is a rendering-server detail and is not observable from the scene tree. Step 5 is where that gets settled by looking.

- [ ] **Step 1: Write the failing tests**

In `test/test_map_renderer.gd`, change every `z_index == 1` selector to `z_index == 0` and every `z_index != -1` guard as needed, then add:

```gdscript
func test_props_and_ground_sit_on_their_intended_layers() -> bool:
	# Ground stays below everything and never sorts. Props join towers and
	# enemies on layer 0 so position decides, instead of a tree covering a
	# tower merely for being a tree.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var ground := 0
	var overlay := 0
	for child in renderer.get_children():
		if not (child is Sprite2D):
			continue
		if child.z_index == -1:
			ground += 1
		elif child.z_index == 0:
			overlay += 1
		else:
			assert_true(false, "a sprite landed on an unexpected layer %d" % child.z_index)
	assert_true(ground > 0, "the ground layer was drawn")
	assert_true(overlay > 0, "props and endpoints were drawn on layer 0")
	renderer.free()
	return true

func test_the_renderer_sorts_its_children_by_position() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	assert_true(renderer.is_y_sort_enabled(), "the renderer Y-sorts")
	renderer.free()
	return true
```

Add to `test/test_game_board.gd`:

```gdscript
func test_the_board_and_its_object_containers_all_y_sort() -> bool:
	# Interleaving across containers only happens if the parent sorts AND each
	# child container sorts. One of them left off silently reverts that
	# container to drawing as one opaque block.
	var board := _board_with_tower()
	assert_true(board.is_y_sort_enabled(), "the board sorts")
	assert_true((board.get_node("MapRenderer") as Node2D).is_y_sort_enabled(),
		"the map renderer sorts")
	assert_true((board.get_node("Towers") as Node2D).is_y_sort_enabled(),
		"towers sort")
	assert_true((board.get_node("Enemies") as Node2D).is_y_sort_enabled(),
		"enemies sort")
	board.free()
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — props are still on layer 1, and nothing has Y-sorting enabled.

- [ ] **Step 3: Move props to layer 0**

In `game/map_renderer.gd`, change the constant and rewrite its comment:

```gdscript
## z-index ordering. Ground draws below everything on its own layer and never
## sorts. Props and endpoints share layer 0 with towers and enemies so that
## POSITION decides what covers what - before this they sat on layer 1 and a
## tree covered a tower standing beside it whatever their positions were.
const _Z_GROUND := -1
const _Z_OVERLAY := 0
```

- [ ] **Step 4: Enable sorting**

In `game/game_board.tscn`, add `y_sort_enabled = true` to `GameBoard`, `MapRenderer`, `Towers` and `Enemies`:

```
[node name="GameBoard" type="Node2D"]
y_sort_enabled = true
script = ExtResource("1_board")

[node name="MapRenderer" type="Node2D" parent="."]
y_sort_enabled = true
script = ExtResource("2_map")

[node name="Towers" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Enemies" type="Node2D" parent="."]
y_sort_enabled = true
```

Leave `Projectiles`, `PlacementPreview` and `PreviewRange` alone — projectiles are in flight above the board, and the preview is a UI affordance that should always be visible.

- [ ] **Step 5: Verify the interleaving in the running game — THE GATE**

This is the step the spec flagged. Draw order cannot be asserted from the scene tree, so it is confirmed by looking.

```bash
godot --path .
```

Place a tower directly **below** a tree (larger y) and another directly **above** one (smaller y). Start a wave and watch enemies walk past props.

Expected: the tower below the tree draws **in front** of it; the tower above draws **behind** it. Enemies pass behind props as they approach and in front as they leave.

**If props, towers and enemies do not interleave** — if each container still draws as one block, so every tower is in front of every prop or every prop in front of every tower — then nested Y-sort containers do not merge on this build. Stop and report it. The fallback is reparenting props, towers and enemies under one Y-sorted node, which is a larger change to `game_board.tscn` and to how the board finds its children, and it needs its own task rather than being improvised here.

Record what you saw in your report either way.

- [ ] **Step 6: Run the suite**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add game/map_renderer.gd game/game_board.tscn test/test_map_renderer.gd test/test_game_board.gd
git commit -m "Sort props, towers and enemies by position instead of by layer"
```

---

### Task 3: Shadows

**Files:**
- Modify: `tools/bake_kenney.gd`
- Create: `assets/shadow.png`
- Modify: `game/map_renderer.gd` (`_place_prop`)
- Modify: `game/tower.gd`
- Modify: `game/enemy.gd`
- Test: `test/test_shadows.gd`

**Interfaces:**
- Consumes: base-anchored props from Task 1, the sorted board from Task 2.
- Produces: `assets/shadow.png` (128×64, soft black ellipse); every prop, tower and enemy owns a child `Sprite2D` named `Shadow`.

**A shadow is a child of the thing that casts it**, not a sibling in a shadow layer. A sibling would sort on its own `y` and could separate from its owner; a child inherits the owner's transform and moves with it. Each shadow carries `z_index = -1` with the default relative z, so it draws just beneath its owner, and because z-index outranks Y-sorting every shadow lands on one layer under all the sorted content — which is what a shadow layer should do.

Ground sits at −1 too, but shadows still draw over it: within a z-layer, order follows the tree, and every shadow's owner is added after the ground sprites.

**Enemies get one too.** Shadows under scenery but not under moving units make the units look pasted on.

- [ ] **Step 1: Write the failing test**

Create `test/test_shadows.gd`:

```gdscript
extends TestCase

# Shadows are what anchor an object to the ground once the board sorts by
# position - without them a Y-sorted sprite reads as floating past its
# neighbours rather than standing among them.
#
# Each shadow is a CHILD of its caster rather than a sibling in a shadow
# layer. A sibling would sort on its own y and could drift away from what it
# belongs to; a child inherits the caster's transform. z_index -1 with the
# default relative z puts every shadow on one layer beneath the sorted
# content, because z-index outranks Y-sorting.

const _SHADOW := "res://assets/shadow.png"

func test_the_shadow_asset_is_a_soft_dark_ellipse() -> bool:
	var bytes := FileAccess.get_file_as_bytes(_SHADOW)
	assert_false(bytes.is_empty(), "shadow.png exists")
	if bytes.is_empty():
		return true
	var img := Image.new()
	assert_eq(img.load_png_from_buffer(bytes), OK, "shadow.png decodes")
	assert_eq(img.get_width(), 128, "128 wide")
	assert_eq(img.get_height(), 64, "64 tall - an ellipse, not a circle")
	# Opaque-ish in the middle, fully transparent at the corners.
	assert_true(img.get_pixel(64, 32).a > 0.2, "the centre is visible")
	assert_eq(img.get_pixel(0, 0).a, 0.0, "the corners are clear")
	return true

func test_every_prop_casts_a_shadow_beneath_itself() -> bool:
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	var props := 0
	for child in renderer.get_children():
		if not (child is Sprite2D) or child.z_index != 0:
			continue
		var path: String = child.texture.resource_path
		if path.ends_with("castle.png") or path.ends_with("cave.png"):
			continue
		var shadow := child.get_node_or_null("Shadow")
		assert_true(shadow != null, "%s casts a shadow" % path.get_file())
		if shadow == null:
			continue
		assert_eq((shadow as Sprite2D).z_index, -1, "the shadow draws beneath its caster")
		props += 1
	assert_true(props > 0, "props were checked")
	renderer.free()
	return true

func test_the_shadow_does_not_sort_away_from_its_caster() -> bool:
	# A shadow parented as a SIBLING would sort on its own y and could
	# separate from the object it belongs to. Being a child is the guarantee.
	var renderer := MapRenderer.new()
	var tiles := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	renderer.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED), &"forest")
	for child in renderer.get_children():
		var shadow := child.get_node_or_null("Shadow") if child is Sprite2D else null
		if shadow == null:
			continue
		assert_eq(shadow.get_parent(), child, "the shadow is a child of its caster")
	renderer.free()
	return true
```

Add to `test/test_tower.gd`:

```gdscript
func test_a_tower_casts_a_shadow_under_its_base() -> bool:
	var tower := _placed_tower(&"basic")
	var shadow := tower.get_node_or_null("Shadow")
	assert_true(shadow != null, "the tower casts a shadow")
	if shadow == null:
		tower.free()
		return true
	assert_eq((shadow as Sprite2D).z_index, -1, "it draws beneath the tower")
	tower.free()
	return true
```

Add to `test/test_enemy.gd`:

```gdscript
func test_an_enemy_casts_a_shadow() -> bool:
	# Scenery with shadows and units without makes the units look pasted on.
	var e := _ready_enemy()
	var shadow := e.get_node_or_null("Shadow")
	assert_true(shadow != null, "the enemy casts a shadow")
	if shadow == null:
		e.free()
		return true
	assert_eq((shadow as Sprite2D).z_index, -1, "it draws beneath the enemy")
	e.free()
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `assets/shadow.png` does not exist and no object has a `Shadow` child.

- [ ] **Step 3: Bake the shadow**

Add to `tools/bake_kenney.gd`:

```gdscript
# One soft ellipse, scaled per caster. A silhouette matched to each sprite
# would read as heavier than this flat vector art supports, and would need a
# blur pass the tool has no reason to grow.
const SHADOW_W := 128
const SHADOW_H := 64
const SHADOW_ALPHA := 0.38

func _bake_shadow() -> void:
	var img := Image.create_empty(SHADOW_W, SHADOW_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rx := float(SHADOW_W) / 2.0
	var ry := float(SHADOW_H) / 2.0
	for y in SHADOW_H:
		for x in SHADOW_W:
			var nx := (float(x) + 0.5 - rx) / rx
			var ny := (float(y) + 0.5 - ry) / ry
			var d := sqrt(nx * nx + ny * ny)
			if d >= 1.0:
				continue
			# Falls off toward the rim rather than ending in a hard edge.
			img.set_pixel(x, y, Color(0, 0, 0, SHADOW_ALPHA * (1.0 - d * d)))
	img.save_png("res://assets/shadow.png")
```

Call it from `_init` after the tower atlases.

- [ ] **Step 4: Run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
git status
```

Expected: `assets/shadow.png` exists. Nothing else under `assets/` may show as modified.

- [ ] **Step 5: Attach shadows**

Add a shared helper. Put it in `game/map_renderer.gd` as a static so all three callers use one implementation:

```gdscript
const SHADOW_TEXTURE := preload("res://assets/shadow.png")

## Adds a shadow beneath `caster`, sized to `width_px` and sitting at
## `base_offset` in the caster's local space.
##
## A child rather than a sibling: a sibling would sort on its own y and could
## drift away from what it belongs to. z_index -1 with the default relative z
## puts it just under its caster, and since z-index outranks Y-sorting every
## shadow lands on one layer beneath the sorted content.
static func attach_shadow(caster: Node2D, width_px: float, base_offset: Vector2) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.name = "Shadow"
	shadow.texture = SHADOW_TEXTURE
	shadow.centered = true
	shadow.z_index = -1
	shadow.scale = Vector2.ONE * (width_px / float(SHADOW_TEXTURE.get_width()))
	shadow.position = base_offset
	caster.add_child(shadow)
	return shadow
```

In `_place_prop`, after the re-anchoring from Task 1 and before recording the sprite:

```gdscript
	# The sprite's origin is its base, so the shadow sits at the origin,
	# centred on the prop's width.
	var drawn_width := float(texture.get_width()) * sprite.scale.x
	MapRenderer.attach_shadow(sprite, drawn_width * 0.8,
		Vector2(drawn_width / 2.0, 0.0))
```

In `game/tower.gd`'s `setup`, after the sprites are scaled:

```gdscript
	MapRenderer.attach_shadow(self, target_px * 0.85, Vector2(0.0, target_px * 0.32))
```

In `game/enemy.gd`, at the end of the function that sizes the sprite:

```gdscript
	MapRenderer.attach_shadow(self, 26.0 * float(def["sprite_scale"]), Vector2(0.0, 14.0))
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add tools/bake_kenney.gd assets/shadow.png assets/shadow.png.import \
        game/map_renderer.gd game/tower.gd game/enemy.gd \
        test/test_shadows.gd test/test_tower.gd test/test_enemy.gd
git commit -m "Anchor every object to the ground with a shadow"
```

---

### Task 4: Look at it, and write down what changed

**Files:**
- Modify: `CONTINUE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: no code.

- [ ] **Step 1: Screenshot all three biomes**

Run the game and capture the forest map. Then, through the Godot MCP, re-render the board under `&"ice"` and `&"desert"` at runtime rather than editing `Maps.DEFS`:

```gdscript
var board = get_tree().current_scene.get_node("GameBoard")
board.get_node("MapRenderer").render(board._tiles, null, &"ice")
```

That leaves no temporary edit in the tree.

Check each capture for: shadows sitting under props rather than beside them, props overlapping correctly with towers by position, no seam or gap introduced at the ground layer, and shadows not doubling up where props are dense.

- [ ] **Step 2: Watch an enemy pass a prop**

Start a wave and watch a single enemy walk the length of the road past several props. It must pass **behind** props above it and **in front** of props below it, with the transition happening as it crosses. This is the property the whole plan exists for and no assertion covers it.

- [ ] **Step 3: Confirm the tower shadow does not fight the turret**

With plan 1's rotation in place, a tower's shadow is a child of the tower while the turret rotates independently. Confirm the shadow stays put while the turret tracks — a shadow that rotates with the turret would be a sign it was attached to the wrong node.

- [ ] **Step 4: Update CONTINUE.md**

Update §0 to describe what shipped, refresh the suite count, and record two things a future reader needs:

- Props are anchored at their **base**, not their top-left, and `prop_footprints()` compensates for that. The two must move together, and `test_prop_footprints_are_unchanged_by_the_sort_anchoring` is what keeps them in step.
- Ground is the only thing on its own z-layer. Everything else shares layer 0 and sorts by position, so adding a new drawable means choosing its layer deliberately rather than picking a number.

Also note in §9 whether the HUD contrast issue recorded during the art swap has become worse, better or unchanged now that shadows have darkened the board.

- [ ] **Step 5: Commit**

```bash
git add CONTINUE.md
git commit -m "Record the depth work in the orientation document"
```

---

## Notes for the executor

**The one gate.** Task 2 Step 5 is not a formality. Nested Y-sort interleaving was probed before this plan was written and could only be partially confirmed — the API exists, but draw order is not observable from the scene tree. If containers do not interleave, stop and report rather than improvising; the fallback reparents props, towers and enemies under a single sorted node and deserves its own task.

**The one trap.** Task 1 inverts TDD on purpose. Its parity test passes before the change and must still pass after — it is a characterization test, and there is no red phase to manufacture. If someone "fixes" it by editing the expected values to match new behaviour, the collision geometry has silently moved and `sim/placement.gd` is now refusing towers in different places than it did. Fix the arithmetic, never the numbers.

**Measured baseline for that gate:** the demo map under the forest biome produces **45** prop footprints, every radius **24.0**, summed positions **(24744.0, 17208.0)**.
