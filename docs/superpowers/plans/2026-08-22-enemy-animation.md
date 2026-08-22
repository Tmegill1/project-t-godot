# Enemy Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enemies walk and die on drawn animation frames instead of on synthesised motion, and the per-spawn variant system that stood in for animation is removed.

**Architecture:** A second sheet at `reference/illustrated-sheet/walk-and-death.png` holds five creatures each drawn as eight walk frames and four death frames. `tools/bake_sheet.gd` gains a pass that cuts them to `assets/art/enemies/<kind>/walk_N.png` and `death_N.png`, replacing `variant_N.png`. `game/enemy.gd` selects a walk frame by **distance travelled** — the same principle the synthesised stride already used, so the cycle still speeds up with the enemy and stops when it stops — and plays the death frames in place of the fade-and-shrink tween.

**Tech Stack:** Godot 4.7.1.stable, GDScript, the project's own `TestCase`/`run_tests.gd` harness.

**Why the variants go.** The previous sheet's enemy rows were *variants* — fifteen different goblins, measured and confirmed twice — so per-spawn variety was the only thing that art could offer. This sheet is the opposite: one goblin that walks. The owner chose animation over variety knowingly. Nothing is left half-wired: `variant_count` and the variant picker go with the files.

## Global Constraints

- Godot 4.7.1.stable. Run the suite with `godot --headless --quit --script test/run_tests.gd` from the repo root.
- Every task ends on a green suite. Baseline at the start of this plan: **7306 checks across 37 files, 0 failing**.
- A green run in this project is deliberately noisy — it emits `push_error` from refusal paths under test. Judge pass/fail from the final summary line, not stderr.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. A test recording zero assertions fails the run.
- Prefer flat `test_*` bodies; where a helper is unavoidable, assert on its result.
- Asset-gate tests read committed PNG bytes via `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`, never the imported `Texture2D`.
- `data/` and `sim/` must contain no engine calls; `test/test_sim_purity.gd` enforces this recursively.
- **The test harness never enters the scene tree.** `test/test_enemy.gd`'s header explains why at length. Anything needing a live tree needs a guard, as `Enemy._die` already has.
- After baking: `godot --headless --import`, then `git checkout -- project.godot`.
- **Nothing outside `assets/art/enemies/` may change under `assets/`.** The ground tiles, road pieces, tower atlas, props and endpoints must all come out byte-identical on a re-bake.
- Stage `.uid` sidecars alongside any new `.gd` file.

## The sheet, measured

**`reference/` is git-ignored**, by the same convention the first sheet follows — neither is tracked, and only the baked PNGs are committed. So the bake cannot be re-run from a fresh clone without the sheet being put back by hand. That is pre-existing and out of scope here; it is worth knowing before you go looking for the file in git.

`reference/illustrated-sheet/walk-and-death.png`, 1683 × 935, background `(6.5, 21.5, 30.0)` — **close to but not the same as the first sheet's `(9, 22, 28)`, so it needs its own constant rather than reusing `BACKGROUND`.**

Five creature bands, each a name label above a sprite band:

| Creature | Sprite band y | Frames found |
|---|---|---|
| Goblin | 78–164 | 12 |
| Goblin Shaman | 242–351 | 12 |
| Troll | 425–532 | 12 |
| Ogre | 593–710 | 12 |
| Bat | 789–881 | 12, one broken |

**Frames 0–7 are the walk cycle and 8–11 are the death sequence**, uniformly across all five rows — verified by rendering every frame of every row and looking at them. The death sequences read correctly as progressions: the goblin goes standing → staggering with the sword dropping → collapsed on its knees → flat.

**Segmentation is gap-based with one split rule.** Goblin and Shaman separate cleanly into twelve. Troll, Ogre and Bat each have one pair of frames whose art touches, producing eleven runs; a run wider than 1.5× the row's median is split at its sparsest interior column, searched between 30% and 70% of its width so the cut never lands at an edge. That recovers the twelfth frame in every case, checked by eye.

**The Bat's frame 7 is broken art and must be dropped.** It is an orphaned wing with no body — the generator produced a wing on its own. It is caught automatically rather than by index: its opaque area is under 55% of its row's median, and no other frame in any row comes close to that threshold. So the Bat has a **seven-frame** walk cycle; every other creature has eight. A seven-frame cycle animates perfectly well, and hard-coding "drop index 7" would silently drop a good frame if the sheet is ever regenerated.

**Kind mapping is unchanged from the previous swap**, by stat profile: `slime` → Goblin, `ogre` → Ogre, `bee` → Bat. Shaman and Troll go to `assets/art/enemies/_unused/` for the deferred enemy-variety feature and are referenced by no code.

---

### Task 1: Cut the walk and death frames

**Files:**
- Modify: `tools/bake_sheet.gd`
- Create: `assets/art/enemies/<kind>/walk_N.png`, `assets/art/enemies/<kind>/death_N.png`
- Delete: `assets/art/enemies/<kind>/variant_N.png`
- Test: `test/test_enemy_sprites.gd`

**Interfaces:**
- Consumes: `_trim` from the existing bake tool.
- Produces: `res://assets/art/enemies/<kind>/walk_0.png` … and `death_0.png` … for `slime`, `ogre`, `bee`, plus `_unused/shaman` and `_unused/troll`.

**The existing `_key` cannot be reused as-is.** It keys against `BACKGROUND`, which is the *first* sheet's `(9, 22, 28)`. This sheet's is `(6.5, 21.5, 30.0)`. Pass the background in rather than adding a second hard-coded constant to a function that already has one.

**Everything the old enemy bake did is replaced, not extended.** `ENEMY_ROWS`, `ENEMY_X0`/`X1`, `MIN_SPRITE_RUN`, `MAX_SPAN_RATIO`, `_row_sprites` and `_bake_enemies` all served the variant extraction from the first sheet. `_row_sprites` is used **only** by `_bake_enemies` — confirm that with a grep before deleting it — and `MAX_SPAN_RATIO`'s over-wide rejection is the opposite of what this sheet needs, which splits over-wide runs rather than dropping them.

- [ ] **Step 1: Write the failing test**

Replace `test/test_enemy_sprites.gd`:

```gdscript
extends TestCase

# One walk cycle and one death sequence per enemy kind, cut from
# reference/illustrated-sheet/walk-and-death.png.
#
# This replaced a per-spawn variant system. The first sheet's enemy rows were
# fifteen different goblins rather than one goblin walking - measured twice,
# once by frame-lag autocorrelation and once by registering consecutive
# sprites on the head and finding the head moved MORE than the legs - so
# variety was all that art could offer. This sheet is the other way round.
#
# The bat's walk cycle is SEVEN frames where every other kind has eight. Its
# eighth frame is an orphaned wing with no body, which the bake drops on area
# rather than on index: hard-coding "skip frame 7" would silently discard a
# good frame if the sheet were regenerated.

const _KINDS := ["slime", "ogre", "bee"]
const _EXPECTED_WALK := {"slime": 8, "ogre": 8, "bee": 7}
const _EXPECTED_DEATH := {"slime": 4, "ogre": 4, "bee": 4}
const _MARGIN_ALPHA_MAX := 8

func _frame(kind: String, action: String, index: int) -> Image:
	var bytes := FileAccess.get_file_as_bytes(
		"res://assets/art/enemies/%s/%s_%d.png" % [kind, action, index])
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return img

func _count(kind: String, action: String) -> int:
	var n := 0
	while FileAccess.file_exists(
			"res://assets/art/enemies/%s/%s_%d.png" % [kind, action, n]):
		n += 1
	return n

func test_every_kind_ships_the_frames_its_row_yields() -> bool:
	for kind in _KINDS:
		assert_eq(_count(kind, "walk"), int(_EXPECTED_WALK[kind]),
			"%s ships %d walk frames" % [kind, int(_EXPECTED_WALK[kind])])
		assert_eq(_count(kind, "death"), int(_EXPECTED_DEATH[kind]),
			"%s ships %d death frames" % [kind, int(_EXPECTED_DEATH[kind])])
	return true

func test_the_variant_files_are_gone() -> bool:
	# Not merely unused - removed. A variant left on disk beside a walk cycle
	# is the next reader's wrong turn.
	for kind in _KINDS:
		assert_false(FileAccess.file_exists(
			"res://assets/art/enemies/%s/variant_0.png" % kind),
			"%s ships no variants any more" % kind)
	return true

func test_every_frame_is_free_standing_with_a_clear_margin() -> bool:
	for kind in _KINDS:
		for action in ["walk", "death"]:
			for i in _count(kind, action):
				var img := _frame(kind, action, i)
				assert_true(img != null, "%s/%s_%d decodes" % [kind, action, i])
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
					"%s/%s_%d edge peak %d" % [kind, action, i, peak])
	return true

func test_no_frame_is_a_fragment_of_another() -> bool:
	# The gate for the bat's orphaned wing, and for any future frame the
	# generator drops a body out of. A fragment is free-standing and cleanly
	# trimmed, so nothing else here can see it - only its area gives it away.
	for kind in _KINDS:
		for action in ["walk", "death"]:
			var areas := []
			for i in _count(kind, action):
				var img := _frame(kind, action, i)
				assert_true(img != null, "%s/%s_%d decodes" % [kind, action, i])
				if img == null:
					continue
				var opaque := 0
				for y in img.get_height():
					for x in img.get_width():
						if img.get_pixel(x, y).a > 8.0 / 255.0:
							opaque += 1
				areas.append(opaque)
			assert_true(not areas.is_empty(), "%s has %s frames" % [kind, action])
			if areas.is_empty():
				continue
			var largest := 0
			for a in areas:
				largest = maxi(largest, int(a))
			for i in areas.size():
				assert_true(float(areas[i]) >= float(largest) * 0.45,
					"%s/%s_%d covers %d against the sequence's %d - a fragment would not"
						% [kind, action, i, int(areas[i]), largest])
	return true

func test_consecutive_walk_frames_differ() -> bool:
	# A cycle that wrote the same crop N times would pass everything above.
	for kind in _KINDS:
		for i in _count(kind, "walk") - 1:
			var a := _frame(kind, "walk", i)
			var b := _frame(kind, "walk", i + 1)
			assert_true(a != null and b != null,
				"%s walk %d and %d decode" % [kind, i, i + 1])
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
			assert_true(differs, "%s walk frames %d and %d differ" % [kind, i, i + 1])
	return true

func test_the_death_sequence_ends_lower_than_it_starts() -> bool:
	# Every one of these creatures falls over. The last death frame is drawn
	# flat, so it is markedly wider than tall relative to the first - which is
	# the cheapest true statement about a death animation, and enough to catch
	# a sequence baked in reverse or one that never left its feet.
	for kind in _KINDS:
		var n := _count(kind, "death")
		assert_true(n >= 2, "%s has a death sequence to compare" % kind)
		if n < 2:
			continue
		var first := _frame(kind, "death", 0)
		var last := _frame(kind, "death", n - 1)
		assert_true(first != null and last != null, "%s death frames decode" % kind)
		if first == null or last == null:
			continue
		var first_ratio := float(first.get_width()) / float(first.get_height())
		var last_ratio := float(last.get_width()) / float(last.get_height())
		assert_true(last_ratio > first_ratio,
			"%s ends its death flatter than it started (%.2f against %.2f)"
				% [kind, last_ratio, first_ratio])
	return true
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — no `walk_*.png` or `death_*.png` exists, and `variant_0.png` still does.

- [ ] **Step 3: Replace the enemy bake**

In `tools/bake_sheet.gd`, delete `ENEMY_ROWS`, `ENEMY_X0`, `ENEMY_X1`, `MIN_SPRITE_RUN`, `MAX_SPAN_RATIO`, `_row_sprites` and `_bake_enemies`. Grep first to confirm `_row_sprites` has no other caller — it should not, since the decor column is segmented by connected components.

`_key` takes the background as a parameter rather than reading the constant, and its existing call sites pass `BACKGROUND`:

```gdscript
## Clears every pixel within KEY_TOLERANCE_SQ of `background` to transparent.
##
## The background is a parameter because the project vendors two sheets and
## they do not agree: the first is (9, 22, 28) and the walk-and-death sheet is
## (6.5, 21.5, 30.0). Close enough to look identical and far enough apart that
## keying one with the other's value leaves a halo.
func _key(img: Image, background: Vector3) -> Image:
```

Then:

```gdscript
const WALK_SHEET := "res://reference/illustrated-sheet/walk-and-death.png"
const WALK_BACKGROUND := Vector3(6.5, 21.5, 30.0)

## kind -> the sprite band its frames are cut from. MEASURED: each creature is
## a name label above a band of twelve frames, and the bands do not touch.
##
## Frames 0-7 are the walk cycle and 8-11 the death sequence, uniformly across
## all five rows - checked by rendering every frame of every row.
const WALK_ROWS := {
	&"slime": {"y0": 78, "y1": 164},
	&"ogre": {"y0": 593, "y1": 710},
	&"bee": {"y0": 789, "y1": 881},
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
		widths.append(r.y - r.x + 1)
	widths.sort()
	var median: float = float(widths[widths.size() / 2])

	# Split a run holding two touching frames at its sparsest interior column,
	# searched between 30% and 70% of its width so the cut cannot land on an
	# edge and shave a sliver off instead of dividing the pair.
	var split := []
	for r in runs:
		var width := r.y - r.x + 1
		if float(width) <= median * WALK_SPLIT_RATIO:
			split.append(r)
			continue
		var best := -1
		var best_count := 1 << 30
		for k in range(int(width * 0.30), int(width * 0.70)):
			var count := 0
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
		var frame := Image.create_empty(r.y - r.x + 1, y1 - y0 + 1, false, Image.FORMAT_RGBA8)
		frame.blit_rect(sheet, Rect2i(r.x, y0, r.y - r.x + 1, y1 - y0 + 1), Vector2i.ZERO)
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
	var out := []
	for i in cut.size():
		if float(areas[i]) >= float(largest) * WALK_MIN_AREA_RATIO:
			out.append(cut[i])
	return out

func _bake_walk_frames() -> void:
	var sheet := Image.new()
	if sheet.load(WALK_SHEET) != OK:
		push_error("cannot load %s" % WALK_SHEET)
		return
	for kind in WALK_ROWS:
		var row: Dictionary = WALK_ROWS[kind]
		var dir := "res://assets/art/enemies/%s" % kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var frames := _walk_row_frames(sheet, int(row["y0"]), int(row["y1"]))
		var walk := 0
		var death := 0
		for i in frames.size():
			# Index against the row as cut, so a dropped broken frame shortens
			# the cycle it belonged to rather than shifting the death sequence
			# up into the walk.
			if i < WALK_FRAMES - (0 if frames.size() >= 12 else 1):
				(frames[i] as Image).save_png("%s/walk_%d.png" % [dir, walk])
				walk += 1
			else:
				(frames[i] as Image).save_png("%s/death_%d.png" % [dir, death])
				death += 1
		print("bake_sheet: %s %d walk, %d death" % [kind, walk, death])
```

Call it from `_init` in place of `_bake_enemies(sheet)`, and delete the old `variant_*.png` files with `git rm`.

- [ ] **Step 4: Run the bake, import, and test**

```bash
godot --headless --script tools/bake_sheet.gd
godot --headless --import
git checkout -- project.godot
godot --headless --quit --script test/run_tests.gd
```

Expected: the bake prints 8 walk / 4 death for slime, ogre, shaman and troll, and **7 walk / 4 death for bee**. Confirm nothing outside `assets/art/enemies/` changed: `git status --porcelain -- assets` must show only that directory and `assets/towers.png` must not appear.

- [ ] **Step 5: Look at the frames**

Contact-sheet every walk and death frame of every kind, in order, composited over an opaque background rather than by dropping alpha. Confirm each walk cycle is one creature with its legs moving, each death sequence is a progression that ends flat, and no frame is a fragment.

- [ ] **Step 6: Commit**

```bash
git add tools/bake_sheet.gd assets/art/enemies test/test_enemy_sprites.gd
git commit -m "Cut the walk and death frames, and retire the variants"
```

---

### Task 2: Play them

**Files:**
- Modify: `game/enemy.gd`
- Modify: `data/enemies.gd`
- Test: `test/test_enemy.gd`
- Test: `test/test_data_tables.gd`

**Interfaces:**
- Consumes: the frames from Task 1.
- Produces: `Enemy.walk_frame() -> int`, `Enemies.walk_frames(kind) -> int`, `Enemies.death_frames(kind) -> int`.

**What goes.** `variant_count` and the variant picker in `setup`. `BOB_FRACTION`, `SQUASH_FRACTION`, `LEAN_RADIANS` and `_apply_stride` — the artist drew all three into the frames, and synthesised motion on top of drawn motion fights it. `stride_phase()` goes with them; `_travelled` stays, because it is what indexes the cycle.

**What stays, and why it matters.** The cycle is still driven by **distance travelled**, not elapsed time. That was the fix that made the synthesised stride read as running rather than sliding, and it is just as necessary with real frames: a timed cycle would make a 60px/s ogre's legs move at the same rate as a 150px/s bat's, and would keep both walking on the spot while stopped. `stride_px` keeps its meaning — the distance covered by one full cycle.

**Death plays frames and then frees.** `_die` currently tweens scale and alpha. It now steps the death frames over `DEATH_TWEEN_MS` and frees at the end. Everything the sim observes — `sim["dying"]`, `sim["alive"]`, the `died` signal, the hidden health bar — must still happen before any of that, and the off-tree guard stays: the harness builds every enemy outside the scene tree.

- [ ] **Step 1: Write the failing tests**

In `test/test_enemy.gd`, delete the tests covering `stride_phase`, the squash, the lean and the variant choice, and add:

```gdscript
func test_the_walk_frame_advances_with_distance_not_with_time() -> bool:
	# The property the synthesised stride was rewritten for, kept now that the
	# frames are real. A timed cycle would move a 60px/s ogre's legs at the
	# same rate as a 150px/s bat's.
	var slow := _ready_enemy()
	slow.setup(&"ogre", _straight_path(), 1)
	var fast := _ready_enemy()
	fast.setup(&"bee", _straight_path(), 1)
	assert_true(Enemies.DEFS[&"bee"]["base_speed"] > Enemies.DEFS[&"ogre"]["base_speed"],
		"precondition: the bat is faster than the ogre")

	var slow_seen := {}
	var fast_seen := {}
	for i in 12:
		slow._physics_process(0.05)
		fast._physics_process(0.05)
		slow_seen[slow.walk_frame()] = true
		fast_seen[fast.walk_frame()] = true

	assert_true(fast_seen.size() > slow_seen.size(),
		"over the same time the faster enemy shows more of its cycle (%d frames against %d)"
			% [fast_seen.size(), slow_seen.size()])
	slow.free()
	fast.free()
	return true

func test_a_stationary_enemy_holds_its_frame() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	for i in 4:
		e._physics_process(0.05)
	var held := e.walk_frame()
	e.sim["speed"] = 0.0
	for i in 20:
		e._physics_process(0.05)
	assert_eq(e.walk_frame(), held, "a stopped enemy does not walk on the spot")
	e.free()
	return true

func test_the_walk_frame_wraps_and_never_leaves_the_cycle() -> bool:
	for kind in Enemies.KINDS:
		var e := _ready_enemy()
		e.setup(kind, _long_path(), 1)
		var n := Enemies.walk_frames(kind)
		var seen := {}
		for i in 200:
			e._physics_process(0.05)
			var f := e.walk_frame()
			assert_true(f >= 0 and f < n,
				"%s frame %d is inside its %d-frame cycle" % [kind, f, n])
			seen[f] = true
		assert_eq(seen.size(), n, "%s reaches every one of its %d frames" % [kind, n])
		e.free()
	return true

func test_the_sprite_shows_the_frame_the_cycle_names() -> bool:
	var e := _ready_enemy()
	e.setup(&"slime", _long_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	for i in 30:
		e._physics_process(0.05)
		assert_true(sprite.texture.resource_path.ends_with(
			"walk_%d.png" % e.walk_frame()),
			"the sprite draws walk_%d" % e.walk_frame())
	e.free()
	return true

func test_the_bat_has_a_shorter_cycle_than_the_others() -> bool:
	# Its eighth frame is broken art the bake drops. Pinned here so a
	# regenerated sheet that fixes it shows up as a failing number rather than
	# as nothing.
	assert_eq(Enemies.walk_frames(&"bee"), 7, "the bat walks on seven frames")
	assert_eq(Enemies.walk_frames(&"slime"), 8, "the goblin walks on eight")
	assert_eq(Enemies.walk_frames(&"ogre"), 8, "the ogre walks on eight")
	return true

func test_the_declared_frame_counts_match_what_was_baked() -> bool:
	for kind in Enemies.KINDS:
		var walk := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/walk_%d.png" % [kind, walk]):
			walk += 1
		var death := 0
		while FileAccess.file_exists(
				"res://assets/art/enemies/%s/death_%d.png" % [kind, death]):
			death += 1
		assert_eq(Enemies.walk_frames(kind), walk, "%s declares its walk frames" % kind)
		assert_eq(Enemies.death_frames(kind), death, "%s declares its death frames" % kind)
	return true

func test_a_lethal_hit_off_the_tree_still_pays_and_hides_the_bar() -> bool:
	# Unchanged from the tween era and must stay so: every enemy this suite
	# builds is outside the scene tree, and the sim's view of a kill must not
	# depend on the presentation reaching its end.
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

`_long_path()` is a new helper: a path long enough that an enemy can cover several cycles without reaching the goal — `PackedVector2Array([Vector2(0, 0), Vector2(4000, 0)])` will do.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `walk_frame`, `Enemies.walk_frames` and `Enemies.death_frames` do not exist.

- [ ] **Step 3: Rewrite the data table**

In `data/enemies.gd`, replace `variant_count` with `walk_frames` and `death_frames` — slime 8/4, ogre 8/4, bee 7/4 — keep `sprite_px`, `stride_px` and `flip_horizontally`, and add the accessors:

```gdscript
## How many frames each animation holds. Baked by tools/bake_sheet.gd and
## pinned by test_enemy.gd against the files on disk.
##
## The bat's walk is SEVEN where the others are eight: its eighth frame came
## off the sheet as an orphaned wing with no body, and the bake drops broken
## art on area rather than on index.
static func walk_frames(kind: StringName) -> int:
	return int(DEFS[kind]["walk_frames"])

static func death_frames(kind: StringName) -> int:
	return int(DEFS[kind]["death_frames"])
```

Update `test/test_data_tables.gd`'s cosmetic-field table to match.

- [ ] **Step 4: Play the frames**

In `game/enemy.gd`, delete `BOB_FRACTION`, `SQUASH_FRACTION`, `LEAN_RADIANS`, `stride_phase` and `_apply_stride`. Keep `_travelled`, `_base_scale`, `apply_sprite_height` and `set_facing_from_travel`. Then:

```gdscript
## Which frame of the walk cycle the enemy is showing.
##
## Indexed by DISTANCE TRAVELLED, not by elapsed time. This was the fix that
## made the synthesised stride read as running rather than sliding, and real
## frames need it just as much: a timed cycle moves a 60px/s ogre's legs at
## the same rate as a 150px/s bat's, and keeps both walking on the spot while
## they are held up. stride_px is the distance one full cycle covers.
func walk_frame() -> int:
	var n := Enemies.walk_frames(kind)
	var cycles := _travelled / float(Enemies.DEFS[kind]["stride_px"])
	return int(floor(cycles * float(n))) % n
```

In `setup`, load the first walk frame instead of picking a variant, and drop the `rng` parameter's variant use — **keep the parameter**, since `GameBoard` passes it and a later feature may want it again; give it a comment saying so, or remove it from both sides. Say which you chose in your report.

In `_physics_process`, after `_travelled` accumulates, set the texture from `walk_frame()`.

Rewrite `_die` to step the death frames:

```gdscript
func _die(source: Dictionary) -> void:
	sim["dying"] = true
	sim["alive"] = false
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
	_health_bar.visible = false
	if not is_inside_tree():
		return
	var n := Enemies.death_frames(kind)
	var step := DEATH_TWEEN_MS / 1000.0 / float(n)
	for i in n:
		_sprite.texture = load("res://assets/art/enemies/%s/death_%d.png" % [kind, i])
		apply_sprite_height()
		await get_tree().create_timer(step).timeout
	queue_free()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 6: Watch a wave**

Run the game and watch one, at 1x and at the faster speed. Confirm each kind's legs move at a rate that suits its speed, that a slowed enemy visibly slows its cycle, and that a killed enemy plays a death sequence and disappears rather than snapping away. `DEATH_TWEEN_MS` is 250 and was tuned for a fade — say whether four drawn frames need longer.

- [ ] **Step 7: Commit**

```bash
git add game/enemy.gd data/enemies.gd test/test_enemy.gd test/test_data_tables.gd
git commit -m "Play the drawn walk and death frames"
```
