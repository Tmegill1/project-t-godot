# Free Tower Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player place towers anywhere on the map that is not occupied by the road, a prop, or another tower, replacing the 48px placement grid with world-space circle collision.

**Architecture:** A new pure rules module `sim/placement.gd` answers "may a tower stand here?" with circle-vs-circle distance tests plus point-to-segment distance against the enemy path polyline. `MapRenderer` publishes prop footprints in world space, `Tower` is positioned by a world `Vector2` instead of a tile coordinate, and `GameBoard` swaps its tile lookup for a `Placement.can_place` call. Map authoring and pathfinding stay tile-based and are untouched.

**Tech Stack:** Godot 4.7.1.stable, GDScript. No new dependencies. Custom test harness at `test/run_tests.gd` (not GUT).

**Spec:** [`docs/superpowers/specs/2026-08-15-free-placement-design.md`](../specs/2026-08-15-free-placement-design.md)

## Global Constraints

- **Godot 4.7.1.stable**, GL Compatibility renderer. Binary at `~/.local/bin/godot`.
- **Run the suite:** `~/.local/bin/godot --headless --quit --script test/run_tests.gd`. There is **no per-file or per-test filter** — the runner always runs everything. Filter the output with `grep`, not the runner.
- **After introducing a new `class_name`,** run `~/.local/bin/godot --headless --import` **once** or every later run fails with a baffling "Identifier not declared" parse error. This applies to Task 1 only.
- **`godot --headless --import` and `--script` both scribble a stray blank line into `project.godot`** under `[autoload]`. Always `git checkout -- project.godot` before committing. It also blocks `git stash`.
- **Every `test_*` method MUST be declared `-> bool` and end with `return true`.** Every early return inside one must also `return true`. This is the harness's crash sentinel, enforced by the runner — not a style rule.
- **A GDScript runtime error aborts only the enclosing function frame**, returning the declared return type's default. It does not unwind. This is why the sentinel works and why Task 4 is dangerous.
- **Assertion API** (`test/case.gd`): `assert_eq(actual, expected, msg)`, `assert_true(v, msg)`, `assert_false(v, msg)`, `assert_almost_eq(actual, expected, epsilon, msg)`. There is no `assert_null` — compare against `null` with `assert_eq`.
- **Baseline suite state:** 5214 checks across 29 files, 0 failing, exit 0. Any drop in check count must be explained in the commit message.
- **Mutation-test the rules layer.** Every defect found in this project's sim layer so far came from mutating the implementation and confirming a test goes red — not from reading code. Tasks 1 and 2 require it explicitly.
- **Commit style:** imperative, sentence case, no `feat:`/`fix:` prefixes. End every commit message with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Do not change** `sim/pathfinder.gd`, `sim/grid.gd`, `sim/movement.gd`, `sim/targeting.gd`, `sim/damage.gd`, `sim/slow.gd`, `sim/economy.gd`, `sim/upgrades.gd`, `sim/harness.gd`, or anything in `data/` except as Task 2 specifies.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `sim/placement.gd` | **create** | Pure placement rules and geometry. No nodes, no globals. |
| `test/test_placement.gd` | **create** | Full TDD + mutation coverage for the above. |
| `game/map_renderer.gd` | modify | Adds `prop_footprints()`; loses the grid overlay and `clear_decoration_at`. |
| `game/tower.gd` | modify | `setup()` takes a world position; `grid_col`/`grid_row` deleted. |
| `game/game_board.gd` | modify | Placement and selection by position; `_occupied` deleted. |
| `game/game_board.tscn` | modify | Retypes the orphaned `PlacementPreview` node to `Sprite2D` and gives it a range child. |
| `test/test_map_renderer.gd` | modify | Grid-overlay tests deleted, footprint tests added. |
| `test/test_game_board.gd` | modify | Tile call sites → world positions. Bulk of the churn. |
| `test/test_tower.gd` | modify | `setup` signature, abort-safety re-pinned. |
| `test/test_tower_inspector.gd` | modify | Selection by position. |
| `test/test_tower_panel.gd` | modify | Helper + two call sites. |
| `test/test_hud.gd` | modify | One helper scan. |

**Unchanged, despite matching a naive grep:** `test/test_harness.gd` (its 22 `Grid.tile_to_world_center` hits are a convenience for building world positions the harness already accepts), `test/test_grid.gd`, `test/test_pathfinder.gd`, `test/test_demo_map.gd`.

---

### Task 1: Placement geometry — distance to a path polyline

**Files:**
- Create: `sim/placement.gd`
- Create: `test/test_placement.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Placement.distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float` and `Placement.distance_to_paths(point: Vector2, paths: Array) -> float`. Task 2 calls the latter.

- [ ] **Step 1: Create the module with only its header and constants**

Create `sim/placement.gd`:

```gdscript
class_name Placement

## Pure placement rules: may a tower stand at a given world point?
##
## No nodes, no scene tree, no static state. Every input is an argument -
## unlike Grid, which keeps the active map in static vars. That is deliberate:
## it lets a test build an arbitrary board without touching engine singletons,
## and it means these rules can never disagree with themselves between callers.

const REASON_OK := &"ok"
const REASON_OUT_OF_BOUNDS := &"out_of_bounds"
const REASON_ON_PATH := &"on_path"
const REASON_BLOCKED_BY_PROP := &"blocked_by_prop"
const REASON_TOO_CLOSE := &"too_close"

## How close two towers may sit, centre to centre. Deliberately NOT derived
## from the tower radius: "how big a tower looks" is an art decision and "how
## close two may sit" is a balance lever, and coupling them would make one
## untunable without disturbing the other. Starts just under the old 48px tile
## pitch so day-one density roughly matches the grid this replaces.
const MIN_TOWER_SPACING := 44.0

## Half the width of the corridor kept clear along the enemy route. Half a
## tile (24) plus a small margin, so a tower may not encroach on the road
## enemies visibly walk down.
const PATH_HALF_WIDTH := 26.0
```

- [ ] **Step 2: Register the new `class_name`**

Run: `~/.local/bin/godot --headless --import`

This is required exactly once, because `Placement` is a new `class_name`. Skipping it makes every later step fail with "Identifier not declared" rather than a real error.

Then: `cd ~/Projects/project-t-godot && git checkout -- project.godot`

- [ ] **Step 3: Write the failing tests for segment distance**

Create `test/test_placement.gd`:

```gdscript
extends TestCase

# Placement is pure static functions with no engine state, so these tests
# call it directly - no scene tree, no NOTIFICATION_READY, no node freeing.

# --------------------------------------------------------------------------
# distance_to_segment
# --------------------------------------------------------------------------

func test_distance_to_segment_measures_perpendicular_distance_to_the_interior() -> bool:
	var d := Placement.distance_to_segment(Vector2(5.0, 3.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(d, 3.0, 0.0001, "a point above the middle of a horizontal segment is its perpendicular distance away")
	return true

# A projection-only implementation (no clamping) passes the interior case above
# and fails this one: it would project (20, 0) onto the infinite line through
# the segment and report distance 0, rather than 10 from the nearer endpoint.
func test_distance_to_segment_clamps_to_the_nearer_endpoint_when_the_point_is_past_the_end() -> bool:
	var past_b := Placement.distance_to_segment(Vector2(20.0, 0.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(past_b, 10.0, 0.0001, "a point beyond b measures from b, not from the infinite line")

	var past_a := Placement.distance_to_segment(Vector2(-4.0, 0.0), Vector2(0.0, 0.0), Vector2(10.0, 0.0))
	assert_almost_eq(past_a, 4.0, 0.0001, "a point before a measures from a, not from the infinite line")
	return true

# A degenerate segment makes length_squared zero; an unguarded projection
# divides by it and returns NAN, which silently compares false against every
# threshold and would make can_place permit building straight through a path.
func test_distance_to_segment_handles_a_zero_length_segment_without_dividing_by_zero() -> bool:
	var d := Placement.distance_to_segment(Vector2(3.0, 4.0), Vector2(0.0, 0.0), Vector2(0.0, 0.0))
	assert_almost_eq(d, 5.0, 0.0001, "a zero-length segment behaves as the point it is")
	assert_false(is_nan(d), "the degenerate case does not produce NAN")
	return true

# --------------------------------------------------------------------------
# distance_to_paths
# --------------------------------------------------------------------------

func test_distance_to_paths_returns_the_nearest_segment_across_every_path() -> bool:
	var near := PackedVector2Array([Vector2(0.0, 100.0), Vector2(100.0, 100.0)])
	var far := PackedVector2Array([Vector2(0.0, 500.0), Vector2(100.0, 500.0)])
	var d := Placement.distance_to_paths(Vector2(50.0, 90.0), [far, near])
	assert_almost_eq(d, 10.0, 0.0001, "the nearest of several paths wins, whatever order they are given in")
	return true

func test_distance_to_paths_measures_every_segment_of_a_multi_point_path() -> bool:
	# An L: right along y=0, then down at x=100. A loop that only measured the
	# first segment would report 100 for a point beside the second leg.
	var path := PackedVector2Array([Vector2(0.0, 0.0), Vector2(100.0, 0.0), Vector2(100.0, 100.0)])
	var d := Placement.distance_to_paths(Vector2(93.0, 50.0), [path])
	assert_almost_eq(d, 7.0, 0.0001, "a point beside the second leg measures against that leg")
	return true

func test_distance_to_paths_handles_a_single_point_path() -> bool:
	var path := PackedVector2Array([Vector2(10.0, 10.0)])
	var d := Placement.distance_to_paths(Vector2(10.0, 13.0), [path])
	assert_almost_eq(d, 3.0, 0.0001, "a one-point path has no segments and measures from the point itself")
	return true

# No paths means nothing to stay clear of. INF rather than 0.0 so that
# `distance < radius + PATH_HALF_WIDTH` reads false and placement is allowed;
# returning 0.0 would make an empty path list block the entire map.
func test_distance_to_paths_with_no_paths_is_infinitely_far() -> bool:
	assert_true(is_inf(Placement.distance_to_paths(Vector2.ZERO, [])), "no paths means no path proximity constraint")
	return true
```

- [ ] **Step 4: Run the suite and verify the new tests fail**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: `FAIL test_placement.gd::...` for all seven tests. The failures will be aborts (the functions do not exist yet), reported as aborted tests. That is the correct RED.

- [ ] **Step 5: Implement the two functions**

Append to `sim/placement.gd`:

```gdscript
## Shortest distance from `point` to the segment ab.
##
## Clamping t to [0, 1] is what makes this a *segment* rather than an infinite
## line: without it, a point far beyond an endpoint reports the distance to the
## line's projection, which for a path polyline means a tower could be built
## past the end of the road and still be judged "on" it.
static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq == 0.0:
		# Degenerate segment: a and b are the same point, so there is no
		# direction to project onto. Guarded explicitly because the division
		# below would produce NAN, and NAN compares false against every
		# threshold - the rules would silently stop rejecting anything.
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

## Shortest distance from `point` to any segment of any path polyline.
## Returns INF when there are no paths, so an absent route imposes no
## constraint rather than blocking everything.
static func distance_to_paths(point: Vector2, paths: Array) -> float:
	var best := INF
	for path in paths:
		var pts: PackedVector2Array = path
		if pts.size() == 0:
			continue
		if pts.size() == 1:
			best = minf(best, point.distance_to(pts[0]))
			continue
		for i in range(pts.size() - 1):
			best = minf(best, distance_to_segment(point, pts[i], pts[i + 1]))
	return best
```

- [ ] **Step 6: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. Check count risen from 5214 to about 5227.

- [ ] **Step 7: Mutation-test the clamp and the degenerate guard**

Make each mutation, run the suite, confirm a test goes red, then revert.

1. Change `clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)` to `(point - a).dot(ab) / len_sq` (drop the clamp).
   Expected red: `test_distance_to_segment_clamps_to_the_nearer_endpoint_when_the_point_is_past_the_end`.
2. Change `if len_sq == 0.0:` to `if false:`.
   Expected red: `test_distance_to_segment_handles_a_zero_length_segment_without_dividing_by_zero`.
3. Change `var best := INF` to `var best := 0.0`.
   Expected red: `test_distance_to_paths_with_no_paths_is_infinitely_far`.

If any mutation survives, the tests are insufficient — strengthen them before continuing.

- [ ] **Step 8: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add sim/placement.gd sim/placement.gd.uid test/test_placement.gd test/test_placement.gd.uid
git commit -m "$(cat <<'EOF'
Add placement geometry for point-to-path distance

The first half of sim/placement.gd: segment and polyline distance, with the
clamp that makes it a segment rather than an infinite line and an explicit
guard on the degenerate zero-length case, whose NAN would otherwise compare
false against every threshold and stop the rules rejecting anything.

No caller yet; the game still places towers on tiles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: The placement rule

**Files:**
- Modify: `sim/placement.gd`
- Modify: `test/test_placement.gd`

**Interfaces:**
- Consumes: `Placement.distance_to_paths` from Task 1. `Towers.DEFS` and `Tiles.TILE_SIZE` from `data/`.
- Produces:
  - `Placement.tower_radius(kind: StringName) -> float`
  - `Placement.can_place(pos: Vector2, radius: float, props: Array, towers: Array, paths: Array, bounds: Rect2, min_spacing: float = MIN_TOWER_SPACING) -> Dictionary` returning `{"ok": bool, "reason": StringName}`. Task 5 calls both.
  - `props` is `Array` of `{"pos": Vector2, "radius": float}`; `towers` is `Array` of `Vector2`; `paths` is `Array` of `PackedVector2Array`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_placement.gd`:

```gdscript
# --------------------------------------------------------------------------
# tower_radius
# --------------------------------------------------------------------------

# Derived from the `size` multiplier data/towers.gd already carries rather than
# introduced as a new constant, so a tower that is re-sized for art reasons
# cannot end up with a collision radius that disagrees with how it looks.
func test_tower_radius_derives_from_the_size_the_tower_already_declares() -> bool:
	for kind in Towers.KINDS:
		var expected := Tiles.TILE_SIZE * float(Towers.DEFS[kind]["size"]) / 2.0
		assert_almost_eq(Placement.tower_radius(kind), expected, 0.0001,
			"%s's radius is half its displayed width" % kind)
	assert_almost_eq(Placement.tower_radius(&"basic"), 19.2, 0.0001,
		"basic is size 0.8 of a 48px tile, so 19.2px radius")
	return true

# --------------------------------------------------------------------------
# can_place
# --------------------------------------------------------------------------

const _BOUNDS := Rect2(Vector2.ZERO, Vector2(1104.0, 672.0))

# A path far from anything the tests below place, so it never accidentally
# becomes the reason a case is rejected.
func _far_path() -> Array:
	return [PackedVector2Array([Vector2(0.0, 600.0), Vector2(1000.0, 600.0)])]

func test_can_place_accepts_open_ground() -> bool:
	var v := Placement.can_place(Vector2(300.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(v["ok"], "open ground well clear of everything is placeable")
	assert_eq(v["reason"], Placement.REASON_OK, "an accepted spot reports the ok reason")
	return true

func test_can_place_rejects_a_tower_whose_circle_leaves_the_map() -> bool:
	var v := Placement.can_place(Vector2(10.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_false(v["ok"], "a tower at x=10 with radius 20 hangs off the left edge")
	assert_eq(v["reason"], Placement.REASON_OUT_OF_BOUNDS, "and says so")

	var inside := Placement.can_place(Vector2(21.0, 100.0), 20.0, [], [], _far_path(), _BOUNDS)
	assert_true(inside["ok"], "one pixel further in, the whole circle fits and it is accepted")
	return true

func test_can_place_rejects_a_spot_on_the_road() -> bool:
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var v := Placement.can_place(Vector2(250.0, 110.0), 20.0, [], [], path, _BOUNDS)
	assert_false(v["ok"], "10px from the road centre is inside the corridor")
	assert_eq(v["reason"], Placement.REASON_ON_PATH, "and says so")
	return true

func test_can_place_rejects_a_spot_overlapping_a_prop() -> bool:
	var props := [{"pos": Vector2(300.0, 100.0), "radius": 24.0}]
	var v := Placement.can_place(Vector2(320.0, 100.0), 20.0, props, [], _far_path(), _BOUNDS)
	assert_false(v["ok"], "20px from a 24px prop with a 20px tower overlaps")
	assert_eq(v["reason"], Placement.REASON_BLOCKED_BY_PROP, "and says so")
	return true

func test_can_place_rejects_a_spot_too_close_to_another_tower() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var v := Placement.can_place(Vector2(330.0, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_false(v["ok"], "30px apart is inside the 44px minimum spacing")
	assert_eq(v["reason"], Placement.REASON_TOO_CLOSE, "and says so")
	return true

# Each threshold is checked from both sides. `<` vs `<=` is the classic
# surviving mutant, and a range-only check would not catch it.
func test_can_place_thresholds_are_exact_on_both_sides() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var just_inside := Placement.can_place(Vector2(300.0 + 43.9, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_false(just_inside["ok"], "43.9px apart is closer than MIN_TOWER_SPACING and is refused")
	var just_outside := Placement.can_place(Vector2(300.0 + 44.1, 100.0), 20.0, [], towers, _far_path(), _BOUNDS)
	assert_true(just_outside["ok"], "44.1px apart clears MIN_TOWER_SPACING and is allowed")

	# radius 20 + PATH_HALF_WIDTH 26 = 46
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var near := Placement.can_place(Vector2(250.0, 100.0 + 45.9), 20.0, [], [], path, _BOUNDS)
	assert_false(near["ok"], "45.9px from the road centre is inside radius + PATH_HALF_WIDTH")
	var clear := Placement.can_place(Vector2(250.0, 100.0 + 46.1), 20.0, [], [], path, _BOUNDS)
	assert_true(clear["ok"], "46.1px from the road centre clears the corridor")
	return true

# With several rules failing at once the reported reason must be stable and
# most-explanatory, or the message shown to the player depends on argument
# order. Reordering the checks in can_place is invisible without this.
func test_can_place_reports_the_first_failing_rule_in_a_fixed_precedence() -> bool:
	var path := [PackedVector2Array([Vector2(0.0, 100.0), Vector2(500.0, 100.0)])]
	var props := [{"pos": Vector2(250.0, 105.0), "radius": 24.0}]
	var towers := [Vector2(250.0, 108.0)]

	# On the road AND overlapping a prop AND too close to a tower.
	var v := Placement.can_place(Vector2(250.0, 105.0), 20.0, props, towers, path, _BOUNDS)
	assert_false(v["ok"], "a spot failing every rule is refused")
	assert_eq(v["reason"], Placement.REASON_ON_PATH, "path proximity outranks prop and spacing")

	# Off the road, but overlapping a prop AND too close to a tower.
	var off_road_props := [{"pos": Vector2(250.0, 300.0), "radius": 24.0}]
	var off_road_towers := [Vector2(250.0, 300.0)]
	var v2 := Placement.can_place(Vector2(250.0, 300.0), 20.0, off_road_props, off_road_towers, path, _BOUNDS)
	assert_eq(v2["reason"], Placement.REASON_BLOCKED_BY_PROP, "prop outranks spacing")
	return true

func test_can_place_handles_empty_prop_and_tower_lists() -> bool:
	var v := Placement.can_place(Vector2(300.0, 300.0), 20.0, [], [], [], _BOUNDS)
	assert_true(v["ok"], "an empty board with no paths places anywhere in bounds")
	return true

# min_spacing is a defaulted parameter rather than read from the constant
# inside the function, so balance tuning is a caller-side change and tests can
# pin behaviour at values other than the shipped default.
func test_can_place_accepts_an_overridden_minimum_spacing() -> bool:
	var towers := [Vector2(300.0, 100.0)]
	var v := Placement.can_place(Vector2(330.0, 100.0), 20.0, [], towers, _far_path(), _BOUNDS, 20.0)
	assert_true(v["ok"], "30px apart is fine when min_spacing is lowered to 20")
	return true
```

- [ ] **Step 2: Run the suite and verify the new tests fail**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: `FAIL test_placement.gd::...` for the ten new tests, aborting because `can_place` and `tower_radius` do not exist.

- [ ] **Step 3: Implement the rule**

Append to `sim/placement.gd`:

```gdscript
## A tower's collision radius, from the `size` multiplier it already declares
## in data/towers.gd. Derived rather than tabulated so that re-sizing a tower
## for art reasons cannot leave its collision disagreeing with its sprite.
static func tower_radius(kind: StringName) -> float:
	return Tiles.TILE_SIZE * float(Towers.DEFS[kind]["size"]) / 2.0

## May a tower of `radius` stand centred on `pos`?
##
## Returns a reason as well as a verdict so the board can keep showing the
## player a specific message instead of one generic refusal. Checks run
## cheapest-and-most-explanatory first, and the order is load-bearing: it is
## what makes the reported reason stable when several rules fail at once.
##
## `props` is [{ "pos": Vector2, "radius": float }], `towers` is [Vector2],
## `paths` is [PackedVector2Array].
static func can_place(
		pos: Vector2,
		radius: float,
		props: Array,
		towers: Array,
		paths: Array,
		bounds: Rect2,
		min_spacing: float = MIN_TOWER_SPACING) -> Dictionary:
	if pos.x - radius < bounds.position.x \
			or pos.y - radius < bounds.position.y \
			or pos.x + radius > bounds.end.x \
			or pos.y + radius > bounds.end.y:
		return {"ok": false, "reason": REASON_OUT_OF_BOUNDS}

	if distance_to_paths(pos, paths) < radius + PATH_HALF_WIDTH:
		return {"ok": false, "reason": REASON_ON_PATH}

	for prop in props:
		var p: Dictionary = prop
		if pos.distance_to(p["pos"]) < radius + float(p["radius"]):
			return {"ok": false, "reason": REASON_BLOCKED_BY_PROP}

	for other in towers:
		var t: Vector2 = other
		if pos.distance_to(t) < min_spacing:
			return {"ok": false, "reason": REASON_TOO_CLOSE}

	return {"ok": true, "reason": REASON_OK}
```

- [ ] **Step 4: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. Check count around 5250.

- [ ] **Step 5: Mutation-test the rule**

Make each mutation, run, confirm red, revert.

1. Swap the path check and the prop loop.
   Expected red: `test_can_place_reports_the_first_failing_rule_in_a_fixed_precedence`.
2. Change `< radius + PATH_HALF_WIDTH` to `<= radius + PATH_HALF_WIDTH` — this should **survive**, because the tests probe 45.9 and 46.1, never exactly 46.0. That is intentional: exact float equality is not a behaviour worth pinning. Note it and move on.
3. Change `< min_spacing` to `< min_spacing - 1.0`.
   Expected red: `test_can_place_thresholds_are_exact_on_both_sides`.
4. Change `radius + float(p["radius"])` to `float(p["radius"])`.
   Expected red: `test_can_place_rejects_a_spot_overlapping_a_prop`.
5. Change the bounds check's `pos.x - radius` to `pos.x`.
   Expected red: `test_can_place_rejects_a_tower_whose_circle_leaves_the_map`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add sim/placement.gd test/test_placement.gd
git commit -m "$(cat <<'EOF'
Add the free-placement rule

can_place answers "may a tower stand here?" from bounds, path proximity, prop
overlap and tower spacing, returning a reason as well as a verdict so the
board can keep showing specific refusal messages.

Check order is load-bearing and tested: it is what makes the reported reason
stable when several rules fail at once. min_spacing is a defaulted parameter
rather than read from the constant inside, so balance tuning stays a
caller-side change.

Still no caller; the game continues to place towers on tiles.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Prop footprints

**Files:**
- Modify: `game/map_renderer.gd`
- Modify: `test/test_map_renderer.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `MapRenderer.prop_footprints() -> Array` of `{"pos": Vector2, "radius": float}` in world space. Task 5 passes this straight into `Placement.can_place`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_map_renderer.gd`:

```gdscript
# --------------------------------------------------------------------------
# prop_footprints
# --------------------------------------------------------------------------

# Blocking circles for free placement. Endpoints are deliberately excluded:
# cave.png and castle.png are drawn 3 tiles wide, so a footprint derived from
# them would carry a ~72px radius and sterilise the ground around the spawn
# and the goal - which is exactly where a player most wants a last line of
# defence. The road corridor already keeps towers off the endpoints themselves.
func test_prop_footprints_cover_every_prop_and_no_endpoint() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var prop_paths := [_TREE_PATH, _STONE_PATH, _SPIKE_PATH, _FIRE_PATH]
	var expected := 0
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path in prop_paths:
			expected += 1
	assert_true(expected > 0, "precondition: the demo map draws props at all")

	var footprints := mr.prop_footprints()
	assert_eq(footprints.size(), expected, "one footprint per tree, stone, spike and fire - and nothing else")

	mr.free()
	return true

# The radius is half the LONGEST displayed axis, so it over-covers rather than
# under-covers. Blocking slightly too much reads as level design; a tower
# clipping into a rock reads as a bug. stone.png displays about 48x22, so a
# radius taken from the short axis would be ~11 and let towers sit inside it.
func test_prop_footprint_radius_covers_the_sprite_s_longest_axis() -> bool:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var tiles := _demo_tiles()
	var mr := MapRenderer.new()
	mr.render(tiles, Rng.new(Seeds.DEFAULT_DECORATION_SEED))

	var stone: Sprite2D = null
	for child in mr.get_children():
		if child is Sprite2D and child.texture.resource_path == _STONE_PATH:
			stone = child
			break
	assert_true(stone != null, "a stone sprite was drawn")

	var tex := stone.texture
	var display := Vector2(tex.get_width(), tex.get_height()) * stone.scale
	var want_radius := maxf(display.x, display.y) / 2.0
	var want_centre := stone.position + display / 2.0

	var matched := false
	for entry in mr.prop_footprints():
		var f: Dictionary = entry
		if f["pos"].distance_to(want_centre) < 0.01:
			matched = true
			assert_almost_eq(f["radius"], want_radius, 0.01,
				"the stone's radius is half its longest displayed axis")
	assert_true(matched, "a footprint sits at the stone's displayed centre, not its top-left corner")

	mr.free()
	return true
```

- [ ] **Step 2: Run the suite and verify the tests fail**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: both new tests fail, aborting on the missing `prop_footprints` method.

- [ ] **Step 3: Implement `prop_footprints`**

In `game/map_renderer.gd`, add after `clear_decoration_at`:

```gdscript
## Every prop as a world-space blocking circle, for sim/placement.gd.
##
## Endpoints are excluded on purpose: they are drawn 3 tiles wide, so a
## footprint from one would carry a ~72px radius and sterilise the ground
## around the spawn and goal - where a player most wants a last line of
## defence. The path corridor already keeps towers off the endpoints.
##
## Radius is half the sprite's LONGEST displayed axis, so it over-covers
## rather than under-covers: blocking slightly too much reads as level design,
## while a tower clipping into a rock reads as a bug. This only measures
## correctly because _place scales uniformly (see its doc comment); under the
## stretch-to-square behaviour it replaced, displayed size was a distortion.
func prop_footprints() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Sprite2D):
			continue
		if not (child.texture in _PROP_TEXTURES):
			continue
		var tex: Texture2D = child.texture
		var display := Vector2(tex.get_width(), tex.get_height()) * child.scale
		out.append({
			"pos": child.position + display / 2.0,
			"radius": maxf(display.x, display.y) / 2.0,
		})
	return out
```

And add the texture list beside the existing preloads near the top of the file:

```gdscript
## Which textures count as solid props for placement. Ground tiles are not
## props, and endpoints are excluded for the reason prop_footprints explains.
const _PROP_TEXTURES := [_TREE, _STONE, _SPIKE, _FIRE]
```

- [ ] **Step 4: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines.

- [ ] **Step 5: Mutation-test the footprint geometry**

1. Change `maxf(display.x, display.y)` to `minf(display.x, display.y)`.
   Expected red: `test_prop_footprint_radius_covers_the_sprite_s_longest_axis`.
2. Change `child.position + display / 2.0` to `child.position`.
   Expected red: the same test, on the "displayed centre, not top-left corner" assertion.
3. Add `_CASTLE` to `_PROP_TEXTURES`.
   Expected red: `test_prop_footprints_cover_every_prop_and_no_endpoint`.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add game/map_renderer.gd test/test_map_renderer.gd
git commit -m "$(cat <<'EOF'
Publish prop footprints as world-space blocking circles

MapRenderer already knows where every tree, stone, spike and fire is drawn
and how big it renders; prop_footprints exposes that for sim/placement.gd.

Radius is half the longest displayed axis so it over-covers: blocking a
little too much reads as level design, a tower clipping into a rock reads as
a bug. Endpoints are excluded because at 3 tiles wide they would sterilise
the ground around the spawn and goal.

No caller yet.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Position a tower by world coordinate

**Files:**
- Modify: `game/tower.gd:32-33`, `game/tower.gd:49-63`
- Modify: `game/game_board.gd` (call site only)
- Modify: `test/test_tower.gd:82-84`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Tower.setup(tower_kind: StringName, world_pos: Vector2, paid: int) -> void`. `Tower.grid_col` and `Tower.grid_row` cease to exist. Task 5 calls the new signature.

**⚠️ This is the riskiest task in the plan.** `Tower.setup` aborts at its first `@onready` access under the headless harness, and everything assigned *before* that line still lands while everything after is silently skipped. The tower-upgrades work already shipped one defect from exactly this. The `position` assignment **must stay above** the `_sprite.scale` line. Do not reorder.

- [ ] **Step 1: Update the existing tower tests to the new signature**

In `test/test_tower.gd`, replace the assertions at lines 82-84:

```gdscript
	assert_eq(t.position, Vector2(264.0, 360.0), "the tower sits exactly where it was placed")
```

Delete the two lines asserting `t.grid_col` and `t.grid_row`. Then find every `setup(` call in that file and change it from tile arguments to a world position — for the case above, `t.setup(&"basic", Vector2(264.0, 360.0), 20)`.

- [ ] **Step 2: Extend the abort-safety test to cover position**

This is the specific defect class this task risks. In `test/test_tower.gd`, find `test_setup_lands_tiers_and_stats_even_when_the_sprite_half_aborts` and add to it:

```gdscript
	assert_eq(t.position, Vector2(264.0, 360.0),
		"position is assigned above the first @onready access, so it survives the abort - "
		+ "a tower whose sprite half aborted must still be somewhere real, or every later "
		+ "distance test in the board and in Placement reads (0, 0)")
```

- [ ] **Step 3: Run the suite and verify these fail**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: `FAIL test_tower.gd::...` — the old `setup(kind, col, row, paid)` signature does not accept a `Vector2`.

- [ ] **Step 4: Change the signature**

In `game/tower.gd`, delete lines 32-33:

```gdscript
var grid_col := 0
var grid_row := 0
```

Replace `setup` (lines 49-63) with:

```gdscript
func setup(tower_kind: StringName, world_pos: Vector2, paid: int) -> void:
	kind = tower_kind
	price_paid = paid
	_def = Towers.DEFS[kind]
	# Rules state before anything visual. The board instantiates a tower under
	# a node that never entered a live tree, so in the test harness the
	# tower's own @onready fields are unresolved and this function aborts at
	# the first line that touches one - everything assigned before that line
	# still lands (see test_game_board.gd's header), and the upgrade path
	# needs tiers and the resolved stats to be among them.
	#
	# `position` is now among them too, and must stay above the _sprite line:
	# a tower is located by its position alone since grid_col/grid_row went
	# away, so a tower that aborted before being positioned would sit at
	# (0, 0) and every distance test in GameBoard and Placement would read it
	# as being in the top-left corner of the map.
	tiers = UpgradesSim.empty_tiers()
	_stats = UpgradesSim.resolve_tower_stats(kind, tiers)
	position = world_pos

	var target_px := Tiles.TILE_SIZE * float(_def["size"])
	_sprite.scale = Vector2.ONE * (target_px / FRAME_SIZE)

	_range_indicator.tint = _def["color"]
	_range_indicator.visible = false
	_refresh_visuals()
```

- [ ] **Step 5: Update the board's call site so the project still builds**

In `game/game_board.gd`, `_try_place` currently calls `tower.setup(_selected_kind, col, row, price)`. Change it to keep today's behaviour exactly, converting the tile to a world centre at the call site:

```gdscript
	tower.setup(_selected_kind, Grid.tile_to_world_center(col, row), price)
```

Placement is still tile-based after this task — only the way a tower learns its position has changed. Task 5 removes the tile lookup.

Then in `sell_selected_tower`, `_occupied.erase(Vector2i(tower.grid_col, tower.grid_row))` no longer compiles. Replace it with a reverse lookup for now, since `_occupied` itself survives until Task 5:

```gdscript
	for key in _occupied.keys():
		if _occupied[key] == tower:
			_occupied.erase(key)
			break
```

- [ ] **Step 6: Fix the remaining `grid_col`/`grid_row` reader**

`test/test_tower_inspector.gd:267` calls `b._handle_tap(Grid.tile_to_world_center(t.grid_col, t.grid_row))`. Change it to:

```gdscript
	b._handle_tap(t.position)
```

- [ ] **Step 7: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. If anything fails with "Invalid access to property 'grid_col'", a reader was missed — find it with `grep -rn "grid_col\|grid_row" --include="*.gd" .`

- [ ] **Step 8: Verify the abort guard actually guards**

Move `position = world_pos` to *below* the `_sprite.scale` line and run the suite.

Expected red: the assertion added in Step 2. This confirms the ordering constraint is enforced by a test rather than only by a comment. **Move it back** and re-run to confirm green.

- [ ] **Step 9: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add game/tower.gd game/game_board.gd test/test_tower.gd test/test_tower_inspector.gd
git commit -m "$(cat <<'EOF'
Locate a tower by world position rather than tile coordinate

Tower.setup takes a Vector2; grid_col and grid_row are gone and the node's
own position is the single source of truth for where a tower is.

Placement is still tile-based - the board converts at the call site - so this
is only the change of address, isolated from the rule change that follows.

The position assignment must stay above the first @onready access: setup
aborts there under the headless harness, and a tower that aborted before
being positioned would sit at (0, 0) and read as top-left to every distance
test. That ordering is now pinned by a test, not just a comment.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Free placement in the board

**Files:**
- Modify: `game/game_board.gd:37` (`_occupied`), `:164-215` (`_handle_tap`, `_try_place`), `sell_selected_tower`
- Modify: `test/test_game_board.gd`, `test/test_tower_inspector.gd`, `test/test_tower_panel.gd`, `test/test_hud.gd`

**Interfaces:**
- Consumes: `Placement.can_place`, `Placement.tower_radius` (Task 2); `MapRenderer.prop_footprints` (Task 3); `Tower.setup(kind, Vector2, paid)` (Task 4).
- Produces: `GameBoard._try_place(world: Vector2) -> void` and `GameBoard._tower_at(world: Vector2) -> Tower`. Task 6's ghost calls `Placement.can_place` with the same arguments this task assembles.

- [ ] **Step 1: Replace the test helper that finds somewhere to build**

`test/test_game_board.gd` has `_find_buildable_tiles(b, count)` returning `Array[Vector2i]`. Every placement test uses it. Replace it with a world-space equivalent — this one helper change is what makes most of the churn mechanical:

```gdscript
## First `count` world positions the board will actually accept, found by
## asking the real rule rather than by reimplementing it. Scans tile centres
## in row-major order purely as a convenient sweep of the map; the tiles carry
## no meaning here beyond being evenly spaced sample points. The demo map is
## seeded and deterministic, so this is stable across runs without hardcoding
## coordinates that would silently go stale if the map or its seed changed.
func _find_placeable_positions(b: GameBoard, count: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(b._map_name)))
	var radius := Placement.tower_radius(&"basic")
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			var pos := Grid.tile_to_world_center(c, r)
			var verdict := Placement.can_place(
				pos, radius, b._map_renderer.prop_footprints(), found, b._paths, bounds)
			if verdict["ok"]:
				found.append(pos)
				if found.size() >= count:
					return found
	return found
```

Note it passes `found` as the tower list, so the positions it returns are mutually legal — otherwise a test placing all of them would hit `too_close` on the second one.

- [ ] **Step 2: Update the placement call sites**

In `test/test_game_board.gd`, every `b._try_place(tile.x, tile.y)` becomes `b._try_place(pos)`, and every `_find_buildable_tiles(b, n)` becomes `_find_placeable_positions(b, n)`. The rejection test at line 140 changes from "a non-buildable tile" to a spot on the road:

```gdscript
func test_try_place_rejects_a_spot_on_the_road() -> bool:
	var b := _ready_board()
	b.select_kind(&"basic")
	var gold_before := b._gold
	# The first point of the first spawn path is the road itself.
	b._try_place(b._paths[0][0])
	assert_eq(b._towers_root.get_child_count(), 0, "no tower was built on the road")
	assert_eq(b._gold, gold_before, "and no gold was spent")
	b.free()
	return true
```

Apply the same helper rename in `test/test_tower_inspector.gd`, `test/test_tower_panel.gd` and `test/test_hud.gd`, each of which has its own local copy of the buildable-tile scan.

- [ ] **Step 3: Delete the tests for behaviour that no longer exists**

Delete `test_try_place_success_clears_the_tiles_decoration` from `test/test_game_board.gd` — a prop is now a hard blocker, so building on one is impossible and `clear_decoration_at` is gone. Delete any test asserting `_occupied` directly.

Record what you deleted; Step 8's commit message must account for the drop in check count.

- [ ] **Step 4: Run the suite and verify the new expectations fail**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: failures in `test_game_board.gd` — `_try_place` still takes two ints.

- [ ] **Step 5: Rewrite tap handling and placement**

In `game/game_board.gd`, delete the `_occupied` declaration at line 37. Replace `_handle_tap` and the head of `_try_place`:

```gdscript
func _handle_tap(world: Vector2) -> void:
	var hit := _tower_at(world)
	if hit != null:
		_select_tower(hit)
		return

	if _selected_kind == &"":
		_deselect_tower()
		return

	_try_place(world)

## The nearest tower whose own radius contains `world`, or null.
##
## Nearest rather than first-match: at the shipped MIN_TOWER_SPACING two hit
## circles cannot overlap, but they can as soon as that value is tuned down,
## and a first-match scan would then make selection depend on child order -
## a bug that would surface during balance tuning, far from its cause.
func _tower_at(world: Vector2) -> Tower:
	var best: Tower = null
	var best_distance := INF
	for child in _towers_root.get_children():
		var tower: Tower = child
		var distance := world.distance_to(tower.position)
		if distance <= Placement.tower_radius(tower.kind) and distance < best_distance:
			best = tower
			best_distance = distance
	return best

## Every tower's position, for Placement.can_place's spacing check.
func _tower_positions() -> Array:
	var out: Array = []
	for child in _towers_root.get_children():
		out.append(child.position)
	return out

func _try_place(world: Vector2) -> void:
	var verdict := Placement.can_place(
		world,
		Placement.tower_radius(_selected_kind),
		_map_renderer.prop_footprints(),
		_tower_positions(),
		_paths,
		Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(_map_name))))
	if not verdict["ok"]:
		placement_rejected.emit(_rejection_message(verdict["reason"]))
		_play_sound(&"denied")
		return

	var total := _towers_root.get_child_count()
	if total >= int(Maps.get_def(_map_name)["tower_budget"]):
		placement_rejected.emit("Tower budget reached.")
		_play_sound(&"denied")
		return

	if _counts[_selected_kind] >= EconomySim.tower_limit(_selected_kind, _map_name):
		placement_rejected.emit("You cannot build any more of that tower.")
		_play_sound(&"denied")
		return

	var price := EconomySim.tower_price(_selected_kind, _counts[_selected_kind])
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		_play_sound(&"denied")
		return

	var tower: Tower = TOWER_SCENE.instantiate()
	_towers_root.add_child(tower)
	tower.setup(_selected_kind, world, price)
	tower.wants_to_fire.connect(_on_tower_fired.bind(tower))

	_counts[_selected_kind] += 1
	_gold -= price

	gold_changed.emit(_gold)
	var placed_kind := _selected_kind
```

Keep the remainder of `_try_place` (the signal emissions after `placed_kind`) exactly as it is.

A `match` rather than a const dictionary, because a `const` whose values reference another class's constants is fragile at parse time:

```gdscript
## Player-facing text for a Placement refusal. A match rather than a const
## dictionary: a const whose keys reference another class's constants is
## evaluated at parse time and is fragile across script load order.
func _rejection_message(reason: StringName) -> String:
	match reason:
		Placement.REASON_OUT_OF_BOUNDS:
			return "That is off the edge of the map."
		Placement.REASON_ON_PATH:
			return "You cannot build on the road."
		Placement.REASON_BLOCKED_BY_PROP:
			return "Something is already in the way there."
		Placement.REASON_TOO_CLOSE:
			return "That is too close to another tower."
	return "You cannot build there."
```

- [ ] **Step 6: Simplify the sell path**

In `sell_selected_tower`, delete the `_occupied` reverse-lookup loop added in Task 4. Freeing the node is now the whole removal — `_towers_root.get_children()` is the only tower registry.

- [ ] **Step 7: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. The check count will have **dropped** from the deletions in Step 3; note the number for the commit message.

- [ ] **Step 8: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add game/game_board.gd test/test_game_board.gd test/test_tower_inspector.gd test/test_tower_panel.gd test/test_hud.gd
git commit -m "$(cat <<'EOF'
Place towers freely instead of on tiles

_handle_tap no longer snaps to a tile and _try_place asks Placement.can_place
instead of reading _tiles[row][col]. _occupied is deleted outright rather than
replaced: _towers_root already parents every tower, so the parallel dict only
ever existed to key them by tile.

Selection is now a nearest-tower hit test, and refusals map the rule's reason
back to the specific message the player already saw.

Check count drops by N: the decoration-clearing tests go with
clear_decoration_at, since a prop is now a hard blocker that can never be
built on.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

Replace `N` with the actual difference before committing.

---

### Task 6: The ghost, and removing the grid overlay

**Files:**
- Modify: `game/game_board.gd`, `game/game_board.tscn`
- Modify: `game/map_renderer.gd` (delete `_draw_grid_overlay`, `_GridOverlay`, `_GRID_LINE_COLOR`, `_Z_GRID`, `clear_decoration_at`)
- Modify: `test/test_map_renderer.gd` (delete grid-overlay tests)

**Interfaces:**
- Consumes: `Placement.can_place` (Task 2), `GameBoard._tower_positions` (Task 5).
- Produces: nothing later tasks depend on. This is the last task.

- [ ] **Step 1: Delete the grid overlay tests**

From `test/test_map_renderer.gd`, delete `test_grid_overlay_line_count_and_bounds`, `test_grid_overlay_sizes_itself_from_the_tiles_argument_not_demo_map_constants`, `test_grid_overlay_sits_above_ground_and_below_decoration`, `test_grid_line_color_matches_the_reference`, the `_grid_overlay` helper, and the grid-overlay assertion inside `test_render_called_twice_does_not_double_up_sprites`.

Also delete `test_clear_decoration_at_removes_a_decorated_tile_and_is_idempotent`.

- [ ] **Step 2: Delete the overlay itself**

From `game/map_renderer.gd`, delete `clear_decoration_at`, `_draw_grid_overlay`, the whole `_GridOverlay` inner class, `_GRID_LINE_COLOR`, `_Z_GRID`, and the `_draw_grid_overlay()` call in `render`.

Update the z-ordering comment at lines 18-25, which describes a three-layer arrangement that is now two. It currently explains why ground sits at -1 to make room for the grid at 0 — with the grid gone that reasoning is stale, and leaving it would mislead the next reader into preserving a gap for a layer that no longer exists:

```gdscript
## z-index ordering. Ground draws below decoration, endpoints and blocked-tile
## overlays. Ground sits at -1 rather than 0 for no reason beyond history: a
## grid overlay used to occupy 0 between them, and the values were left alone
## when it was removed rather than renumbering every layer.
const _Z_GROUND := -1
const _Z_OVERLAY := 1
```

- [ ] **Step 3: Run the suite and verify green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. Check count drops again; note it.

- [ ] **Step 4: Claim the orphaned preview node**

`game/game_board.tscn` already declares `[node name="PlacementPreview" type="Node2D" parent="."]`, and **no script references it** — verified with `grep -rn "PlacementPreview\|_preview" --include="*.gd" .`, which returns nothing. It is dead scaffolding from the core slice, evidently reserved for exactly this feature. Reuse it rather than adding a parallel `Ghost` node, so the scene does not end up with both.

Its type must change from `Node2D` to `Sprite2D`, and `range_indicator.gd` must be added as an `ext_resource` — it is **not** currently one in this scene, which only loads `game_board.gd` and `map_renderer.gd`. Bump `load_steps` from 3 to 4.

Replace the whole file with:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://game/game_board.gd" id="1_board"]
[ext_resource type="Script" path="res://game/map_renderer.gd" id="2_map"]
[ext_resource type="Script" path="res://game/range_indicator.gd" id="3_range"]

[node name="GameBoard" type="Node2D"]
script = ExtResource("1_board")

[node name="MapRenderer" type="Node2D" parent="."]
script = ExtResource("2_map")

[node name="Towers" type="Node2D" parent="."]

[node name="Enemies" type="Node2D" parent="."]

[node name="Projectiles" type="Node2D" parent="."]

[node name="PlacementPreview" type="Sprite2D" parent="."]
visible = false
z_index = 2

[node name="PreviewRange" type="Node2D" parent="PlacementPreview"]
script = ExtResource("3_range")
```

- [ ] **Step 5: Drive the ghost from mouse motion**

In `game/game_board.gd`, add the `@onready` handles beside the existing ones:

```gdscript
@onready var _ghost: Sprite2D = $PlacementPreview
@onready var _ghost_range: RangeIndicator = $PlacementPreview/PreviewRange
```

And add the update, called from `_unhandled_input` on `InputEventMouseMotion`:

```gdscript
## Ghost preview: green where the tower would land, red where it would not,
## with the range ring shown only when the spot is legal so its absence is a
## second, redundant signal. Pure view - it asks Placement the same question
## _try_place will ask and stores nothing of its own, so the preview cannot
## drift from the rule it previews.
func _update_ghost(world: Vector2) -> void:
	if _selected_kind == &"":
		_ghost.visible = false
		return

	var def: Dictionary = Towers.DEFS[_selected_kind]
	var radius := Placement.tower_radius(_selected_kind)
	var verdict := Placement.can_place(
		world,
		radius,
		_map_renderer.prop_footprints(),
		_tower_positions(),
		_paths,
		Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(_map_name))))

	_ghost.visible = true
	_ghost.position = world

	var atlas := AtlasTexture.new()
	atlas.atlas = Tower.TOWER_SHEET
	atlas.region = Tower.frame_region(int(def["sprite_frame"]))
	_ghost.texture = atlas
	_ghost.centered = true
	_ghost.scale = Vector2.ONE * (Tiles.TILE_SIZE * float(def["size"]) / Tower.FRAME_SIZE)
	_ghost.modulate = Color(0.4, 1.0, 0.4, 0.5) if verdict["ok"] else Color(1.0, 0.3, 0.3, 0.5)

	_ghost_range.visible = verdict["ok"]
	_ghost_range.radius = float(def["range"])
	_ghost_range.tint = def["color"]
	_ghost_range.queue_redraw()
```

In `_unhandled_input`, before the existing button handling:

```gdscript
	if event is InputEventMouseMotion:
		_update_ghost(get_global_mouse_position())
		return
```

Hide the ghost in `select_kind` when the selection is cleared, and after a successful placement.

- [ ] **Step 6: Run the suite and verify still green**

Run: `~/.local/bin/godot --headless --quit --script test/run_tests.gd 2>&1 | grep -E "^FAIL|checks across"`

Expected: no `FAIL` lines. The ghost is view-only and is not unit-tested — Step 7 verifies it instead.

- [ ] **Step 7: Screenshot-verify, because a green suite cannot see this**

Run the project through the Godot MCP (`run_project` with scene `res://game/game.tscn`), then:

1. Select a tower kind and move the mouse over open grass. **Expect:** green ghost, range ring visible.
2. Move it over the road. **Expect:** red ghost, no range ring.
3. Move it over a tree. **Expect:** red ghost.
4. Place two towers as close together as allowed. **Expect:** they sit ~44px apart and neither overlaps the other.
5. Place a tower hard against a prop and against the road edge. **Expect:** no visual overlap.
6. Confirm no grid lines are drawn anywhere.
7. Call `game_get_errors`. **Expect:** only the pre-existing warnings from `tower.gd:25`, `tower.gd:72` and the MCP's own server script.

- [ ] **Step 8: Commit**

```bash
cd ~/Projects/project-t-godot
git checkout -- project.godot
git add game/game_board.gd game/game_board.tscn game/map_renderer.gd test/test_map_renderer.gd
git commit -m "$(cat <<'EOF'
Preview placement with a ghost tower and drop the grid overlay

A translucent tower follows the cursor while a kind is selected: green where
it would land, red where it would not, with the range ring shown only when
legal so its absence is a second signal. It asks Placement the same question
_try_place asks and keeps no state, so the preview cannot drift from the rule.

The grid overlay goes with the grid it described, taking clear_decoration_at
with it - a prop is a hard blocker now and can never be built on.

Verified by screenshot: green over grass, red over road and props, towers
placed adjacent to a prop and the road edge with no visual overlap.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Definition of Done

- Towers place anywhere in bounds not overlapping the road, a prop, or another tower — and nowhere else.
- Refusals name their specific reason to the player.
- Selecting, upgrading and selling all work by position.
- No grid lines drawn; no code path deciding *where a tower may go* reads a tile coordinate.
- `sim/placement.gd` is mutation-tested, not merely covered.
- Suite green, exit 0, with every drop in check count explained in its commit.
- Screenshots taken of the ghost's legal and illegal states, and of towers adjacent to a prop and to the road.
- `project.godot` is not in any commit.
