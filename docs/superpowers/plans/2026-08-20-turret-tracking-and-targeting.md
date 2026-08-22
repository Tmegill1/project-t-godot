# Turret Tracking and Targeting Priorities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turrets rotate to track what they are shooting, upgrades change a tower visibly along two channels, and the player picks each tower's targeting priority.

**Architecture:** The tower sprite splits into a fixed `Base` and a rotating `Turret`, fed by two new atlases baked at the geometry the existing one already uses, so `Tower.frame_region` and the build panel need no change. The base keeps reading total investment; the turret carries kind, branch and tier band. Targeting priorities are already implemented and tested in `sim/targeting.gd` — this plan adds one scorer and the wiring that has never existed.

**Tech Stack:** Godot 4.7.1.stable, GDScript, the project's own `TestCase`/`run_tests.gd` harness, `tools/bake_kenney.gd` for asset composition.

**Spec:** `docs/superpowers/specs/2026-08-20-turret-depth-and-targeting-design.md`

> **STATUS, 2026-08-22.** Tasks 1 to 3 — the targeting priorities and the
> control that picks them — are **live and unexecuted**, and are what to run
> if you are here for the targeting selector. Tasks 4 to 7 are **dead**: they
> bake base and turret atlases with `tools/bake_kenney.gd`, which the
> illustrated art swap deleted along with the Kenney pack they read from.
> Turret rotation is still wanted and still unbuilt; it needs re-planning
> against `tools/bake_sheet.gd` and the illustrated sheet, whose towers are
> drawn as single pieces rather than as a base plus a separable turret. The
> global constraint below naming `tools/bake_kenney.gd` and the Kenney tile
> indices applies only to those dead tasks.

**This is plan 1 of 2.** It delivers packages A and B and is complete on its own — the game is playable and better at the end of it. `docs/superpowers/plans/2026-08-20-board-depth.md` delivers package C (shadows and Y-sorting) and stacks on top of this one. Execute this plan alone to leave the graphics as they are; execute both, in order, to add depth.

## Global Constraints

- Godot 4.7.1.stable. Run the suite with `godot --headless --quit --script test/run_tests.gd` from the repo root.
- `class_name` does not resolve until `godot --headless --import` has run once. After adding assets or a new `class_name`, run `godot --headless --import`, then `git checkout -- project.godot` — the reimport writes a stray blank line under `[autoload]` that must never be committed.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. A test recording zero assertions fails the run, as does a suite file with zero test methods. See `test/case.gd`.
- Prefer flat `test_*` bodies over helper delegation; where a helper is unavoidable, assert on its result.
- Asset-gate tests read committed PNG bytes via `FileAccess.get_file_as_bytes` + `Image.load_png_from_buffer`, never the imported `Texture2D`. Renderer tests compare `Texture2D.resource_path`.
- Every task ends on a green suite. Baseline at the start of this plan: **6688 checks across 36 files, 0 failing**.
- A green run in this project is deliberately noisy — it emits `push_error` from refusal paths under test. Judge pass/fail from the final summary line, not stderr.
- `data/` and `sim/` must contain no engine calls; `test/test_sim_purity.gd` enforces this recursively over both directories. Anything that needs `load()` belongs in `game/`.
- Tile indices are individual-PNG indices (`towerDefense_tileNNN.png`) under `reference/kenney-td/PNG/Retina/`. The tilesheet packs 70 of 299 tiles in a different order — never cross-check an index against it.
- Atlas geometry is fixed: 5 columns × 96px frames, 20 frames, 480×384, row-major. All three tower atlases share it so `Tower.frame_region` serves them all.
- `assets/towers.png`, `sprite_frame`, `upgrade_frames`, `Tower.frame_region`, `UpgradesSim.sprite_frame_for` and `ui/tower_panel.gd` are NOT changed by this plan.
- `sim/placement.gd`, enemy art, map layouts and map progression are out of scope.

---

### Task 1: Add the `weakest` targeting priority

**Files:**
- Modify: `sim/targeting.gd`
- Test: `test/test_targeting.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Targeting.PRIORITIES` becomes `[&"first", &"last", &"strongest", &"weakest", &"closest"]`; `Targeting.LABELS` gains `&"weakest"` and relabels `&"strongest"`.

**Insertion position is load-bearing.** Put `weakest` immediately after `strongest`, not at the end. `test_next_priority_cycles` asserts `next_priority(&"first") == &"last"` and `next_priority(&"closest") == &"first"`; with `weakest` third-from-last both still hold, so **no existing test changes**. Appending it would break the wrap assertion and force an edit that looks like a weakened test. The design doc's §5.1 predicted those tests would need updating — this ordering makes that unnecessary.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_targeting.gd`:

```gdscript
func test_weakest_prefers_the_lowest_health_enemy() -> bool:
	var tower := {"position": Vector2.ZERO, "range": 500.0,
		"priority": &"weakest", "detection": false}
	var candidates := [
		{"id": 1, "position": Vector2(10, 0), "health": 9, "path_index": 5,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(20, 0), "health": 2, "path_index": 3,
			"alive": true, "dying": false},
		{"id": 3, "position": Vector2(30, 0), "health": 7, "path_index": 9,
			"alive": true, "dying": false},
	]
	var picked = Targeting.select(tower, candidates)
	assert_true(picked != null, "something was picked")
	if picked == null:
		return true
	assert_eq(int(picked["id"]), 2, "the 2-health enemy is chosen over 7 and 9")
	return true

func test_weakest_is_the_exact_inverse_of_strongest() -> bool:
	# Guards a sign error: a scorer returning +health for weakest would still
	# pick "a" target and still pass a single-case test.
	var candidates := [
		{"id": 1, "position": Vector2(10, 0), "health": 4, "path_index": 1,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(10, 0), "health": 11, "path_index": 1,
			"alive": true, "dying": false},
	]
	var weak := Targeting.select({"position": Vector2.ZERO, "range": 500.0,
		"priority": &"weakest", "detection": false}, candidates)
	var strong := Targeting.select({"position": Vector2.ZERO, "range": 500.0,
		"priority": &"strongest", "detection": false}, candidates)
	assert_true(weak != null and strong != null, "both picked a target")
	if weak == null or strong == null:
		return true
	assert_eq(int(weak["id"]), 1, "weakest takes the 4-health enemy")
	assert_eq(int(strong["id"]), 2, "strongest takes the 11-health enemy")
	return true

func test_weakest_still_respects_range_and_the_phasing_gate() -> bool:
	# The new scorer must not bypass is_targetable: a low-health enemy out of
	# range, or phased against a tower without detection, is not a target.
	var tower := {"position": Vector2.ZERO, "range": 50.0,
		"priority": &"weakest", "detection": false}
	var candidates := [
		{"id": 1, "position": Vector2(500, 0), "health": 1, "path_index": 1,
			"alive": true, "dying": false},
		{"id": 2, "position": Vector2(10, 0), "health": 3, "path_index": 1,
			"alive": true, "dying": false, "phased": true},
		{"id": 3, "position": Vector2(20, 0), "health": 8, "path_index": 1,
			"alive": true, "dying": false},
	]
	var picked = Targeting.select(tower, candidates)
	assert_true(picked != null, "something in range was picked")
	if picked == null:
		return true
	assert_eq(int(picked["id"]), 3, "the far 1-health and phased 3-health are both ineligible")
	return true

func test_the_priority_list_pairs_the_two_health_scorers() -> bool:
	# Ordering is load-bearing: next_priority() cycles this array, and the two
	# existing cycle tests only keep passing while `closest` stays last.
	assert_eq(Targeting.PRIORITIES.size(), 5, "five priorities")
	assert_eq(Targeting.PRIORITIES[Targeting.PRIORITIES.size() - 1], &"closest",
		"closest stays last so the wrap assertion holds")
	var strongest_at := Targeting.PRIORITIES.find(&"strongest")
	assert_eq(Targeting.PRIORITIES[strongest_at + 1], &"weakest",
		"weakest sits directly after strongest")
	return true

func test_every_priority_has_a_label() -> bool:
	for priority in Targeting.PRIORITIES:
		var label: String = Targeting.LABELS.get(priority, "")
		assert_false(label.is_empty(), "%s has a label" % priority)
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `weakest` is not in `PRIORITIES`, has no label, and falls through `_score_for`'s `_` default to the closest scorer, so `test_weakest_prefers_the_lowest_health_enemy` picks id 1 rather than id 2.

- [ ] **Step 3: Add the priority**

In `sim/targeting.gd`, update the three tables and the scorer:

```gdscript
## `weakest` sits directly after `strongest` rather than at the end. The two
## health scorers read as a pair there, and it keeps `closest` last, which is
## what lets next_priority()'s existing wrap test keep passing unchanged.
const PRIORITIES: Array[StringName] = [&"first", &"last", &"strongest", &"weakest", &"closest"]
```

```gdscript
const LABELS := {
	&"first": "First", &"last": "Last",
	&"strongest": "Highest Health", &"weakest": "Lowest Health",
	&"closest": "Closest",
}
```

In `_score_for`, add the branch beside `strongest`:

```gdscript
		&"strongest":
			return float(candidate["health"])
		&"weakest":
			return -float(candidate["health"])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS. Confirm `test_next_priority_cycles` and `test_next_priority_cycles_through_all_and_returns_to_start` are still green **without having been edited** — if either needed a change, the insertion position is wrong.

- [ ] **Step 5: Commit**

```bash
git add sim/targeting.gd test/test_targeting.gd
git commit -m "Add the weakest targeting priority beside strongest"
```

---

### Task 2: Make a tower's priority settable

**Files:**
- Modify: `game/tower.gd`
- Modify: `game/game_board.gd`
- Test: `test/test_tower.gd`
- Test: `test/test_game_board.gd`

**Interfaces:**
- Consumes: `Targeting.PRIORITIES` from Task 1.
- Produces: `Tower.set_priority(priority: StringName) -> void`, `Tower.get_priority() -> StringName`, and `GameBoard.cycle_selected_tower_priority() -> void`.

`Tower._priority` has existed since the tower was written and has never been assigned. This task is the assignment.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_tower.gd`:

```gdscript
func test_a_new_tower_starts_on_the_default_priority() -> bool:
	var tower := _setup_tower(&"basic")
	assert_eq(tower.get_priority(), Targeting.DEFAULT_PRIORITY,
		"a fresh tower uses the default priority")
	tower.free()
	return true

func test_set_priority_changes_what_targeting_is_asked_for() -> bool:
	# to_targeting_dict is the only path the priority reaches the rules by, so
	# setting the field without it reaching the dict would be invisible.
	var tower := _setup_tower(&"basic")
	tower.set_priority(&"weakest")
	assert_eq(tower.get_priority(), &"weakest", "the getter reports the new value")
	assert_eq(tower.to_targeting_dict()["priority"], &"weakest",
		"the targeting dict carries it to the rules")
	tower.free()
	return true

func test_priority_survives_an_upgrade() -> bool:
	# apply_upgrade rebuilds stats and visuals; a naive implementation that
	# re-ran setup would silently reset the player's choice.
	var tower := _setup_tower(&"basic")
	tower.set_priority(&"first")
	tower.apply_upgrade(&"sustained")
	assert_eq(tower.get_priority(), &"first", "the choice survives buying a tier")
	tower.free()
	return true
```

`_setup_tower(kind)` is this file's existing helper — it calls `Grid.set_active`, instantiates the scene, fires `NOTIFICATION_READY` and runs `setup`.

Add to `test/test_game_board.gd`:

```gdscript
func test_cycling_priority_advances_the_selected_tower() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var before := tower.get_priority()
	b.cycle_selected_tower_priority()
	assert_eq(tower.get_priority(), Targeting.next_priority(before),
		"the board advances the tower one step through the cycle")
	b.free()
	return true

func test_cycling_priority_with_nothing_selected_is_a_no_op() -> bool:
	# The inspector is hidden with no selection, but the board must not crash
	# if the call arrives anyway - every other board mutator guards this.
	var b := _ready_board()
	b.cycle_selected_tower_priority()
	assert_eq(b.get_gold(), Maps.get_def(Maps.FIRST)["starting_gold"],
		"a fresh board with nothing selected was left untouched")
	b.free()
	return true
```

`_ready_board()` and `_place_and_select(board, kind)` are this file's existing helpers; `_place_and_select` returns the board's currently selected tower.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `set_priority`, `get_priority` and `cycle_selected_tower_priority` do not exist, so the scripts fail to parse with "Invalid call" / "Identifier not declared".

- [ ] **Step 3: Add the accessors**

In `game/tower.gd`, beside `get_stats`:

```gdscript
## The player's target-selection choice for this tower.
##
## Deliberately per-tower rather than global: which enemy to shoot is a
## positional decision, and the tower covering the entrance wants a different
## answer from the one guarding the exit. Survives upgrades - apply_upgrade
## rebuilds stats and visuals but never touches this.
func set_priority(priority: StringName) -> void:
	_priority = priority

func get_priority() -> StringName:
	return _priority
```

In `game/game_board.gd`, beside `upgrade_selected_tower`:

```gdscript
## Advances the selected tower one step through Targeting.PRIORITIES.
##
## The inspector calls this rather than reaching into the tower, matching how
## upgrades and selling already work: the board owns what happens to a
## selected tower, and the panel only asks.
func cycle_selected_tower_priority() -> void:
	if _selected_tower == null:
		return
	_selected_tower.set_priority(Targeting.next_priority(_selected_tower.get_priority()))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add game/tower.gd game/game_board.gd test/test_tower.gd test/test_game_board.gd
git commit -m "Let a tower's targeting priority be set and cycled"
```

---

### Task 3: The inspector's priority control

**Files:**
- Modify: `ui/tower_inspector.gd`
- Test: `test/test_tower_inspector.gd`

**Interfaces:**
- Consumes: `GameBoard.cycle_selected_tower_priority` and `Tower.get_priority` from Task 2, `Targeting.LABELS` from Task 1.
- Produces: `TowerInspector.priority_row() -> Button`, matching the existing `sell_row()` accessor so tests can reach it without touching privates.

**Two constraints from the file itself, both the result of bugs already paid for:**

The rows are **built once in `_build_rows` and rewritten in place**. Nothing may free a node after `_ready`. `ui/tower_inspector.gd:11-19` records why: Godot locks an object while it is emitting a signal and refuses to free it, so an earlier rebuild-on-change version bought a tier and then left the panel showing the tier it had just bought.

The sidebar is **140px wide** and a `Label` reports its longest line as its minimum width, so a wide child pushes the whole column over the map — it grew 37px out before that was measured. This is why the control is **one cycling button**, not five buttons and not a dropdown. It is also what `Targeting.next_priority()` was written for and has never been used by.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_tower_inspector.gd`:

```gdscript
func test_the_priority_row_shows_the_selected_tower_s_priority() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	t.set_priority(&"first")
	i.show_tower(t)
	assert_eq(i.priority_row().text, "Target: First", "the row names the current priority")

	t.set_priority(&"weakest")
	i.show_tower(t)
	assert_eq(i.priority_row().text, "Target: Lowest Health", "and follows it when it changes")
	i.free(); b.free()
	return true

func test_pressing_the_priority_row_cycles_and_relabels() -> bool:
	# The press has to reach the tower through the board AND come back as new
	# text without the row being rebuilt - this panel may not free a node
	# after _ready(), which is what the rebuild-on-change version got wrong.
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _place_and_select(b, &"basic")
	t.set_priority(&"first")
	i.show_tower(t)

	i.priority_row().pressed.emit()

	assert_eq(t.get_priority(), &"last", "the press advanced the tower")
	assert_eq(i.priority_row().text, "Target: Last", "and the row relabelled itself")
	i.free(); b.free()
	return true

func test_the_priority_row_meets_the_tap_target_minimum() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))
	assert_eq(i.priority_row().custom_minimum_size, TowerInspector.MIN_TAP_SIZE,
		"the priority row is as tappable as every other row")
	i.free(); b.free()
	return true

func test_the_priority_row_clips_rather_than_widening_the_panel() -> bool:
	# The 140px sidebar once grew 37px out over the map because a child
	# reported a wider minimum. "Lowest Health" is the longest label.
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))
	assert_true(i.priority_row().clip_text, "the row clips its text like the branch rows do")
	i.free(); b.free()
	return true
```

`_ready_inspector()`, `_ready_board()`, `_ready_tower_on(board)` and `_place_and_select(board, kind)` are this file's existing helpers. `_place_and_select` is used where the press must reach a *selected* tower, since `cycle_selected_tower_priority` acts on the board's selection.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `priority_row()` does not exist, so the suite reports a parse failure for `test_tower_inspector.gd`.

- [ ] **Step 3: Add the row**

In `ui/tower_inspector.gd`, add the field beside `_sell`:

```gdscript
var _priority: Button = null
```

In `_build_rows`, add the button after the branch rows and before Sell, so the order reads as upgrades, then how to aim, then how to leave:

```gdscript
	# One cycling button rather than one per priority. Five side-by-side
	# controls would report a minimum width the 140px sidebar cannot hold -
	# the failure this panel's header documents - and Targeting.next_priority
	# already exists for exactly this control.
	_priority = Button.new()
	_priority.custom_minimum_size = MIN_TAP_SIZE
	_priority.clip_text = true
	_priority.pressed.connect(_on_priority_pressed)
	_rows_root.add_child(_priority)
```

Add the accessor beside `sell_row`:

```gdscript
func priority_row() -> Button:
	return _priority
```

In `_refresh`, set its text beside the Sell row's:

```gdscript
	_priority.text = "Target: %s" % Targeting.LABELS[_tower.get_priority()]
```

Add the handler beside `_on_sell_pressed`:

```gdscript
## Asks the board to cycle, then re-reads the tower. The panel never advances
## the priority itself - the board owns what happens to a selected tower.
func _on_priority_pressed() -> void:
	_board.cycle_selected_tower_priority()
	_refresh()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 5: Verify the panel did not widen**

Run the game and select a tower:

```bash
godot --path .
```

Confirm the sidebar still ends where the map ends and the new row reads `Target: Closest`. Press it and watch it advance. Close the game. This is a two-minute check that no assertion covers — the panel-width failure this row's comment describes was found by eye, not by a test.

- [ ] **Step 6: Commit**

```bash
git add ui/tower_inspector.gd test/test_tower_inspector.gd
git commit -m "Expose targeting priority as a cycling row in the inspector"
```

---

### Task 4: Bake the base and turret atlases

**Files:**
- Modify: `tools/bake_kenney.gd`
- Create: `assets/tower_bases.png`, `assets/tower_turrets.png`
- Test: `test/test_tower_atlas.gd`

**Interfaces:**
- Consumes: the existing `ATLAS_FRAMES`, `_bake_tower_atlas` and `tiles` cache in `tools/bake_kenney.gd`.
- Produces: `res://assets/tower_bases.png` and `res://assets/tower_turrets.png`, both 480×384, 5 columns × 96px frames, row-major.

**`tower_bases.png` is the existing composite minus its turret** — frame N holds the base plate that frame N currently draws under its turret. No new mapping, and `UpgradesSim.sprite_frame_for` keeps selecting it unchanged.

**`tower_turrets.png` is composed, not cut.** The pack ships no separable turret heads: tiles 203–206, 249 and 250 carry integrated plates that visibly spin past the base when rotated, and 245–248 are rotationally ambiguous. Only the bare rockets pivot cleanly. Heads are therefore built from tile **251** at a size set by tower kind, a count or size set by tier band, and a tint set by branch.

**The turret must encode kind, or kinds stop being distinguishable.** Today each kind has its own four `upgrade_frames`, which is the only thing making a Basic look different from a Mortar. Once the base carries tier alone (shared across kinds) the turret is the sole remaining kind signal, so it carries kind × branch × band = 4 × 2 × 2 = 16 frames.

Frame assignment, row-major in `Towers.KINDS` order (`basic`, `fast`, `mortar`, `long`):

| kind | sustained low / high | burst low / high |
|---|---|---|
| basic | 0 / 1 | 2 / 3 |
| fast | 4 / 5 | 6 / 7 |
| mortar | 8 / 9 | 10 / 11 |
| long | 12 / 13 | 14 / 15 |

Frames 16–19 stay blank.

- [ ] **Step 1: Write the failing test**

Create `test/test_tower_turret_atlas.gd`:

```gdscript
extends TestCase

# Gates for the split tower atlases.
#
# tower_bases.png is the existing composite minus its turret, so it keeps
# being selected by UpgradesSim.sprite_frame_for at the same frame numbers.
#
# tower_turrets.png is COMPOSED rather than cut, because the pack ships no
# separable turret heads: the pieces with integrated plates visibly spin past
# the base when rotated, and the round modules rotate invisibly. Only the bare
# rockets pivot cleanly, so heads are built from tile 251.
#
# The turret carries KIND as well as branch and band. That is not decoration:
# once the base is selected by tier alone it is shared across kinds, so the
# turret is the only thing left that distinguishes a Basic from a Mortar.

const _BASES := "res://assets/tower_bases.png"
const _TURRETS := "res://assets/tower_turrets.png"
const _COLUMNS := 5
const _FRAME := 96
const _TURRET_FRAMES := 16

func _sheet(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
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

func _mean_colour(img: Image, frame: int) -> Vector3:
	var ox := (frame % _COLUMNS) * _FRAME
	var oy := (frame / _COLUMNS) * _FRAME
	var acc := Vector3.ZERO
	var n := 0
	for y in range(0, _FRAME, 2):
		for x in range(0, _FRAME, 2):
			var c := img.get_pixel(ox + x, oy + y)
			if c.a > 0.5:
				acc += Vector3(c.r, c.g, c.b) * 255.0
				n += 1
	return acc / maxf(1.0, float(n))

func test_both_atlases_share_the_geometry_tower_gd_assumes() -> bool:
	for path in [_BASES, _TURRETS]:
		var img := _sheet(path)
		assert_true(img != null, "%s decodes" % path)
		if img == null:
			continue
		assert_eq(img.get_width(), _COLUMNS * _FRAME, "%s is 5 frames wide" % path)
		assert_eq(img.get_height(), 4 * _FRAME, "%s is 4 frames tall" % path)
	return true

func test_every_base_frame_a_tower_kind_names_carries_art() -> bool:
	var img := _sheet(_BASES)
	assert_true(img != null, "tower_bases.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		for frame in Towers.get_def(kind)["upgrade_frames"]:
			assert_true(_opaque_pixels(img, int(frame)) > 0,
				"%s base frame %d carries art" % [kind, int(frame)])
	return true

func test_every_turret_frame_a_kind_names_carries_art() -> bool:
	var img := _sheet(_TURRETS)
	assert_true(img != null, "tower_turrets.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var frames: Dictionary = Towers.get_def(kind)["turret_frames"]
		for branch in frames:
			for frame in frames[branch]:
				assert_true(_opaque_pixels(img, int(frame)) > 0,
					"%s %s turret frame %d carries art" % [kind, branch, int(frame)])
	return true

func test_the_unused_turret_frames_are_blank() -> bool:
	var img := _sheet(_TURRETS)
	assert_true(img != null, "tower_turrets.png decodes")
	if img == null:
		return true
	for frame in range(_TURRET_FRAMES, 20):
		assert_eq(_opaque_pixels(img, frame), 0, "turret frame %d is blank" % frame)
	return true

func test_a_branch_is_readable_from_the_turret_s_colour() -> bool:
	# The whole point of the two-channel look: a Barrage turret and a Marksman
	# turret of the same kind and band must not be the same image.
	for kind in Towers.KINDS:
		var frames: Dictionary = Towers.get_def(kind)["turret_frames"]
		var img := _sheet(_TURRETS)
		assert_true(img != null, "tower_turrets.png decodes")
		if img == null:
			return true
		var warm := _mean_colour(img, int(frames[&"sustained"][1]))
		var cool := _mean_colour(img, int(frames[&"burst"][1]))
		assert_true(warm.x > cool.x,
			"%s: the sustained turret is warmer than the burst one (%v vs %v)" % [kind, warm, cool])
		assert_true(cool.z > warm.z,
			"%s: the burst turret is cooler than the sustained one (%v vs %v)" % [kind, cool, warm])
	return true

func test_a_higher_band_turret_is_visibly_more_than_a_lower_one() -> bool:
	# Barrage gains a second rocket, Marksman's rocket grows. Either way the
	# high band covers more pixels than the low one - which is what makes an
	# upgrade legible at tile size.
	var img := _sheet(_TURRETS)
	assert_true(img != null, "tower_turrets.png decodes")
	if img == null:
		return true
	for kind in Towers.KINDS:
		var frames: Dictionary = Towers.get_def(kind)["turret_frames"]
		for branch in frames:
			var low := _opaque_pixels(img, int(frames[branch][0]))
			var high := _opaque_pixels(img, int(frames[branch][1]))
			assert_true(high > low,
				"%s %s: the high band covers more than the low (%d vs %d)" % [kind, branch, high, low])
	return true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — neither atlas exists, and `Towers.get_def(kind)["turret_frames"]` is not a key yet, so the frame tests fail on a missing dictionary entry. Task 5 adds that key; this task's job is the images.

- [ ] **Step 3: Extend the bake tool**

Add to `tools/bake_kenney.gd`, beside the existing atlas constants:

```gdscript
# The split tower atlases. Both share the existing 5x96 geometry so
# Tower.frame_region serves all three sheets.
#
# tower_bases.png is the existing composite minus its turret - same frame
# numbers, so UpgradesSim.sprite_frame_for keeps selecting it unchanged.
#
# tower_turrets.png is COMPOSED. The pack ships no separable turret heads:
# tiles 203-206, 249 and 250 each carry an integrated plate that visibly spins
# past the base when rotated, and 245-248 are rotationally ambiguous so
# tracking would be invisible. Only the bare rockets pivot cleanly, which is
# why every head here is built from tile 251. Verified by rendering each
# candidate at several angles before this was written - do not "simplify" it
# back to slicing the composite.
const TURRET_SOURCE := 251

## Rocket size per kind, in atlas pixels. The turret is the only thing left
## distinguishing a Basic from a Mortar once the base is selected by tier
## alone, so kind has to be legible here.
const TURRET_KIND_PX := {
	&"basic": 52, &"fast": 44, &"mortar": 64, &"long": 70,
}

## Branch reads as colour, blended against the sprite rather than replacing it
## so the rocket's own shading survives.
const TURRET_TINTS := {
	&"sustained": Color8(214, 88, 74),
	&"burst": Color8(86, 140, 214),
}
const TURRET_TINT_BLEND := 0.55

## Band reads as form, and the form matches what the branch does: Barrage
## gains a second rocket, Marksman's single rocket grows. More shots versus
## bigger shots, straight off the silhouette.
const TURRET_TWIN_OFFSET := 13
const TURRET_BURST_GROWTH := 18

## kind -> branch -> [low band frame, high band frame]. Row-major in
## Towers.KINDS order; frames 16-19 stay blank.
const TURRET_FRAMES := {
	&"basic": {&"sustained": [0, 1], &"burst": [2, 3]},
	&"fast": {&"sustained": [4, 5], &"burst": [6, 7]},
	&"mortar": {&"sustained": [8, 9], &"burst": [10, 11]},
	&"long": {&"sustained": [12, 13], &"burst": [14, 15]},
}
```

Add the compositing helpers:

```gdscript
## Blends `colour` into every opaque pixel, preserving the sprite's own shading.
func _tint(img: Image, colour: Color, amount: float) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			out.set_pixel(x, y, Color(
				lerpf(c.r, colour.r, amount),
				lerpf(c.g, colour.g, amount),
				lerpf(c.b, colour.b, amount), c.a))
	return out

## One turret head, centred in a 96px frame.
func _compose_turret(kind: StringName, branch: StringName, band: int,
		tiles: Dictionary) -> Image:
	var px: int = int(TURRET_KIND_PX[kind])
	var twin := branch == &"sustained" and band == 1
	if branch == &"burst" and band == 1:
		px += TURRET_BURST_GROWTH

	var rocket: Image = tiles[TURRET_SOURCE].duplicate()
	rocket.convert(Image.FORMAT_RGBA8)
	rocket.resize(px, px, Image.INTERPOLATE_LANCZOS)
	rocket = _tint(rocket, TURRET_TINTS[branch], TURRET_TINT_BLEND)

	var frame := Image.create_empty(ATLAS_FRAME, ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	frame.fill(Color(0, 0, 0, 0))
	var centre := (ATLAS_FRAME - px) / 2
	if twin:
		for dx in [-TURRET_TWIN_OFFSET, TURRET_TWIN_OFFSET]:
			frame.blend_rect(rocket, Rect2i(Vector2i.ZERO, rocket.get_size()),
				Vector2i(centre + int(dx), centre))
	else:
		frame.blend_rect(rocket, Rect2i(Vector2i.ZERO, rocket.get_size()),
			Vector2i(centre, centre))
	return frame

func _bake_tower_bases(tiles: Dictionary) -> void:
	var sheet := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for frame in ATLAS_FRAMES:
		var spec: Dictionary = ATLAS_FRAMES[frame]
		var ox: int = (int(frame) % ATLAS_COLUMNS) * ATLAS_FRAME
		var oy: int = (int(frame) / ATLAS_COLUMNS) * ATLAS_FRAME
		var base: Image = tiles[spec["base"]].duplicate()
		base.convert(Image.FORMAT_RGBA8)
		base.resize(ATLAS_BASE_PX, ATLAS_BASE_PX, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i(ox + (ATLAS_FRAME - ATLAS_BASE_PX) / 2,
			oy + (ATLAS_FRAME - ATLAS_BASE_PX) / 2)
		sheet.blend_rect(base, Rect2i(Vector2i.ZERO, base.get_size()), at)
	sheet.save_png("res://assets/tower_bases.png")

func _bake_tower_turrets(tiles: Dictionary) -> void:
	var sheet := Image.create_empty(
		ATLAS_COLUMNS * ATLAS_FRAME, ATLAS_ROWS * ATLAS_FRAME, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for kind in TURRET_FRAMES:
		for branch in TURRET_FRAMES[kind]:
			var frames: Array = TURRET_FRAMES[kind][branch]
			for band in frames.size():
				var frame: int = int(frames[band])
				var head := _compose_turret(kind, branch, band, tiles)
				var ox: int = (frame % ATLAS_COLUMNS) * ATLAS_FRAME
				var oy: int = (frame / ATLAS_COLUMNS) * ATLAS_FRAME
				sheet.blend_rect(head, Rect2i(Vector2i.ZERO, head.get_size()),
					Vector2i(ox, oy))
	sheet.save_png("res://assets/tower_turrets.png")
```

Call both from `_init`, right after the existing `_bake_tower_atlas(tiles)`:

```gdscript
	_bake_tower_bases(tiles)
	_bake_tower_turrets(tiles)
```

- [ ] **Step 4: Run the bake and import**

```bash
godot --headless --script tools/bake_kenney.gd
godot --headless --import
git checkout -- project.godot
git status
```

Expected: `assets/tower_bases.png` and `assets/tower_turrets.png` exist at 480×384. **Nothing under `assets/kenney/` and no other file in `assets/` may show as modified** — the bake regenerates them and they must come out byte-identical. If any does, stop and report it.

- [ ] **Step 5: Set mipmaps off on both new atlases**

Both are region-sampled through `AtlasTexture` and drawn with the default `LINEAR` filter, exactly like `assets/towers.png`. Mip levels would average across frame boundaries and bleed neighbouring frames together. Confirm both `.import` sidecars read `mipmaps/generate=false`, and leave `test/test_asset_import.gd` covering only `assets/kenney/**` as it already does.

- [ ] **Step 6: Run tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: the geometry and blank-frame tests PASS; the three tests that read `turret_frames` still FAIL because `data/towers.gd` has no such key. Task 5 closes that.

- [ ] **Step 7: Commit**

```bash
git add tools/bake_kenney.gd assets/tower_bases.png assets/tower_turrets.png \
        assets/tower_bases.png.import assets/tower_turrets.png.import \
        test/test_tower_turret_atlas.gd
git commit -m "Bake split base and turret atlases at the existing geometry"
```

---

### Task 5: Select the turret frame from kind, branch and tier

**Files:**
- Modify: `data/towers.gd`
- Modify: `sim/upgrades.gd`
- Test: `test/test_upgrades.gd`
- Test: `test/test_data_tables.gd`

**Interfaces:**
- Consumes: the frame assignment from Task 4.
- Produces: `Towers.DEFS[kind]["turret_frames"]` as `{sustained: [low, high], burst: [low, high]}`, and `UpgradesSim.turret_frame_for(kind: StringName, tiers: Dictionary) -> int`.

`visual_tier` and `sprite_frame_for` are unchanged — the base keeps reading total investment. This adds the second channel beside them.

**Band threshold:** a branch is in its high band once it holds **2 or more** tiers on that branch. Tie on equal tier counts goes to `sustained`, which is `Upgrades.BRANCHES[0]`, so the tie-break is stable rather than arbitrary.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_upgrades.gd`:

```gdscript
func test_turret_frame_follows_the_leading_branch() -> bool:
	var sustained_led := {&"sustained": 2, &"burst": 0}
	var burst_led := {&"sustained": 0, &"burst": 2}
	var frames: Dictionary = Towers.get_def(&"basic")["turret_frames"]
	assert_eq(UpgradesSim.turret_frame_for(&"basic", sustained_led),
		int(frames[&"sustained"][1]), "two sustained tiers give the high sustained turret")
	assert_eq(UpgradesSim.turret_frame_for(&"basic", burst_led),
		int(frames[&"burst"][1]), "two burst tiers give the high burst turret")
	return true

func test_turret_frame_uses_the_low_band_below_two_tiers() -> bool:
	var frames: Dictionary = Towers.get_def(&"mortar")["turret_frames"]
	assert_eq(UpgradesSim.turret_frame_for(&"mortar", {&"sustained": 1, &"burst": 0}),
		int(frames[&"sustained"][0]), "one tier is still the low band")
	assert_eq(UpgradesSim.turret_frame_for(&"mortar", UpgradesSim.empty_tiers()),
		int(frames[&"sustained"][0]), "an unupgraded tower shows the low sustained turret")
	return true

func test_an_equal_split_breaks_toward_the_first_branch() -> bool:
	# Stable, not arbitrary: a tie must not depend on dictionary order.
	var frames: Dictionary = Towers.get_def(&"long")["turret_frames"]
	var even := {&"sustained": 2, &"burst": 2}
	assert_eq(UpgradesSim.turret_frame_for(&"long", even),
		int(frames[Upgrades.BRANCHES[0]][1]),
		"an even split shows the first branch's turret")
	return true

func test_each_kind_has_its_own_turret_frames() -> bool:
	# Once the base is chosen by tier alone it is shared across kinds, so the
	# turret is the only thing left telling a Basic from a Mortar. Two kinds
	# sharing a turret frame would make them indistinguishable in play.
	var seen := {}
	for kind in Towers.KINDS:
		var frames: Dictionary = Towers.get_def(kind)["turret_frames"]
		for branch in frames:
			for frame in frames[branch]:
				var n := int(frame)
				assert_false(seen.has(n),
					"turret frame %d is claimed by %s and by %s" % [n, seen.get(n, ""), kind])
				seen[n] = String(kind)
	assert_eq(seen.size(), 16, "sixteen distinct turret frames across four kinds")
	return true
```

Add to `test/test_data_tables.gd`:

```gdscript
func test_every_kind_names_two_bands_per_branch() -> bool:
	for kind in Towers.KINDS:
		var frames: Dictionary = Towers.get_def(kind)["turret_frames"]
		for branch in Upgrades.BRANCHES:
			assert_true(frames.has(branch), "%s names turret frames for %s" % [kind, branch])
			assert_eq((frames[branch] as Array).size(), 2,
				"%s %s has a low and a high band" % [kind, branch])
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `turret_frames` is not a key in `Towers.DEFS`, and `UpgradesSim.turret_frame_for` does not exist.

- [ ] **Step 3: Add the data and the selector**

In `data/towers.gd`, add to each kind's dictionary. The values match Task 4's frame assignment exactly:

```gdscript
		# basic
		"turret_frames": {&"sustained": [0, 1], &"burst": [2, 3]},
		# fast
		"turret_frames": {&"sustained": [4, 5], &"burst": [6, 7]},
		# mortar
		"turret_frames": {&"sustained": [8, 9], &"burst": [10, 11]},
		# long
		"turret_frames": {&"sustained": [12, 13], &"burst": [14, 15]},
```

Add to `sim/upgrades.gd`, beside `sprite_frame_for`:

```gdscript
## A branch counts as "committed" at this many tiers, which switches its
## turret to the high band.
const TURRET_HIGH_BAND_TIERS := 2

## The turret a tower should be showing.
##
## The second of the two visual channels. The base answers "how much is
## invested here" through visual_tier; the turret answers "in what, and how
## far" - which branch leads and whether it is committed. Both are needed:
## once the base is selected by tier alone it is shared across kinds, so the
## turret is also the only thing distinguishing a Basic from a Mortar.
##
## An even split breaks toward BRANCHES[0] so the result never depends on
## dictionary iteration order.
static func turret_frame_for(kind: StringName, tiers: Dictionary) -> int:
	var leading: StringName = Upgrades.BRANCHES[0]
	var best := -1
	for branch in Upgrades.BRANCHES:
		var held := maxi(0, int(tiers.get(branch, 0)))
		if held > best:
			best = held
			leading = branch
	var band := 1 if best >= TURRET_HIGH_BAND_TIERS else 0
	return int(Towers.DEFS[kind]["turret_frames"][leading][band])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, including Task 4's three turret-frame tests which were waiting on this key.

- [ ] **Step 5: Commit**

```bash
git add data/towers.gd sim/upgrades.gd test/test_upgrades.gd test/test_data_tables.gd
git commit -m "Select a turret frame from kind, leading branch and tier band"
```

---

### Task 6: Split the tower scene and draw both sprites

**Files:**
- Modify: `game/tower.tscn`
- Modify: `game/tower.gd`
- Test: `test/test_tower.gd`

**Interfaces:**
- Consumes: the two atlases from Task 4 and `UpgradesSim.turret_frame_for` from Task 5.
- Produces: `Tower` draws `$Base` and `$Turret`; `Tower.turret_sprite() -> Sprite2D` for tests.

The existing `$Sprite` node is renamed `$Base`, and `$Turret` is added after it so it draws on top. `Tower.frame_region` is unchanged and now cuts three sheets.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_tower.gd`:

```gdscript
func test_the_tower_draws_a_base_and_a_turret_from_their_own_sheets() -> bool:
	var tower := _setup_tower(&"basic")
	var base: Sprite2D = tower.get_node("Base")
	var turret: Sprite2D = tower.turret_sprite()
	assert_true(base.texture != null, "the base has a texture")
	assert_true(turret.texture != null, "the turret has a texture")
	assert_eq((base.texture as AtlasTexture).atlas.resource_path,
		"res://assets/tower_bases.png", "the base is cut from the bases sheet")
	assert_eq((turret.texture as AtlasTexture).atlas.resource_path,
		"res://assets/tower_turrets.png", "the turret is cut from the turrets sheet")
	tower.free()
	return true

func test_the_two_sprites_track_their_own_selectors() -> bool:
	# The base follows visual_tier, the turret follows the leading branch.
	# Buying on one branch must move both, and they must not move together.
	var tower := _setup_tower(&"basic")
	var base_before := (tower.get_node("Base").texture as AtlasTexture).region
	var turret_before := (tower.turret_sprite().texture as AtlasTexture).region
	tower.apply_upgrade(&"burst")
	tower.apply_upgrade(&"burst")
	var base_after := (tower.get_node("Base").texture as AtlasTexture).region
	var turret_after := (tower.turret_sprite().texture as AtlasTexture).region
	assert_true(base_before != base_after, "two tiers moved the base")
	assert_true(turret_before != turret_after, "two tiers moved the turret to the burst high band")
	assert_eq(turret_after, Tower.frame_region(
		UpgradesSim.turret_frame_for(tower.kind, tower.tiers)),
		"the turret shows exactly the frame the selector names")
	tower.free()
	return true

func test_a_maxed_barrage_tower_differs_from_a_maxed_marksman_one() -> bool:
	# The legibility feature's whole point, and invisible to every other
	# assertion: both towers resolve stats through the same path and wear the
	# same base frame.
	var barrage := _setup_tower(&"basic")
	var marksman := _setup_tower(&"basic")
	for i in 3:
		barrage.apply_upgrade(&"sustained")
		marksman.apply_upgrade(&"burst")
	var b_base := (barrage.get_node("Base").texture as AtlasTexture).region
	var m_base := (marksman.get_node("Base").texture as AtlasTexture).region
	var b_turret := (barrage.turret_sprite().texture as AtlasTexture).region
	var m_turret := (marksman.turret_sprite().texture as AtlasTexture).region
	assert_eq(b_base, m_base, "equal investment wears the same base")
	assert_true(b_turret != m_turret, "but the branch is readable from the turret")
	barrage.free()
	marksman.free()
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — there is no `Base` node and no `turret_sprite()`, so the tests error on a missing node.

- [ ] **Step 3: Split the scene**

In `game/tower.tscn`, rename the `Sprite` node to `Base` and add a `Turret` sprite after it:

```
[node name="Base" type="Sprite2D" parent="."]

[node name="Turret" type="Sprite2D" parent="."]
```

Node order matters: `Turret` after `Base` means it draws on top without needing a z-index.

- [ ] **Step 4: Draw both sprites**

In `game/tower.gd`, replace the `_sprite` field and add the turret:

```gdscript
const BASE_SHEET := preload("res://assets/tower_bases.png")
const TURRET_SHEET := preload("res://assets/tower_turrets.png")
```

```gdscript
@onready var _base: Sprite2D = $Base
@onready var _turret: Sprite2D = $Turret
```

Keep `TOWER_SHEET` — `ui/tower_panel.gd` still reads it for the build-panel icons.

In `setup`, scale both sprites where the single one was scaled:

```gdscript
	var target_px := Tiles.TILE_SIZE * float(_def["size"])
	var scale_factor := target_px / FRAME_SIZE
	_base.scale = Vector2.ONE * scale_factor
	_turret.scale = Vector2.ONE * scale_factor
```

Rewrite `_refresh_visuals`:

```gdscript
## Both sprites and the range ring, all derived from the tiers.
##
## Two channels: the base follows visual_tier (how much is invested), the
## turret follows the leading branch and its band (in what, and how far). See
## UpgradesSim.turret_frame_for.
func _refresh_visuals() -> void:
	var base_atlas := AtlasTexture.new()
	base_atlas.atlas = BASE_SHEET
	base_atlas.region = frame_region(UpgradesSim.sprite_frame_for(kind, tiers))
	_base.texture = base_atlas

	var turret_atlas := AtlasTexture.new()
	turret_atlas.atlas = TURRET_SHEET
	turret_atlas.region = frame_region(UpgradesSim.turret_frame_for(kind, tiers))
	_turret.texture = turret_atlas

	_range_indicator.radius = float(_stats["range"])
	_range_indicator.queue_redraw()

## The rotating sprite, for tests that assert tracking.
func turret_sprite() -> Sprite2D:
	return _turret
```

Replace every other `_sprite` reference in the file with `_base`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add game/tower.tscn game/tower.gd test/test_tower.gd
git commit -m "Split the tower into a fixed base and a separate turret sprite"
```

---

### Task 7: Rotate the turret toward its target

**Files:**
- Modify: `game/tower.gd:115-133` (`tick`)
- Test: `test/test_tower.gd`

**Interfaces:**
- Consumes: `Tower.turret_sprite()` from Task 6.
- Produces: no new API — `tick` gains the rotation as a side effect.

**`tick` must be restructured, and this is the substantive change.** It currently returns early when `_cooldown > 0`, so `Targeting.select` runs only on fire-ready ticks. A turret that only re-aims when it fires does not track. Target resolution moves above the cooldown gate; firing stays behind it.

The cost is that `Targeting.select` runs every physics tick per tower instead of only on firing ticks. With the map's tower budget of 16 and a wave's worth of enemies that is a few hundred distance comparisons per tick — the same order as the collision checks already run each frame.

**Behaviour that must be preserved:** the shot still uses the target selected on the tick it fires, so what a tower shoots is unchanged. Only when selection happens moves.

**With no target the turret holds its last angle.** Snapping back to north between shots reads as broken. Rotation is instantaneous rather than eased: a traverse speed would let the turret point somewhere the shot did not come from, which is a worse lie than instant traverse.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_tower.gd`:

```gdscript
func test_the_turret_points_at_its_target() -> bool:
	# The turret art is drawn pointing north, so facing a target due east is
	# a +90 degree rotation. This is what catches a sign error or a
	# degrees/radians mix-up, neither of which any other test would see.
	var tower := _setup_tower(&"basic")
	tower.position = Vector2(100, 100)
	tower.tick(0.0, [_candidate(1, Vector2(300, 100))])
	assert_almost_eq(tower.turret_sprite().rotation, PI / 2.0, 0.01,
		"a target due east rotates the north-facing turret a quarter turn clockwise")
	tower.free()
	return true

func test_the_turret_tracks_between_shots_not_only_when_firing() -> bool:
	# The bug this guards: tick() used to return early while on cooldown, so
	# the turret would only re-aim on the tick it fired.
	var tower := _setup_tower(&"basic")
	tower.position = Vector2.ZERO
	tower.tick(0.0, [_candidate(1, Vector2(100, 0))])
	var after_first := tower.turret_sprite().rotation
	# A tiny delta leaves the tower deep in cooldown; the target has moved.
	tower.tick(1.0, [_candidate(1, Vector2(0, 100))])
	assert_true(absf(tower.turret_sprite().rotation - after_first) > 0.5,
		"the turret followed the target while still on cooldown")
	assert_almost_eq(tower.turret_sprite().rotation, PI, 0.01,
		"and it is pointing due south")
	tower.free()
	return true

func test_the_turret_holds_its_angle_with_nothing_in_range() -> bool:
	# Snapping back to north between waves reads as broken.
	var tower := _setup_tower(&"basic")
	tower.position = Vector2.ZERO
	tower.tick(0.0, [_candidate(1, Vector2(100, 0))])
	var held := tower.turret_sprite().rotation
	tower.tick(1000.0, [])
	assert_almost_eq(tower.turret_sprite().rotation, held, 0.001,
		"an empty candidate list leaves the turret where it was")
	tower.free()
	return true

func test_the_base_never_rotates() -> bool:
	# The whole reason the sprite was split.
	var tower := _setup_tower(&"basic")
	tower.position = Vector2.ZERO
	tower.tick(0.0, [_candidate(1, Vector2(0, -100))])
	assert_almost_eq(tower.get_node("Base").rotation, 0.0, 0.001,
		"the base stays planted while the turret tracks")
	tower.free()
	return true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — the turret's rotation never leaves 0.0, so the first test reports `0.0` against the expected `1.5708`.

- [ ] **Step 3: Restructure tick**

Replace `tick` in `game/tower.gd`:

```gdscript
## Called by the board each physics tick with the current enemy candidates.
##
## Target resolution happens EVERY tick, above the cooldown gate, because the
## turret has to keep tracking between shots - an earlier version returned
## early while on cooldown and the turret only re-aimed on the tick it fired.
## Firing itself stays behind the gate, and the shot still uses the target
## selected on the tick it fires, so what a tower shoots is unchanged.
func tick(delta_ms: float, candidates: Array) -> void:
	_cooldown -= delta_ms

	var target = Targeting.select(to_targeting_dict(), candidates)
	if target != null:
		_aim_at(target["position"])

	if _cooldown > 0.0 or target == null:
		return

	_cooldown = float(_stats["fire_rate"])
	wants_to_fire.emit(target["node"],
		{
			"damage": _stats["damage"],
			"pierce": _stats["pierce"],
			"gold_multiplier": _stats["gold_multiplier"],
			"bonus_gold_per_kill": _stats["bonus_gold_per_kill"],
			"slow_factor": _stats["slow_factor"],
			"slow_duration_ms": _stats["slow_duration_ms"],
		},
		float(_stats["splash_radius"]))

## Points the turret at a world position.
##
## The turret art is drawn pointing north, so the angle needs a quarter turn
## added: angle_to_point returns 0 for due east. With no target the caller
## simply does not call this, which is what makes the turret hold its last
## angle rather than snapping back.
func _aim_at(world_position: Vector2) -> void:
	_turret.rotation = position.angle_to_point(world_position) + PI / 2.0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 5: Watch it in the running game**

```bash
godot --path .
```

Place two towers near the road, start a wave, and watch. Confirm the turrets swing to follow enemies along the path, that they keep tracking between shots rather than twitching only when firing, that the bases stay planted, and that a turret holds its angle after the wave clears. Then buy three tiers on one branch of one tower and three on the other branch of a second tower, and confirm the two look different. Close the game.

No assertion covers any of this — `test_the_turret_points_at_its_target` proves the arithmetic, not that it reads correctly in motion.

- [ ] **Step 6: Commit**

```bash
git add game/tower.gd test/test_tower.gd
git commit -m "Track the current target with the turret every tick"
```

---

## Notes for the executor

**The three things most likely to go wrong:**

1. **`weakest`'s position in `PRIORITIES`.** It goes after `strongest`, keeping `closest` last. Put it anywhere else and two existing cycle tests break, and editing them to pass looks exactly like weakening a test.

2. **`tick`'s restructure.** Resolving the target above the cooldown gate is the point of Task 7. If the early return survives, every test passes except the tracking one, and the feature silently does not work between shots.

3. **The turret is composed, not cut.** The pack has no separable turret heads — this was established by rendering every candidate. If `_compose_turret` looks like more work than slicing the existing composite, that is because slicing does not produce something that can rotate.

**Baseline suite count:** 6688 checks across 36 files. Every task adds to it; none should reduce it.

**Deferred to plan 2 (`2026-08-20-board-depth.md`):** drop shadows, Y-sorted drawing, prop base-anchoring and the collision-parity gate that goes with it. Nothing in this plan depends on that work, and this plan is complete without it.
