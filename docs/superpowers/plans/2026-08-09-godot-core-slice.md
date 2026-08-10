# Godot Core-Slice Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the core loop of the `project-t` Phaser tower defence to Godot 4.7 — one map, four towers, three enemies, twenty waves, win and lose — with the rules layer engine-free and headlessly testable.

**Architecture:** Faithful sim, native shell. `sim/` and `data/` are pure GDScript (`RefCounted` / static-only classes) ported near-verbatim from the TypeScript, quirks and unit tests intact. Everything above that line — rendering, input, UI, scene flow — is rebuilt in Godot idiom using `TileMapLayer`, `AnimatedSprite2D` and `Control` nodes with signals. Combat uses distance arithmetic, never physics, so the rules stay deterministic and testable.

**Tech Stack:** Godot 4.7.1.stable · GDScript · GL Compatibility renderer · a dependency-free headless test runner (verified working; see Task 1).

**Spec:** [`docs/superpowers/specs/2026-08-09-godot-port-design.md`](../specs/2026-08-09-godot-port-design.md)

## Global Constraints

Every task's requirements implicitly include this section.

- **Engine:** Godot 4.7.1.stable. Binary at `/home/tylermegill/.local/bin/godot`.
- **Language:** GDScript only. No C#, no addons, no external dependencies.
- **Purity rule:** No file under `sim/` or `data/` may reference `Node`, `get_tree()`, `preload`, `@onready`, `@export`, or any scene/visual type. Enforced by test in Task 13.
- **Time unit:** every `sim/` function takes and returns **milliseconds**. Callers convert with `delta * 1000.0`. This keeps `fire_rate: 1000` and `interval_ms: 500` transferable unchanged.
- **Renderer:** `gl_compatibility` for both desktop and mobile. No threads.
- **Determinism:** all randomness goes through `sim/rng.gd`. Never call `randf()`, `randi()`, or `RandomNumberGenerator`.
- **Ints:** GDScript ints are 64-bit signed; JS bitwise ops are 32-bit. Mask with `& 0xFFFFFFFF` after every arithmetic step when porting bitwise code.
- **Test command:** `godot --headless --quit --script test/run_tests.gd` from the project root. Exit 0 = pass, exit 1 = failure.
- **After adding any new `class_name`**, run `godot --headless --import` once before the tests, or the class will not resolve.
- **Reference source:** `reference/project-t/td-browser/` (cloned in Task 1, gitignored). All "port from" paths below are relative to it.
- **Commit** at the end of every task, only when its tests pass.

---

## File Structure

| Path | Responsibility |
|---|---|
| `project.godot` | Renderer, viewport, stretch, main scene |
| `test/case.gd` | `TestCase` base — assertions and failure collection |
| `test/run_tests.gd` | Headless discovery runner (`SceneTree`) |
| `test/test_*.gd` | One file per module under test |
| `data/tiles.gd` | `TILE_SIZE`, `TileKind` |
| `data/seeds.gd` | Default seeds |
| `data/demo_map.gd` | 23×14 grid generation |
| `data/maps.gd` | Map registry: budget, starting gold, next |
| `data/towers.gd` | `TOWER_DEFS` × 4 |
| `data/enemies.gd` | `ENEMY_DEFS` × 3 |
| `data/waves.gd` | Composition, scaling, spawn timing |
| `data/economy.gd` | Economy constants |
| `sim/rng.gd` | mulberry32, bit-exact with the JS |
| `sim/grid.gd` | Tile ↔ world conversion |
| `sim/pathfinder.gd` | BFS spawn→goal |
| `sim/movement.gd` | Path following |
| `sim/damage.gd` | Damage resolution |
| `sim/leak.gd` | Life cost of a leak |
| `sim/targeting.gd` | Target selection |
| `sim/economy.gd` | Currency and pricing arithmetic |
| `sim/harness.gd` | Headless fixed-timestep wave runner |
| `game/map_renderer.gd` | TileMapLayer + seeded decoration |
| `game/enemy.gd/.tscn` | Enemy view |
| `game/tower.gd/.tscn` | Tower view |
| `game/projectile.gd/.tscn` | Projectile view |
| `game/game_board.gd/.tscn` | Board owner: input, placement, waves |
| `ui/hud.gd/.tscn` | Gold, lives, wave |
| `ui/tower_panel.gd/.tscn` | Build buttons |
| `ui/main_menu.tscn`, `ui/game_over.tscn`, `ui/victory.tscn` | Flow |
| `audio/audio_manager.gd` | Autoload, sound playback |
| `tools/slice_atlas.gd` | One-shot atlas extraction (editor tool) |

---

## Task 1: Project scaffold and test harness

Everything downstream depends on this. The runner pattern below was verified working on 4.7.1 before this plan was written — discovery, failure diffs, and exit codes all confirmed.

**Files:**
- Create: `project.godot`, `.gitignore`, `test/case.gd`, `test/run_tests.gd`, `test/test_harness_selfcheck.gd`
- Clone: `reference/project-t`

**Interfaces:**
- Produces: `TestCase` with `assert_eq(actual, expected, msg)`, `assert_true(actual: bool, msg)`, `assert_false(actual: bool, msg)`, `assert_almost_eq(actual: float, expected: float, epsilon: float, msg)`, `check_count() -> int`, `failures() -> Array[String]`.

- [ ] **Step 1: Clone the reference source**

```bash
cd ~/Projects/project-t-godot
git clone --depth 1 https://github.com/Tmegill1/project-t.git reference/project-t
```

- [ ] **Step 2: Write `.gitignore`**

```
.godot/
reference/
*.tmp
export/
```

- [ ] **Step 3: Write `project.godot`**

Verified valid on 4.7.1. No main scene yet — that arrives in Task 21.

```ini
config_version=5

[application]
config/name="project-t-godot"
config/features=PackedStringArray("4.7", "GL Compatibility")

[display]
window/size/viewport_width=1104
window/size/viewport_height=672
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
```

- [ ] **Step 4: Write `test/case.gd`**

The filename must NOT match `test_*.gd`, or the runner will try to execute the base class itself.

```gdscript
class_name TestCase
extends RefCounted

var _failures: Array[String] = []
var _checks := 0

func check_count() -> int:
	return _checks

func failures() -> Array[String]:
	return _failures

func assert_eq(actual, expected, msg: String) -> void:
	_checks += 1
	if not _values_equal(actual, expected):
		_failures.append("%s\n      expected: %s\n      actual:   %s" % [msg, expected, actual])

func assert_true(actual: bool, msg: String) -> void:
	assert_eq(actual, true, msg)

func assert_false(actual: bool, msg: String) -> void:
	assert_eq(actual, false, msg)

func assert_almost_eq(actual: float, expected: float, epsilon: float, msg: String) -> void:
	_checks += 1
	if absf(actual - expected) > epsilon:
		_failures.append("%s\n      expected: %f (+/- %f)\n      actual:   %f" % [msg, expected, epsilon, actual])

func _values_equal(a, b) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b
```

- [ ] **Step 5: Write `test/run_tests.gd`**

```gdscript
extends SceneTree

func _initialize() -> void:
	var files := _discover("res://test")
	var checks := 0
	var failing_assertions := 0
	var failing_tests := 0

	for path in files:
		var script: GDScript = load(path)
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			case.call(test_name)
			checks += case.check_count()
			var fails := case.failures()
			if not fails.is_empty():
				failing_tests += 1
				failing_assertions += fails.size()
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				for f in fails:
					printerr("    " + f)

	print("%d checks across %d files | %d failing assertions in %d tests" % [
		checks, files.size(), failing_assertions, failing_tests])
	quit(1 if failing_assertions > 0 else 0)

func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
```

- [ ] **Step 6: Write a self-check test that must fail first**

`test/test_harness_selfcheck.gd`:

```gdscript
extends TestCase

func test_assertions_pass() -> void:
	assert_eq(2 + 2, 4, "arithmetic works")
	assert_true(true, "true is true")
	assert_almost_eq(0.1 + 0.2, 0.3, 0.0001, "floats compare with epsilon")
```

- [ ] **Step 7: Import, then run — expect PASS**

```bash
cd ~/Projects/project-t-godot
godot --headless --import
godot --headless --quit --script test/run_tests.gd
echo "exit=$?"
```

Expected: `3 checks across 1 files | 0 failing assertions in 0 tests`, `exit=0`.

- [ ] **Step 8: Verify the harness detects failure**

Temporarily change `assert_eq(2 + 2, 4, ...)` to `assert_eq(2 + 2, 5, ...)`, re-run.
Expected: a `FAIL test_harness_selfcheck.gd::test_assertions_pass` block showing `expected: 5 / actual: 4`, and `exit=1`. **Revert the change** and confirm exit 0 again.

This step is not optional. A test harness that cannot fail is worse than none.

- [ ] **Step 9: Commit**

```bash
git add .gitignore project.godot test/
git commit -m "Add Godot project scaffold and dependency-free test harness

Runner discovers test_*.gd recursively, executes test_* methods, prints
expected/actual diffs and exits non-zero on failure. Verified in both
directions before committing."
```

---

## Task 2: Seeded RNG

The single highest-risk port in the project. JS `Math.imul` and `>>>` are 32-bit; GDScript ints are 64-bit signed. The implementation below was verified bit-exact against the JS reference for seed 12345 across 8 draws, to 17 decimal places, before this plan was written. **Do not "simplify" the masking.**

**Files:**
- Create: `sim/rng.gd`, `test/test_rng.gd`
- Port from: `src/game/sim/rng.ts`

**Interfaces:**
- Produces: `Rng` (`RefCounted`) — `Rng.new(seed: int)`, `next() -> float` in [0,1), `int_range(lo: int, hi: int) -> int` inclusive both ends, `pick(items: Array)`, `shuffle(items: Array) -> Array` (non-mutating copy), `fork() -> Rng`.

Note the rename: `int` is a reserved word in GDScript, so `Rng.int(min,max)` becomes `int_range(lo,hi)`.

- [ ] **Step 1: Write the failing test**

`test/test_rng.gd`:

```gdscript
extends TestCase

# Golden values generated from the reference implementation in
# reference/project-t/td-browser/src/game/sim/rng.ts with seed 12345.
# If these ever change, map layouts diverge from the Phaser build.
const GOLDEN_12345 := [
	0.97972826776094735,
	0.30675226449966431,
	0.48420542152598500,
	0.81793441250920296,
	0.50942836934700608,
	0.34747186047025025,
	0.07375754183158278,
	0.76639646734111011,
]

func test_matches_javascript_reference() -> void:
	var r := Rng.new(12345)
	for i in GOLDEN_12345.size():
		assert_almost_eq(r.next(), GOLDEN_12345[i], 1e-15,
			"draw %d matches the JS mulberry32 stream" % i)

func test_same_seed_same_sequence() -> void:
	var a := Rng.new(777)
	var b := Rng.new(777)
	for i in 20:
		assert_almost_eq(a.next(), b.next(), 1e-15, "draw %d reproducible" % i)

func test_next_stays_in_unit_interval() -> void:
	var r := Rng.new(4242)
	for i in 500:
		var v := r.next()
		assert_true(v >= 0.0 and v < 1.0, "draw %d within [0,1)" % i)

func test_int_range_is_inclusive_both_ends() -> void:
	var r := Rng.new(9)
	var seen_lo := false
	var seen_hi := false
	for i in 400:
		var v := r.int_range(1, 3)
		assert_true(v >= 1 and v <= 3, "int_range stays in bounds")
		if v == 1:
			seen_lo = true
		if v == 3:
			seen_hi = true
	assert_true(seen_lo, "low bound is reachable")
	assert_true(seen_hi, "high bound is reachable")

func test_shuffle_does_not_mutate_input() -> void:
	var source := [1, 2, 3, 4, 5]
	var r := Rng.new(31337)
	var out := r.shuffle(source)
	assert_eq(source, [1, 2, 3, 4, 5], "input array untouched")
	assert_eq(out.size(), 5, "output has same length")
	out.sort()
	assert_eq(out, [1, 2, 3, 4, 5], "output is a permutation")

func test_fork_is_independent_and_reproducible() -> void:
	var parent_a := Rng.new(2024)
	var forked_a := parent_a.fork()
	var parent_b := Rng.new(2024)
	var forked_b := parent_b.fork()
	for i in 10:
		assert_almost_eq(forked_a.next(), forked_b.next(), 1e-15,
			"forked stream %d reproducible" % i)
```

- [ ] **Step 2: Run to verify it fails**

```bash
godot --headless --quit --script test/run_tests.gd
```
Expected: parse error, `Identifier "Rng" not declared`.

- [ ] **Step 3: Implement `sim/rng.gd`**

```gdscript
class_name Rng
extends RefCounted

## Seeded mulberry32, bit-exact with the JavaScript original.
##
## GDScript ints are 64-bit signed and JS bitwise operators are 32-bit, so
## every arithmetic step is masked back to 32 bits. The multiplications
## overflow int64 and wrap; that is fine and intended, because two's-complement
## wrapping preserves the low 32 bits, which is all the algorithm reads.
## Verified against the JS reference for seed 12345 to 17 decimal places.

const MASK := 0xFFFFFFFF

var _state: int

func _init(seed_value: int) -> void:
	_state = seed_value & MASK

## Next value in [0, 1).
func next() -> float:
	_state = (_state + 0x6d2b79f5) & MASK
	var t := _state
	t = ((t ^ (t >> 15)) * (t | 1)) & MASK
	t = (t ^ (t + (((t ^ (t >> 7)) * (t | 61)) & MASK))) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

## Integer in [lo, hi], both inclusive.
func int_range(lo: int, hi: int) -> int:
	if hi < lo:
		var swap := lo
		lo = hi
		hi = swap
	return lo + int(next() * float(hi - lo + 1))

## A uniformly chosen element. Returns null on an empty array.
func pick(items: Array):
	if items.is_empty():
		push_error("Rng.pick: cannot choose from an empty array")
		return null
	return items[int(next() * float(items.size()))]

## A shuffled copy. Fisher-Yates; does not mutate the input.
func shuffle(items: Array) -> Array:
	var out := items.duplicate()
	var i := out.size() - 1
	while i > 0:
		var j := int(next() * float(i + 1))
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
		i -= 1
	return out

## An independent generator seeded from this one's stream. Forking lets a
## subsystem draw freely without shifting anyone else's sequence.
func fork() -> Rng:
	return Rng.new(int(next() * 4294967296.0))
```

- [ ] **Step 4: Import and run — expect PASS**

```bash
godot --headless --import
godot --headless --quit --script test/run_tests.gd
```

- [ ] **Step 5: Commit**

```bash
git add sim/rng.gd test/test_rng.gd
git commit -m "Add seeded RNG, bit-exact with the JS mulberry32

Golden-value test pins the stream against the reference implementation.
If it ever fails, generated map layouts have diverged from the Phaser build."
```

---

## Task 3: Tiles and grid conversion

**Files:**
- Create: `data/tiles.gd`, `sim/grid.gd`, `test/test_grid.gd`
- Port from: `src/game/data/tiles.ts`, `src/game/map/Grid.ts`

**Interfaces:**
- Produces: `Tiles.TILE_SIZE` (int, 48); `Tiles.BUILDABLE/PATH/BLOCKED/SPAWN/GOAL` (StringName constants). `Grid.set_active(cols: int, rows: int, tile_size: int = Tiles.TILE_SIZE)`, `Grid.get_active() -> Dictionary` with keys `cols`/`rows`/`tile_size`, `Grid.tile_to_world_center(col: int, row: int) -> Vector2`, `Grid.world_to_tile(x: float, y: float) -> Dictionary` with keys `col`/`row`/`in_bounds`.

`Grid` keeps active dimensions as static state, matching the original's rationale: there is only ever one map loaded, and threading a map through every pointer handler buys nothing.

- [ ] **Step 1: Write the failing test**

`test/test_grid.gd`:

```gdscript
extends TestCase

func test_tile_size_is_48() -> void:
	assert_eq(Tiles.TILE_SIZE, 48, "tile size matches the Phaser build")

func test_tile_to_world_returns_tile_centre() -> void:
	Grid.set_active(23, 14)
	assert_eq(Grid.tile_to_world_center(0, 0), Vector2(24, 24), "first tile centre")
	assert_eq(Grid.tile_to_world_center(2, 3), Vector2(120, 168), "arbitrary tile centre")

func test_world_to_tile_floors() -> void:
	Grid.set_active(23, 14)
	var t := Grid.world_to_tile(100.0, 100.0)
	assert_eq(t["col"], 2, "col floors")
	assert_eq(t["row"], 2, "row floors")
	assert_true(t["in_bounds"], "inside the board")

func test_world_to_tile_reports_out_of_bounds() -> void:
	Grid.set_active(23, 14)
	assert_false(Grid.world_to_tile(-1.0, 10.0)["in_bounds"], "negative x is out")
	assert_false(Grid.world_to_tile(23 * 48.0, 10.0)["in_bounds"], "past last column is out")
	assert_false(Grid.world_to_tile(10.0, 14 * 48.0)["in_bounds"], "past last row is out")

# The original's Grid imported the FIRST map's dimensions and used them no
# matter which map was loaded, so 30% of the larger map silently rejected
# every click. set_active is what prevents that; this test is the guard.
func test_bounds_follow_the_active_map() -> void:
	Grid.set_active(26, 17)
	var t := Grid.world_to_tile(25 * 48.0 + 5.0, 16 * 48.0 + 5.0)
	assert_eq(t["col"], 25, "col on the larger board")
	assert_eq(t["row"], 16, "row on the larger board")
	assert_true(t["in_bounds"], "the outer band of a larger map is usable")
	Grid.set_active(23, 14)
	assert_false(Grid.world_to_tile(25 * 48.0 + 5.0, 16 * 48.0 + 5.0)["in_bounds"],
		"same point is out of bounds on the smaller board")
```

- [ ] **Step 2: Run to verify it fails**

Expected: `Identifier "Tiles" not declared`.

- [ ] **Step 3: Implement `data/tiles.gd`**

```gdscript
class_name Tiles

## The tile vocabulary, in one place. Every map shares TILE_SIZE.

const TILE_SIZE := 48

const BUILDABLE := &"buildable"
const PATH := &"path"
const BLOCKED := &"blocked"
const SPAWN := &"spawn"
const GOAL := &"goal"

## Tiles an enemy may walk over.
const WALKABLE: Array[StringName] = [PATH, SPAWN, GOAL]
```

- [ ] **Step 4: Implement `sim/grid.gd`**

```gdscript
class_name Grid

## Tile <-> world-pixel conversion for whichever map is loaded.
##
## Active dimensions are static state rather than a parameter: there is only
## ever one map loaded, and threading it through every caller buys nothing.
## Call set_active() before anything reads a tile coordinate.

static var _cols := 23
static var _rows := 14
static var _tile_size := Tiles.TILE_SIZE

static func set_active(cols: int, rows: int, tile_size: int = Tiles.TILE_SIZE) -> void:
	_cols = cols
	_rows = rows
	_tile_size = tile_size

static func get_active() -> Dictionary:
	return {"cols": _cols, "rows": _rows, "tile_size": _tile_size}

static func tile_to_world_center(col: int, row: int) -> Vector2:
	var half := float(_tile_size) / 2.0
	return Vector2(float(col * _tile_size) + half, float(row * _tile_size) + half)

static func world_to_tile(x: float, y: float) -> Dictionary:
	var col := int(floor(x / float(_tile_size)))
	var row := int(floor(y / float(_tile_size)))
	return {
		"col": col,
		"row": row,
		"in_bounds": col >= 0 and col < _cols and row >= 0 and row < _rows,
	}
```

- [ ] **Step 5: Import, run — expect PASS**

- [ ] **Step 6: Commit**

```bash
git add data/tiles.gd sim/grid.gd test/test_grid.gd
git commit -m "Add tile vocabulary and grid conversion

set_active makes bounds follow the loaded map, fixing by construction the
original's bug where a larger map's outer band rejected every click."
```

---

## Task 4: Map generation

**Files:**
- Create: `data/seeds.gd`, `data/demo_map.gd`, `test/test_demo_map.gd`
- Port from: `src/game/data/seeds.ts`, `src/game/data/demoMap.ts`

**Interfaces:**
- Produces: `Seeds.DEFAULT_DEMO_MAP_SEED` (20260804), `Seeds.DEFAULT_DECORATION_SEED` (771144). `DemoMap.GRID_COLS` (23), `DemoMap.GRID_ROWS` (14), `DemoMap.build(rng: Rng = null) -> Array` — an `Array` of `GRID_ROWS` rows, each an `Array` of `GRID_COLS` `StringName` tile kinds.

Draw order inside `build` is load-bearing: adjacent tiles are shuffled before distant ones, from the same stream. Reordering changes the layout.

- [ ] **Step 1: Write the failing test**

`test/test_demo_map.gd`:

```gdscript
extends TestCase

func _build() -> Array:
	return DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))

func test_dimensions() -> void:
	var m := _build()
	assert_eq(m.size(), 14, "14 rows")
	assert_eq(m[0].size(), 23, "23 columns")

func test_has_exactly_one_spawn_and_one_goal() -> void:
	var m := _build()
	var spawns := 0
	var goals := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] == Tiles.SPAWN:
				spawns += 1
			elif m[r][c] == Tiles.GOAL:
				goals += 1
	assert_eq(spawns, 1, "one spawn")
	assert_eq(goals, 1, "one goal")

func test_spawn_and_goal_positions() -> void:
	var m := _build()
	assert_eq(m[4][0], Tiles.SPAWN, "spawn at row 4, col 0")
	assert_eq(m[10][21], Tiles.GOAL, "goal at row 10, col 21")

func test_path_runs_where_authored() -> void:
	var m := _build()
	# First leg: row 4, columns 1..16 (column 0 is the spawn).
	for c in range(1, 17):
		assert_eq(m[4][c], Tiles.PATH, "row 4 col %d is path" % c)
	# Second leg: column 16, rows 5..7. Indexing is map[row][col].
	for r in range(5, 8):
		assert_eq(m[r][16], Tiles.PATH, "col 16 row %d is path" % r)
	# Final leg: row 10, columns 4..20 (21 is the goal).
	for c in range(4, 21):
		assert_eq(m[10][c], Tiles.PATH, "row 10 col %d is path" % c)

func test_spawn_and_goal_surroundings_are_blocked() -> void:
	var m := _build()
	for r in range(3, 6):
		for c in range(0, 3):
			assert_true(m[r][c] == Tiles.BLOCKED or m[r][c] == Tiles.SPAWN or m[r][c] == Tiles.PATH,
				"tile (%d,%d) near spawn is not buildable" % [r, c])
	for r in range(9, 12):
		for c in range(20, 23):
			assert_true(m[r][c] != Tiles.BUILDABLE,
				"tile (%d,%d) near goal is not buildable" % [r, c])

func test_blocked_scatter_is_capped_at_twelve() -> void:
	var m := _build()
	var scattered := 0
	for r in m.size():
		for c in m[r].size():
			if m[r][c] != Tiles.BLOCKED:
				continue
			var near_spawn := r >= 3 and r <= 5 and c <= 2
			var near_goal := r >= 9 and r <= 11 and c >= 20 and c <= 22
			if not near_spawn and not near_goal:
				scattered += 1
	assert_true(scattered <= 12, "at most 12 scattered blocked tiles, got %d" % scattered)

func test_top_row_and_last_column_are_never_scatter_blocked() -> void:
	var m := _build()
	for c in 23:
		assert_true(m[0][c] != Tiles.BLOCKED, "row 0 reserved for UI, col %d" % c)
	for r in 14:
		if r >= 9 and r <= 11:
			continue  # the goal surround legitimately blocks column 22
		assert_true(m[r][22] != Tiles.BLOCKED, "last column reserved, row %d" % r)

func test_same_seed_same_map() -> void:
	var a := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	var b := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	assert_eq(a, b, "generation is reproducible")

func test_different_seed_different_map() -> void:
	var a := DemoMap.build(Rng.new(1))
	var b := DemoMap.build(Rng.new(2))
	assert_false(a == b, "a different seed scatters differently")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `data/seeds.gd`**

```gdscript
class_name Seeds

## Default seeds for the game's random systems.
##
## Map generation used to call unseeded random at module load, so blocked
## tiles landed differently on every page load. Blocked tiles remove build
## space, so that was gameplay randomness that could not be reproduced.

const DEFAULT_DEMO_MAP_SEED := 20260804
const DEFAULT_MAP2_SEED := 20260805
const DEFAULT_MAP3_SEED := 20260806
const DEFAULT_DECORATION_SEED := 771144
```

- [ ] **Step 4: Implement `data/demo_map.gd`**

```gdscript
class_name DemoMap

## Builds "The Pass" — the 23x14 first map.
##
## Takes an Rng so the blocked-tile layout is reproducible. Draw order is
## load-bearing: adjacent tiles are shuffled before distant ones, from the
## same stream, exactly as the TypeScript does.

const GRID_COLS := 23
const GRID_ROWS := 14

const MAX_ADJACENT_BLOCKED := 5
const MAX_DISTANT_BLOCKED := 7
const MAX_TOTAL_BLOCKED := 12

static func build(rng: Rng = null) -> Array:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED)

	var map: Array = []
	for r in GRID_ROWS:
		var row: Array = []
		for c in GRID_COLS:
			row.append(Tiles.BUILDABLE)
		map.append(row)

	# Path legs, authored as [col, row] pairs.
	var path_coords: Array[Vector2i] = []
	for c in range(0, 17):
		path_coords.append(Vector2i(c, 4))
	for r in range(4, 8):
		path_coords.append(Vector2i(16, r))
	for c in range(16, 3, -1):
		path_coords.append(Vector2i(c, 8))
	for r in range(8, 11):
		path_coords.append(Vector2i(4, r))
	for c in range(4, GRID_COLS - 1):
		path_coords.append(Vector2i(c, 10))

	var path_set := {}
	for coord in path_coords:
		map[coord.y][coord.x] = Tiles.PATH
		path_set[Vector2i(coord.x, coord.y)] = true

	map[4][0] = Tiles.SPAWN
	map[10][GRID_COLS - 2] = Tiles.GOAL

	# The spawn and goal sprites are drawn 3x3, so the tiles they cover are
	# blocked rather than left buildable underneath the artwork.
	for r in range(3, 6):
		for c in range(0, 3):
			if r >= 0 and r < GRID_ROWS and c < GRID_COLS and map[r][c] == Tiles.BUILDABLE:
				map[r][c] = Tiles.BLOCKED

	var goal_row := 10
	var goal_col := GRID_COLS - 2
	for r in range(goal_row - 1, goal_row + 2):
		for c in range(goal_col - 1, goal_col + 2):
			if r >= 0 and r < GRID_ROWS and c >= 0 and c < GRID_COLS and map[r][c] == Tiles.BUILDABLE:
				map[r][c] = Tiles.BLOCKED

	# Scatter. Row 0 is reserved for UI; the last column for the tower menu.
	var adjacent: Array = []
	var distant: Array = []
	for r in GRID_ROWS:
		for c in GRID_COLS:
			if map[r][c] != Tiles.BUILDABLE:
				continue
			if r == 0 or c == GRID_COLS - 1:
				continue
			if _is_adjacent_to_path(r, c, path_set):
				adjacent.append(Vector2i(c, r))
			else:
				distant.append(Vector2i(c, r))

	var shuffled_adjacent := rng.shuffle(adjacent)
	var shuffled_distant := rng.shuffle(distant)

	var blocked_count := 0
	var adjacent_blocked: int = mini(MAX_ADJACENT_BLOCKED, shuffled_adjacent.size())
	for i in adjacent_blocked:
		var t: Vector2i = shuffled_adjacent[i]
		map[t.y][t.x] = Tiles.BLOCKED
		blocked_count += 1

	var remaining := MAX_TOTAL_BLOCKED - blocked_count
	var distant_blocked: int = mini(MAX_DISTANT_BLOCKED, mini(shuffled_distant.size(), remaining))
	for i in distant_blocked:
		var t: Vector2i = shuffled_distant[i]
		map[t.y][t.x] = Tiles.BLOCKED

	return map

static func _is_adjacent_to_path(row: int, col: int, path_set: Dictionary) -> bool:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nr := row + d.y
		var nc := col + d.x
		if nr < 0 or nr >= GRID_ROWS or nc < 0 or nc >= GRID_COLS:
			continue
		if path_set.has(Vector2i(nc, nr)):
			return true
	return false
```

- [ ] **Step 5: Import, run — expect PASS**

If `test_path_runs_where_authored` fails on the second leg, note that the third leg (row 8, columns 4..16) overwrites part of the board and the legs intersect; verify against `reference/project-t/td-browser/src/game/data/demoMap.ts` lines 40–48 rather than adjusting the test to fit.

- [ ] **Step 6: Commit**

```bash
git add data/seeds.gd data/demo_map.gd test/test_demo_map.gd
git commit -m "Add seeded generation for The Pass

Draw order (adjacent shuffled before distant, one stream) is load-bearing
and pinned by a reproducibility test."
```

---

## Task 5: Pathfinding

**Files:**
- Create: `sim/pathfinder.gd`, `test/test_pathfinder.gd`
- Port from: `src/game/map/PathFinder.ts`

**Interfaces:**
- Produces: `PathFinder.get_all_spawn_paths(map: Array) -> Array[PackedVector2Array]` — one world-space path per spawn tile, each starting at the spawn's centre and ending at the goal's centre. `PathFinder.get_path_from_spawn_to_goal(map: Array) -> PackedVector2Array` — the first such path.

BFS walks only `path`/`spawn`/`goal` tiles, 4-connected.

- [ ] **Step 1: Write the failing test**

`test/test_pathfinder.gd`:

```gdscript
extends TestCase

func _tiny_map() -> Array:
	# 3 rows x 4 cols:  S P P G
	var blank := [
		[Tiles.SPAWN, Tiles.PATH, Tiles.PATH, Tiles.GOAL],
		[Tiles.BUILDABLE, Tiles.BUILDABLE, Tiles.BUILDABLE, Tiles.BUILDABLE],
		[Tiles.BUILDABLE, Tiles.BLOCKED, Tiles.BUILDABLE, Tiles.BUILDABLE],
	]
	return blank

func test_finds_path_on_a_tiny_map() -> void:
	Grid.set_active(4, 3)
	var paths := PathFinder.get_all_spawn_paths(_tiny_map())
	assert_eq(paths.size(), 1, "one spawn, one path")
	var p: PackedVector2Array = paths[0]
	assert_eq(p.size(), 4, "spawn plus three walked tiles")
	assert_eq(p[0], Grid.tile_to_world_center(0, 0), "starts at the spawn centre")
	assert_eq(p[p.size() - 1], Grid.tile_to_world_center(3, 0), "ends at the goal centre")

func test_path_does_not_enter_non_walkable_tiles() -> void:
	Grid.set_active(4, 3)
	var p: PackedVector2Array = PathFinder.get_all_spawn_paths(_tiny_map())[0]
	for point in p:
		var t := Grid.world_to_tile(point.x, point.y)
		var kind = _tiny_map()[t["row"]][t["col"]]
		assert_true(kind in Tiles.WALKABLE, "point %s is on a walkable tile" % point)

func test_real_map_path_is_connected_and_reaches_goal() -> void:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	var map := DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
	var paths := PathFinder.get_all_spawn_paths(map)
	assert_eq(paths.size(), 1, "The Pass has one spawn")
	var p: PackedVector2Array = paths[0]
	assert_true(p.size() > 20, "the route is long, got %d points" % p.size())
	assert_eq(p[0], Grid.tile_to_world_center(0, 4), "starts at the spawn")
	assert_eq(p[p.size() - 1], Grid.tile_to_world_center(21, 10), "ends at the goal")
	# Consecutive points must be exactly one tile apart.
	for i in range(1, p.size()):
		var step := (p[i] - p[i - 1]).length()
		assert_almost_eq(step, float(Tiles.TILE_SIZE), 0.001,
			"step %d is one tile" % i)

func test_returns_empty_when_no_spawn() -> void:
	Grid.set_active(2, 1)
	var no_spawn := [[Tiles.BUILDABLE, Tiles.GOAL]]
	assert_eq(PathFinder.get_all_spawn_paths(no_spawn).size(), 0, "no spawn, no paths")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/pathfinder.gd`**

```gdscript
class_name PathFinder

## BFS from each spawn tile to the goal, over walkable tiles only.
## Returns world-space paths; the first point is the spawn centre.

static func get_path_from_spawn_to_goal(map: Array) -> PackedVector2Array:
	var all := get_all_spawn_paths(map)
	return all[0] if all.size() > 0 else PackedVector2Array()

static func get_all_spawn_paths(map: Array) -> Array[PackedVector2Array]:
	var results: Array[PackedVector2Array] = []
	var rows := map.size()
	if rows == 0:
		return results
	var cols: int = map[0].size()

	var spawns: Array[Vector2i] = []
	var goal := Vector2i(-1, -1)
	for r in rows:
		for c in cols:
			if map[r][c] == Tiles.SPAWN:
				spawns.append(Vector2i(c, r))
			elif map[r][c] == Tiles.GOAL:
				goal = Vector2i(c, r)

	if spawns.is_empty() or goal.x < 0:
		return results

	for spawn in spawns:
		var tiles := _bfs(spawn, goal, map, rows, cols)
		var path := PackedVector2Array()
		path.append(Grid.tile_to_world_center(spawn.x, spawn.y))
		for t in tiles:
			path.append(Grid.tile_to_world_center(t.x, t.y))
		results.append(path)

	return results

static func _bfs(start: Vector2i, goal: Vector2i, map: Array, rows: int, cols: int) -> Array[Vector2i]:
	var visited := {start: true}
	var queue: Array = [[start, [] as Array[Vector2i]]]
	var directions := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

	while not queue.is_empty():
		var entry = queue.pop_front()
		var current: Vector2i = entry[0]
		var trail: Array[Vector2i] = entry[1]

		if current == goal:
			return trail

		for d in directions:
			var nxt := current + d
			if nxt.x < 0 or nxt.x >= cols or nxt.y < 0 or nxt.y >= rows:
				continue
			if visited.has(nxt):
				continue
			if not (map[nxt.y][nxt.x] in Tiles.WALKABLE):
				continue
			visited[nxt] = true
			var extended := trail.duplicate()
			extended.append(nxt)
			queue.append([nxt, extended])

	return [] as Array[Vector2i]
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/pathfinder.gd test/test_pathfinder.gd
git commit -m "Add BFS pathfinding over walkable tiles"
```

---

## Task 6: Enemy, tower and economy data tables

Every number here is asserted in a test, mirroring the original's rule that extraction must not silently move a value.

**Files:**
- Create: `data/enemies.gd`, `data/towers.gd`, `data/economy.gd`, `data/maps.gd`, `test/test_data_tables.gd`
- Port from: `src/game/data/enemies.ts`, `towers.ts`, `economy.ts`, `maps.ts`

**Interfaces:**
- Produces:
  - `Enemies.DEFS: Dictionary` keyed by `&"slime"/&"ogre"/&"bee"`; each value has `label, base_speed, base_health, reward, life_loss, texture_key, sprite_scale, flip_horizontally`. `Enemies.scaled_health(kind, modifier) -> int`, `Enemies.scaled_speed(kind, modifier) -> float`.
  - `Towers.DEFS: Dictionary` keyed by `&"basic"/&"fast"/&"mortar"/&"long"`; each value has `label, cost, cost_escalation, range, fire_rate, damage, pierce, detection, base_splash_radius, projectile_speed, projectile_arcs, color, size, sprite_frame, upgrade_frames, base_limit, limit_bonus_map2`. `Towers.KINDS: Array[StringName]` in display order.
  - `Economy.STARTING_LIVES` (20), `Economy.SELL_REFUND_FRACTION` (0.5).
  - `Maps.DEFS: Dictionary`; `Maps.FIRST` (`&"demoMap"`); `Maps.get_def(name) -> Dictionary` with `label, cols, rows, tile_size, tower_budget, starting_gold, next`.

- [ ] **Step 1: Write the failing test**

`test/test_data_tables.gd`:

```gdscript
extends TestCase

func test_enemy_stats_match_the_phaser_build() -> void:
	var slime: Dictionary = Enemies.DEFS[&"slime"]
	assert_eq(slime["base_speed"], 100.0, "slime speed")
	assert_eq(slime["base_health"], 5, "slime health")
	assert_eq(slime["reward"], 5, "slime reward")
	assert_eq(slime["life_loss"], 1, "slime leak cost")

	var ogre: Dictionary = Enemies.DEFS[&"ogre"]
	assert_eq(ogre["base_speed"], 60.0, "ogre speed")
	assert_eq(ogre["base_health"], 8, "ogre health")
	assert_eq(ogre["reward"], 20, "ogre reward")
	assert_eq(ogre["life_loss"], 5, "ogre leak cost")
	assert_eq(ogre["sprite_scale"], 1.2, "ogre is larger than the others")
	assert_true(ogre["flip_horizontally"], "ogre artwork faces the wrong way")

	var bee: Dictionary = Enemies.DEFS[&"bee"]
	assert_eq(bee["base_speed"], 150.0, "bee speed")
	assert_eq(bee["base_health"], 3, "bee health")
	assert_eq(bee["reward"], 10, "bee reward")
	assert_eq(bee["life_loss"], 2, "bee leak cost")

func test_scaled_health_floors_and_clamps_to_one() -> void:
	assert_eq(Enemies.scaled_health(&"slime", 1.0), 5, "unmodified")
	assert_eq(Enemies.scaled_health(&"slime", 1.5), 7, "7.5 floors to 7")
	assert_eq(Enemies.scaled_health(&"slime", 0.0), 1, "never below one")

func test_scaled_speed_is_unrounded_and_clamps_to_one() -> void:
	assert_almost_eq(Enemies.scaled_speed(&"ogre", 1.05), 63.0, 0.001, "unrounded")
	assert_almost_eq(Enemies.scaled_speed(&"ogre", 0.0), 1.0, 0.001, "never below one")

func test_tower_stats_match_the_phaser_build() -> void:
	var expected := {
		&"basic":  {"cost": 20,  "cost_escalation": 10, "range": 100.0, "fire_rate": 1000.0, "damage": 4,  "base_splash_radius": 0.0,  "base_limit": 8},
		&"fast":   {"cost": 50,  "cost_escalation": 15, "range": 80.0,  "fire_rate": 500.0,  "damage": 2,  "base_splash_radius": 0.0,  "base_limit": 8},
		&"mortar": {"cost": 70,  "cost_escalation": 35, "range": 120.0, "fire_rate": 2000.0, "damage": 5,  "base_splash_radius": 55.0, "base_limit": 5},
		&"long":   {"cost": 100, "cost_escalation": 50, "range": 150.0, "fire_rate": 1500.0, "damage": 15, "base_splash_radius": 0.0,  "base_limit": 5},
	}
	for kind in expected.keys():
		var def: Dictionary = Towers.DEFS[kind]
		for field in expected[kind].keys():
			assert_eq(def[field], expected[kind][field], "%s.%s" % [kind, field])

func test_only_the_mortar_has_splash_and_arcing_shots() -> void:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		var is_mortar := kind == &"mortar"
		assert_eq(def["base_splash_radius"] > 0.0, is_mortar, "%s splash" % kind)
		assert_eq(def["projectile_arcs"], is_mortar, "%s arcing" % kind)

func test_no_base_tower_has_pierce_or_detection() -> void:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		assert_eq(def["pierce"], 0, "%s pierce is earned, not given" % kind)
		assert_false(def["detection"], "%s detection is earned, not given" % kind)

func test_economy_constants() -> void:
	assert_eq(Economy.STARTING_LIVES, 20, "twenty lives")
	assert_eq(Economy.SELL_REFUND_FRACTION, 0.5, "half back on sale")

func test_first_map_definition() -> void:
	var m := Maps.get_def(Maps.FIRST)
	assert_eq(m["label"], "The Pass", "map label")
	assert_eq(m["cols"], 23, "columns")
	assert_eq(m["rows"], 14, "rows")
	assert_eq(m["tower_budget"], 16, "tower budget")
	assert_eq(m["starting_gold"], 100, "starting gold")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement the four data files**

`data/enemies.gd`:

```gdscript
class_name Enemies

const DEFS := {
	&"slime": {
		"label": "Slime", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "texture_key": "slime", "sprite_scale": 0.7,
		"flip_horizontally": false,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 60.0, "base_health": 8, "reward": 20,
		"life_loss": 5, "texture_key": "ogre", "sprite_scale": 1.2,
		"flip_horizontally": true,
	},
	&"bee": {
		"label": "Bee", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "texture_key": "bee", "sprite_scale": 0.7,
		"flip_horizontally": false,
	},
}

const KINDS: Array[StringName] = [&"slime", &"ogre", &"bee"]

## Health for a spawn, applying the wave modifier. Floors, never below one.
static func scaled_health(kind: StringName, health_modifier: float) -> int:
	return maxi(1, int(floor(float(DEFS[kind]["base_health"]) * health_modifier)))

## Speed for a spawn, applying the wave modifier. Unrounded, never below one.
static func scaled_speed(kind: StringName, speed_modifier: float) -> float:
	return maxf(1.0, float(DEFS[kind]["base_speed"]) * speed_modifier)
```

`data/towers.gd` — transcribe every field from `reference/project-t/td-browser/src/game/data/towers.ts` lines 109–208, snake_cased. The test above pins the numeric fields; `label`, `color`, `size`, `sprite_frame` and `upgrade_frames` must also be carried across:

```gdscript
class_name Towers

const DEFS := {
	&"basic": {
		"label": "Basic", "cost": 20, "cost_escalation": 10, "range": 100.0,
		"fire_rate": 1000.0, "damage": 4, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0x66, 0xff),
		"size": 0.8, "sprite_frame": 8, "upgrade_frames": [8, 9, 11, 17],
		"base_limit": 8, "limit_bonus_map2": 2,
	},
	&"fast": {
		"label": "Fast", "cost": 50, "cost_escalation": 15, "range": 80.0,
		"fire_rate": 500.0, "damage": 2, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0xff, 0x00),
		"size": 0.75, "sprite_frame": 1, "upgrade_frames": [1, 0, 7, 16],
		"base_limit": 8, "limit_bonus_map2": 2,
	},
	&"mortar": {
		"label": "Mortar", "cost": 70, "cost_escalation": 35, "range": 120.0,
		"fire_rate": 2000.0, "damage": 5, "pierce": 0, "detection": false,
		"base_splash_radius": 55.0, "projectile_speed": 350.0,
		"projectile_arcs": true, "color": Color8(0xb0, 0x7a, 0x3a),
		"size": 0.85, "sprite_frame": 5, "upgrade_frames": [5, 6, 12, 13],
		"base_limit": 5, "limit_bonus_map2": 2,
	},
	&"long": {
		"label": "Long Range", "cost": 100, "cost_escalation": 50, "range": 150.0,
		"fire_rate": 1500.0, "damage": 15, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0xff, 0x66, 0x00),
		"size": 0.85, "sprite_frame": 2, "upgrade_frames": [2, 10, 18, 19],
		"base_limit": 5, "limit_bonus_map2": 2,
	},
}

const KINDS: Array[StringName] = [&"basic", &"fast", &"mortar", &"long"]

static func get_def(kind: StringName) -> Dictionary:
	return DEFS[kind]
```

`data/economy.gd`:

```gdscript
class_name Economy

## Every tunable economy number for the core slice, in one place.
## Wave-clear bonus, call-early and interest belong to the later phase that
## introduced them and are deliberately absent.

const STARTING_LIVES := 20
const SELL_REFUND_FRACTION := 0.5
```

`data/maps.gd`:

```gdscript
class_name Maps

const FIRST := &"demoMap"

const DEFS := {
	&"demoMap": {
		"label": "The Pass",
		"cols": 23, "rows": 14, "tile_size": 48,
		"tower_budget": 16, "starting_gold": 100,
		"next": &"map2",
	},
}

static func get_def(name: StringName) -> Dictionary:
	return DEFS[name]

## Tiles for a map, generated with its default seed.
static func build_tiles(name: StringName) -> Array:
	match name:
		&"demoMap":
			return DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED))
		_:
			push_error("Maps.build_tiles: unknown map %s" % name)
			return []

## Canvas size a map needs, in pixels.
static func pixel_size(name: StringName) -> Vector2i:
	var d: Dictionary = DEFS[name]
	return Vector2i(d["cols"] * d["tile_size"], d["rows"] * d["tile_size"])
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add data/enemies.gd data/towers.gd data/economy.gd data/maps.gd test/test_data_tables.gd
git commit -m "Add enemy, tower, economy and map data tables

Every value asserted against the Phaser build so extraction cannot
silently move a number."
```

---

## Task 7: Wave composition and scaling

**Files:**
- Create: `data/waves.gd`, `test/test_waves.gd`
- Port from: `src/game/data/waves.ts`

**Interfaces:**
- Produces: `Waves.MAX_WAVES` (20); `Waves.get_composition(wave: int) -> Array[Dictionary]` with `kind`/`count`; `Waves.get_modifiers(wave: int) -> Dictionary` with `health_modifier`/`speed_modifier`; `Waves.ogre_spawn_delay(slime_count: int) -> float`; `Waves.INTERVAL_MS` (500.0), `Waves.BEE_START_DELAY_MS` (5000.0).

Enemy properties are out of slice, so `propertiesFor` is **not** ported.

- [ ] **Step 1: Write the failing test**

`test/test_waves.gd`:

```gdscript
extends TestCase

func _count_of(wave: int, kind: StringName) -> int:
	for entry in Waves.get_composition(wave):
		if entry["kind"] == kind:
			return entry["count"]
	return 0

func test_max_waves_is_twenty() -> void:
	assert_eq(Waves.MAX_WAVES, 20, "victory at wave 20")

func test_wave_one_is_five_slimes() -> void:
	assert_eq(_count_of(1, &"slime"), 5, "five slimes")
	assert_eq(_count_of(1, &"bee"), 0, "no bees yet")
	assert_eq(_count_of(1, &"ogre"), 0, "no ogres yet")

# Composition ACCUMULATES from wave 1, so wave 3 contains waves 1 and 2 too.
# This is surprising and is preserved deliberately.
func test_composition_accumulates_from_wave_one() -> void:
	assert_eq(_count_of(2, &"slime"), 8, "5 + 3")
	assert_eq(_count_of(2, &"bee"), 3, "0 + 3")
	assert_eq(_count_of(3, &"slime"), 11, "5 + 3 + 3")
	assert_eq(_count_of(3, &"bee"), 6, "3 + 3")

func test_ogres_arrive_at_wave_four() -> void:
	assert_eq(_count_of(3, &"ogre"), 0, "no ogres at wave 3")
	assert_eq(_count_of(4, &"ogre"), 2, "two ogres at wave 4")

func test_wave_five_totals() -> void:
	assert_eq(_count_of(5, &"slime"), 14, "5+3+3+0+3")
	assert_eq(_count_of(5, &"bee"), 9, "3+3+0+3")
	assert_eq(_count_of(5, &"ogre"), 3, "2+1")

func test_beyond_wave_five_adds_a_fixed_bundle() -> void:
	assert_eq(_count_of(6, &"slime"), 16, "14 + 2")
	assert_eq(_count_of(6, &"bee"), 14, "9 + 5")
	assert_eq(_count_of(6, &"ogre"), 5, "3 + 2")
	assert_eq(_count_of(7, &"slime"), 18, "two bundles past wave 5")

func test_modifiers_are_flat_through_wave_five() -> void:
	for w in range(1, 6):
		var m := Waves.get_modifiers(w)
		assert_almost_eq(m["health_modifier"], 1.0, 0.0001, "wave %d health flat" % w)
		assert_almost_eq(m["speed_modifier"], 1.0, 0.0001, "wave %d speed flat" % w)

func test_modifiers_scale_past_wave_five() -> void:
	var m10 := Waves.get_modifiers(10)
	assert_almost_eq(m10["health_modifier"], 1.5, 0.0001, "wave 10 health +50%")
	assert_almost_eq(m10["speed_modifier"], 1.25, 0.0001, "wave 10 speed +25%")
	var m20 := Waves.get_modifiers(20)
	assert_almost_eq(m20["health_modifier"], 2.5, 0.0001, "wave 20 health +150%")
	assert_almost_eq(m20["speed_modifier"], 1.75, 0.0001, "wave 20 speed +75%")

func test_ogre_delay_trails_the_last_slime_but_is_capped() -> void:
	assert_almost_eq(Waves.ogre_spawn_delay(5), 5000.0, 0.001, "4*500 + 3000")
	assert_almost_eq(Waves.ogre_spawn_delay(30), 10000.0, 0.001, "capped at 10s")

func test_composition_returns_fresh_objects() -> void:
	var a := Waves.get_composition(5)
	a[0]["count"] = 999
	var b := Waves.get_composition(5)
	assert_false(b[0]["count"] == 999, "callers cannot corrupt later waves")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `data/waves.gd`**

```gdscript
class_name Waves

## Wave composition, difficulty scaling, and spawn scheduling.
##
## Composition ACCUMULATES: a wave's contents are the sum of the additions
## table from wave 1 up to it, so wave 3 contains waves 1 and 2 as well.
## That is how the game has always behaved.

const MAX_WAVES := 20
const LAST_AUTHORED_WAVE := 5

const _ADDITIONS := {
	1: [{"kind": &"slime", "count": 5}],
	2: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}],
	3: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}],
	4: [{"kind": &"ogre", "count": 2}],
	5: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}, {"kind": &"ogre", "count": 1}],
}

const _ENDLESS_BUNDLE := [
	{"kind": &"slime", "count": 2},
	{"kind": &"bee", "count": 5},
	{"kind": &"ogre", "count": 2},
]

const HEALTH_PER_WAVE := 0.1
const SPEED_PER_WAVE := 0.05

const INTERVAL_MS := 500.0
const BEE_START_DELAY_MS := 5000.0
const OGRE_DELAY_AFTER_LAST_SLIME_MS := 3000.0
const OGRE_MAX_START_DELAY_MS := 10000.0

## Enemy counts for a wave, accumulated from wave 1. Returns fresh
## dictionaries on every call so a caller cannot corrupt later waves.
static func get_composition(wave_number: int) -> Array[Dictionary]:
	var composition: Array[Dictionary] = []

	var authored_through: int = mini(wave_number, LAST_AUTHORED_WAVE)
	for wave in range(1, authored_through + 1):
		if _ADDITIONS.has(wave):
			for entry in _ADDITIONS[wave]:
				_add(composition, entry)

	var endless: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	for i in endless:
		for entry in _ENDLESS_BUNDLE:
			_add(composition, entry)

	return composition

static func _add(composition: Array[Dictionary], entry: Dictionary) -> void:
	for existing in composition:
		if existing["kind"] == entry["kind"]:
			existing["count"] += entry["count"]
			return
	composition.append({"kind": entry["kind"], "count": entry["count"]})

## Health and speed multipliers. Both are 1.0 through wave 5.
static func get_modifiers(wave_number: int) -> Dictionary:
	var past: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	return {
		"health_modifier": 1.0 + float(past) * HEALTH_PER_WAVE,
		"speed_modifier": 1.0 + float(past) * SPEED_PER_WAVE,
	}

## When the ogre column starts, given how many slimes precede it. Ogres trail
## the last slime by three seconds but never wait more than ten.
static func ogre_spawn_delay(slime_count: int) -> float:
	var last_slime_at := float(slime_count - 1) * INTERVAL_MS
	return minf(last_slime_at + OGRE_DELAY_AFTER_LAST_SLIME_MS, OGRE_MAX_START_DELAY_MS)
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add data/waves.gd test/test_waves.gd
git commit -m "Add wave composition, scaling and spawn timing

Accumulate-from-wave-1 is preserved and pinned by test; it reads as a bug
and is not one."
```

---

## Task 8: Movement

**Files:**
- Create: `sim/movement.gd`, `test/test_movement.gd`
- Port from: `src/game/sim/movement.ts`

**Interfaces:**
- Produces: `Movement.WAYPOINT_ARRIVAL_RADIUS` (2.0); `Movement.starting_path_index(position: Vector2, path: PackedVector2Array) -> int`; `Movement.advance(position: Vector2, path_index: int, path: PackedVector2Array, speed: float, delta_ms: float) -> Dictionary` with keys `position` (Vector2), `path_index` (int), `reached_goal` (bool), `advanced_waypoint` (bool), `direction` (StringName: `&"up"`/`&"down"`/`&"side"`), `moving_left` (bool).

Both quirks are preserved and tested: arrival consumes the whole tick without moving, and there is no clamping to the waypoint.

- [ ] **Step 1: Write the failing test**

`test/test_movement.gd`:

```gdscript
extends TestCase

func _straight_path() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100)])

func test_moves_at_speed_over_time() -> void:
	var r := Movement.advance(Vector2(0, 0), 1, _straight_path(), 100.0, 100.0)
	assert_eq(r["position"], Vector2(10, 0), "100px/s for 100ms is 10px")
	assert_false(r["advanced_waypoint"], "still travelling")
	assert_false(r["reached_goal"], "not at the end")

# QUIRK, preserved: arriving consumes the whole tick. The original's if/else
# never advances the index and moves in the same frame; changing it would
# shift every enemy's arrival time.
func test_arrival_consumes_the_whole_tick() -> void:
	var r := Movement.advance(Vector2(99.5, 0), 1, _straight_path(), 100.0, 100.0)
	assert_true(r["advanced_waypoint"], "waypoint advanced")
	assert_eq(r["path_index"], 2, "index moved on")
	assert_eq(r["position"], Vector2(99.5, 0), "no distance covered this tick")

# QUIRK, preserved: no clamping, so a fast enemy overshoots and steers back.
func test_fast_enemy_overshoots_rather_than_clamping() -> void:
	var r := Movement.advance(Vector2(0, 0), 1, _straight_path(), 10000.0, 100.0)
	assert_true(r["position"].x > 100.0, "overshoots the waypoint")
	assert_false(r["advanced_waypoint"], "did not arrive this tick")

func test_reaching_the_end_reports_goal() -> void:
	var path := _straight_path()
	var r := Movement.advance(Vector2(100, 99.5), 2, path, 100.0, 100.0)
	assert_true(r["advanced_waypoint"], "final waypoint consumed")
	assert_true(r["reached_goal"], "path exhausted")

func test_exhausted_path_stays_at_goal() -> void:
	var r := Movement.advance(Vector2(100, 100), 3, _straight_path(), 100.0, 100.0)
	assert_true(r["reached_goal"], "already leaked")
	assert_eq(r["position"], Vector2(100, 100), "does not drift")

func test_direction_ties_fall_to_side() -> void:
	# |dy| > |dx| picks up/down; equal magnitudes fall to "side".
	var diag := PackedVector2Array([Vector2(0, 0), Vector2(50, 50)])
	var r := Movement.advance(Vector2(0, 0), 1, diag, 10.0, 100.0)
	assert_eq(r["direction"], &"side", "equal dx and dy reads as side")

func test_direction_up_and_down() -> void:
	var vertical := PackedVector2Array([Vector2(0, 0), Vector2(0, 100)])
	assert_eq(Movement.advance(Vector2(0, 0), 1, vertical, 10.0, 100.0)["direction"],
		&"down", "positive dy is down")
	var upward := PackedVector2Array([Vector2(0, 100), Vector2(0, 0)])
	assert_eq(Movement.advance(Vector2(0, 100), 1, upward, 10.0, 100.0)["direction"],
		&"up", "negative dy is up")

func test_moving_left_flag() -> void:
	var leftward := PackedVector2Array([Vector2(100, 0), Vector2(0, 0)])
	assert_true(Movement.advance(Vector2(100, 0), 1, leftward, 10.0, 100.0)["moving_left"],
		"travelling right-to-left")

func test_starting_index_skips_a_waypoint_spawned_on_top_of() -> void:
	var path := _straight_path()
	assert_eq(Movement.starting_path_index(Vector2(0, 0), path), 1,
		"spawned on path[0], head for path[1]")
	assert_eq(Movement.starting_path_index(Vector2(50, 0), path), 0,
		"spawned elsewhere, head for path[0]")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/movement.gd`**

```gdscript
class_name Movement

## Path following. Pure: returns new values rather than mutating.
##
## Two quirks from the original are preserved deliberately, both affecting
## arrival timing. They are called out at their sites.

const WAYPOINT_ARRIVAL_RADIUS := 2.0
const _SPAWN_SNAP_RADIUS := 1.0

## Which waypoint an enemy spawning at `position` should head for first.
## An enemy spawned exactly on path[0] would otherwise sit at zero distance
## from its own target and stall.
static func starting_path_index(position: Vector2, path: PackedVector2Array) -> int:
	if path.size() <= 1:
		return 0
	var first := path[0]
	var on_first := absf(first.x - position.x) < _SPAWN_SNAP_RADIUS \
		and absf(first.y - position.y) < _SPAWN_SNAP_RADIUS
	return 1 if on_first else 0

## Advances one tick along the path. `delta_ms` is milliseconds.
static func advance(position: Vector2, path_index: int, path: PackedVector2Array,
		speed: float, delta_ms: float) -> Dictionary:

	if path_index >= path.size():
		return {
			"position": position, "path_index": path_index, "reached_goal": true,
			"advanced_waypoint": false, "direction": &"down", "moving_left": false,
		}

	var target := path[path_index]
	var dx := target.x - position.x
	var dy := target.y - position.y
	var distance := sqrt(dx * dx + dy * dy)

	# Ties fall to "side": the original test is abs(dy) > abs(dx).
	var direction: StringName = &"side"
	if absf(dy) > absf(dx):
		direction = &"down" if dy > 0.0 else &"up"
	var moving_left := dx < 0.0

	if distance < WAYPOINT_ARRIVAL_RADIUS:
		# QUIRK: arriving consumes the whole tick. The original never advances
		# the index and moves in the same frame, and changing that would shift
		# every enemy's arrival time.
		var next_index := path_index + 1
		return {
			"position": position, "path_index": next_index,
			"reached_goal": next_index >= path.size(),
			"advanced_waypoint": true, "direction": direction,
			"moving_left": moving_left,
		}

	# QUIRK: no clamping to the waypoint, so a fast enough enemy overshoots
	# and then steers back. At current speeds this is imperceptible.
	var move_distance := speed * delta_ms / 1000.0
	return {
		"position": Vector2(
			position.x + (dx / distance) * move_distance,
			position.y + (dy / distance) * move_distance),
		"path_index": path_index, "reached_goal": false,
		"advanced_waypoint": false, "direction": direction,
		"moving_left": moving_left,
	}
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/movement.gd test/test_movement.gd
git commit -m "Add path-following movement with both timing quirks preserved"
```

---

## Task 9: Damage resolution

**Files:**
- Create: `sim/damage.gd`, `test/test_damage.gd`
- Port from: `src/game/sim/damage.ts`

**Interfaces:**
- Produces: `Damage.resolve(source: Dictionary, target: Dictionary) -> Dictionary`.
  - `source`: `damage` (int/float), optional `pierce` (int, default 0).
  - `target`: `health` (float), `alive` (bool), optional `armor` (int, default 0), optional `shield` (int, default 0).
  - returns: `damage_dealt`, `remaining_health`, `remaining_shield`, `shield_absorbed`, `armor_absorbed`, `lethal`.

Armour and shield are never set during the core slice, but the module ports whole — two of its behaviours are load-bearing regardless, and the later properties phase needs the rest.

- [ ] **Step 1: Write the failing test**

`test/test_damage.gd`:

```gdscript
extends TestCase

func _target(health: float, extra := {}) -> Dictionary:
	var t := {"health": health, "max_health": health, "alive": true}
	t.merge(extra, true)
	return t

func test_plain_hit_subtracts_health() -> void:
	var r := Damage.resolve({"damage": 4}, _target(10.0))
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001, "four dealt")
	assert_almost_eq(r["remaining_health"], 6.0, 0.001, "six left")
	assert_false(r["lethal"], "not dead")

func test_overkill_is_not_counted() -> void:
	var r := Damage.resolve({"damage": 50}, _target(5.0))
	assert_almost_eq(r["damage_dealt"], 5.0, 0.001, "a 50-damage hit on 5 health dealt 5")
	assert_almost_eq(r["remaining_health"], 0.0, 0.001, "health floors at zero")
	assert_true(r["lethal"], "the hit killed it")

# Load-bearing even without enemy properties: enemies linger while their death
# animation plays, and without this guard a second projectile already in
# flight would report a kill again and pay the reward twice.
func test_a_corpse_absorbs_nothing() -> void:
	var dead := {"health": 0.0, "max_health": 5.0, "alive": false}
	var r := Damage.resolve({"damage": 10}, dead)
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no damage to a corpse")
	assert_false(r["lethal"], "cannot kill twice")

func test_zero_health_target_absorbs_nothing_even_if_flagged_alive() -> void:
	var r := Damage.resolve({"damage": 10}, {"health": 0.0, "max_health": 5.0, "alive": true})
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "already at zero")
	assert_false(r["lethal"], "no second kill")

func test_negative_damage_does_not_heal() -> void:
	var r := Damage.resolve({"damage": -10}, _target(5.0))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "inert, not healing")
	assert_almost_eq(r["remaining_health"], 5.0, 0.001, "health unchanged")

func test_armour_reduces_each_hit_flatly() -> void:
	var r := Damage.resolve({"damage": 4}, _target(10.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 1.0, 0.001, "4 minus 3 armour")
	assert_almost_eq(r["armor_absorbed"], 3.0, 0.001, "three absorbed")

func test_armour_cannot_make_damage_negative() -> void:
	var r := Damage.resolve({"damage": 2}, _target(10.0, {"armor": 9}))
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "floors at zero")

func test_pierce_ignores_armour() -> void:
	var r := Damage.resolve({"damage": 4, "pierce": 3}, _target(10.0, {"armor": 3}))
	assert_almost_eq(r["damage_dealt"], 4.0, 0.001, "pierce cancels armour")

func test_a_shield_swallows_a_whole_hit() -> void:
	var r := Damage.resolve({"damage": 15}, _target(10.0, {"shield": 2}))
	assert_true(r["shield_absorbed"], "absorbed by shield")
	assert_almost_eq(r["damage_dealt"], 0.0, 0.001, "no health lost")
	assert_eq(r["remaining_shield"], 1, "one charge spent")

# A zero-damage source must not strip a charge for free, or a tower that
# cannot hurt an armoured target could still peel its shield.
func test_zero_damage_does_not_strip_a_shield() -> void:
	var r := Damage.resolve({"damage": 0}, _target(10.0, {"shield": 2}))
	assert_false(r["shield_absorbed"], "no charge spent")
	assert_eq(r["remaining_shield"], 2, "shield intact")

func test_armour_and_shields_are_answered_by_opposite_profiles() -> void:
	# Rapid cheap fire: 8 hits of 2. Heavy slow fire: 1 hit of 16.
	var armoured := _target(20.0, {"armor": 3})
	var shielded := _target(20.0, {"shield": 3})
	assert_almost_eq(Damage.resolve({"damage": 2}, armoured)["damage_dealt"], 0.0, 0.001,
		"rapid fire is useless against armour")
	assert_almost_eq(Damage.resolve({"damage": 16}, armoured)["damage_dealt"], 13.0, 0.001,
		"a heavy hit punches armour")
	assert_true(Damage.resolve({"damage": 16}, shielded)["shield_absorbed"],
		"a heavy hit is wasted on a shield")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/damage.gd`**

Port `reference/project-t/td-browser/src/game/sim/damage.ts` lines 69–123. Order matters: the corpse guard first, then the negative-damage clamp, then the shield check, then armour.

```gdscript
class_name Damage

## Every point of damage in the game routes through resolve().
##
## Armour reduces every hit by a flat amount, so it punishes many small hits
## and is beaten by few large ones. Shields absorb a whole hit regardless of
## size, so they punish large hits and are beaten by rapid cheap fire. If
## either could be answered by the same build as the other, enemy properties
## would be decoration.

static func resolve(source: Dictionary, target: Dictionary) -> Dictionary:
	var shield: int = maxi(0, int(target.get("shield", 0)))
	var health := float(target["health"])
	var alive: bool = target.get("alive", true)

	# A corpse absorbs nothing. Enemies linger while their death animation
	# plays; without this a second projectile already in flight would report
	# a kill again and pay the reward twice.
	if not alive or health <= 0.0:
		return {
			"damage_dealt": 0.0, "remaining_health": maxf(0.0, health),
			"remaining_shield": shield, "shield_absorbed": false,
			"armor_absorbed": 0.0, "lethal": false,
		}

	# Negative damage must not heal. Nothing produces it today, but a bad data
	# value should be inert rather than a source of invincible enemies.
	var incoming := maxf(0.0, float(source["damage"]))

	# A zero-damage source must not strip a shield charge for free.
	if shield > 0 and incoming > 0.0:
		return {
			"damage_dealt": 0.0, "remaining_health": health,
			"remaining_shield": shield - 1, "shield_absorbed": true,
			"armor_absorbed": 0.0, "lethal": false,
		}

	var armor: float = maxf(0.0, float(target.get("armor", 0)))
	var pierce: float = maxf(0.0, float(source.get("pierce", 0)))
	var effective_armor := maxf(0.0, armor - pierce)
	var after_armor := maxf(0.0, incoming - effective_armor)

	var damage_dealt := minf(after_armor, health)
	var remaining_health := health - damage_dealt

	return {
		"damage_dealt": damage_dealt, "remaining_health": remaining_health,
		"remaining_shield": shield, "shield_absorbed": false,
		"armor_absorbed": incoming - after_armor,
		"lethal": remaining_health <= 0.0 and damage_dealt > 0.0,
	}
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/damage.gd test/test_damage.gd
git commit -m "Add damage resolution

Corpse guard and overkill clamping are load-bearing in the core slice;
armour and shield terms port whole for the later properties phase."
```

---

## Task 10: Leak penalty

**Files:**
- Create: `sim/leak.gd`, `test/test_leak.gd`
- Port from: `src/game/sim/leak.ts`

**Interfaces:**
- Produces: `Leak.LIFE_LOSS_SCALING_WAVE` (5), `Leak.MAX_LIFE_LOSS_PER_LEAK` (4), `Leak.resolve(enemy: Dictionary, wave: int) -> int` where `enemy` has `life_loss`, `health`, optional `exempt_from_life_loss`.

- [ ] **Step 1: Write the failing test**

`test/test_leak.gd`:

```gdscript
extends TestCase

func test_flat_cost_at_or_below_the_scaling_wave() -> void:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 5.0}, 1), 1, "slime costs 1")
	assert_eq(Leak.resolve({"life_loss": 2, "health": 3.0}, 3), 2, "bee costs 2")
	assert_eq(Leak.resolve({"life_loss": 5, "health": 8.0}, 5), 4, "ogre's 5 caps to 4")

func test_health_based_cost_past_the_scaling_wave() -> void:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 2.0}, 6), 2, "2 health costs 2")
	assert_eq(Leak.resolve({"life_loss": 1, "health": 2.3}, 6), 3, "rounds up")

# Uncapped, one leaked ogre cost 12 of 20 lives by wave 10 and all of them by
# wave 20, making lives binary rather than a resource.
func test_the_cost_is_capped_at_four() -> void:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 40.0}, 20), 4, "capped")
	assert_eq(Leak.resolve({"life_loss": 99, "health": 1.0}, 2), 4, "flat value capped too")

func test_a_leak_always_costs_at_least_one() -> void:
	assert_eq(Leak.resolve({"life_loss": 1, "health": 0.2}, 10), 1, "minimum of one")

func test_exempt_enemies_cost_nothing() -> void:
	assert_eq(Leak.resolve({"life_loss": 5, "health": 8.0, "exempt_from_life_loss": true}, 10),
		0, "exempt escapes free")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/leak.gd`**

```gdscript
class_name Leak

## What it costs the player when an enemy reaches the exit.

## Past this wave, a leak costs the enemy's remaining health instead of its
## flat life value.
const LIFE_LOSS_SCALING_WAVE := 5

## Most lives a single leak can cost. The health-based rule was unbounded and
## enemy health compounds every wave, so by wave 20 one leak ended the run.
## Capped, twenty lives is a budget of five mistakes.
const MAX_LIFE_LOSS_PER_LEAK := 4

static func resolve(enemy: Dictionary, wave: int) -> int:
	if enemy.get("exempt_from_life_loss", false):
		return 0

	if wave > LIFE_LOSS_SCALING_WAVE:
		return mini(MAX_LIFE_LOSS_PER_LEAK, maxi(1, int(ceil(float(enemy["health"])))))

	return mini(MAX_LIFE_LOSS_PER_LEAK, int(enemy["life_loss"]))
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/leak.gd test/test_leak.gd
git commit -m "Add capped leak penalty"
```

---

## Task 11: Targeting

**Files:**
- Create: `sim/targeting.gd`, `test/test_targeting.gd`
- Port from: `src/game/sim/targeting.ts`

**Interfaces:**
- Produces: `Targeting.PRIORITIES: Array[StringName]` = `[&"first", &"last", &"strongest", &"closest"]`; `Targeting.DEFAULT_PRIORITY` (`&"closest"`); `Targeting.LABELS: Dictionary`; `Targeting.next_priority(current: StringName) -> StringName`; `Targeting.is_targetable(tower: Dictionary, candidate: Dictionary) -> bool`; `Targeting.select(tower: Dictionary, candidates: Array) -> Variant` returning the chosen candidate `Dictionary` or `null`.
  - `tower`: `position` (Vector2), `range` (float), `priority` (StringName), optional `detection` (bool).
  - `candidate`: `id` (int), `position` (Vector2), `health` (float), `path_index` (int), `alive` (bool), `dying` (bool), optional `phased` (bool).

- [ ] **Step 1: Write the failing test**

`test/test_targeting.gd`:

```gdscript
extends TestCase

func _tower(priority: StringName, extra := {}) -> Dictionary:
	var t := {"position": Vector2(0, 0), "range": 100.0, "priority": priority}
	t.merge(extra, true)
	return t

func _enemy(id: int, pos: Vector2, health: float, path_index: int, extra := {}) -> Dictionary:
	var e := {"id": id, "position": pos, "health": health,
		"path_index": path_index, "alive": true, "dying": false}
	e.merge(extra, true)
	return e

func test_default_priority_is_closest() -> void:
	assert_eq(Targeting.DEFAULT_PRIORITY, &"closest", "matches pre-upgrade behaviour")

func test_out_of_range_enemies_are_not_targetable() -> void:
	assert_false(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(200, 0), 5.0, 0)),
		"beyond range")
	assert_true(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(50, 0), 5.0, 0)),
		"within range")

func test_range_boundary_is_inclusive() -> void:
	assert_true(Targeting.is_targetable(_tower(&"closest"), _enemy(1, Vector2(100, 0), 5.0, 0)),
		"exactly at range counts")

func test_dead_and_dying_enemies_are_not_targetable() -> void:
	assert_false(Targeting.is_targetable(_tower(&"closest"),
		_enemy(1, Vector2(10, 0), 5.0, 0, {"alive": false})), "dead")
	assert_false(Targeting.is_targetable(_tower(&"closest"),
		_enemy(1, Vector2(10, 0), 5.0, 0, {"dying": true})), "dying")

func test_phasing_is_a_hard_gate_not_a_penalty() -> void:
	var phased := _enemy(1, Vector2(10, 0), 5.0, 0, {"phased": true})
	assert_false(Targeting.is_targetable(_tower(&"closest"), phased),
		"invisible without detection")
	assert_true(Targeting.is_targetable(_tower(&"closest", {"detection": true}), phased),
		"visible with detection")

func test_closest_picks_the_nearest() -> void:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "nearest wins")

func test_first_picks_the_one_furthest_along() -> void:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"first"), enemies)["id"], 1, "highest path index")

func test_last_picks_the_one_least_far_along() -> void:
	var enemies := [_enemy(1, Vector2(90, 0), 5.0, 9), _enemy(2, Vector2(10, 0), 5.0, 1)]
	assert_eq(Targeting.select(_tower(&"last"), enemies)["id"], 2, "lowest path index")

func test_strongest_picks_the_highest_health() -> void:
	var enemies := [_enemy(1, Vector2(90, 0), 3.0, 9), _enemy(2, Vector2(10, 0), 20.0, 1)]
	assert_eq(Targeting.select(_tower(&"strongest"), enemies)["id"], 2, "most health")

func test_ties_break_on_lowest_id_so_results_are_reproducible() -> void:
	var enemies := [_enemy(7, Vector2(50, 0), 5.0, 3), _enemy(2, Vector2(50, 0), 5.0, 3)]
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "lowest id wins a tie")
	# Reversed input order must not change the answer.
	enemies.reverse()
	assert_eq(Targeting.select(_tower(&"closest"), enemies)["id"], 2, "order independent")

func test_returns_null_when_nothing_is_eligible() -> void:
	assert_eq(Targeting.select(_tower(&"closest"), []), null, "empty list")
	assert_eq(Targeting.select(_tower(&"closest"), [_enemy(1, Vector2(500, 0), 5.0, 0)]), null,
		"all out of range")

func test_next_priority_cycles() -> void:
	assert_eq(Targeting.next_priority(&"first"), &"last", "first to last")
	assert_eq(Targeting.next_priority(&"closest"), &"first", "wraps around")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/targeting.gd`**

```gdscript
class_name Targeting

## Target selection. Which enemy a tower shoots is a tactical lever: "first"
## pushes damage toward the exit where leaks happen, "last" protects the back
## of a queue, "strongest" focuses elites, "closest" maximises uptime.

const PRIORITIES: Array[StringName] = [&"first", &"last", &"strongest", &"closest"]

## The default a freshly placed tower uses, matching pre-upgrade behaviour
## where every tower shot whatever was nearest.
const DEFAULT_PRIORITY := &"closest"

const LABELS := {
	&"first": "First", &"last": "Last",
	&"strongest": "Strongest", &"closest": "Closest",
}

static func next_priority(current: StringName) -> StringName:
	var index := PRIORITIES.find(current)
	return PRIORITIES[(index + 1) % PRIORITIES.size()]

## Whether a tower is allowed to shoot a given enemy at all.
static func is_targetable(tower: Dictionary, candidate: Dictionary) -> bool:
	if not candidate.get("alive", true) or candidate.get("dying", false):
		return false
	# Phasing is a hard gate, not a penalty: without detection the enemy
	# simply is not there as far as this tower is concerned.
	if candidate.get("phased", false) and not tower.get("detection", false):
		return false
	var d: float = tower["position"].distance_to(candidate["position"])
	return d <= float(tower["range"])

## Picks a target, or null when nothing is eligible. Ties break on lowest id,
## so the result never depends on iteration order.
static func select(tower: Dictionary, candidates: Array):
	var best = null
	var best_score := 0.0

	for candidate in candidates:
		if not is_targetable(tower, candidate):
			continue
		var score := _score_for(tower, candidate)
		if best == null or score > best_score \
				or (is_equal_approx(score, best_score) and int(candidate["id"]) < int(best["id"])):
			best = candidate
			best_score = score

	return best

static func _score_for(tower: Dictionary, candidate: Dictionary) -> float:
	match tower["priority"]:
		&"first":
			return float(candidate["path_index"])
		&"last":
			return -float(candidate["path_index"])
		&"strongest":
			return float(candidate["health"])
		_:
			return -tower["position"].distance_to(candidate["position"])
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/targeting.gd test/test_targeting.gd
git commit -m "Add target selection with reproducible tie-breaking"
```

---

## Task 12: Economy arithmetic

**Files:**
- Create: `sim/economy.gd`, `test/test_economy.gd`
- Port from: `src/game/sim/economy.ts` and the pricing logic in `src/game/managers/TowerManager.ts`

**Interfaces:**
- Produces: `EconomySim.tower_price(kind: StringName, owned_of_kind: int) -> int`; `EconomySim.sell_refund(paid: int) -> int`; `EconomySim.can_afford(gold: int, price: int) -> bool`; `EconomySim.tower_limit(kind: StringName, map_name: StringName) -> int`.

Named `EconomySim` because `Economy` is already the data table from Task 6.

- [ ] **Step 1: Write the failing test**

`test/test_economy.gd`:

```gdscript
extends TestCase

func test_first_tower_costs_base_price() -> void:
	assert_eq(EconomySim.tower_price(&"basic", 0), 20, "first basic")
	assert_eq(EconomySim.tower_price(&"long", 0), 100, "first long range")

func test_price_escalates_per_tower_already_owned() -> void:
	assert_eq(EconomySim.tower_price(&"basic", 1), 30, "20 + 10")
	assert_eq(EconomySim.tower_price(&"basic", 3), 50, "20 + 3*10")
	assert_eq(EconomySim.tower_price(&"mortar", 2), 140, "70 + 2*35")

func test_escalation_is_per_kind_not_global() -> void:
	assert_eq(EconomySim.tower_price(&"fast", 0), 50,
		"owning basics does not raise the price of a fast tower")

func test_sell_refunds_half_rounded_down() -> void:
	assert_eq(EconomySim.sell_refund(20), 10, "half of 20")
	assert_eq(EconomySim.sell_refund(35), 17, "half of 35 floors to 17")

func test_affordability() -> void:
	assert_true(EconomySim.can_afford(100, 100), "exact gold is affordable")
	assert_false(EconomySim.can_afford(99, 100), "one short")

func test_tower_limits_on_the_first_map() -> void:
	assert_eq(EconomySim.tower_limit(&"basic", &"demoMap"), 8, "basic limit")
	assert_eq(EconomySim.tower_limit(&"long", &"demoMap"), 5, "long range limit")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/economy.gd`**

```gdscript
class_name EconomySim

## Currency and pricing arithmetic. Named EconomySim because Economy is the
## data table of constants.

## Price of the next tower of a kind. Escalation is per kind, and exists to
## stop the board becoming twenty copies of one tower.
static func tower_price(kind: StringName, owned_of_kind: int) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	return int(def["cost"]) + owned_of_kind * int(def["cost_escalation"])

## Half of everything sunk into a tower comes back on sale, rounded down.
static func sell_refund(paid: int) -> int:
	return int(floor(float(paid) * Economy.SELL_REFUND_FRACTION))

static func can_afford(gold: int, price: int) -> bool:
	return gold >= price

## How many of a kind this map allows.
static func tower_limit(kind: StringName, map_name: StringName) -> int:
	var def: Dictionary = Towers.DEFS[kind]
	var limit := int(def["base_limit"])
	if map_name != Maps.FIRST:
		limit += int(def["limit_bonus_map2"])
	return limit
```

- [ ] **Step 4: Import, run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add sim/economy.gd test/test_economy.gd
git commit -m "Add tower pricing, refund and limit arithmetic"
```

---

## Task 13: Purity guard

The rule that makes everything above testable. Its detector is itself tested, so the guard cannot pass vacuously.

**Files:**
- Create: `test/test_sim_purity.gd`
- Port from: `src/game/sim/purity.test.ts`

**Interfaces:**
- Consumes: nothing. Reads `res://sim/` and `res://data/` from disk.

- [ ] **Step 1: Write the test**

This one is written and run in a single step because it should pass immediately — every module so far was written to the rule. If it fails, the offending module is fixed, not the test.

`test/test_sim_purity.gd`:

```gdscript
extends TestCase

## sim/ and data/ must never touch the engine's scene layer, or the headless
## harness becomes impossible and balance stops being testable.

const FORBIDDEN := [
	"extends Node", "extends Node2D", "extends Control", "extends Sprite2D",
	"extends Area2D", "extends CharacterBody2D", "extends CanvasItem",
	"get_tree()", "preload(", "@onready", "@export", "get_node(",
	"randf(", "randi(", "RandomNumberGenerator",
]

const GUARDED_DIRS := ["res://sim", "res://data"]

func test_no_engine_or_scene_references_in_sim_or_data() -> void:
	var offences: Array[String] = []
	for dir in GUARDED_DIRS:
		for path in _gd_files(dir):
			var text := FileAccess.get_file_as_string(path)
			for token in FORBIDDEN:
				if _contains_outside_comments(text, token):
					offences.append("%s contains %s" % [path, token])
	assert_eq(offences, [] as Array[String],
		"sim/ and data/ must stay engine-free")

func test_the_guard_finds_at_least_one_file() -> void:
	var count := 0
	for dir in GUARDED_DIRS:
		count += _gd_files(dir).size()
	assert_true(count >= 8, "the guard actually scanned files, found %d" % count)

# The detector must be able to detect. Without these, the guard above could
# pass simply by never matching anything.
func test_detector_flags_a_positive_sample() -> void:
	assert_true(_contains_outside_comments("var x = get_tree()", "get_tree()"),
		"detects a real call")
	assert_true(_contains_outside_comments("extends Node2D", "extends Node2D"),
		"detects a scene base class")

func test_detector_ignores_comments() -> void:
	assert_false(_contains_outside_comments("# never call get_tree() here", "get_tree()"),
		"a mention in a comment is not a violation")
	assert_false(_contains_outside_comments("## preload( is forbidden", "preload("),
		"a mention in a doc comment is not a violation")

func test_detector_rejects_a_negative_sample() -> void:
	assert_false(_contains_outside_comments("var x = 1 + 2", "get_tree()"),
		"clean code is not flagged")

func _contains_outside_comments(text: String, token: String) -> bool:
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var code := stripped
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		if code.contains(token):
			return true
	return false

func _gd_files(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
```

- [ ] **Step 2: Run — expect PASS**

If `test_no_engine_or_scene_references_in_sim_or_data` fails, fix the offending module. Never relax `FORBIDDEN` to make it pass.

- [ ] **Step 3: Verify the guard can actually fail**

Temporarily add `var _leak = get_tree()` to `sim/grid.gd`, re-run, confirm the guard reports it, then **revert**.

- [ ] **Step 4: Commit**

```bash
git add test/test_sim_purity.gd
git commit -m "Add purity guard for sim/ and data/

Detector is itself tested against positive and negative samples so the
guard cannot pass vacuously."
```

---

## Task 14: Headless wave harness

The piece that makes a balance claim a test rather than an assertion.

**Files:**
- Create: `sim/harness.gd`, `test/test_harness.gd`
- Port from: `src/game/sim/harness.ts`

**Interfaces:**
- Produces: `Harness.run_wave(config: Dictionary) -> Dictionary`.
  - `config`: `wave` (int), `towers` (Array of `{kind, position}`), `path` (PackedVector2Array), `max_ticks` (int, default 60000), `tick_ms` (float, default 16.666).
  - returns: `kills` (int), `leaks` (int), `lives_lost` (int), `gold_earned` (int), `ticks` (int), `timed_out` (bool).

- [ ] **Step 1: Write the failing test**

`test/test_harness.gd`:

```gdscript
extends TestCase

func _path() -> PackedVector2Array:
	Grid.set_active(DemoMap.GRID_COLS, DemoMap.GRID_ROWS)
	return PathFinder.get_path_from_spawn_to_goal(
		DemoMap.build(Rng.new(Seeds.DEFAULT_DEMO_MAP_SEED)))

func test_an_undefended_wave_leaks_everything() -> void:
	var r := Harness.run_wave({"wave": 1, "towers": [], "path": _path()})
	assert_eq(r["kills"], 0, "no towers, no kills")
	assert_eq(r["leaks"], 5, "all five slimes leak")
	assert_eq(r["lives_lost"], 5, "one life each at wave 1")
	assert_false(r["timed_out"], "the wave completed")

func test_a_defended_wave_kills_everything() -> void:
	# Long Range towers packed onto the first straight give overwhelming cover.
	var towers: Array = []
	for col in [3, 5, 7, 9, 11]:
		towers.append({"kind": &"long", "position": Grid.tile_to_world_center(col, 3)})
	var r := Harness.run_wave({"wave": 1, "towers": towers, "path": _path()})
	assert_eq(r["leaks"], 0, "nothing gets through")
	assert_eq(r["kills"], 5, "all five die")
	assert_eq(r["gold_earned"], 25, "five slimes at 5 gold")

func test_results_are_reproducible() -> void:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var a := Harness.run_wave({"wave": 3, "towers": towers, "path": _path()})
	var b := Harness.run_wave({"wave": 3, "towers": towers, "path": _path()})
	assert_eq(a, b, "same input, same result")

func test_later_waves_are_harder_for_the_same_board() -> void:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var early := Harness.run_wave({"wave": 2, "towers": towers, "path": _path()})
	var late := Harness.run_wave({"wave": 12, "towers": towers, "path": _path()})
	assert_true(late["leaks"] > early["leaks"],
		"wave 12 leaks more than wave 2 against the same single tower")
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement `sim/harness.gd`**

```gdscript
class_name Harness

## Runs a wave headlessly on a fixed timestep, with no engine involvement.
##
## It reuses the game's own sim modules, so there is no second rules
## implementation to drift. Every balance claim in this project is a test
## rather than an assertion because of this file.

const DEFAULT_TICK_MS := 1000.0 / 60.0
const DEFAULT_MAX_TICKS := 60000

static func run_wave(config: Dictionary) -> Dictionary:
	var wave: int = config["wave"]
	var path: PackedVector2Array = config["path"]
	var tick_ms: float = config.get("tick_ms", DEFAULT_TICK_MS)
	var max_ticks: int = config.get("max_ticks", DEFAULT_MAX_TICKS)

	var towers: Array = []
	for t in config.get("towers", []):
		var def: Dictionary = Towers.DEFS[t["kind"]]
		towers.append({
			"position": t["position"],
			"range": float(def["range"]),
			"fire_rate": float(def["fire_rate"]),
			"damage": float(def["damage"]),
			"pierce": int(def["pierce"]),
			"detection": bool(def["detection"]),
			"splash": float(def["base_splash_radius"]),
			"priority": Targeting.DEFAULT_PRIORITY,
			"cooldown": 0.0,
		})

	var schedule := _build_schedule(wave)
	var modifiers := Waves.get_modifiers(wave)

	var enemies: Array = []
	var next_id := 0
	var elapsed := 0.0
	var ticks := 0
	var kills := 0
	var leaks := 0
	var lives_lost := 0
	var gold_earned := 0
	var spawned := 0

	while ticks < max_ticks:
		ticks += 1
		elapsed += tick_ms

		# Spawns due this tick.
		while spawned < schedule.size() and schedule[spawned]["at_ms"] <= elapsed:
			var s: Dictionary = schedule[spawned]
			var kind: StringName = s["kind"]
			var health := float(Enemies.scaled_health(kind, modifiers["health_modifier"]))
			enemies.append({
				"id": next_id,
				"kind": kind,
				"position": path[0],
				"path_index": Movement.starting_path_index(path[0], path),
				"health": health,
				"max_health": health,
				"speed": Enemies.scaled_speed(kind, modifiers["speed_modifier"]),
				"alive": true,
				"dying": false,
			})
			next_id += 1
			spawned += 1

		# Move.
		var survivors: Array = []
		for e in enemies:
			if not e["alive"]:
				continue
			var m := Movement.advance(e["position"], e["path_index"], path,
				e["speed"], tick_ms)
			e["position"] = m["position"]
			e["path_index"] = m["path_index"]
			if m["reached_goal"]:
				leaks += 1
				lives_lost += Leak.resolve(
					{"life_loss": Enemies.DEFS[e["kind"]]["life_loss"], "health": e["health"]},
					wave)
				e["alive"] = false
			else:
				survivors.append(e)
		enemies = survivors

		# Fire.
		for tower in towers:
			tower["cooldown"] -= tick_ms
			if tower["cooldown"] > 0.0:
				continue
			var target = Targeting.select(tower, enemies)
			if target == null:
				continue
			tower["cooldown"] = tower["fire_rate"]
			var hit_list: Array = [target]
			if tower["splash"] > 0.0:
				for e in enemies:
					if e["id"] != target["id"] \
							and e["position"].distance_to(target["position"]) <= tower["splash"]:
						hit_list.append(e)
			for e in hit_list:
				var r := Damage.resolve({"damage": tower["damage"], "pierce": tower["pierce"]}, e)
				e["health"] = r["remaining_health"]
				if r["lethal"]:
					e["alive"] = false
					kills += 1
					gold_earned += int(Enemies.DEFS[e["kind"]]["reward"])

		enemies = enemies.filter(func(e): return e["alive"])

		if spawned >= schedule.size() and enemies.is_empty():
			return _result(kills, leaks, lives_lost, gold_earned, ticks, false)

	return _result(kills, leaks, lives_lost, gold_earned, ticks, true)

static func _result(kills: int, leaks: int, lives_lost: int, gold: int,
		ticks: int, timed_out: bool) -> Dictionary:
	return {
		"kills": kills, "leaks": leaks, "lives_lost": lives_lost,
		"gold_earned": gold, "ticks": ticks, "timed_out": timed_out,
	}

## Spawn instants for a wave, mirroring GameScene.startWave's offsets.
static func _build_schedule(wave: int) -> Array:
	var schedule: Array = []
	var composition := Waves.get_composition(wave)

	var slime_count := 0
	for entry in composition:
		if entry["kind"] == &"slime":
			slime_count = entry["count"]

	for entry in composition:
		var kind: StringName = entry["kind"]
		var start := 0.0
		match kind:
			&"bee":
				start = Waves.BEE_START_DELAY_MS
			&"ogre":
				start = Waves.ogre_spawn_delay(slime_count)
			_:
				start = 0.0
		for i in entry["count"]:
			schedule.append({"kind": kind, "at_ms": start + float(i) * Waves.INTERVAL_MS})

	schedule.sort_custom(func(a, b): return a["at_ms"] < b["at_ms"])
	return schedule
```

- [ ] **Step 4: Import, run — expect PASS**

If `test_a_defended_wave_kills_everything` fails, check tower placement covers the path's first straight (row 4 in tile terms, so `tile_to_world_center(col, 3)` sits one row above it, within a 150px range). Adjust the *test's* tower positions to give genuine coverage — but never adjust `Towers.DEFS`.

- [ ] **Step 5: Commit**

```bash
git add sim/harness.gd test/test_harness.gd
git commit -m "Add headless fixed-timestep wave harness

Reuses the game's own sim modules, so there is no second rules
implementation to drift."
```

---

## Task 15: Asset import and atlas extraction

Copies the artwork across and pre-slices the map sheet. This is the load-size win the spec calls out: the 3.9 MB sheet contributes eight rects totalling ~15% of its pixels.

**Files:**
- Create: `tools/slice_atlas.gd`, `assets/` tree
- Reads: `reference/project-t/td-browser/public/`

**Interfaces:**
- Produces: `assets/map_atlas.png` (the eight tiles packed), `assets/towers.png`, `assets/enemies/{slime,ogre,bee}/*.png`, `assets/audio/*.ogg`.

- [ ] **Step 1: Copy artwork and audio**

```bash
cd ~/Projects/project-t-godot
mkdir -p assets/enemies assets/audio
cp reference/project-t/td-browser/public/towers/towers.png assets/
cp reference/project-t/td-browser/public/map-sprites.png assets/map_sprites_source.png
cp -r reference/project-t/td-browser/public/enemies/slime-enemy assets/enemies/slime
cp -r reference/project-t/td-browser/public/enemies/ogre-enemy assets/enemies/ogre
cp -r reference/project-t/td-browser/public/enemies/bee-enemy assets/enemies/bee
cp reference/project-t/td-browser/public/audio/*.wav assets/audio/
```

Note the reference repo misspells the wolf directory as `wolf-eneemy`; it is unused by the core slice and is not copied.

- [ ] **Step 2: Write the atlas extraction tool**

`tools/slice_atlas.gd` — run once via `godot --headless --script`. Rects are transcribed from `reference/project-t/td-browser/src/scenes/BootScene.ts` `create()`.

```gdscript
extends SceneTree

# Frame -> source rect in map-sprites.png (1024x1536), from BootScene.create().
const FRAMES := [
	{"name": "grass",  "rect": Rect2i(60, 150, 64, 64)},
	{"name": "path",   "rect": Rect2i(60, 64, 64, 64)},
	{"name": "tree",   "rect": Rect2i(40, 250, 100, 150)},
	{"name": "stone",  "rect": Rect2i(670, 230, 128, 128)},
	{"name": "castle", "rect": Rect2i(750, 600, 256, 350)},
	{"name": "cave",   "rect": Rect2i(700, 880, 300, 300)},
	{"name": "spike",  "rect": Rect2i(760, 530, 100, 100)},
	{"name": "fire",   "rect": Rect2i(650, 500, 100, 100)},
]

func _initialize() -> void:
	var source := Image.load_from_file("res://assets/map_sprites_source.png")
	if source == null:
		printerr("could not load res://assets/map_sprites_source.png")
		quit(1)
		return

	for frame in FRAMES:
		var rect: Rect2i = frame["rect"]
		var out := Image.create(rect.size.x, rect.size.y, false, source.get_format())
		out.blit_rect(source, rect, Vector2i.ZERO)
		var path := "res://assets/map/%s.png" % frame["name"]
		DirAccess.make_dir_recursive_absolute("res://assets/map")
		var err := out.save_png(path)
		if err != OK:
			printerr("failed writing %s: %d" % [path, err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [path, rect.size.x, rect.size.y])

	quit(0)
```

- [ ] **Step 3: Run the tool**

```bash
cd ~/Projects/project-t-godot
godot --headless --import
godot --headless --quit --script tools/slice_atlas.gd
ls -la assets/map/
```

Expected: eight PNGs. Verify `grass.png` is 64×64 and `castle.png` is 256×350.

- [ ] **Step 4: Verify the size win, then drop the source sheet**

```bash
du -sh assets/map/ assets/map_sprites_source.png
rm assets/map_sprites_source.png
```

Expected: the eight extracted PNGs total well under 500 KB against the 3.9 MB source.

- [ ] **Step 5: Convert audio to OGG**

```bash
cd ~/Projects/project-t-godot/assets/audio
for f in *.wav; do ffmpeg -loglevel error -y -i "$f" "${f%.wav}.ogg" && rm "$f"; done
ls
```

If `ffmpeg` is unavailable, keep the WAVs and note it — Godot imports both, and this is a size optimisation, not a correctness requirement.

- [ ] **Step 6: Verify visually**

```bash
godot --headless --import
```

Then read `assets/map/castle.png` and `assets/map/cave.png` with the Read tool to confirm they contain the intended artwork and not empty or misaligned regions. The rects were eyeballed against a Phaser display size; if one is wrong, adjust it here rather than compensating downstream.

- [ ] **Step 7: Commit**

```bash
git add assets/ tools/
git commit -m "Import artwork and pre-slice the map sheet

The 3.9MB source sheet contributed eight rects totalling ~15% of its
pixels; extracting them is the largest load-size win available."
```

---

## Task 16: Map renderer

**Files:**
- Create: `game/map_renderer.gd`
- Port from: `src/game/systems/MapRenderer.ts`

**Interfaces:**
- Consumes: `Tiles`, `Grid`, `Rng`, `Seeds`.
- Produces: `MapRenderer` (`extends Node2D`) — `render(tiles: Array, rng: Rng = null) -> void`, `clear_decoration_at(col: int, row: int) -> bool`.

Rendering uses `Sprite2D` children rather than a `TileMapLayer`, because the goal and spawn artwork is drawn 3×3 with a pixel offset and the decoration layer is scattered rather than grid-aligned. A `TileMapLayer` would fight both.

- [ ] **Step 1: Implement `game/map_renderer.gd`**

```gdscript
class_name MapRenderer
extends Node2D

## Draws a tile grid. Decoration scatter is seeded so a map renders
## identically every run.

const _GRASS := preload("res://assets/map/grass.png")
const _PATH := preload("res://assets/map/path.png")
const _TREE := preload("res://assets/map/tree.png")
const _STONE := preload("res://assets/map/stone.png")
const _CASTLE := preload("res://assets/map/castle.png")
const _CAVE := preload("res://assets/map/cave.png")
const _SPIKE := preload("res://assets/map/spike.png")
const _FIRE := preload("res://assets/map/fire.png")

const _MAX_FIRE_TILES := 7

var _tiles: Array = []
var _rows := 0
var _cols := 0
var _decorations := {}  # Vector2i -> Sprite2D

func render(tiles: Array, rng: Rng = null) -> void:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DECORATION_SEED)
	_tiles = tiles
	_rows = tiles.size()
	_cols = tiles[0].size() if _rows > 0 else 0

	for child in get_children():
		child.queue_free()
	_decorations.clear()

	_draw_ground()
	_draw_endpoints()
	_scatter_decoration(rng)
	_draw_blocked(rng)

## Removes a decoration sprite when a tower is built on its tile.
func clear_decoration_at(col: int, row: int) -> bool:
	var key := Vector2i(col, row)
	if not _decorations.has(key):
		return false
	_decorations[key].queue_free()
	_decorations.erase(key)
	return true

func _place(texture: Texture2D, col: int, row: int, size_px: float,
		z: int, offset := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE) + offset
	s.scale = Vector2(size_px / texture.get_width(), size_px / texture.get_height())
	s.z_index = z
	add_child(s)
	return s

func _draw_ground() -> void:
	for r in _rows:
		for c in _cols:
			var kind = _tiles[r][c]
			if kind == Tiles.PATH or kind == Tiles.SPAWN or kind == Tiles.GOAL:
				_place(_PATH, c, r, Tiles.TILE_SIZE, 0)
			else:
				_place(_GRASS, c, r, Tiles.TILE_SIZE, 0)

func _draw_endpoints() -> void:
	# Drawn 3 tiles wide, offset up and left, matching the Phaser build.
	var offset := Vector2(-Tiles.TILE_SIZE, -Tiles.TILE_SIZE - 20)
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.SPAWN:
				_place(_CAVE, c, r, Tiles.TILE_SIZE * 3, 1, offset)
			elif _tiles[r][c] == Tiles.GOAL:
				_place(_CASTLE, c, r, Tiles.TILE_SIZE * 3, 1, offset)

func _scatter_decoration(rng: Rng) -> void:
	var buildable: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BUILDABLE:
				buildable.append(Vector2i(c, r))

	var spike_count: int = mini(buildable.size(), maxi(5, int(floor(buildable.size() * 0.1))))
	var shuffled := rng.shuffle(buildable)
	for i in spike_count:
		var t: Vector2i = shuffled[i]
		_decorations[t] = _place(_SPIKE, t.x, t.y, Tiles.TILE_SIZE, 1)

	var path_adjacent: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.BUILDABLE:
				continue
			if _decorations.has(Vector2i(c, r)):
				continue
			if _is_adjacent_to_walkable(r, c):
				path_adjacent.append(Vector2i(c, r))

	var fire_count: int = mini(path_adjacent.size(), _MAX_FIRE_TILES)
	var shuffled_adjacent := rng.shuffle(path_adjacent)
	for i in fire_count:
		var t: Vector2i = shuffled_adjacent[i]
		_decorations[t] = _place(_FIRE, t.x, t.y, Tiles.TILE_SIZE, 1)

func _draw_blocked(rng: Rng) -> void:
	var excluded := {}
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.SPAWN and _tiles[r][c] != Tiles.GOAL:
				continue
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					excluded[Vector2i(c + dc, r + dr)] = true

	var blocked: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BLOCKED and not excluded.has(Vector2i(c, r)):
				blocked.append(Vector2i(c, r))

	var stone_count: int = mini(blocked.size(), rng.int_range(3, 5))
	var shuffled := rng.shuffle(blocked)
	var stones := {}
	for i in stone_count:
		stones[shuffled[i]] = true

	for t in blocked:
		_place(_STONE if stones.has(t) else _TREE, t.x, t.y, Tiles.TILE_SIZE, 1)

func _is_adjacent_to_walkable(row: int, col: int) -> bool:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nr := row + d.y
		var nc := col + d.x
		if nr < 0 or nr >= _rows or nc < 0 or nc >= _cols:
			continue
		if _tiles[nr][nc] in Tiles.WALKABLE:
			return true
	return false
```

- [ ] **Step 2: Verify it parses**

```bash
godot --headless --import
godot --headless --quit --script test/run_tests.gd
```

The purity guard must still pass — `MapRenderer` lives in `game/`, not `sim/`, so its `preload` calls are legal.

- [ ] **Step 3: Commit**

```bash
git add game/map_renderer.gd
git commit -m "Add map renderer with seeded decoration scatter"
```

---

## Task 17: Enemy view

**Files:**
- Create: `game/enemy.gd`, `game/enemy.tscn`

**Interfaces:**
- Consumes: `Enemies`, `Movement`, `Damage`, `Leak`.
- Produces: `Enemy` (`extends Node2D`) with signals `died(reward: int)` and `leaked(life_loss: int)`; methods `setup(kind: StringName, path: PackedVector2Array, wave: int) -> void`, `take_damage(source: Dictionary) -> Dictionary`, `to_candidate() -> Dictionary`, `get_sim_state() -> Dictionary`.

**Scene tree for `game/enemy.tscn`:**

```
Enemy (Node2D)              [script: enemy.gd]
├── Sprite (AnimatedSprite2D)
└── HealthBar (ColorRect)    size 32x4, position (-16, -22)
```

- [ ] **Step 1: Build the SpriteFrames**

Each sheet is 288×48 — six 48px frames. Build one `SpriteFrames` per creature in `_build_frames()` at runtime from the six PNGs, with animations `walk_up`, `walk_side`, `walk_down`, `death_up`, `death_side`, `death_down`.

- [ ] **Step 2: Implement `game/enemy.gd`**

```gdscript
class_name Enemy
extends Node2D

signal died(reward: int)
signal leaked(life_loss: int)

const FRAME_SIZE := 48
const FRAMES_PER_SHEET := 6
const WALK_FPS := 8.0
const DEATH_FPS := 10.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _health_bar: ColorRect = $HealthBar

var kind: StringName
var sim := {}
var _path: PackedVector2Array
var _wave := 1
var _facing: StringName = &"side"
var _flip := false

func setup(enemy_kind: StringName, path: PackedVector2Array, wave: int) -> void:
	kind = enemy_kind
	_path = path
	_wave = wave
	var def: Dictionary = Enemies.DEFS[kind]
	var modifiers := Waves.get_modifiers(wave)
	var health := float(Enemies.scaled_health(kind, modifiers["health_modifier"]))

	sim = {
		"id": get_instance_id(),
		"health": health,
		"max_health": health,
		"speed": Enemies.scaled_speed(kind, modifiers["speed_modifier"]),
		"alive": true,
		"dying": false,
		"path_index": Movement.starting_path_index(path[0], path),
	}

	position = path[0]
	_sprite.sprite_frames = _build_frames(def["texture_key"])
	_sprite.scale = Vector2.ONE * float(def["sprite_scale"])
	_play_walk()
	_update_health_bar()

func _physics_process(delta: float) -> void:
	if not sim["alive"] or sim["dying"]:
		return

	var result := Movement.advance(position, sim["path_index"], _path,
		sim["speed"], delta * 1000.0)
	position = result["position"]
	sim["path_index"] = result["path_index"]

	# A tick that advanced a waypoint covered no distance, so its reported
	# direction comes from a sub-pixel delta and would make the sprite jitter.
	if not result["advanced_waypoint"]:
		_set_facing(result["direction"], result["moving_left"])

	if result["reached_goal"]:
		sim["alive"] = false
		leaked.emit(Leak.resolve(
			{"life_loss": Enemies.DEFS[kind]["life_loss"], "health": sim["health"]}, _wave))
		queue_free()

func take_damage(source: Dictionary) -> Dictionary:
	var result := Damage.resolve(source, sim)
	sim["health"] = result["remaining_health"]
	_update_health_bar()
	if result["lethal"]:
		_die()
	return result

func to_candidate() -> Dictionary:
	return {
		"id": sim["id"], "position": position, "health": sim["health"],
		"path_index": sim["path_index"], "alive": sim["alive"],
		"dying": sim["dying"], "node": self,
	}

func get_sim_state() -> Dictionary:
	return sim

func _die() -> void:
	sim["dying"] = true
	sim["alive"] = false
	died.emit(int(Enemies.DEFS[kind]["reward"]))
	_health_bar.visible = false
	_sprite.play("death_%s" % _facing)
	await _sprite.animation_finished
	queue_free()

func _set_facing(direction: StringName, moving_left: bool) -> void:
	var flip := moving_left if direction == &"side" else false
	if Enemies.DEFS[kind]["flip_horizontally"]:
		flip = not flip
	if direction == _facing and flip == _flip:
		return
	_facing = direction
	_flip = flip
	_sprite.flip_h = flip
	_play_walk()

func _play_walk() -> void:
	_sprite.play("walk_%s" % _facing)

func _update_health_bar() -> void:
	var fraction: float = clampf(sim["health"] / sim["max_health"], 0.0, 1.0)
	_health_bar.size.x = 32.0 * fraction
	_health_bar.color = Color.GREEN.lerp(Color.RED, 1.0 - fraction)

func _build_frames(texture_key: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for action in ["Walk", "Death"]:
		for dir_pair in [["U", "up"], ["S", "side"], ["D", "down"]]:
			var anim := "%s_%s" % [action.to_lower(), dir_pair[1]]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, WALK_FPS if action == "Walk" else DEATH_FPS)
			frames.set_animation_loop(anim, action == "Walk")
			var path := "res://assets/enemies/%s/%s_%s.png" % [texture_key, dir_pair[0], action]
			var sheet: Texture2D = load(path)
			if sheet == null:
				push_error("missing sheet %s" % path)
				continue
			for i in FRAMES_PER_SHEET:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim, atlas)
	return frames
```

- [ ] **Step 3: Verify it parses and tests still pass**

```bash
godot --headless --import && godot --headless --quit --script test/run_tests.gd
```

- [ ] **Step 4: Commit**

```bash
git add game/enemy.gd game/enemy.tscn
git commit -m "Add enemy view with directional walk and death animation"
```

---

## Task 18: Tower and projectile views

**Files:**
- Create: `game/tower.gd`, `game/tower.tscn`, `game/projectile.gd`, `game/projectile.tscn`

**Interfaces:**
- Produces:
  - `Tower` (`extends Node2D`) — `setup(kind: StringName, col: int, row: int, price_paid: int)`, `set_range_visible(visible: bool)`, `to_targeting_dict() -> Dictionary`, properties `kind`, `price_paid`, `grid_col`, `grid_row`; signal `wants_to_fire(target_node, source: Dictionary, splash: float)`.
  - `Projectile` (`extends Node2D`) — `launch(target: Node2D, source: Dictionary, speed: float, arcs: bool, splash: float)`; signal `hit(target_node, source: Dictionary, splash: float)`.

**Scene trees:**

```
Tower (Node2D)                Projectile (Node2D)
├── Sprite (Sprite2D)         └── Dot (ColorRect) 6x6, centred
├── RangeIndicator (Node2D)   [script: projectile.gd]
└── ClickArea (Area2D)
    └── CollisionShape2D (RectangleShape2D 48x48)
[script: tower.gd]
```

`RangeIndicator` draws a circle in `_draw()`; `ClickArea` exists only for tap-picking, never for combat.

- [ ] **Step 1: Implement `game/tower.gd`**

```gdscript
class_name Tower
extends Node2D

signal wants_to_fire(target_node: Node2D, source: Dictionary, splash: float)

const TOWER_SHEET := preload("res://assets/towers.png")
const SHEET_COLUMNS := 5
const FRAME_SIZE := 96

var kind: StringName
var price_paid := 0
var grid_col := 0
var grid_row := 0

var _def := {}
var _cooldown := 0.0
var _priority: StringName = Targeting.DEFAULT_PRIORITY
var _range_visible := false

@onready var _sprite: Sprite2D = $Sprite
@onready var _range_indicator: Node2D = $RangeIndicator

func setup(tower_kind: StringName, col: int, row: int, paid: int) -> void:
	kind = tower_kind
	grid_col = col
	grid_row = row
	price_paid = paid
	_def = Towers.DEFS[kind]
	position = Grid.tile_to_world_center(col, row)

	var frame: int = _def["upgrade_frames"][0]
	var atlas := AtlasTexture.new()
	atlas.atlas = TOWER_SHEET
	atlas.region = Rect2(
		(frame % SHEET_COLUMNS) * FRAME_SIZE,
		(frame / SHEET_COLUMNS) * FRAME_SIZE,
		FRAME_SIZE, FRAME_SIZE)
	_sprite.texture = atlas
	var target_px := Tiles.TILE_SIZE * float(_def["size"])
	_sprite.scale = Vector2.ONE * (target_px / FRAME_SIZE)

func set_range_visible(is_visible: bool) -> void:
	_range_visible = is_visible
	_range_indicator.visible = is_visible
	_range_indicator.queue_redraw()

func to_targeting_dict() -> Dictionary:
	return {
		"position": position, "range": float(_def["range"]),
		"priority": _priority, "detection": bool(_def["detection"]),
	}

## Called by the board each physics tick with the current enemy candidates.
func tick(delta_ms: float, candidates: Array) -> void:
	_cooldown -= delta_ms
	if _cooldown > 0.0:
		return
	var target = Targeting.select(to_targeting_dict(), candidates)
	if target == null:
		return
	_cooldown = float(_def["fire_rate"])
	wants_to_fire.emit(target["node"],
		{"damage": _def["damage"], "pierce": _def["pierce"]},
		float(_def["base_splash_radius"]))

func get_def() -> Dictionary:
	return _def
```

Attach a small script to `RangeIndicator` that draws the circle:

```gdscript
extends Node2D

var radius := 0.0
var tint := Color.WHITE

func _draw() -> void:
	if not visible or radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius, Color(tint.r, tint.g, tint.b, 0.12))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(tint.r, tint.g, tint.b, 0.6), 1.5)
```

In `Tower.setup`, after `_def` is assigned, set `_range_indicator.radius = float(_def["range"])` and `_range_indicator.tint = _def["color"]`, then `_range_indicator.visible = false`.

- [ ] **Step 2: Implement `game/projectile.gd`**

```gdscript
class_name Projectile
extends Node2D

signal hit(target_node: Node2D, source: Dictionary, splash: float)

const ARC_HEIGHT := 28.0
const HIT_RADIUS := 6.0

var _target: Node2D
var _source := {}
var _speed := 500.0
var _splash := 0.0
var _arcs := false
var _origin := Vector2.ZERO
var _total_distance := 1.0

@onready var _dot: ColorRect = $Dot

func launch(target: Node2D, source: Dictionary, speed: float,
		arcs: bool, splash: float) -> void:
	_target = target
	_source = source
	_speed = speed
	_arcs = arcs
	_splash = splash
	_origin = global_position
	_total_distance = maxf(1.0, _origin.distance_to(target.global_position))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		queue_free()
		return

	var to_target := _target.global_position - global_position
	var step := _speed * delta
	if to_target.length() <= step or to_target.length() <= HIT_RADIUS:
		hit.emit(_target, _source, _splash)
		queue_free()
		return

	global_position += to_target.normalized() * step

	# Arcing is purely how the shot is drawn. It still homes and still hits;
	# a mortar firing flat bolts read as a slow gun rather than as artillery.
	if _arcs:
		var travelled := _origin.distance_to(global_position)
		var t: float = clampf(travelled / _total_distance, 0.0, 1.0)
		_dot.position.y = -sin(t * PI) * ARC_HEIGHT
```

- [ ] **Step 3: Verify it parses and tests still pass**

- [ ] **Step 4: Commit**

```bash
git add game/tower.gd game/tower.tscn game/projectile.gd game/projectile.tscn
git commit -m "Add tower and projectile views

Combat targeting stays in sim/; Area2D on the tower is for tap-picking only."
```

---

## Task 19: Game board

The hub that wires sim to views. Kept deliberately narrower than the original's 1,096-line `GameScene`.

**Files:**
- Create: `game/game_board.gd`, `game/game_board.tscn`

**Interfaces:**
- Consumes: everything above.
- Produces: `GameBoard` (`extends Node2D`) with signals `gold_changed(gold: int)`, `lives_changed(lives: int)`, `wave_changed(wave: int, max_waves: int)`, `game_over()`, `victory()`, `tower_placed(kind: StringName)`, `placement_rejected(reason: String)`.
- Public: `select_tower_kind(kind: StringName)`, `start_next_wave()`, `sell_selected_tower()`, `get_gold() -> int`, `get_lives() -> int`.

**Scene tree:**

```
GameBoard (Node2D)          [script: game_board.gd]
├── MapRenderer (Node2D)    [script: map_renderer.gd]
├── Towers (Node2D)
├── Enemies (Node2D)
├── Projectiles (Node2D)
└── PlacementPreview (Node2D)
```

- [ ] **Step 1: Implement `game/game_board.gd`**

```gdscript
class_name GameBoard
extends Node2D

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int, max_waves: int)
signal wave_state_changed(active: bool)
signal game_over()
signal victory()
signal tower_placed(kind: StringName)
signal placement_rejected(reason: String)

const ENEMY_SCENE := preload("res://game/enemy.tscn")
const TOWER_SCENE := preload("res://game/tower.tscn")
const PROJECTILE_SCENE := preload("res://game/projectile.tscn")

var _map_name: StringName = Maps.FIRST
var _tiles: Array = []
var _paths: Array[PackedVector2Array] = []
var _gold := 0
var _lives := 0
var _wave := 0
var _wave_active := false
var _run_finished := false
var _selected_kind: StringName = &""
var _selected_tower: Tower = null
var _occupied := {}          # Vector2i -> Tower
var _counts := {}            # StringName -> int
var _spawn_queue: Array = []  # {kind, at_ms}
var _wave_clock := 0.0
var _spawned := 0

@onready var _map_renderer: MapRenderer = $MapRenderer
@onready var _towers_root: Node2D = $Towers
@onready var _enemies_root: Node2D = $Enemies
@onready var _projectiles_root: Node2D = $Projectiles

func _ready() -> void:
	var def := Maps.get_def(_map_name)
	Grid.set_active(def["cols"], def["rows"], def["tile_size"])
	_tiles = Maps.build_tiles(_map_name)
	_map_renderer.render(_tiles)
	_paths = PathFinder.get_all_spawn_paths(_tiles)

	_gold = int(def["starting_gold"])
	_lives = Economy.STARTING_LIVES
	for kind in Towers.KINDS:
		_counts[kind] = 0

	gold_changed.emit(_gold)
	lives_changed.emit(_lives)
	wave_changed.emit(_wave, Waves.MAX_WAVES)

func get_gold() -> int: return _gold
func get_lives() -> int: return _lives
func get_wave() -> int: return _wave
func is_wave_active() -> bool: return _wave_active

func select_tower_kind(kind: StringName) -> void:
	_selected_kind = kind
	_deselect_tower()

func start_next_wave() -> void:
	if _wave_active or _run_finished:
		return
	_wave += 1
	if _wave > Waves.MAX_WAVES:
		return
	_wave_active = true
	_wave_clock = 0.0
	_spawned = 0
	_spawn_queue = Harness._build_schedule(_wave)
	wave_changed.emit(_wave, Waves.MAX_WAVES)
	wave_state_changed.emit(true)

func _physics_process(delta: float) -> void:
	if _run_finished:
		return
	var delta_ms := delta * 1000.0

	if _wave_active:
		_wave_clock += delta_ms
		while _spawned < _spawn_queue.size() \
				and _spawn_queue[_spawned]["at_ms"] <= _wave_clock:
			_spawn(_spawn_queue[_spawned]["kind"])
			_spawned += 1

	var candidates: Array = []
	for enemy in _enemies_root.get_children():
		if enemy is Enemy and enemy.sim["alive"] and not enemy.sim["dying"]:
			candidates.append(enemy.to_candidate())

	for tower in _towers_root.get_children():
		if tower is Tower:
			tower.tick(delta_ms, candidates)

	if _wave_active and _spawned >= _spawn_queue.size() \
			and _enemies_root.get_child_count() == 0:
		_on_wave_cleared()

func _spawn(kind: StringName) -> void:
	if _paths.is_empty():
		return
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	_enemies_root.add_child(enemy)
	enemy.setup(kind, _paths[0], _wave)
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)

func _on_enemy_died(reward: int) -> void:
	_gold += reward
	gold_changed.emit(_gold)

func _on_enemy_leaked(life_loss: int) -> void:
	_lives -= life_loss
	lives_changed.emit(_lives)
	if _lives <= 0 and not _run_finished:
		_lives = 0
		_run_finished = true
		_wave_active = false
		game_over.emit()

func _on_wave_cleared() -> void:
	_wave_active = false
	wave_state_changed.emit(false)
	if _wave >= Waves.MAX_WAVES and not _run_finished:
		_run_finished = true
		victory.emit()

# --- Input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _run_finished:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(get_global_mouse_position())
		get_viewport().set_input_as_handled()

func _handle_tap(world: Vector2) -> void:
	var t := Grid.world_to_tile(world.x, world.y)
	if not t["in_bounds"]:
		return
	var key := Vector2i(t["col"], t["row"])

	if _occupied.has(key):
		_select_tower(_occupied[key])
		return

	if _selected_kind == &"":
		_deselect_tower()
		return

	_try_place(t["col"], t["row"])

func _try_place(col: int, row: int) -> void:
	if _tiles[row][col] != Tiles.BUILDABLE:
		placement_rejected.emit("You can only build on open ground.")
		return

	var total := _towers_root.get_child_count()
	if total >= int(Maps.get_def(_map_name)["tower_budget"]):
		placement_rejected.emit("Tower budget reached.")
		return

	if _counts[_selected_kind] >= EconomySim.tower_limit(_selected_kind, _map_name):
		placement_rejected.emit("You cannot build any more of that tower.")
		return

	var price := EconomySim.tower_price(_selected_kind, _counts[_selected_kind])
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		return

	var tower: Tower = TOWER_SCENE.instantiate()
	_towers_root.add_child(tower)
	tower.setup(_selected_kind, col, row, price)
	tower.wants_to_fire.connect(_on_tower_fired.bind(tower))

	_occupied[Vector2i(col, row)] = tower
	_counts[_selected_kind] += 1
	_gold -= price
	_map_renderer.clear_decoration_at(col, row)

	gold_changed.emit(_gold)
	tower_placed.emit(_selected_kind)

func _on_tower_fired(target_node: Node2D, source: Dictionary,
		splash: float, tower: Tower) -> void:
	if not is_instance_valid(target_node):
		return
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	_projectiles_root.add_child(projectile)
	projectile.global_position = tower.global_position
	projectile.hit.connect(_on_projectile_hit)
	projectile.launch(target_node, source,
		float(tower.get_def()["projectile_speed"]),
		bool(tower.get_def()["projectile_arcs"]), splash)

func _on_projectile_hit(target_node: Node2D, source: Dictionary, splash: float) -> void:
	if not is_instance_valid(target_node):
		return
	target_node.take_damage(source)
	if splash <= 0.0:
		return
	for enemy in _enemies_root.get_children():
		if enemy == target_node or not enemy is Enemy:
			continue
		if enemy.global_position.distance_to(target_node.global_position) <= splash:
			enemy.take_damage(source)

func _select_tower(tower: Tower) -> void:
	_deselect_tower()
	_selected_tower = tower
	tower.set_range_visible(true)

func _deselect_tower() -> void:
	if _selected_tower != null and is_instance_valid(_selected_tower):
		_selected_tower.set_range_visible(false)
	_selected_tower = null

func sell_selected_tower() -> void:
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	var tower := _selected_tower
	_deselect_tower()
	_gold += EconomySim.sell_refund(tower.price_paid)
	_counts[tower.kind] -= 1
	_occupied.erase(Vector2i(tower.grid_col, tower.grid_row))
	tower.queue_free()
	gold_changed.emit(_gold)
```

Move `_build_schedule` from `Harness` into `Waves` as a public `Waves.build_schedule(wave: int) -> Array` and call it from both, rather than reaching into `Harness`'s private function. Update `sim/harness.gd` and `test/test_waves.gd` accordingly, adding:

```gdscript
func test_schedule_orders_spawns_by_time() -> void:
	var schedule := Waves.build_schedule(4)
	for i in range(1, schedule.size()):
		assert_true(schedule[i]["at_ms"] >= schedule[i - 1]["at_ms"],
			"schedule is sorted at index %d" % i)
	assert_eq(schedule.size(), 11 + 6 + 2, "wave 4 totals slimes+bees+ogres")
```

- [ ] **Step 2: Run the tests — expect PASS**

- [ ] **Step 3: Commit**

```bash
git add game/game_board.gd game/game_board.tscn sim/harness.gd data/waves.gd test/test_waves.gd
git commit -m "Add game board wiring sim to views

Spawn scheduling moves to Waves.build_schedule so the board and the
headless harness share one implementation."
```

---

## Task 20: HUD and tower panel

Touch-first: every control is a button with a tap target of at least 44×44, and nothing depends on hover.

**Files:**
- Create: `ui/hud.gd`, `ui/hud.tscn`, `ui/tower_panel.gd`, `ui/tower_panel.tscn`

**Interfaces:**
- `Hud` (`extends CanvasLayer`) — `bind(board: GameBoard) -> void`.
- `TowerPanel` (`extends Control`) — `bind(board: GameBoard) -> void`; emits nothing, calls `board.select_tower_kind()` directly.

**Scene trees:**

```
Hud (CanvasLayer)                    TowerPanel (Control)
└── Top (HBoxContainer)              └── Buttons (VBoxContainer)
    ├── GoldLabel (Label)                └── one Button per Towers.KINDS
    ├── LivesLabel (Label)
    ├── WaveLabel (Label)
    ├── StartButton (Button)
    ├── SellButton (Button)
    └── Message (Label)
```

- [ ] **Step 1: Implement `ui/hud.gd`**

```gdscript
class_name Hud
extends CanvasLayer

const MESSAGE_SECONDS := 2.0

@onready var _gold: Label = $Top/GoldLabel
@onready var _lives: Label = $Top/LivesLabel
@onready var _wave: Label = $Top/WaveLabel
@onready var _start: Button = $Top/StartButton
@onready var _sell: Button = $Top/SellButton
@onready var _message: Label = $Top/Message

var _board: GameBoard
var _message_timer := 0.0

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.lives_changed.connect(_on_lives_changed)
	board.wave_changed.connect(_on_wave_changed)
	board.wave_state_changed.connect(_on_wave_state_changed)
	board.placement_rejected.connect(_show_message)
	_start.pressed.connect(board.start_next_wave)
	_sell.pressed.connect(board.sell_selected_tower)

	_on_gold_changed(board.get_gold())
	_on_lives_changed(board.get_lives())
	_on_wave_changed(board.get_wave(), Waves.MAX_WAVES)
	_message.text = ""

func _process(delta: float) -> void:
	if _message_timer <= 0.0:
		return
	_message_timer -= delta
	if _message_timer <= 0.0:
		_message.text = ""

func _on_gold_changed(gold: int) -> void:
	_gold.text = "Gold %d" % gold

func _on_lives_changed(lives: int) -> void:
	_lives.text = "Lives %d" % lives

func _on_wave_changed(wave: int, max_waves: int) -> void:
	_wave.text = "Wave %d / %d" % [wave, max_waves]

func _on_wave_state_changed(active: bool) -> void:
	_start.disabled = active
	_start.text = "In progress" if active else "Start wave"

func _show_message(text: String) -> void:
	_message.text = text
	_message_timer = MESSAGE_SECONDS
```

- [ ] **Step 2: Implement `ui/tower_panel.gd`**

```gdscript
class_name TowerPanel
extends Control

const MIN_TAP_SIZE := Vector2(120, 48)

var _board: GameBoard
var _buttons := {}

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_refresh)
	board.tower_placed.connect(func(_kind): _refresh(board.get_gold()))

	var container: VBoxContainer = $Buttons
	for child in container.get_children():
		child.queue_free()

	for kind in Towers.KINDS:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.toggle_mode = true
		button.pressed.connect(_on_selected.bind(kind))
		container.add_child(button)
		_buttons[kind] = button

	_refresh(board.get_gold())

func _on_selected(kind: StringName) -> void:
	_board.select_tower_kind(kind)
	for k in _buttons:
		_buttons[k].button_pressed = (k == kind)

func _refresh(gold: int) -> void:
	for kind in Towers.KINDS:
		var def: Dictionary = Towers.DEFS[kind]
		# The board owns the authoritative count; the panel shows the base
		# price plus escalation is applied on placement, so display the
		# current asking price by asking the board.
		var price := EconomySim.tower_price(kind, _board.get_tower_count(kind))
		var button: Button = _buttons[kind]
		button.text = "%s\n%d gold" % [def["label"], price]
		button.disabled = not EconomySim.can_afford(gold, price)
```

Add to `game/game_board.gd`:

```gdscript
func get_tower_count(kind: StringName) -> int:
	return _counts.get(kind, 0)
```

- [ ] **Step 3: Run the tests — expect PASS**

- [ ] **Step 4: Commit**

```bash
git add ui/hud.gd ui/hud.tscn ui/tower_panel.gd ui/tower_panel.tscn game/game_board.gd
git commit -m "Add touch-first HUD and tower build panel"
```

---

## Task 21: Scene flow and main scene

**Files:**
- Create: `ui/main_menu.gd`, `ui/main_menu.tscn`, `ui/game_over.gd`, `ui/game_over.tscn`, `ui/victory.gd`, `ui/victory.tscn`, `game/game.gd`, `game/game.tscn`
- Modify: `project.godot` (add `run/main_scene`)

**Interfaces:**
- `Game` (`extends Node2D`) composes `GameBoard`, `Hud` and `TowerPanel`, and swaps in the end screens.

- [ ] **Step 1: Implement `game/game.gd`**

```gdscript
extends Node2D

const GAME_OVER_SCENE := preload("res://ui/game_over.tscn")
const VICTORY_SCENE := preload("res://ui/victory.tscn")

@onready var _board: GameBoard = $GameBoard
@onready var _hud: Hud = $Hud
@onready var _panel: TowerPanel = $Hud/TowerPanel

func _ready() -> void:
	_hud.bind(_board)
	_panel.bind(_board)
	_board.game_over.connect(_on_game_over)
	_board.victory.connect(_on_victory)

func _on_game_over() -> void:
	_show_end_screen(GAME_OVER_SCENE)

func _on_victory() -> void:
	_show_end_screen(VICTORY_SCENE)

func _show_end_screen(scene: PackedScene) -> void:
	var screen := scene.instantiate()
	screen.wave_reached = _board.get_wave()
	add_child(screen)
```

- [ ] **Step 2: Implement the end screens**

`ui/game_over.gd` (and `ui/victory.gd`, identical but for its copy):

```gdscript
extends CanvasLayer

var wave_reached := 0

@onready var _summary: Label = $Panel/Summary
@onready var _retry: Button = $Panel/Retry
@onready var _menu: Button = $Panel/MainMenu

func _ready() -> void:
	_summary.text = "You held until wave %d of %d." % [wave_reached, Waves.MAX_WAVES]
	_retry.pressed.connect(func(): get_tree().reload_current_scene())
	_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/main_menu.tscn"))
```

- [ ] **Step 3: Implement `ui/main_menu.gd`**

```gdscript
extends Control

@onready var _play: Button = $Panel/Play
@onready var _quit: Button = $Panel/Quit

func _ready() -> void:
	_play.pressed.connect(func(): get_tree().change_scene_to_file("res://game/game.tscn"))
	_quit.pressed.connect(func(): get_tree().quit())
	# Quit is meaningless in a browser build.
	_quit.visible = OS.get_name() != "Web"
```

- [ ] **Step 4: Set the main scene**

Add to `project.godot` under `[application]`:

```ini
run/main_scene="res://ui/main_menu.tscn"
```

- [ ] **Step 5: Run the game and verify by screenshot**

```bash
godot --headless --import
```

Then launch it via the Godot MCP `run_project` tool against `~/Projects/project-t-godot`, take a screenshot, and confirm: the map renders with grass, path, castle and cave; the HUD shows `Gold 100`, `Lives 20`, `Wave 0 / 20`; four build buttons appear with correct prices (20/50/70/100).

Place a Basic tower, start wave 1, and confirm slimes walk the path and are shot.

- [ ] **Step 6: Commit**

```bash
git add ui/ game/game.gd game/game.tscn project.godot
git commit -m "Add scene flow: main menu, game, game over and victory"
```

---

## Task 22: Audio

**Files:**
- Create: `audio/audio_manager.gd`
- Modify: `project.godot` (autoload), `game/game_board.gd`, `ui/hud.gd`

**Interfaces:**
- Produces: autoload singleton `AudioManager` — `play(sound: StringName) -> void`, `set_muted(muted: bool) -> void`.

Only the sounds the core slice can fire are wired: `place`, `sell`, `denied`, `ui-click`, `wave-start`, `wave-clear`, `leak`, `victory`, `defeat`, `fire-basic`, `fire-fast`, `fire-mortar`, `fire-long`, `death-slime`, `death-ogre`, `death-bee`, `explosion`.

- [ ] **Step 1: Implement `audio/audio_manager.gd`**

```gdscript
extends Node

## Sounds the core slice can fire. Others exist in assets/audio and are wired
## by the phases that introduce their events.
const SOUNDS := [
	&"place", &"sell", &"denied", &"ui-click", &"wave-start", &"wave-clear",
	&"leak", &"victory", &"defeat", &"fire-basic", &"fire-fast",
	&"fire-mortar", &"fire-long", &"death-slime", &"death-ogre",
	&"death-bee", &"explosion",
]

const POOL_SIZE := 12

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _muted := false

func _ready() -> void:
	for name in SOUNDS:
		for ext in [".ogg", ".wav"]:
			var path := "res://assets/audio/%s%s" % [name, ext]
			if ResourceLoader.exists(path):
				_streams[name] = load(path)
				break
		if not _streams.has(name):
			push_warning("missing sound: %s" % name)

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

func play(sound: StringName) -> void:
	if _muted or not _streams.has(sound):
		return
	var player := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	player.stream = _streams[sound]
	player.play()

func set_muted(muted: bool) -> void:
	_muted = muted
```

A pool of players is used rather than one, so overlapping sounds do not cut each other off — with eight towers firing, a single player would drop most shots.

- [ ] **Step 2: Register the autoload**

Add to `project.godot`:

```ini
[autoload]

AudioManager="*res://audio/audio_manager.gd"
```

- [ ] **Step 3: Wire the calls**

In `game/game_board.gd`:
- `_try_place` success → `AudioManager.play(&"place")`; each `placement_rejected` path → `AudioManager.play(&"denied")`
- `sell_selected_tower` → `AudioManager.play(&"sell")`
- `start_next_wave` → `AudioManager.play(&"wave-start")`
- `_on_wave_cleared` → `AudioManager.play(&"wave-clear")`
- `_on_enemy_leaked` → `AudioManager.play(&"leak")`
- `_on_enemy_died` → `AudioManager.play(&"death-%s" % kind)` (pass the kind through the `died` signal)
- `_on_tower_fired` → `AudioManager.play(&"fire-%s" % tower.kind)`
- `game_over` → `defeat`; `victory` → `victory`

Change `Enemy`'s signal to `died(reward: int, kind: StringName)` and update `GameBoard._on_enemy_died` to match.

- [ ] **Step 4: Verify audio plays**

Run the project via the MCP and confirm no `missing sound` warnings in the log. Godot's web export requires a user gesture before audio starts; the main menu's Play button supplies it, so no explicit unlock call is needed — this was the single most common way audio "didn't work" in the Phaser build.

- [ ] **Step 5: Commit**

```bash
git add audio/ project.godot game/game_board.gd game/enemy.gd ui/hud.gd
git commit -m "Add pooled audio playback for core-slice events"
```

---

## Task 23: Web export and README

**Files:**
- Create: `export_presets.cfg`, `README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Install web export templates**

```bash
godot --headless --quit 2>&1 | head -5
ls ~/.local/share/godot/export_templates/
```

If the 4.7.1 templates are absent, install them from the editor (`Editor → Manage Export Templates → Download`) or place them in `~/.local/share/godot/export_templates/4.7.1.stable/`.

- [ ] **Step 2: Add a Web export preset**

Create `export_presets.cfg` with a `Web` preset targeting `export/web/index.html`. Set `variant/thread_support=false` — threads require COOP/COEP headers that most static hosts do not send, and the spec forbids them.

- [ ] **Step 3: Export and check size**

```bash
mkdir -p export/web
godot --headless --export-release "Web" export/web/index.html
du -sh export/web/
ls -la export/web/
```

Record the total. The spec anticipates 25–40 MB; the pre-sliced atlas and OGG audio are the mitigations already applied.

- [ ] **Step 4: Smoke-test the build**

```bash
cd export/web && python3 -m http.server 8000
```

Open `http://localhost:8000`, confirm the menu loads, a game starts, towers place, and a wave runs.

- [ ] **Step 5: Write `README.md`**

Cover: what the project is and its relationship to the Phaser original; how to run (`godot --path . `); how to test (`godot --headless --quit --script test/run_tests.gd`); how to export; the sim/view boundary rule and why it exists; what is in the core slice and what is deferred; and a pointer to the spec and this plan.

- [ ] **Step 6: Commit**

```bash
git add export_presets.cfg README.md .gitignore
git commit -m "Add web export preset and README"
```

---

## Self-Review

**Spec coverage.** Every section maps to a task: scope §3 → Tasks 6/7 (data) and 19 (flow); the boundary rule §5 → Task 13; layout §5 → Tasks 1–20; rules §6 → Tasks 2–12; assets §7 → Task 15; web/mobile §8 → Tasks 1 and 23; not-reproduced §9 → honoured by Task 19 building a single board rather than two scenes with separate emitters; testing §10 → Tasks 1, 13, 14; risks §11 → mitigated in Task 15 Step 6 (visual verification) and Task 14 (timing via harness). Definition of done §12 → Task 21 Step 5 and Task 23 Step 4.

**Deferred deliberately, matching the spec's "Out" list:** enemy properties (so `Waves.propertiesFor` is not ported), upgrade branches, bosses, powers, currencies beyond gold, meta-progression, maps 2–3, auth.

**Two corrections made during review, already applied above:**
- `Harness._build_schedule` was private but needed by `GameBoard`; Task 19 promotes it to `Waves.build_schedule` and updates both callers plus the wave tests.
- `TowerPanel` needed the live per-kind tower count to show the escalated price; Task 20 adds `GameBoard.get_tower_count`.

**Naming consistency checked:** `EconomySim` (sim) versus `Economy` (data) is deliberate and used consistently from Task 12 onward. `Enemy.died` gains a `kind` parameter in Task 22 and both the emitter and the handler are updated there. `Grid.set_active` (not `set_active_grid`) is used in every task from 3 onward.
