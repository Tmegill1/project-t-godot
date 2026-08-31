# Multi-lane Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `Harness.run_wave` simulate any number of lanes, so The Fork and The Coils can be measured the way The Pass already is, and benchmark every map rather than one.

**Architecture:** `run_wave` gains `config["paths"]`; `config["path"]` stays and means `paths: [path]`. Each enemy carries a `lane` index, route metrics are precomputed per lane, and spawning uses one shared schedule with a cursor per lane — mirroring `game_board.gd`'s `_spawn_queues` / `_spawned_per_path` rather than approximating it. Backward compatibility is the load-bearing guarantee: 64 existing call sites must keep working unedited and return byte-identical results.

**Tech Stack:** Godot 4.7.1, GDScript. No new dependencies, no new assets.

**Spec:** [`docs/superpowers/specs/2026-08-30-multi-lane-harness-design.md`](../specs/2026-08-30-multi-lane-harness-design.md)

## Global Constraints

- **Godot 4.7.1**, GDScript only. Static typing throughout, matching the codebase.
- **Run the suite with** `godot --headless --quit --script test/run_tests.gd`. Exit code 0 means pass. A green run prints many `SCRIPT ERROR` lines to stderr by design — **judge by the exit code, never by stderr**.
- **Every `test_*` method must be declared `-> bool` and end with `return true`**, including every early return. Enforced crash detection, not style.
- **`data/` and `sim/` are pure.** `test/test_sim_purity.gd` bans scene types, clocks, RNG and platform state.
- **No call site may be edited to make a test pass.** The 64 existing `Harness.run_wave` calls are the project's measured corpus. If one of their numbers moves, the change is wrong — fix the change, not the pin.
- **Adding a new `class_name` needs `godot --headless --import`** before the suite sees it, or it fails with `Parse Error: Identifier "X" not declared`. That pass also writes the `.uid`; every other `.gd.uid` here is tracked, so commit it with its script.
- **NO NEW ASSETS.** Standing owner rule in `.ai/handoff.md`: if any visual, audio, animation, sprite, texture or icon turns out to be needed, stop and return to Codex.
- **Do not commit `test/test_balance_tuning.gd.uid`.** It is untracked deliberately.
- **Another agent may be working in this tree.** `git status` before every commit and stage only the files the task names. Never `git add -A`.
- **Pushing to `master` redeploys the live site.** Do not push without the owner asking.
- **Suite runtime budget is three minutes.** Task 4 names the fallback if the honest implementation exceeds it.

---

## File Structure

| File | Responsibility |
|---|---|
| `sim/harness.gd` | **Modify.** Accept `paths`; per-lane routes, spawn cursors and wave-clear. |
| `test/test_harness.gd` | **Modify.** Compatibility, spawning, wave-clear, determinism. |
| `test/test_balance_tuning.gd` | **Modify.** Per-map placement helper and per-map benchmarks. |
| `update.md`, `CONTINUE.md` | **Modify.** Task 6. |

---

## Task 1: `run_wave` accepts `paths`, and one lane is unchanged

The whole task is the compatibility guarantee. Multi-lane spawning arrives in Task 2; here the internals become lane-aware while still running exactly one lane.

**Files:**
- Modify: `sim/harness.gd` — the config header, the counters, the spawn block, the movement block, the death record
- Test: `test/test_harness.gd`

**Interfaces:**
- Produces: `Harness.run_wave` honours `config["paths"]: Array` of `PackedVector2Array`; `config["path"]` continues to mean `paths: [path]`. Enemy dictionaries carry `"lane": int`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_harness.gd`:

```gdscript
# --------------------------------------------------------------------------
# Lanes
# --------------------------------------------------------------------------

# THE compatibility guarantee. Every balance number this project has measured
# came through the single-path interface, so `paths: [p]` has to be that
# interface and not merely something close to it - equality, including ticks
# and both progress fields, not a tolerance.
func test_one_lane_by_either_name_is_the_same_wave() -> bool:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var path := _path()
	var by_path := Harness.run_wave({"wave": 6, "towers": towers, "path": path})
	var by_lanes := Harness.run_wave({"wave": 6, "towers": towers, "paths": [path]})
	assert_eq(by_lanes, by_path, "paths:[p] is exactly path:p")
	return true
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `config["path"]` is read unconditionally, so a config with only `paths` errors, and `paths` is ignored.

- [ ] **Step 3: Make the harness lane-aware**

In `sim/harness.gd`, replace the path line at the top of `run_wave`:

```gdscript
	var path: PackedVector2Array = config["path"]
```

with:

```gdscript
	# One lane or many. `path` is the older spelling and means exactly one
	# lane; every balance number this project has measured came through it, so
	# it stays a first-class spelling rather than a deprecated one.
	var paths: Array = config["paths"] if config.has("paths") else [config["path"]]
```

Replace the single route metric with one per lane:

```gdscript
	var route := _route_metrics(path)
```

becomes:

```gdscript
	# Precomputed once per lane. A lane's route never changes during a wave and
	# this is read for every living enemy on every tick.
	var routes: Array = []
	for lane_path in paths:
		routes.append(_route_metrics(lane_path))
```

In the spawn block, the enemy dictionary gains its lane and takes its start
from that lane. Replace:

```gdscript
			enemies.append({
				"id": next_id,
				"kind": kind,
				"position": path[0],
				"path_index": Movement.starting_path_index(path[0], path),
```

with:

```gdscript
			var lane_path: PackedVector2Array = paths[lane]
			enemies.append({
				"id": next_id,
				"kind": kind,
				# The lane this enemy walks. Carried on the enemy rather than
				# looked up, because a lane belongs to the thing walking it -
				# which is why targeting, damage, splash, slow and the aura all
				# needed no changes at all: none of them ever looks at a path.
				"lane": lane,
				"position": lane_path[0],
				"path_index": Movement.starting_path_index(lane_path[0], lane_path),
```

Wrap the existing spawn `while` in a per-lane loop. The block currently reads
`while spawned < schedule.size() and schedule[spawned]["at_ms"] <= elapsed:`;
make `spawned` an array and iterate lanes. Replace the counter declaration:

```gdscript
	var spawned := 0
```

with:

```gdscript
	# One cursor per lane over one shared schedule, mirroring GameBoard's
	# _spawn_queues and _spawned_per_path. Sharing the schedule is safe because
	# it is only ever read, and build_schedule already returns fresh
	# dictionaries per call - the board's own comment records that a per-lane
	# deep copy was measured to change nothing.
	var spawned: Array[int] = []
	for i in paths.size():
		spawned.append(0)
```

and the spawn loop header:

```gdscript
		# Spawns due this tick.
		while spawned < schedule.size() and schedule[spawned]["at_ms"] <= elapsed:
			var s: Dictionary = schedule[spawned]
```

with:

```gdscript
		# Spawns due this tick, lane by lane. Every lane issues the WHOLE
		# schedule, so an N-lane map fields N times the enemies of the same
		# wave number - which is what the board does and what The Fork's map
		# comment has always claimed.
		for lane in paths.size():
			while spawned[lane] < schedule.size() \
					and schedule[spawned[lane]]["at_ms"] <= elapsed:
				var s: Dictionary = schedule[spawned[lane]]
```

Indent the rest of that block one level and change its two trailing lines from

```gdscript
			next_id += 1
			spawned += 1
```

to

```gdscript
				next_id += 1
				spawned[lane] += 1
```

In the movement block, take the walking enemy's own lane. Replace:

```gdscript
			var m := Movement.advance(e["position"], e["path_index"], path,
				Slow.effective_speed(float(e["speed"]), e["slow"]), tick_ms)
```

with:

```gdscript
			var lane_path: PackedVector2Array = paths[e["lane"]]
			var m := Movement.advance(e["position"], e["path_index"], lane_path,
				Slow.effective_speed(float(e["speed"]), e["slow"]), tick_ms)
```

and the progress record just below it:

```gdscript
			deepest_progress = maxf(deepest_progress,
				_progress_of(e["position"], e["path_index"], path, route))
```

with:

```gdscript
			# A fraction of ITS OWN lane, maxed across lanes - so a single-lane
			# wave reports exactly what it always did.
			deepest_progress = maxf(deepest_progress,
				_progress_of(e["position"], e["path_index"], lane_path, routes[e["lane"]]))
```

and the death record:

```gdscript
					death_progress_total += _progress_of(
						e["position"], e["path_index"], path, route)
```

with:

```gdscript
					death_progress_total += _progress_of(e["position"],
						e["path_index"], paths[e["lane"]], routes[e["lane"]])
```

Finally the wave-clear condition, which still checks one cursor:

```gdscript
		if spawned >= schedule.size() and enemies.is_empty():
```

becomes:

```gdscript
		if _all_spawns_issued(spawned, schedule.size()) and enemies.is_empty():
```

and add the helper beside `_result`:

```gdscript
## Whether every lane has issued its whole schedule.
##
## Checking one cursor is not enough: a wave is not over while any entrance
## still has enemies to send. GameBoard._all_spawns_issued exists for exactly
## this reason and says exactly this.
static func _all_spawns_issued(spawned: Array[int], total: int) -> bool:
	for issued in spawned:
		if issued < total:
			return false
	return true
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

Expected: `exit=0`, with **no call site edited**. Every one of the 64 existing
`run_wave` calls passes a single `path` and must produce the number it produced
before. If any balance pin moves, the change is wrong — fix the change.

- [ ] **Step 5: Commit**

```bash
git add sim/harness.gd test/test_harness.gd
git commit -m "Let the harness take lanes, one of which is what it took before"
```

---

## Task 2: Two lanes are two lanes

Task 1's loops already iterate `paths`, so this task is mostly proving the behaviour rather than adding it — which is the point of splitting them. If an assertion here fails, Task 1's plumbing is wrong somewhere specific.

**Files:**
- Test: `test/test_harness.gd`
- Modify: `sim/harness.gd` only if an assertion below fails

**Interfaces:**
- Consumes: `config["paths"]` (Task 1).

- [ ] **Step 1: Write the tests**

Append to `test/test_harness.gd`:

```gdscript
## The Fork's own two lanes, so this is the shipped geometry rather than a
## fixture that happens to have two entries.
func _fork_paths() -> Array:
	Grid.set_active(Maps.cols(&"map2"), Maps.rows(&"map2"))
	return PathFinder.get_all_spawn_paths(Maps.build_tiles(&"map2"))

func test_the_fork_really_has_two_lanes() -> bool:
	assert_eq(_fork_paths().size(), 2, "the fixture below is worth having")
	return true

# Every lane issues the WHOLE schedule, so two entrances field twice the wave.
# That is the board's behaviour - one shared schedule, a cursor each - and the
# thing a per-lane simulation summed afterwards could never reproduce.
func test_each_lane_runs_the_whole_wave() -> bool:
	var lanes := _fork_paths()
	var one := Harness.run_wave({"wave": 4, "towers": [], "paths": [lanes[0]]})
	var both := Harness.run_wave({"wave": 4, "towers": [], "paths": lanes})
	assert_eq(int(both["leaks"]), int(one["leaks"]) * 2,
		"two lanes leak twice as many, undefended")
	return true

# A wave is not over while any entrance still has enemies to send.
func test_a_wave_does_not_clear_while_a_lane_still_has_spawns() -> bool:
	var lanes := _fork_paths()
	var both := Harness.run_wave({"wave": 4, "towers": [], "paths": lanes})
	var longest := Harness.run_wave({"wave": 4, "towers": [], "paths": [lanes[0]]})
	assert_true(int(both["ticks"]) >= int(longest["ticks"]),
		"a two-lane wave runs at least as long as either lane alone")
	assert_false(both["timed_out"], "and it does finish")
	return true

func test_lanes_are_deterministic() -> bool:
	var lanes := _fork_paths()
	var config := {"wave": 7, "towers": [], "paths": lanes}
	assert_eq(Harness.run_wave(config), Harness.run_wave(config),
		"same lanes, same config, same result")
	return true

# Progress is a fraction of an enemy's OWN lane, so it stays a fraction however
# many lanes there are and however different their lengths.
func test_progress_stays_a_fraction_across_lanes() -> bool:
	var lanes := _fork_paths()
	var r := Harness.run_wave({"wave": 4, "towers": [], "paths": lanes})
	assert_almost_eq(r["deepest_progress"], 1.0, 0.01,
		"undefended, something reaches the end of its lane")
	assert_true(r["progress_at_death"] >= 0.0 and r["progress_at_death"] <= 1.0,
		"and the mean death depth is a fraction")
	return true
```

- [ ] **Step 2: Run them**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

Expected: `exit=0`. These pass on Task 1's implementation if it is right. **If
one fails, do not weaken it** — it is pointing at a specific defect in Task 1:
a shared cursor, a lane-blind route lookup, or a wave-clear that checks one
queue.

- [ ] **Step 3: Commit**

```bash
git add test/test_harness.gd
git commit -m "Pin what two lanes mean"
```

---

## Task 3: Twelve towers on any map, placed by a stated rule

**Files:**
- Modify: `test/test_balance_tuning.gd`
- Test: `test/test_balance_tuning.gd`

**Interfaces:**
- Produces: `_lanes_for(map_name) -> Array`, `_spread_positions(map_name) -> Array[Vector2]`, `_board_on(map_name, splits) -> Array`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_balance_tuning.gd`:

```gdscript
# --------------------------------------------------------------------------
# Placing twelve towers on a map nobody hardcoded
# --------------------------------------------------------------------------

# Where twelve towers land decides what a benchmark says, so the rule is
# stated and pinned rather than left to whatever the loop happened to find.
# A naive "first twelve legal tiles" clusters them in a corner and makes a map
# look far worse than it plays.
func test_every_generated_position_is_one_the_board_would_accept() -> bool:
	for map_name in Maps.DEFS:
		var positions := _spread_positions(map_name)
		var budget := int(Maps.get_def(map_name)["tower_budget"])
		assert_eq(positions.size(), budget,
			"%s yields its whole budget of %d" % [map_name, budget])

		Grid.set_active(Maps.cols(map_name), Maps.rows(map_name))
		var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(map_name)))
		var radius := Placement.tower_radius(&"basic")
		var placed: Array = []
		for pos in positions:
			var verdict := Placement.can_place(
				pos, radius, [], placed, _lanes_for(map_name), bounds)
			assert_true(verdict["ok"],
				"%s position %s is legal, got %s" % [map_name, pos, verdict])
			placed.append(pos)
	return true
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `_spread_positions` and `_lanes_for` do not exist.

- [ ] **Step 3: Implement the helpers**

Add to `test/test_balance_tuning.gd`:

```gdscript
## Every lane of a map, in the order PathFinder reports them.
func _lanes_for(map_name: StringName) -> Array:
	Grid.set_active(Maps.cols(map_name), Maps.rows(map_name))
	return PathFinder.get_all_spawn_paths(Maps.build_tiles(map_name))

## The map's whole tower budget, spaced along its lanes.
##
## THE RULE, stated because a benchmark whose placement is not stated is a
## number nobody can argue with: walk each lane, take evenly spaced points
## along it, and put a tower at the nearest legal spot to each. The budget is
## divided between the lanes rather than spread over a concatenated route -
## six and six on a two-lane map - because both lanes carry the same wave, and
## spacing by total distance would under-cover the shorter one.
##
## Legality is asked of Placement.can_place, the same rule the board enforces,
## rather than reimplemented. Props are deliberately passed as EMPTY: decoration
## is seeded, and a benchmark that moved with the decoration seed would not be a
## benchmark. Build space against decoration is test_placement.gd's job.
func _spread_positions(map_name: StringName) -> Array[Vector2]:
	var lanes := _lanes_for(map_name)
	var budget := int(Maps.get_def(map_name)["tower_budget"])
	var bounds := Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(map_name)))
	var radius := Placement.tower_radius(&"basic")
	var tiles := Maps.build_tiles(map_name)

	var positions: Array[Vector2] = []
	var per_lane := int(ceil(float(budget) / float(maxi(1, lanes.size()))))
	for lane in lanes:
		for i in per_lane:
			if positions.size() >= budget:
				break
			var along: Vector2 = lane[int(float(lane.size() - 1)
				* (float(i) + 0.5) / float(per_lane))]
			var spot := _nearest_legal(along, tiles, positions, lanes, bounds, radius)
			if spot != Vector2.INF:
				positions.append(spot)
	return positions

## The legal tile centre closest to a point on the route, searched outward so
## the tower lands beside the road it is meant to cover.
func _nearest_legal(near: Vector2, tiles: Array, placed: Array, lanes: Array,
		bounds: Rect2, radius: float) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for r in tiles.size():
		for c in tiles[r].size():
			var pos := Grid.tile_to_world_center(c, r)
			var distance := pos.distance_to(near)
			if distance >= best_distance:
				continue
			if Placement.can_place(pos, radius, [], placed, lanes, bounds)["ok"]:
				best = pos
				best_distance = distance
	return best

## Twelve towers on any map, each kind on the split named for it.
func _board_on(map_name: StringName, splits: Array) -> Array:
	var positions := _spread_positions(map_name)
	var towers: Array = []
	var per_kind := int(positions.size() / Towers.KINDS.size())
	var i := 0
	for k in Towers.KINDS.size():
		for n in per_kind:
			towers.append({"kind": Towers.KINDS[k],
				"position": positions[i], "tiers": splits[k]})
			i += 1
	return towers
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add test/test_balance_tuning.gd
git commit -m "Place a benchmark board on any map, by a stated rule"
```

---

## Task 4: Benchmark every map

**Files:**
- Modify: `test/test_balance_tuning.gd`

**Interfaces:**
- Consumes: `_board_on`, `_lanes_for` (Task 3); `config["paths"]` (Task 1).

- [ ] **Step 1: Time the suite as it stands**

Run: `time godot --headless --quit --script test/run_tests.gd`

Record the figure. The budget is **three minutes**; Step 4 needs the before and
after to know whether the fallback applies.

- [ ] **Step 2: Add the per-map benchmarks**

Append to `test/test_balance_tuning.gd`:

```gdscript
# --------------------------------------------------------------------------
# Every map, not just the one that was easy to measure
# --------------------------------------------------------------------------
#
# The Pass keeps the sixteen-board sweeps above: the branch-spread bound needs
# the full set, and it is the map every tier value was measured against. The
# other maps are asked the narrower question they exist to answer - does a
# completed board hold this map, and does the hardest tier still bite - which
# the two extreme builds answer between them.

func test_every_map_is_comfortable_on_normal_for_a_completed_board() -> bool:
	for map_name in Maps.DEFS:
		for splits in [[SUSTAINED, SUSTAINED, SUSTAINED, SUSTAINED],
				[BURST, BURST, BURST, BURST]]:
			var r := Harness.run_wave({"wave": Waves.MAX_WAVES,
				"towers": _board_on(map_name, splits), "paths": _lanes_for(map_name),
				"difficulty": Difficulty.NORMAL})
			assert_eq(r["leaks"], 0,
				"%s stays comfortable on Normal for a completed board, got %s"
					% [map_name, r])
			assert_false(r["timed_out"], "%s completes" % map_name)
	return true

func test_no_map_shuts_out_the_hardest_tier() -> bool:
	for map_name in Maps.DEFS:
		for splits in [[SUSTAINED, SUSTAINED, SUSTAINED, SUSTAINED],
				[BURST, BURST, BURST, BURST]]:
			var r := Harness.run_wave({"wave": Waves.MAX_WAVES,
				"towers": _board_on(map_name, splits), "paths": _lanes_for(map_name),
				"difficulty": Difficulty.NIGHTMARE})
			assert_true(r["leaks"] > 0,
				"%s must not shut out Nightmare's last wave, got %s" % [map_name, r])
	return true
```

- [ ] **Step 3: Run the full suite**

Run: `time godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

**A failure here is very likely and is not automatically a defect in this
work.** The Fork and The Coils have never been measured. If one of them shuts
out Nightmare, or leaks on Normal, that is Task 5's finding — carry it forward,
say so in the commit, and **do not weaken either assertion and do not retune a
map**. The spec's non-goals say why: retuning inside the change that made
measurement possible destroys the evidence it was built to produce.

If the failure is instead about *placement* — a map yielding fewer than twelve
towers, or towers stacked on one another — that is a Task 3 defect and belongs
back there.

- [ ] **Step 4: Check the runtime budget**

Compare against Step 1.

Step 2 already spends the spec's first fallback: the per-map benchmarks sweep
**two** builds rather than the sixteen The Pass gets. If the suite still exceeds
**three minutes** after that, take the second cut — drop the Normal benchmark to
the **burst** build alone. Burst is the weaker of the two against late waves, so
it is the binding case for "does a completed board hold this map"; the Nightmare
benchmark keeps both builds, because that is the one asking whether any build
shuts a map out.

Record whichever cut was taken in the test's own comment, with the runtime that
forced it. A budget met by quietly measuring less is worth no more than a budget
missed.

- [ ] **Step 5: Commit**

```bash
git add test/test_balance_tuning.gd
git commit -m "Benchmark every map, not just the one that was easy to measure"
```

---

## Task 5: Measure The Fork and The Coils, and report

**Files:**
- Create then delete: `probe_maps.gd`
- Modify: `update.md` (the finding)

- [ ] **Step 1: Write the probe**

Create `probe_maps.gd` in the project root — **throwaway, deleted in Step 3**:

```gdscript
extends SceneTree

## Throwaway: what every map actually looks like, now that they can be measured.

const SUSTAINED := {&"sustained": 4, &"burst": 2}
const BURST := {&"sustained": 2, &"burst": 4}

func _lanes(map_name: StringName) -> Array:
	Grid.set_active(Maps.cols(map_name), Maps.rows(map_name))
	return PathFinder.get_all_spawn_paths(Maps.build_tiles(map_name))

func _init() -> void:
	var suite = load("res://test/test_balance_tuning.gd").new()
	for map_name in Maps.DEFS:
		var lanes := _lanes(map_name)
		var length := 0.0
		for lane in lanes:
			for i in range(1, lane.size()):
				length += lane[i - 1].distance_to(lane[i])
		for tier in Difficulty.ORDER:
			for build in [{"n": "S", "t": SUSTAINED}, {"n": "B", "t": BURST}]:
				var splits := [build["t"], build["t"], build["t"], build["t"]]
				var towers: Array = suite._board_on(map_name, splits)
				var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": towers,
					"paths": lanes, "difficulty": tier})
				print("PROBE %-8s %d lane(s) %5.0fpx | %-9s %s | leaks %3d lives %3d deepest %.2f" % [
					map_name, lanes.size(), length, tier, build["n"],
					r["leaks"], r["lives_lost"], r["deepest_progress"]])
	quit(0)
```

- [ ] **Step 2: Run it and read the result**

Run: `godot --headless --quit --script probe_maps.gd 2>/dev/null | grep PROBE`

- [ ] **Step 3: Delete the probe**

```bash
rm -f probe_maps.gd probe_maps.gd.uid
```

- [ ] **Step 4: Write the finding into `update.md`**

Record what the three maps look like side by side: lanes, route length, and how
each tier treats a completed board. **Report it; do not act on it.** If The Fork
or The Coils is badly balanced, say so plainly and leave the numbers alone — the
owner decides what happens next, and this change exists to make that decision
possible rather than to pre-empt it.

- [ ] **Step 5: Commit**

```bash
git add update.md
git commit -m "Report what the other two maps actually look like"
```

---

## Task 6: Update the docs

**Files:**
- Modify: `update.md`, `CONTINUE.md`

- [ ] **Step 1: `update.md`**

Move the multi-lane harness from "the biggest hole in this project's measurement
story" to done, and say what it now makes possible. The Fork's purse comment
records that it was not simulated; note that it now *can* be, and whether the
number survived contact with measurement.

- [ ] **Step 2: `CONTINUE.md`**

`sim/harness.gd`'s "one lane" simplification is quoted in §5's engine-and-harness
facts. Correct it, and record the two things a reader must not undo: `path` and
`paths: [path]` are the same interface, and the per-map benchmark's placement
rule is stated in `test_balance_tuning.gd` because a benchmark whose placement
is unstated is a number nobody can argue with.

- [ ] **Step 3: Commit**

```bash
git add update.md CONTINUE.md
git commit -m "Bring the docs up to a harness that can see every map"
```

---

## Self-review

**Spec coverage.** §3's lane-as-index → Task 1. §4's spawning, wave-clear and
progress → Tasks 1 and 2. §5's compatibility guarantee → Task 1 Step 1's
equality assertion and Step 4's unedited-call-site rule. §6's placement rule and
its honesty problem → Task 3, with the rule written into the helper's own doc
comment. §7's runtime budget and named fallback → Task 4 Steps 1 and 4. §8's
testing table → Tasks 1–4. §9's "The Fork may be badly balanced" risk → Task 4
Step 3 and Task 5, both of which forbid retuning and require reporting.

**Placeholders.** None. Task 5's numbers come from a probe whose code is given;
Task 4's runtime decision has its threshold and its fallback stated in advance.

**Type consistency.** `paths` is an `Array` of `PackedVector2Array` throughout.
`spawned` is `Array[int]` from Task 1 and consumed by `_all_spawns_issued` in
the same task. `_lanes_for`, `_spread_positions` and `_board_on` are defined in
Task 3 and consumed unchanged in Tasks 4 and 5. `SUSTAINED` and `BURST` already
exist in `test_balance_tuning.gd` and are reused rather than redefined.
