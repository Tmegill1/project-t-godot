# Difficulty Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-run difficulty selector whose harder tiers attack board coverage — the measured binding constraint — and close the measurement gap that let a shut-out board read as balanced.

**Architecture:** Difficulty is a **parameter**, never a global. `data/difficulty.gd` holds a pure tier table; `Waves.get_composition`, `Waves.get_modifiers` and `Waves.build_schedule` each take a tier defaulting to `Difficulty.NORMAL`; `Harness.run_wave` reads it from its config dict. Normal is the exact identity transform, so all 13,436 existing assertions describe Normal, pass unchanged, and become the regression net for this work. The live board carries the choice between scenes the way `GameBoard.pending_map` already carries the map.

**Tech Stack:** Godot 4.7.1, GDScript. No new dependencies, no new assets.

**Spec:** [`docs/superpowers/specs/2026-08-29-difficulty-selector-design.md`](../specs/2026-08-29-difficulty-selector-design.md)

## Global Constraints

- **Godot 4.7.1**, GDScript only. Static typing throughout, matching the codebase.
- **Run the suite with** `godot --headless --quit --script test/run_tests.gd`. Exit code 0 means pass. A green run prints many `SCRIPT ERROR` lines to stderr by design — **judge by the exit code, never by stderr**.
- **Every `test_*` method must be declared `-> bool` and end with `return true`**, including every early return. This is an enforced crash-detection contract, not a style rule.
- **`data/` and `sim/` are pure.** `test/test_sim_purity.gd` bans scene types, clocks, RNG and platform state. Difficulty must not become a mutable global — that is the whole point of threading it as a parameter.
- **Normal must stay byte-identical.** Any change to a Normal-path number is a bug in this work, not a rebalance. The existing suite is the detector.
- **NO NEW ASSETS.** Standing owner rule in `.ai/handoff.md`: if any visual, audio, animation, sprite, texture or icon turns out to be needed, **stop and return to Codex**. Everything here uses existing `Button` nodes and the existing theme.
- **Do not commit `test/test_balance_tuning.gd.uid`** or anything under `.ai/`. Both are untracked deliberately.
- **Another agent may be working in this tree.** Before every commit, run `git status` and stage only the files the task names. Never `git add -A`.
- **Pushing to `master` redeploys the live site.** Do not push without the owner asking.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/difficulty.gd` | **Create.** Pure tier table plus accessors. The only place a difficulty number lives. |
| `data/waves.gd` | **Modify.** Three functions gain an optional tier. |
| `data/enemies.gd` | **Modify.** Base health bump (Task 9 only). |
| `sim/harness.gd` | **Modify.** Accept `difficulty`; add route-progress reporting. |
| `game/game_board.gd` | **Modify.** `pending_difficulty` static; tier-sourced starting lives; pass tier to `build_schedule`. |
| `game/enemy.gd` | **Modify.** Pass tier to `get_modifiers` at both call sites. |
| `ui/main_menu.gd` / `.tscn` | **Modify.** Three tier buttons. |
| `ui/hud.gd` / `.tscn` | **Modify.** Show the active tier. |
| `test/test_difficulty.gd` | **Create.** Table shape, identity, monotonicity. |
| `test/test_affordability.gd` | **Create.** What a run can actually fund. |
| `test/test_balance_tuning.gd` | **Modify.** Full twelve-tower board at every tier. |
| `test/test_waves.gd`, `test/test_harness.gd` | **Modify.** Tier plumbing and determinism. |

---

## Task 1: Measure what a run can afford

The spec names this as the open risk and requires it **before any tier value is set**. The shut-out threshold of ten maxed towers assumes ten maxed towers are fundable; `121bc7f` cut the budget 16 → 12 without moving `GOLD_PER_WAVE`, so the spend ceiling fell and income did not.

**Files:**
- Create: `test/test_affordability.gd`

**Interfaces:**
- Consumes: `Harness.run_wave`, `EconomySim.tower_price`, `EconomySim.wave_clear_bonus`, `UpgradesSim.total_invested`, `Maps`, `Grid`, `PathFinder`.
- Produces: a committed, measured figure for total run income against full-board cost. Task 8 reads it.

- [ ] **Step 1: Write the measurement test**

Create `test/test_affordability.gd`:

```gdscript
extends TestCase

## What a twenty-wave run can actually FUND, against what the board costs.
##
## The shut-out threshold measured on 2026-08-29 is ten maxed towers. That
## number is only meaningful if ten maxed towers are reachable: the budget
## fell 16 -> 12 in 121bc7f while Waves.GOLD_PER_WAVE did not move, so the
## spend ceiling dropped and the income did not follow it.
##
## Income counted here is a FLOOR, deliberately. Kill rewards and wave-clear
## bonuses only - no interest, no call-early bonus - because those two are the
## income a player cannot choose not to earn.

const MAXED := {&"sustained": 2, &"burst": 4}

func _path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

## Three of each kind, twelve towers, the full legal roster under the caps.
func _full_roster() -> Array[StringName]:
	var kinds: Array[StringName] = []
	for kind in Towers.KINDS:
		for i in 3:
			kinds.append(kind)
	return kinds

## Gold to buy all twelve AND take every tier the cross-path rule allows.
func _full_board_cost() -> int:
	var total := 0
	for kind in Towers.KINDS:
		for owned in 3:
			total += EconomySim.tower_price(kind, owned)
			total += UpgradesSim.total_invested(kind, MAXED)
	return total

func test_a_full_run_income_against_a_full_board_cost() -> bool:
	var path := _path()
	var kinds := _full_roster()
	var spots := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
		[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]
	var towers: Array = []
	for i in kinds.size():
		towers.append({
			"kind": kinds[i],
			"position": Grid.tile_to_world_center(spots[i][0], spots[i][1]),
			"tiers": MAXED,
		})

	var income := 0
	for wave in range(1, Waves.MAX_WAVES + 1):
		var r := Harness.run_wave({"wave": wave, "towers": towers, "path": path})
		var clear := EconomySim.wave_clear_bonus(wave, float(r["ticks"]) * (1000.0 / 60.0))
		income += int(r["gold_earned"]) + int(clear["base"]) + int(clear["speed"])

	var cost := _full_board_cost()
	var starting := int(Maps.get_def(Maps.FIRST)["starting_gold"])
	print("AFFORDABILITY: income %d + starting %d = %d against full-board cost %d"
		% [income, starting, income + starting, cost])

	# PIN: replace both numbers below with what the line above prints, then
	# re-run. Derived from this implementation and reconfirmed directly - the
	# point of the pin is that a change to the gold curve or the tower caps
	# has to move it deliberately.
	assert_eq(income + starting, 0, "run income is the measured figure")
	assert_eq(cost, 0, "full-board cost is the measured figure")
	return true
```

- [ ] **Step 2: Run it and read the measurement**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | grep AFFORDABILITY`

Expected: FAIL on both assertions, with the `AFFORDABILITY:` line printing the two real numbers.

- [ ] **Step 3: Pin the measured numbers**

Replace the two `0` literals with the printed values. Then add the finding as a comment above `test_a_full_run_income_against_a_full_board_cost`, stating in one line whether the full board is affordable.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add test/test_affordability.gd
git commit -m "Measure what a run can actually fund"
```

- [ ] **Step 6: Report the finding before continuing**

If income + starting gold is **below** the full-board cost, the shut-out threshold is lower than ten maxed towers and Task 8's targets must be set against the affordable board, not the placeable one. **Say so explicitly in the task report.** Do not silently proceed on the assumption that twelve maxed towers is the target.

---

## Task 2: The difficulty table

**Files:**
- Create: `data/difficulty.gd`
- Test: `test/test_difficulty.gd`

**Interfaces:**
- Produces: `Difficulty.NORMAL`/`HARD`/`NIGHTMARE` (`StringName`), `Difficulty.ORDER: Array[StringName]`, `Difficulty.KEYS: Array[StringName]`, `Difficulty.DEFS: Dictionary`, `Difficulty.multiplier(tier: StringName, key: StringName) -> float`, `Difficulty.starting_lives(tier: StringName) -> int`, `Difficulty.label(tier: StringName) -> String`. Every later task consumes these.

- [ ] **Step 1: Write the failing test**

Create `test/test_difficulty.gd`:

```gdscript
extends TestCase

## Normal is the IDENTITY row. Every balance number this project has measured
## describes Normal, so if any multiplier here drifts off 1.0 the whole
## existing suite becomes a description of something nobody tuned.
func test_normal_is_the_identity_transform() -> bool:
	for key in Difficulty.KEYS:
		assert_almost_eq(Difficulty.multiplier(Difficulty.NORMAL, key), 1.0, 0.0001,
			"normal's %s is exactly 1.0" % key)
	assert_eq(Difficulty.starting_lives(Difficulty.NORMAL), Economy.STARTING_LIVES,
		"normal keeps the shipped life budget")
	return true

## Every tier carries every key. A tier missing one would push the default
## onto the lookup site, which puts a balance number in code instead of data.
func test_every_tier_carries_every_key() -> bool:
	for tier in Difficulty.ORDER:
		assert_true(Difficulty.DEFS.has(tier), "%s is in DEFS" % tier)
		var def: Dictionary = Difficulty.DEFS[tier]
		for key in Difficulty.KEYS:
			assert_true(def.has(key), "%s carries %s" % [tier, key])
		assert_true(def.has("starting_lives"), "%s carries starting_lives" % tier)
		assert_true(def.has("label"), "%s carries label" % tier)
	return true

func test_order_and_defs_agree() -> bool:
	assert_eq(Difficulty.ORDER.size(), Difficulty.DEFS.size(),
		"ORDER covers DEFS exactly")
	return true

## Catches a transposed table row, which no single-tier test can see: each
## lever must move the same direction across the whole ladder.
func test_tiers_never_get_easier_as_they_go_up() -> bool:
	for i in range(1, Difficulty.ORDER.size()):
		var lower: StringName = Difficulty.ORDER[i - 1]
		var higher: StringName = Difficulty.ORDER[i]
		for key in [&"count_multiplier", &"health_multiplier", &"speed_multiplier"]:
			assert_true(Difficulty.multiplier(higher, key) >= Difficulty.multiplier(lower, key),
				"%s's %s is at least %s's" % [higher, key, lower])
		# These two run the other way: SMALLER is harsher.
		for key in [&"interval_multiplier", &"gold_multiplier"]:
			assert_true(Difficulty.multiplier(higher, key) <= Difficulty.multiplier(lower, key),
				"%s's %s is at most %s's" % [higher, key, lower])
		assert_true(Difficulty.starting_lives(higher) <= Difficulty.starting_lives(lower),
			"%s grants no more lives than %s" % [higher, lower])
	return true
```

- [ ] **Step 2: Run it to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero exit — `Difficulty` is not declared.

- [ ] **Step 3: Write the table**

Create `data/difficulty.gd`:

```gdscript
class_name Difficulty

## Difficulty tiers. Pure data, like the rest of data/.
##
## Difficulty is a PARAMETER in this project, never a global. Waves and the
## harness take a tier argument; nothing reads a mutable singleton. That is
## what keeps sim/ pure and keeps Harness.run_wave's guarantee - same input,
## same result - which is the property every balance claim here rests on.
##
## Normal is the exact identity transform. Every measured number in this
## project describes Normal, so the existing suite doubles as the regression
## net for this file: if a Normal multiplier drifts, something else fails.

const NORMAL := &"normal"
const HARD := &"hard"
const NIGHTMARE := &"nightmare"

## Easiest first. Task 2's monotonicity test walks this in order.
const ORDER: Array[StringName] = [NORMAL, HARD, NIGHTMARE]

## The multiplier keys, as distinct from starting_lives (an int) and label
## (a string). Tests iterate this rather than restating the list.
const KEYS: Array[StringName] = [
	&"count_multiplier",
	&"interval_multiplier",
	&"health_multiplier",
	&"speed_multiplier",
	&"gold_multiplier",
]

## Which lever attacks what, and why these and not others:
##
##   interval_multiplier  spawn spacing, so CONCURRENCY. The sharpest lever
##                        available. Measurement established that board
##                        COVERAGE binds, not hit points; halving the interval
##                        doubles the crowd one tower must cover without
##                        touching a single enemy stat.
##   count_multiplier     enemies per wave. Same constraint, blunter, and it
##                        compounds with the accumulating composition.
##   health_multiplier    hit points. Proven WEAK ALONE - wave-20 health x11.5
##                        leaked zero against a maxed board - but real in
##                        combination, because it lengthens the window during
##                        which concurrency matters.
##   speed_multiplier     time under fire. The other side of coverage: less
##                        time in range is the same as less range.
##   gold_multiplier      the board a player can afford. Indirect, strong.
##   starting_lives       forgiveness. The only lever a player feels at once.
##
## SMALLER is harsher for interval_multiplier and gold_multiplier. Larger is
## harsher for the other three. The monotonicity test encodes both directions.
const DEFS := {
	&"normal": {
		"label": "Normal",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"starting_lives": Economy.STARTING_LIVES,
	},
	# PLACEHOLDER ROWS - identity copies of Normal, replaced by Task 8's
	# measured sweep. They are identity rather than invented numbers on
	# purpose: a plausible figure written down once becomes the shipped figure
	# by inertia, which is exactly how the six-tower benchmark happened.
	&"hard": {
		"label": "Hard",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"starting_lives": Economy.STARTING_LIVES,
	},
	&"nightmare": {
		"label": "Nightmare",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"starting_lives": Economy.STARTING_LIVES,
	},
}

static func get_def(tier: StringName) -> Dictionary:
	return DEFS[tier]

static func multiplier(tier: StringName, key: StringName) -> float:
	return float(DEFS[tier][key])

static func starting_lives(tier: StringName) -> int:
	return int(DEFS[tier]["starting_lives"])

static func label(tier: StringName) -> String:
	return String(DEFS[tier]["label"])

## Whether a tier name is one this table knows. Callers that read a tier from
## outside the table - a saved run, a menu, a harness config - use this rather
## than indexing DEFS and crashing on a typo.
static func is_valid(tier: StringName) -> bool:
	return DEFS.has(tier)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add data/difficulty.gd test/test_difficulty.gd
git commit -m "Add the difficulty tier table"
```

---

## Task 3: Waves takes a tier

**Files:**
- Modify: `data/waves.gd` — `get_composition`, `get_modifiers`, `ogre_spawn_delay`, `build_schedule`
- Test: `test/test_waves.gd`

**Interfaces:**
- Consumes: `Difficulty.NORMAL`, `Difficulty.multiplier` (Task 2).
- Produces: `Waves.get_composition(wave_number: int, tier := Difficulty.NORMAL) -> Array[Dictionary]`, `Waves.get_modifiers(wave_number: int, tier := Difficulty.NORMAL) -> Dictionary`, `Waves.build_schedule(wave: int, tier := Difficulty.NORMAL) -> Array`, `Waves.ogre_spawn_delay(goblin_count: int, interval_ms := INTERVAL_MS) -> float`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_waves.gd`:

```gdscript
## The identity guarantee, stated directly rather than left implicit in the
## rest of the suite. Every measured number in this project describes Normal.
func test_normal_is_identical_to_the_untiered_call() -> bool:
	for wave in [1, 5, 10, 18, 20]:
		assert_eq(Waves.get_composition(wave), Waves.get_composition(wave, Difficulty.NORMAL),
			"wave %d composition is unchanged at Normal" % wave)
		assert_eq(Waves.get_modifiers(wave), Waves.get_modifiers(wave, Difficulty.NORMAL),
			"wave %d modifiers are unchanged at Normal" % wave)
		assert_eq(Waves.build_schedule(wave), Waves.build_schedule(wave, Difficulty.NORMAL),
			"wave %d schedule is unchanged at Normal" % wave)
	return true

## A count multiplier must never round a kind out of a wave: a wave that
## silently loses its ogres is a different wave, not a harder one.
func test_a_count_multiplier_never_empties_a_kind() -> bool:
	var scaled := Waves._scale_counts(Waves.get_composition(1), 0.01)
	for entry in scaled:
		assert_true(int(entry["count"]) >= 1, "%s survives a brutal count multiplier" % entry["kind"])
	return true

func test_a_larger_count_multiplier_spawns_more() -> bool:
	var base := Waves._scale_counts(Waves.get_composition(8), 1.0)
	var more := Waves._scale_counts(Waves.get_composition(8), 2.0)
	var base_total := 0
	var more_total := 0
	for entry in base:
		base_total += int(entry["count"])
	for entry in more:
		more_total += int(entry["count"])
	assert_true(more_total > base_total, "doubling the multiplier spawns more")
	return true

## The interval is what attacks concurrency, so it must actually reach the
## schedule rather than only the composition.
func test_a_tighter_interval_packs_the_schedule() -> bool:
	var wide := Waves.build_schedule(8)
	var tight := Waves._build_schedule_at(8, Difficulty.NORMAL, 0.5)
	assert_eq(wide.size(), tight.size(), "the same enemies are scheduled")
	var wide_last := 0.0
	var tight_last := 0.0
	for e in wide:
		wide_last = maxf(wide_last, float(e["at_ms"]))
	for e in tight:
		tight_last = maxf(tight_last, float(e["at_ms"]))
	assert_true(tight_last < wide_last, "a halved interval finishes spawning sooner")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `_scale_counts` and `_build_schedule_at` do not exist.

- [ ] **Step 3: Implement the tier parameter**

In `data/waves.gd`, replace `get_composition`, `get_modifiers`, `ogre_spawn_delay` and `build_schedule` with:

```gdscript
## Enemy counts for a wave, accumulated from wave 1, then scaled by the
## tier's count multiplier. Returns fresh dictionaries on every call so a
## caller cannot corrupt later waves.
static func get_composition(wave_number: int, tier := Difficulty.NORMAL) -> Array[Dictionary]:
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

	return _scale_counts(composition, Difficulty.multiplier(tier, &"count_multiplier"))

## Applies a count multiplier in place and returns the same array.
##
## Floored at one per kind that the wave already contained: a multiplier that
## rounded a kind to zero would silently change WHICH enemies a wave fields,
## and a wave without its ogres is a different wave rather than an easier one.
##
## Exactly 1.0 short-circuits, so Normal's compositions are the same objects
## the game has always produced - identical, not merely equal.
static func _scale_counts(composition: Array[Dictionary], multiplier: float) -> Array[Dictionary]:
	if is_equal_approx(multiplier, 1.0):
		return composition
	for entry in composition:
		entry["count"] = maxi(1, int(round(float(entry["count"]) * multiplier)))
	return composition

## Health, speed and gold multipliers, then the tier's own scaling.
##
## The tier's gold multiplier is applied AFTER MIN_GOLD_MODIFIER, not before.
## The floor is a safety rail against a negative reward in endless play; a
## harder tier paying less is the intent, so the floor must not undo it.
static func get_modifiers(wave_number: int, tier := Difficulty.NORMAL) -> Dictionary:
	var past: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	return {
		"health_modifier": (1.0 + float(past) * HEALTH_PER_WAVE)
			* Difficulty.multiplier(tier, &"health_multiplier"),
		"speed_modifier": (1.0 + float(past) * SPEED_PER_WAVE)
			* Difficulty.multiplier(tier, &"speed_multiplier"),
		"gold_modifier": maxf(MIN_GOLD_MODIFIER, 1.0 - float(past) * GOLD_PER_WAVE)
			* Difficulty.multiplier(tier, &"gold_multiplier"),
	}

## When the ogre column starts, given how many goblins precede it. Ogres trail
## the last goblin by three seconds but never wait more than ten.
##
## interval_ms is a parameter because a tier that tightens spawn spacing moves
## the last goblin earlier; deriving this from the constant would leave the
## ogres waiting on a schedule the goblins no longer keep.
static func ogre_spawn_delay(goblin_count: int, interval_ms := INTERVAL_MS) -> float:
	var last_goblin_at := float(goblin_count - 1) * interval_ms
	return minf(last_goblin_at + OGRE_DELAY_AFTER_LAST_GOBLIN_MS, OGRE_MAX_START_DELAY_MS)

static func build_schedule(wave: int, tier := Difficulty.NORMAL) -> Array:
	return _build_schedule_at(wave, tier, Difficulty.multiplier(tier, &"interval_multiplier"))
```

Then rename the existing `build_schedule` body to `_build_schedule_at` and thread the interval through it:

```gdscript
## The schedule for a wave at an explicit interval multiplier.
##
## Split out from build_schedule so a test can vary the spacing without
## inventing a difficulty tier for it.
static func _build_schedule_at(wave: int, tier: StringName, interval_multiplier: float) -> Array:
	var schedule: Array = []
	var composition := get_composition(wave, tier)
	var interval := INTERVAL_MS * interval_multiplier

	var goblin_count := 0
	for entry in composition:
		if entry["kind"] == &"goblin":
			goblin_count = entry["count"]

	var push_index := 0
	for entry in composition:
		var kind: StringName = entry["kind"]
		var start := 0.0
		match kind:
			&"bat":
				start = BAT_START_DELAY_MS * interval_multiplier
			&"ogre":
				start = ogre_spawn_delay(goblin_count, interval)
			_:
				start = 0.0
		for i in entry["count"]:
			schedule.append({
				"kind": kind, "at_ms": start + float(i) * interval,
				"_push_index": push_index,
			})
			push_index += 1

	schedule.sort_custom(func(a, b):
		if a["at_ms"] != b["at_ms"]:
			return a["at_ms"] < b["at_ms"]
		return a["_push_index"] < b["_push_index"])

	for entry in schedule:
		entry.erase("_push_index")

	if Bosses.has_boss(wave):
		var last_at := 0.0
		for entry in schedule:
			last_at = maxf(last_at, float(entry["at_ms"]))
		schedule.append({
			"kind": Bosses.on_wave(wave)["kind"],
			"at_ms": last_at + BOSS_DELAY_MS,
			"boss": true,
		})

	return schedule
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`. **Every pre-existing wave, harness and balance assertion must still pass** — that is the identity guarantee doing its job. If any fails, Normal moved and the change is wrong.

- [ ] **Step 5: Commit**

```bash
git add data/waves.gd test/test_waves.gd
git commit -m "Let a wave be built at a difficulty tier"
```

---

## Task 4: The harness accepts a tier

**Files:**
- Modify: `sim/harness.gd:51-52`
- Test: `test/test_harness.gd`

**Interfaces:**
- Consumes: `Waves.get_composition/get_modifiers/build_schedule` with a tier (Task 3).
- Produces: `Harness.run_wave` honours `config["difficulty"]`, defaulting to `Difficulty.NORMAL`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_harness.gd`:

```gdscript
func test_an_absent_difficulty_means_normal() -> bool:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	var bare := Harness.run_wave({"wave": 3, "towers": towers, "path": _path()})
	var named := Harness.run_wave({"wave": 3, "towers": towers, "path": _path(),
		"difficulty": Difficulty.NORMAL})
	assert_eq(bare, named, "omitting difficulty is exactly Normal")
	return true

func test_results_stay_reproducible_per_tier() -> bool:
	var towers := [{"kind": &"basic", "position": Grid.tile_to_world_center(5, 3)}]
	for tier in Difficulty.ORDER:
		var config := {"wave": 8, "towers": towers, "path": _path(), "difficulty": tier}
		var first := Harness.run_wave(config)
		assert_eq(Harness.run_wave(config), first, "%s is reproducible" % tier)
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero. Note that while Hard and Nightmare are still identity rows (until Task 8), a passing result here proves nothing — the tiers are genuinely equivalent at this point. Confirm the plumbing by temporarily setting Nightmare's `health_multiplier` to `2.0`, re-running to see the tests fail, then reverting it. Do not implement until you have seen a real failure.

- [ ] **Step 3: Thread the tier through**

In `sim/harness.gd`, replace lines 51–52:

```gdscript
	# Difficulty travels as a parameter, never a global, so this stays a pure
	# function of its config - which is what makes every balance claim in this
	# project reproducible.
	var tier: StringName = config.get("difficulty", Difficulty.NORMAL)
	var schedule := Waves.build_schedule(wave, tier)
	var modifiers := Waves.get_modifiers(wave, tier)
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add sim/harness.gd test/test_harness.gd
git commit -m "Run a harness wave at a difficulty tier"
```

---

## Task 5: Teach the harness where enemies died

The spec calls this the part most likely to still be paying off in six months. "They don't reach the first bend" is currently not expressible against `run_wave`'s result, which is why a regression obvious to a player was invisible to 13,436 assertions.

**Files:**
- Modify: `sim/harness.gd` — the tick loop and `_result`
- Test: `test/test_harness.gd`

**Interfaces:**
- Produces: `run_wave` result gains `deepest_progress: float` and `progress_at_death: float`, both 0.0–1.0.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_harness.gd`:

```gdscript
## The Pass is 2,448px end to end and its first bend is 768px in, so a wave
## decided before the corner never exceeds this fraction.
const FIRST_BEND_FRACTION := 0.31

func test_an_undefended_wave_walks_the_whole_route() -> bool:
	var r := Harness.run_wave({"wave": 1, "towers": [], "path": _path()})
	assert_almost_eq(r["deepest_progress"], 1.0, 0.01,
		"nothing shooting means something reaches the goal")
	return true

func test_progress_is_a_fraction() -> bool:
	var towers: Array = []
	for col in [3, 5, 7]:
		towers.append({"kind": &"basic", "position": Grid.tile_to_world_center(col, 3)})
	for wave in [1, 5, 12]:
		var r := Harness.run_wave({"wave": wave, "towers": towers, "path": _path()})
		assert_true(r["deepest_progress"] >= 0.0 and r["deepest_progress"] <= 1.0,
			"wave %d deepest_progress is a fraction" % wave)
		assert_true(r["progress_at_death"] >= 0.0 and r["progress_at_death"] <= 1.0,
			"wave %d progress_at_death is a fraction" % wave)
	return true

## The owner's report, as an assertion: an overwhelming board decides wave 1
## before the first corner.
func test_an_overwhelming_board_kills_before_the_first_bend() -> bool:
	var towers: Array = []
	for col in [3, 5, 7, 9, 11]:
		towers.append({"kind": &"long", "position": Grid.tile_to_world_center(col, 3)})
	var r := Harness.run_wave({"wave": 1, "towers": towers, "path": _path()})
	assert_eq(r["leaks"], 0, "nothing gets through")
	assert_true(r["deepest_progress"] < FIRST_BEND_FRACTION,
		"wave 1 is over before the first bend, at %f" % r["deepest_progress"])
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — the result has no `deepest_progress` key.

- [ ] **Step 3: Implement route progress**

Add to `sim/harness.gd`, above `run_wave`:

```gdscript
## Cumulative distance to each waypoint, and the route's total length.
##
## Precomputed once per run rather than per tick: the route never changes
## during a wave, and this is read for every living enemy on every tick.
static func _route_metrics(path: PackedVector2Array) -> Dictionary:
	var cumulative := PackedFloat32Array()
	cumulative.resize(path.size())
	if path.size() > 0:
		cumulative[0] = 0.0
	for i in range(1, path.size()):
		cumulative[i] = cumulative[i - 1] + path[i - 1].distance_to(path[i])
	var total := 0.0 if path.size() == 0 else float(cumulative[path.size() - 1])
	return {"cumulative": cumulative, "total": total}

## How far along the route a position is, as a fraction of the whole.
##
## path_index is the waypoint being walked TOWARD, so everything up to
## path_index - 1 is already behind the enemy; the remainder is the straight
## line from that waypoint to where it now stands.
static func _progress_of(position: Vector2, path_index: int,
		path: PackedVector2Array, route: Dictionary) -> float:
	var total: float = route["total"]
	if total <= 0.0 or path.size() == 0:
		return 0.0
	var cumulative: PackedFloat32Array = route["cumulative"]
	var behind := clampi(path_index - 1, 0, path.size() - 1)
	var travelled := float(cumulative[behind]) + path[behind].distance_to(position)
	return clampf(travelled / total, 0.0, 1.0)
```

In `run_wave`, alongside the other counters:

```gdscript
	var route := _route_metrics(path)
	var deepest_progress := 0.0
	var death_progress_total := 0.0
	var deaths := 0
```

After the movement block writes `e["position"]` and `e["path_index"]`, and before the `reached_goal` branch, record the furthest anything has reached:

```gdscript
			deepest_progress = maxf(deepest_progress,
				_progress_of(e["position"], e["path_index"], path, route))
```

In the `reached_goal` branch, a leak has by definition reached the end:

```gdscript
				deepest_progress = 1.0
```

Where a shot proves lethal — immediately after `kills += 1` — record where it fell:

```gdscript
					death_progress_total += _progress_of(e["position"], e["path_index"], path, route)
					deaths += 1
```

Change both `_result(...)` calls to pass the two new figures, and extend `_result`:

```gdscript
static func _result(kills: int, leaks: int, lives_lost: int, gold: int,
		ticks: int, timed_out: bool, deepest_progress: float,
		death_progress_total: float, deaths: int) -> Dictionary:
	return {
		"kills": kills,
		"leaks": leaks,
		"lives_lost": lives_lost,
		"gold_earned": gold,
		"ticks": ticks,
		"timed_out": timed_out,
		# How far the furthest enemy got, as a fraction of the route. This is
		# what makes "they never reach the first bend" an assertion instead of
		# an observation - the gap that let a shut-out board read as balanced.
		"deepest_progress": deepest_progress,
		# Mean progress at the moment of death, over enemies that died. Zero
		# when nothing died, which is the honest answer rather than a
		# division by zero.
		"progress_at_death": 0.0 if deaths == 0 else death_progress_total / float(deaths),
	}
```

Keep the existing keys and their order — `test_harness.gd` compares whole result dictionaries for equality, so a renamed or dropped key breaks reproducibility tests that have nothing to do with this change.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add sim/harness.gd test/test_harness.gd
git commit -m "Teach the harness where enemies died"
```

---

## Task 6: The live board runs at a tier

**Files:**
- Modify: `game/game_board.gd` — the `pending_map` static (near line 50), the `_ready` lives assignment, the `build_schedule` call (near line 248)
- Modify: `game/enemy.gd:43` and `game/enemy.gd:293`
- Test: `test/test_game_board.gd`

**Interfaces:**
- Produces: `GameBoard.pending_difficulty: StringName`, `GameBoard.active_difficulty() -> StringName`.

> **Note:** another agent has been editing `game/game_board.gd`. Locate these by symbol, not by line number, and re-read the file before editing.

- [ ] **Step 1: Write the failing test**

Append to `test/test_game_board.gd`:

```gdscript
func test_a_board_starts_at_the_pending_difficulty() -> bool:
	GameBoard.pending_difficulty = Difficulty.NIGHTMARE
	assert_eq(GameBoard.active_difficulty(), Difficulty.NIGHTMARE,
		"the pending tier is the active one")
	GameBoard.pending_difficulty = &""
	assert_eq(GameBoard.active_difficulty(), Difficulty.NORMAL,
		"an unset tier falls back to Normal")
	return true

func test_an_unknown_difficulty_falls_back_to_normal() -> bool:
	GameBoard.pending_difficulty = &"impossible"
	assert_eq(GameBoard.active_difficulty(), Difficulty.NORMAL,
		"a tier the table does not know never reaches the rules")
	GameBoard.pending_difficulty = &""
	return true
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `pending_difficulty` does not exist.

- [ ] **Step 3: Implement the carry**

In `game/game_board.gd`, beside `static var pending_map`:

```gdscript
## The tier the next board runs at, set by the main menu and consumed on
## _ready - the same pattern pending_map uses, for the same reason: a run's
## settings have to outlive the scene change that starts it.
static var pending_difficulty: StringName = &""

## The tier in force, with an unset or unknown name falling back to Normal.
##
## Validated rather than indexed: this value arrives from outside the table
## (a menu today, a saved run later), and a typo must not crash a run.
static func active_difficulty() -> StringName:
	return pending_difficulty if Difficulty.is_valid(pending_difficulty) else Difficulty.NORMAL
```

Add a member alongside `_map_name`:

```gdscript
var _difficulty: StringName = Difficulty.NORMAL
```

In `_ready`, beside the `pending_map` consumption:

```gdscript
	_difficulty = active_difficulty()
	pending_difficulty = &""
```

Replace the lives assignment:

```gdscript
	_lives = Difficulty.starting_lives(_difficulty)
```

Pass the tier to the schedule:

```gdscript
	var schedule := Waves.build_schedule(_wave, _difficulty)
```

In `game/enemy.gd`, both call sites take the board's tier. Add a `difficulty` field to the setup dictionary the board passes, defaulting to Normal, and use it:

```gdscript
	var modifiers := Waves.get_modifiers(wave, _difficulty)
```

```gdscript
		float(Waves.get_modifiers(_wave, _difficulty)["gold_modifier"])), kind)
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add game/game_board.gd game/enemy.gd test/test_game_board.gd
git commit -m "Run the live board at the chosen difficulty"
```

---

## Task 7: The menu selector and the HUD readout

**Files:**
- Modify: `ui/main_menu.tscn` — three `Button`s under `Panel`, between `Title` and `Play`
- Modify: `ui/main_menu.gd`
- Modify: `ui/hud.tscn`, `ui/hud.gd`
- Test: `test/test_hud.gd`

**NO NEW ASSETS.** Plain `Button` nodes, existing theme. If this appears to need art, stop and return to Codex.

**Interfaces:**
- Consumes: `Difficulty.ORDER`, `Difficulty.label`, `GameBoard.pending_difficulty` (Tasks 2, 6).

- [ ] **Step 1: Write the failing test**

Append to `test/test_hud.gd`:

```gdscript
func test_the_hud_names_the_active_difficulty() -> bool:
	var hud := preload("res://ui/hud.tscn").instantiate()
	hud.set_difficulty(Difficulty.NIGHTMARE)
	assert_eq(hud.difficulty_text(), "Nightmare", "the HUD names the tier")
	hud.free()
	return true
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `set_difficulty` is not defined.

- [ ] **Step 3: Add the HUD readout**

Add a `Label` named `DifficultyLabel` to `ui/hud.tscn` beside the existing wave readout, and in `ui/hud.gd`:

```gdscript
@onready var _difficulty_label: Label = $DifficultyLabel

## Shown during a run because a run whose difficulty is invisible produces bug
## reports that cannot be diagnosed - the same lesson BuildStamp exists for.
func set_difficulty(tier: StringName) -> void:
	_difficulty_label.text = Difficulty.label(tier)

func difficulty_text() -> String:
	return _difficulty_label.text
```

- [ ] **Step 4: Add the menu buttons**

Add three `Button` nodes named `Normal`, `Hard` and `Nightmare` under `Panel`, between `Title` and `Play`, each with `toggle_mode = true`. In `ui/main_menu.gd`:

```gdscript
@onready var _tier_buttons := {
	Difficulty.NORMAL: $Panel/Normal,
	Difficulty.HARD: $Panel/Hard,
	Difficulty.NIGHTMARE: $Panel/Nightmare,
}

var _chosen: StringName = Difficulty.NORMAL
```

In `_ready`, after the existing wiring:

```gdscript
	for tier in _tier_buttons:
		var button: Button = _tier_buttons[tier]
		button.text = Difficulty.label(tier)
		button.pressed.connect(_choose.bind(tier))
	_choose(Difficulty.NORMAL)
```

```gdscript
## Difficulty is chosen per run and deliberately NOT persisted: there is no
## settings file in this project, and update.md records that Slice 3 owns
## saving. Inventing one here would hand Slice 3 a versioning problem early.
func _choose(tier: StringName) -> void:
	_chosen = tier
	for other in _tier_buttons:
		_tier_buttons[other].button_pressed = (other == tier)
```

Change the Play handler to carry the choice:

```gdscript
	_play.pressed.connect(func():
		begin_new_run()
		GameBoard.pending_difficulty = _chosen
		get_tree().change_scene_to_file("res://game/game.tscn"))
```

And clear it in `begin_new_run`, so "Play" always means a fresh run:

```gdscript
static func begin_new_run() -> void:
	GameBoard.pending_map = &""
	GameBoard.pending_difficulty = &""
```

Have `GameBoard` call `hud.set_difficulty(_difficulty)` where it already initialises the HUD.

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 6: Commit**

```bash
git add ui/main_menu.gd ui/main_menu.tscn ui/hud.gd ui/hud.tscn game/game_board.gd test/test_hud.gd
git commit -m "Choose a difficulty before a run, and show it during one"
```

---

## Task 8: Sweep the tiers and set their numbers

Everything before this has been plumbing that leaves Normal untouched. This is where Hard and Nightmare stop being identity rows.

**Files:**
- Modify: `data/difficulty.gd` — the `hard` and `nightmare` rows
- Test: `test/test_balance_tuning.gd`

**Interfaces:**
- Consumes: Task 1's affordability finding, Tasks 3–5's plumbing.

- [ ] **Step 1: Write the sweep probe**

Create `probe_tiers.gd` in the project root — **throwaway, deleted in step 4**:

```gdscript
extends SceneTree

const MAXED := {&"sustained": 2, &"burst": 4}

func _init() -> void:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	var path := PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

	var kinds: Array[StringName] = []
	for kind in Towers.KINDS:
		for i in 3:
			kinds.append(kind)
	var spots := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
		[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]
	var towers: Array = []
	for i in kinds.size():
		towers.append({"kind": kinds[i],
			"position": Grid.tile_to_world_center(spots[i][0], spots[i][1]), "tiers": MAXED})

	# Candidate rows, swept one lever combination at a time.
	var candidates := [
		{"label": "count 1.3 / interval 0.7 / health 1.3 / speed 1.1 / gold 0.9",
			"count_multiplier": 1.3, "interval_multiplier": 0.7,
			"health_multiplier": 1.3, "speed_multiplier": 1.1, "gold_multiplier": 0.9},
		{"label": "count 1.6 / interval 0.5 / health 1.6 / speed 1.2 / gold 0.8",
			"count_multiplier": 1.6, "interval_multiplier": 0.5,
			"health_multiplier": 1.6, "speed_multiplier": 1.2, "gold_multiplier": 0.8},
		{"label": "count 2.0 / interval 0.4 / health 2.0 / speed 1.3 / gold 0.7",
			"count_multiplier": 2.0, "interval_multiplier": 0.4,
			"health_multiplier": 2.0, "speed_multiplier": 1.3, "gold_multiplier": 0.7},
	]

	for c in candidates:
		# Temporarily install the candidate as Nightmare's row by editing
		# data/difficulty.gd between runs; DEFS is a const and cannot be
		# mutated here. Run this probe once per candidate.
		print("\n=== %s ===" % c["label"])
		for wave in [5, 10, 15, 18, 20]:
			var r := Harness.run_wave({"wave": wave, "towers": towers, "path": path,
				"difficulty": Difficulty.NIGHTMARE})
			print("  wave %2d: leaks %3d lives %3d deepest %.2f mean_death %.2f"
				% [wave, r["leaks"], r["lives_lost"], r["deepest_progress"], r["progress_at_death"]])
	quit(0)
```

- [ ] **Step 2: Run the sweep**

For each candidate row: paste it into `data/difficulty.gd`'s `nightmare` entry, then run

`godot --headless --quit --script probe_tiers.gd 2>&1 | grep -vE "^(SCRIPT )?ERROR|^ *at:|WARNING"`

Record leaks, lives lost and `deepest_progress` for each.

- [ ] **Step 3: Choose the two rows against these targets**

- **Nightmare:** a full twelve-tower maxed board **must leak** on wave 20. This is the assertion that fails the moment the game becomes unlosable again.
- **Nightmare:** `deepest_progress` on wave 10 must exceed `0.31` — enemies get past the first bend, which is the owner's actual complaint.
- **Hard:** sits between Normal and Nightmare on every lever, and should cost a full maxed board real lives late without ending the run.
- **Both:** must satisfy Task 2's monotonicity test. If it fails, a row is transposed.
- If Task 1 found the full board **unaffordable**, set these against the largest board a run can actually fund, and say so in the commit message.

Write the chosen rows into `data/difficulty.gd`, replacing the placeholder comment with a note recording what was swept and why these values won — matching how `HEALTH_PER_WAVE` and `GOLD_PER_WAVE` document their own measurements.

- [ ] **Step 4: Delete the probe**

```bash
rm -f probe_tiers.gd probe_tiers.gd.uid
```

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`, monotonicity included.

- [ ] **Step 6: Commit**

```bash
git add data/difficulty.gd
git commit -m "Set the Hard and Nightmare rows from a measured sweep"
```

---

## Task 9: Give the opening a pulse

The one change to the default, and the only part of the owner's original request that lands on Normal. A goblin has 5 health against a Basic tower's 4 damage — two shots — and a bat has 3, which is one. Wave 1 ends in 4.6 seconds.

**Files:**
- Modify: `data/enemies.gd` — `base_health` for `goblin` and `bat`
- Test: `test/test_data_tables.gd`

- [ ] **Step 1: Confirm the constraints that must survive**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

`test_data_tables.gd` pins the roster ordering `ogre > shaman > goblin > bat` **before and after wave scaling**. Read those assertions before touching a number.

- [ ] **Step 2: Raise the two values**

In `data/enemies.gd`, raise `goblin`'s `base_health` from 5 and `bat`'s from 3, keeping `ogre > shaman > goblin > bat` intact. Start with goblin 8 and bat 5, then measure.

Record the reasoning in the table's comment, in the style of the file's existing notes:

```gdscript
## Raised from 5 and 3 on 2026-08-29. At the old values a Basic tower's 4
## damage killed a goblin in two shots and a bat in ONE, so wave 1 was over in
## 4.6 seconds and nothing reached the first bend. This is not the fix for a
## shut-out board - health alone was measured as unable to threaten a good one
## at any rate - it is here so the opening lasts long enough to be seen.
```

- [ ] **Step 3: Measure the effect on the opening**

Re-run the affordability test from Task 1 and check `test_harness.gd`'s wave-1 assertions. The two constraints from the spec:

- The roster ordering survives, before and after wave scaling.
- Wave 5 against three ungraded Basics must not cost **more** than the 20 lives it already does. The opening is already a cliff; this must not steepen it.

Several pinned tick counts and gold totals in `test_harness.gd` and `test_balance_tuning.gd` will move. Update each to its newly measured value and note in the commit that they moved because base health moved.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add data/enemies.gd test/test_data_tables.gd test/test_harness.gd test/test_balance_tuning.gd
git commit -m "Give the opening waves a pulse"
```

---

## Task 10: Benchmark the board the game actually hands out

The gap that let all of this through. `test_balance_tuning.gd` benchmarks a six-tower board — one the player passes through on the way to the one they finish with — and its `leaks > 0` assertion stays true however easy the game becomes for a full board.

**Files:**
- Modify: `test/test_balance_tuning.gd`

- [ ] **Step 1: Add the full-roster benchmark**

Append to `test/test_balance_tuning.gd`:

```gdscript
## Three of each kind, twelve towers, every tier the cross-path rule allows:
## the board the game actually hands out, and the only one the endgame is
## really played on.
##
## The existing six-tower case above stays - a mid-run board is worth
## benchmarking too. It simply cannot be the only one, which is what let a
## board that shut the game out completely read as balanced.
const MAXED := {&"sustained": 2, &"burst": 4}

func _full_board() -> Array:
	var kinds: Array[StringName] = []
	for kind in Towers.KINDS:
		for i in 3:
			kinds.append(kind)
	var spots := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
		[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]
	var towers: Array = []
	for i in kinds.size():
		towers.append({"kind": kinds[i],
			"position": Grid.tile_to_world_center(spots[i][0], spots[i][1]), "tiers": MAXED})
	return towers

func _full_path() -> PackedVector2Array:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	return PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))

## THE assertion this whole change exists to make. Directional rather than a
## magic number, so it survives future retuning: whatever else moves, the
## hardest tier must not be winnable by simply filling the budget.
func test_a_full_maxed_board_does_not_shut_out_the_hardest_tier() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(r["leaks"] > 0,
		"a full maxed board must not shut out Nightmare's last wave, got %s" % r)
	assert_false(r["timed_out"], "the benchmark completes")
	return true

## The owner's report as a permanent assertion. On Nightmare the enemies must
## get past the first bend - 768px into The Pass's 2,448px route.
func test_enemies_reach_past_the_first_bend_on_the_hardest_tier() -> bool:
	var r := Harness.run_wave({"wave": 10, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NIGHTMARE})
	assert_true(r["deepest_progress"] > 0.31,
		"enemies get past the first bend, reached %f" % r["deepest_progress"])
	return true

## Normal keeps its shape, by owner decision (2026-08-29): a full maxed board
## should win wave 20 comfortably. Pinned so a later tier change cannot make
## the default harder as a side effect.
func test_a_full_maxed_board_still_wins_on_normal() -> bool:
	var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _full_board(),
		"path": _full_path(), "difficulty": Difficulty.NORMAL})
	assert_eq(r["leaks"], 0, "Normal stays comfortable for a completed board")
	return true
```

- [ ] **Step 2: Run to verify the new assertions hold**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`. If `test_a_full_maxed_board_does_not_shut_out_the_hardest_tier` fails, Nightmare's row from Task 8 is too soft — return to Task 8 rather than weakening the assertion.

- [ ] **Step 3: Commit**

```bash
git add test/test_balance_tuning.gd
git commit -m "Benchmark the full twelve-tower board, not half of it"
```

---

## Task 11: Update the docs

**Files:**
- Modify: `update.md`, `CONTINUE.md`

- [ ] **Step 1: Move the status row**

In `update.md`, change the difficulty selector row from *designed, not built* to done, and replace the "Hard and Nightmare values are deliberately unset" paragraph with the measured rows from Task 8 and the affordability finding from Task 1.

- [ ] **Step 2: Record what is now measurable**

Note in `update.md` that `Harness.run_wave` reports `deepest_progress` and `progress_at_death`, and that `test_balance_tuning.gd` now covers the full twelve-tower board at every tier — so this class of regression is catchable.

- [ ] **Step 3: Bring `CONTINUE.md` up to the selector**

`CONTINUE.md` records what *is*. Add the difficulty tiers, the menu selector, the HUD readout and the two new harness result fields.

- [ ] **Step 4: Commit**

```bash
git add update.md CONTINUE.md
git commit -m "Bring the docs up to the difficulty selector"
```

---

## Self-review

**Spec coverage.** §3 tier table → Task 2. §3 parameter threading → Tasks 3, 4. §3.3 scene carry → Task 6. §4 menu → Task 7. §5 health bump → Task 9. §6.1 harness instrumentation → Task 5. §6.2 full-board benchmark → Task 10. §7 testing → distributed across every task. §8's affordability risk → Task 1, gating Task 8. §8's "Normal cannot stay comfortable" risk → Task 8 step 3 and Task 10's Normal pin.

**Placeholders.** The `hard` and `nightmare` rows in Task 2 are identity placeholders **by design**, replaced in Task 8; the spec argues why inventing them earlier is the failure mode being fixed. Task 1 and Task 8 both carry explicit measure-then-pin steps rather than invented figures.

**Type consistency.** `Difficulty.multiplier(StringName, StringName) -> float`, `Difficulty.starting_lives(StringName) -> int`, `Difficulty.label(StringName) -> String` and `Difficulty.is_valid(StringName) -> bool` are defined in Task 2 and used unchanged in Tasks 3–7. `Waves._scale_counts` and `Waves._build_schedule_at` are introduced in Task 3 and referenced by the tests written in the same task. `deepest_progress` and `progress_at_death` are defined in Task 5 and consumed in Task 10.
