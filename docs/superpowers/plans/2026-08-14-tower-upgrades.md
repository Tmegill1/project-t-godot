# Tower Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tower a two-branch, four-tier upgrade path with a cross-path commitment rule, plus the slow and gold-per-kill mechanics those tiers need.

**Architecture:** A pure data table (`data/upgrades.gd`) and a pure rules module (`sim/upgrades.gd`) hold everything; `game/tower.gd` swaps its direct `_def` reads for resolved stats, `game/game_board.gd` gains one purchase entry point, and a new `ui/tower_inspector.tscn` fills the lower sidebar. `sim/harness.gd` resolves stats through the same function the game does, so headless balance claims and the running game cannot diverge.

**Tech Stack:** Godot 4.7.1, GDScript only. No addons, no C#, no external dependencies.

## Global Constraints

- **GDScript only.** No C#, no addons, no external dependencies.
- **`sim/` and `data/` must never touch the engine** — no `Node`, `get_tree()`, `preload`, `@onready`, `@export`, scene types, `load(`, `ResourceLoader`, `$`/`%` shorthand, engine RNG, or `Time.` / `Engine.` / `OS.`. `test/test_sim_purity.gd` enforces this.
- **Sim time is milliseconds.** Callers convert with `delta * 1000.0`.
- **One rule, one home.** If the harness and the board both need an answer, it lives in `sim/` and both call it.
- **Every `test_*` method is declared `-> bool` and ends `return true`**, including at every early return. This is the runner's crash sentinel.
- **No `await` in a test method.** `Object.call()` returns a `GDScriptFunctionState` and the sentinel misreads it as an aborted test.
- **Use `free()`, not `queue_free()`**, when a node is exclusively owned and removal must be observable in a frameless test.
- **`node.notification(Node.NOTIFICATION_READY)`** after `instantiate()` in tests — `@onready` never resolves otherwise.
- **Any test reading tile coordinates calls `Grid.set_active()` first.**
- **After adding a new `class_name`, run `godot --headless --import` once** before the tests, or you get a bare "Identifier not declared" parse error. Tasks 1, 2 and 6 add one each.
- **Port the reference's full test suite, not the brief's subset, and mutation-test your own work** — deliberately break each value and confirm the suite notices. Report survivors honestly.
- **Naming convention:** a data table and its rules module share a name, with the sim side suffixed. `data/economy.gd` is `Economy`, `sim/economy.gd` is `EconomySim`. Follow it: `data/upgrades.gd` is `Upgrades`, `sim/upgrades.gd` is `UpgradesSim`.
- **Test command:** `godot --headless --quit --script test/run_tests.gd`. Exit 0 passes. A green run prints ~54 `SCRIPT ERROR` lines — judge by the summary line and exit code, never stderr volume.

---

## File Structure

**Create:**
- `data/upgrades.gd` — the 32-tier table. Pure data, no logic.
- `sim/upgrades.gd` — tier legality, cost, investment, visual tier, stat resolution. Pure.
- `sim/slow.gd` — slow application, expiry, effective speed. Pure.
- `ui/tower_inspector.tscn` + `ui/tower_inspector.gd` — the selected-tower section.
- `test/test_upgrade_tables.gd` — pins the data table.
- `test/test_upgrades.gd` — the rules suite, ported from `upgrades.test.ts`.
- `test/test_slow.gd` — the slow rule.
- `test/test_tower_inspector.gd` — the inspector's wiring.

**Modify:**
- `sim/economy.gd` — add `kill_reward`.
- `sim/harness.gd:26-39` — resolve tower stats through `UpgradesSim`; carry slow on enemies.
- `game/tower.gd` — hold tiers, read resolved stats, refresh sprite, accumulate `price_paid`.
- `game/game_board.gd` — `upgrade_selected_tower`, `tower_upgraded` signal.
- `game/enemy.gd` — carry and tick slow.
- `ui/tower_panel.tscn` — host the inspector below the build list.
- `ui/hud.tscn` / `ui/hud.gd` — remove Sell.
- `test/test_hud.gd` — drop Sell coverage.
- `test/test_economy.gd` — `kill_reward` coverage.
- `test/test_harness.gd` — slow and upgraded-tower balance coverage.

---

### Task 1: The upgrade data table

**Files:**
- Create: `data/upgrades.gd`
- Test: `test/test_upgrade_tables.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Upgrades.BRANCHES: Array[StringName]`, `Upgrades.DEFS: Dictionary` keyed `kind -> branch -> {label, summary, tiers}` where each tier is `{label, description, cost, effects}`. `Upgrades.get_branch(kind, branch) -> Dictionary`.

**Reference:** `reference/project-t/td-browser/src/game/data/upgrades.ts`. Port every label, description and cost verbatim. Effect keys become snake_case: `damage_multiplier`, `fire_rate_multiplier`, `range_multiplier`, `pierce_bonus`, `splash_radius`, `detection`, `slow_factor`, `slow_duration_ms`, `gold_multiplier`, `bonus_gold_per_kill`.

The table is **32 tiers** (4 kinds × 2 branches × 4 tiers). Step 1's test pins every cost and every label, so a transcription slip fails loudly rather than sitting in the table.

**Dormant-effect markers.** Three tiers reach for pierce or detection, which have working machinery but no target until enemy properties land. Each gets a `(no effect yet)` marker on the dormant clause of its description, and nothing else changes:

- `basic` / `burst` / tier 3 `Spotter` → `"Reveals and targets phased enemies (no effect yet). Damage up by half."`
- `long` / `burst` / tier 4 `Siege Cannon` → `"Damage doubles and ignores 10 more armour (no effect yet)."`
- `long` / `burst` / tier 3 `Tungsten Core` → see below.

**One deliberate divergence — `Tungsten Core`.** The reference gives it `pierceBonus: 5` and nothing else. The other two dormant tiers carry live damage effects, so their purchase is early rather than wasted; this one is 260 gold for literally no effect, and it is the mandatory step to `Siege Cannon` behind it. Add `"damage_multiplier": 1.3` alongside the pierce bonus and set its description to `"Ignores 5 armour (no effect yet). Damage up by 30%."` Delete the multiplier, the marker and its pinning test when armoured enemies land. Put that instruction in a comment at the tier so it is found later. Every other tier is verbatim.

- [ ] **Step 1: Write the failing test**

Create `test/test_upgrade_tables.gd`:

```gdscript
extends TestCase

# Pins the shape and every cost in the upgrade table. The costs are the
# balance surface: they are what a player feels, and a transcription slip in
# one of thirty-two numbers is invisible without this.
#
# test/case.gd's _values_equal cannot distinguish 20 from 20.0, so no test
# here detects a *type* change - a cost that became a float would pass. The
# shape assertions below at least catch a missing or extra tier.

const EXPECTED_COSTS := {
	&"basic": {&"sustained": [30, 60, 130, 260], &"burst": [30, 65, 145, 290]},
	&"fast": {&"sustained": [40, 80, 165, 330], &"burst": [40, 85, 175, 350]},
	&"mortar": {&"sustained": [50, 100, 200, 400], &"burst": [50, 105, 210, 420]},
	&"long": {&"sustained": [60, 120, 240, 450], &"burst": [60, 130, 260, 500]},
}

const EXPECTED_TIER_LABELS := {
	&"basic": {
		&"sustained": ["Quick Loader", "Drum Feed", "Fragmentation", "Saturation"],
		&"burst": ["Heavy Rounds", "Rifled Barrel", "Spotter", "Executioner"],
	},
	&"fast": {
		&"sustained": ["Hair Trigger", "Overclocked", "Cryo Rounds", "Deep Freeze"],
		&"burst": ["Machined Rounds", "Scavenger", "Bounty Board", "War Profiteer"],
	},
	&"mortar": {
		&"sustained": ["Wide Bore", "Quick Crew", "Cluster Shell", "Firestorm"],
		&"burst": ["Packed Charge", "Heavy Shell", "Siege Charge", "Bunker Buster"],
	},
	&"long": {
		&"sustained": ["Long Barrel", "Rapid Loader", "Shellburst", "Carpet Fire"],
		&"burst": ["Dense Slug", "Shaped Charge", "Tungsten Core", "Siege Cannon"],
	},
}

func test_branches_are_sustained_and_burst() -> bool:
	assert_eq(Upgrades.BRANCHES.size(), 2, "exactly two branches")
	assert_true(Upgrades.BRANCHES.has(&"sustained"), "sustained branch exists")
	assert_true(Upgrades.BRANCHES.has(&"burst"), "burst branch exists")
	return true

func test_every_tower_kind_has_both_branches() -> bool:
	for kind in Towers.KINDS:
		assert_true(Upgrades.DEFS.has(kind), "%s has upgrade defs" % kind)
		for branch in Upgrades.BRANCHES:
			assert_true(Upgrades.DEFS[kind].has(branch), "%s has a %s branch" % [kind, branch])
	return true

func test_every_branch_has_exactly_four_tiers() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			assert_eq(tiers.size(), 4, "%s/%s has four tiers" % [kind, branch])
	return true

func test_tier_costs_match_the_reference_table() -> bool:
	for kind in EXPECTED_COSTS:
		for branch in EXPECTED_COSTS[kind]:
			var expected: Array = EXPECTED_COSTS[kind][branch]
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			for i in expected.size():
				assert_eq(int(tiers[i]["cost"]), int(expected[i]),
					"%s/%s tier %d costs %d" % [kind, branch, i + 1, expected[i]])
	return true

func test_tier_labels_match_the_reference_table() -> bool:
	for kind in EXPECTED_TIER_LABELS:
		for branch in EXPECTED_TIER_LABELS[kind]:
			var expected: Array = EXPECTED_TIER_LABELS[kind][branch]
			var tiers: Array = Upgrades.DEFS[kind][branch]["tiers"]
			for i in expected.size():
				assert_eq(tiers[i]["label"], expected[i],
					"%s/%s tier %d is '%s'" % [kind, branch, i + 1, expected[i]])
	return true

func test_every_tier_has_a_nonempty_description() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				assert_true(String(tier["description"]).length() > 0,
					"%s/%s '%s' has description text for the UI" % [kind, branch, tier["label"]])
	return true

# Guards the transcription against invented effect keys: a typo like
# "damage_multipler" would otherwise sit in the table doing nothing, and
# resolve_tower_stats would silently ignore it.
func test_every_effect_key_is_recognised() -> bool:
	var known := [
		&"damage_multiplier", &"fire_rate_multiplier", &"range_multiplier",
		&"pierce_bonus", &"splash_radius", &"detection",
		&"slow_factor", &"slow_duration_ms",
		&"gold_multiplier", &"bonus_gold_per_kill",
	]
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				for key in tier["effects"]:
					assert_true(known.has(key),
						"%s/%s '%s' effect key %s is recognised" % [kind, branch, tier["label"], key])
	return true

# The one divergence from the reference table, pinned so it is deliberate
# rather than drift. Delete this test together with the effect when armoured
# enemies land and pierce starts biting.
func test_tungsten_core_carries_an_interim_live_effect() -> bool:
	var tier: Dictionary = Upgrades.DEFS[&"long"][&"burst"]["tiers"][2]
	assert_eq(tier["label"], "Tungsten Core", "tier 3 of long/burst")
	assert_eq(int(tier["effects"][&"pierce_bonus"]), 5, "keeps the reference's pierce")
	assert_almost_eq(float(tier["effects"][&"damage_multiplier"]), 1.3, 0.0001,
		"carries interim damage so the purchase is not inert while pierce is dormant")
	return true

func test_get_branch_returns_the_branch_definition() -> bool:
	var branch := Upgrades.get_branch(&"basic", &"sustained")
	assert_eq(branch["label"], "Barrage", "basic's sustained branch is Barrage")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: a load error for `test_upgrade_tables.gd` — `Upgrades` is not declared yet.

- [ ] **Step 3: Write `data/upgrades.gd`**

Port the full table from `reference/project-t/td-browser/src/game/data/upgrades.ts`. Structure:

```gdscript
class_name Upgrades

## Tower upgrade tiers. Two branches per tower, four tiers each, and a
## cross-path rule (in sim/upgrades.gd) that lets only one branch pass tier 2.
##
##   sustained  rate of fire, splash, slowing  -> clears waves
##   burst      damage per hit, pierce         -> kills elites
##
## Ported from the Phaser build's data/upgrades.ts. Every number is a
## placeholder that has never been playtested, exactly as the rest of data/ is.
##
## Scarce counters sit at tier 3+ deliberately: the cross-path rule hands every
## tower two free tiers of its off-branch, so a counter any cheaper would be
## given to every build for nothing.

const BRANCHES: Array[StringName] = [&"sustained", &"burst"]

const DEFS := {
	&"basic": {
		&"sustained": {
			"label": "Barrage",
			"summary": "Faster fire, then splash damage. Clears crowds and splitters.",
			"tiers": [
				{"label": "Quick Loader", "description": "Fires 20% faster.",
					"cost": 30, "effects": {&"fire_rate_multiplier": 0.8}},
				{"label": "Drum Feed", "description": "Fires 20% faster again.",
					"cost": 60, "effects": {&"fire_rate_multiplier": 0.8}},
				{"label": "Fragmentation", "description": "Shots splash for 45px.",
					"cost": 130, "effects": {&"splash_radius": 45.0, &"fire_rate_multiplier": 0.9}},
				{"label": "Saturation", "description": "Splash grows to 75px and damage rises by half.",
					"cost": 260, "effects": {&"splash_radius": 75.0, &"damage_multiplier": 1.5}},
			],
		},
		# ... burst branch, then fast, mortar, long — all verbatim from the
		# reference except long/burst tier 3, noted below.
	},
}

static func get_branch(kind: StringName, branch: StringName) -> Dictionary:
	return DEFS[kind][branch]
```

Long Range's burst tier 3 is the single divergence:

```gdscript
				# DIVERGENCE from the reference, deliberate and temporary.
				# Upstream gives this tier pierce and nothing else, which is
				# inert until armoured enemies exist - 260 gold for no effect,
				# and a mandatory step to Siege Cannon behind it. The damage
				# multiplier and the "(no effect yet)" note are interim: delete
				# both, and test_tungsten_core_carries_an_interim_live_effect,
				# when enemy properties land.
				{"label": "Tungsten Core",
					"description": "Ignores 5 armour (no effect yet). Damage up by 30%.",
					"cost": 260, "effects": {&"pierce_bonus": 5, &"damage_multiplier": 1.3}},
```

- [ ] **Step 4: Run the import pass, then the tests**

Run: `godot --headless --import` then `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0. The import is required because `Upgrades` is a new `class_name`.

- [ ] **Step 5: Mutation-test the table**

Change one cost (e.g. `basic/sustained` tier 1 from 30 to 31), re-run, confirm `test_tier_costs_match_the_reference_table` fails. Change one label, confirm the label test fails. Add a bogus effect key, confirm `test_every_effect_key_is_recognised` fails. Restore all three and confirm green.

- [ ] **Step 6: Commit**

```bash
git add data/upgrades.gd test/test_upgrade_tables.gd
git commit -m "Add the tower upgrade table"
```

---

### Task 2: Tier legality, cost and investment

**Files:**
- Create: `sim/upgrades.gd`
- Test: `test/test_upgrades.gd`

**Interfaces:**
- Consumes: `Upgrades.DEFS`, `Upgrades.BRANCHES` (Task 1).
- Produces: `UpgradesSim.MAX_TIER: int`, `UpgradesSim.CROSS_PATH_CAP: int`, `UpgradesSim.empty_tiers() -> Dictionary`, `UpgradesSim.can_upgrade(tiers: Dictionary, branch: StringName) -> bool`, `UpgradesSim.with_upgrade(tiers: Dictionary, branch: StringName) -> Dictionary`, `UpgradesSim.upgrade_cost(kind: StringName, branch: StringName, current_tier: int) -> int`, `UpgradesSim.total_invested(kind: StringName, tiers: Dictionary) -> int`. Tier dictionaries are `{&"sustained": int, &"burst": int}`.

**Reference:** `reference/project-t/td-browser/src/game/sim/upgrades.ts` and its test file `upgrades.test.ts`. Port every test in that file, not a subset.

- [ ] **Step 1: Write the failing test**

Create `test/test_upgrades.gd`:

```gdscript
extends TestCase

# Ported from the Phaser build's sim/upgrades.test.ts, in full.
#
# The cross-path rule is the load-bearing one: a branch may pass tier 2 only
# while the other sits at or below CROSS_PATH_CAP. Without it gold is the only
# constraint and every tower converges on the same shape, so its boundaries
# get more coverage than anything else here.

func _tiers(sustained: int, burst: int) -> Dictionary:
	return {&"sustained": sustained, &"burst": burst}

# --------------------------------------------------------------------------
# constants and empty_tiers
# --------------------------------------------------------------------------

func test_max_tier_is_four() -> bool:
	assert_eq(UpgradesSim.MAX_TIER, 4, "four tiers per branch")
	return true

func test_cross_path_cap_is_two() -> bool:
	assert_eq(UpgradesSim.CROSS_PATH_CAP, 2, "the off-branch may sit at two")
	return true

func test_empty_tiers_starts_both_branches_at_zero() -> bool:
	var t := UpgradesSim.empty_tiers()
	assert_eq(t[&"sustained"], 0, "sustained starts at zero")
	assert_eq(t[&"burst"], 0, "burst starts at zero")
	return true

# --------------------------------------------------------------------------
# can_upgrade
# --------------------------------------------------------------------------

func test_can_upgrade_allows_the_first_tier_on_either_branch() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(0, 0), &"sustained"), "sustained from zero")
	assert_true(UpgradesSim.can_upgrade(_tiers(0, 0), &"burst"), "burst from zero")
	return true

func test_can_upgrade_refuses_past_max_tier() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(4, 0), &"sustained"), "already at MAX_TIER")
	return true

# The exact boundary the rule exists for. At the cap on both, either branch
# may still commit; one step past, the other is locked out.
func test_can_upgrade_allows_passing_the_cap_while_the_other_branch_is_at_it() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 2), &"sustained"),
		"2/2 may still commit either way")
	assert_true(UpgradesSim.can_upgrade(_tiers(2, 2), &"burst"),
		"2/2 may still commit either way")
	return true

func test_can_upgrade_refuses_passing_the_cap_once_the_other_branch_has() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(2, 3), &"sustained"),
		"burst already committed, so sustained cannot pass the cap")
	assert_false(UpgradesSim.can_upgrade(_tiers(3, 2), &"burst"),
		"sustained already committed, so burst cannot pass the cap")
	return true

# Below the cap the other branch's depth is irrelevant - a committed tower can
# still fill its shallow side out to the cap.
func test_can_upgrade_allows_reaching_the_cap_regardless_of_the_other_branch() -> bool:
	assert_true(UpgradesSim.can_upgrade(_tiers(1, 4), &"sustained"),
		"sustained 1 -> 2 is at the cap, always allowed")
	return true

func test_can_upgrade_refuses_an_unknown_branch() -> bool:
	assert_false(UpgradesSim.can_upgrade(_tiers(0, 0), &"nonsense"),
		"an unknown branch is not upgradeable")
	return true

# --------------------------------------------------------------------------
# with_upgrade
# --------------------------------------------------------------------------

func test_with_upgrade_increments_only_the_named_branch() -> bool:
	var t := UpgradesSim.with_upgrade(_tiers(1, 2), &"sustained")
	assert_eq(t[&"sustained"], 2, "sustained advanced")
	assert_eq(t[&"burst"], 2, "burst untouched")
	return true

func test_with_upgrade_does_not_mutate_its_argument() -> bool:
	var original := _tiers(1, 1)
	UpgradesSim.with_upgrade(original, &"burst")
	assert_eq(original[&"burst"], 1, "the caller's dictionary is unchanged")
	return true

# The reference throws here. GDScript has no exceptions and assert() compiles
# out of release builds, so this returns the tiers unchanged and pushes an
# error instead: loud in tests, inert in a shipped build. Callers gate on
# can_upgrade first.
func test_with_upgrade_returns_tiers_unchanged_on_an_illegal_buy() -> bool:
	var t := UpgradesSim.with_upgrade(_tiers(2, 3), &"sustained")
	assert_eq(t[&"sustained"], 2, "illegal cross-path buy did not apply")
	assert_eq(t[&"burst"], 3, "and nothing else moved")
	return true

# --------------------------------------------------------------------------
# upgrade_cost
# --------------------------------------------------------------------------

func test_upgrade_cost_reads_the_next_tiers_price() -> bool:
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 0), 30, "first tier")
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 3), 260, "fourth tier")
	return true

func test_upgrade_cost_is_zero_when_maxed_or_negative() -> bool:
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", 4), 0, "nothing left to buy")
	assert_eq(UpgradesSim.upgrade_cost(&"basic", &"sustained", -1), 0, "a bad tier is inert, not a crash")
	return true

# --------------------------------------------------------------------------
# total_invested
# --------------------------------------------------------------------------

func test_total_invested_is_zero_for_an_unupgraded_tower() -> bool:
	assert_eq(UpgradesSim.total_invested(&"basic", UpgradesSim.empty_tiers()), 0, "nothing sunk in")
	return true

func test_total_invested_sums_every_purchased_tier_on_both_branches() -> bool:
	# basic sustained 1-2 = 30 + 60, burst 1-3 = 30 + 65 + 145.
	assert_eq(UpgradesSim.total_invested(&"basic", _tiers(2, 3)), 330,
		"sums both branches up to their current tier")
	return true

func test_total_invested_counts_a_fully_committed_branch() -> bool:
	# long burst 1-4 = 60 + 130 + 260 + 500, sustained 1-2 = 60 + 120.
	assert_eq(UpgradesSim.total_invested(&"long", _tiers(2, 4)), 1130,
		"a maxed branch plus a capped one")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: load error for `test_upgrades.gd` — `UpgradesSim` is not declared.

- [ ] **Step 3: Write `sim/upgrades.gd`**

```gdscript
class_name UpgradesSim

## Upgrade rules: what may be bought, what it costs, what a tower becomes.
##
## The cross-path rule is the whole point. A tower may take one branch deep
## only while the other stays shallow, so every tower is a commitment rather
## than a checklist. Without it, gold is the only constraint and every tower
## converges on the same fully-upgraded shape.
##
## Pure: no engine references, no mutation of arguments.

const MAX_TIER := 4

## Highest tier the *other* branch may sit at while one branch goes deep.
const CROSS_PATH_CAP := 2

static func empty_tiers() -> Dictionary:
	return {&"sustained": 0, &"burst": 0}

static func _other_branch(branch: StringName) -> StringName:
	return &"burst" if branch == &"sustained" else &"sustained"

## Whether the next tier on a branch may be bought. Ignores affordability.
static func can_upgrade(tiers: Dictionary, branch: StringName) -> bool:
	if not tiers.has(branch):
		return false
	var next: int = int(tiers[branch]) + 1
	if next > MAX_TIER:
		return false
	# Going past the cap commits this tower; the other branch must already be
	# shallow, and stays locked there afterwards.
	if next > CROSS_PATH_CAP and int(tiers[_other_branch(branch)]) > CROSS_PATH_CAP:
		return false
	return true

## Buys the next tier. Returns a new dictionary; never mutates the argument.
##
## The reference throws on an illegal buy, on the reasoning that a call which
## should have been gated is a bug rather than a no-op. GDScript has no
## exceptions and assert() compiles out of release builds, so this pushes an
## error and returns the tiers unchanged: loud where it matters, inert in a
## shipped build. Callers gate on can_upgrade first.
static func with_upgrade(tiers: Dictionary, branch: StringName) -> Dictionary:
	if not can_upgrade(tiers, branch):
		push_error("Illegal upgrade: %s from tier %s" % [branch, tiers.get(branch, "?")])
		return tiers.duplicate()
	var next := tiers.duplicate()
	next[branch] = int(tiers[branch]) + 1
	return next

## Price of moving a branch from `current_tier` to the next. Zero when maxed.
static func upgrade_cost(kind: StringName, branch: StringName, current_tier: int) -> int:
	if current_tier >= MAX_TIER or current_tier < 0:
		return 0
	return int(Upgrades.DEFS[kind][branch]["tiers"][current_tier]["cost"])

## Total gold sunk into a tower's upgrades, for sell-value calculations.
static func total_invested(kind: StringName, tiers: Dictionary) -> int:
	var total := 0
	for branch in Upgrades.BRANCHES:
		for tier in range(int(tiers.get(branch, 0))):
			total += upgrade_cost(kind, branch, tier)
	return total
```

- [ ] **Step 4: Run the import pass, then the tests**

Run: `godot --headless --import` then `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Change `CROSS_PATH_CAP` to 3 and confirm the two cross-path boundary tests fail. Change `>` to `>=` in the cap check and confirm `test_can_upgrade_allows_passing_the_cap_while_the_other_branch_is_at_it` fails. Make `with_upgrade` mutate its argument instead of duplicating, and confirm `test_with_upgrade_does_not_mutate_its_argument` fails. Restore all three, confirm green.

- [ ] **Step 6: Commit**

```bash
git add sim/upgrades.gd test/test_upgrades.gd
git commit -m "Add upgrade tier legality, cost and investment rules"
```

---

### Task 3: Visual tier and sprite frame

**Files:**
- Modify: `sim/upgrades.gd`
- Test: `test/test_upgrades.gd`

**Interfaces:**
- Consumes: `UpgradesSim` (Task 2), `Towers.DEFS[kind]["upgrade_frames"]`.
- Produces: `UpgradesSim.VISUAL_TIERS: int`, `UpgradesSim.visual_tier(tiers: Dictionary) -> int`, `UpgradesSim.sprite_frame_for(kind: StringName, tiers: Dictionary) -> int`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_upgrades.gd`:

```gdscript
# --------------------------------------------------------------------------
# visual tier
# --------------------------------------------------------------------------

# Four looks, not seven. A tower can hold six tiers across both branches, but
# six silhouettes are not readable at tile size, and the useful signal is "how
# much is invested here" rather than the exact tier. Driven by the total across
# both branches, so a tower taken deep down one path and one taken evenly both
# read as expensive.
#
# Every boundary is pinned: ceil(total / 2) capped at VISUAL_TIERS - 1 is easy
# to write as floor, or to leave uncapped, and either passes a test that only
# samples the middle.
func test_visual_tier_maps_total_investment_onto_four_looks() -> bool:
	assert_eq(UpgradesSim.visual_tier(_tiers(0, 0)), 0, "0 tiers -> frame 0")
	assert_eq(UpgradesSim.visual_tier(_tiers(1, 0)), 1, "1 tier -> frame 1")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 0)), 1, "2 tiers -> frame 1")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 1)), 2, "3 tiers -> frame 2")
	assert_eq(UpgradesSim.visual_tier(_tiers(2, 2)), 2, "4 tiers -> frame 2")
	assert_eq(UpgradesSim.visual_tier(_tiers(3, 2)), 3, "5 tiers -> frame 3")
	assert_eq(UpgradesSim.visual_tier(_tiers(4, 2)), 3, "6 tiers -> frame 3, the cap")
	return true

func test_visual_tiers_constant_is_four() -> bool:
	assert_eq(UpgradesSim.VISUAL_TIERS, 4, "four distinct looks")
	return true

func test_visual_tier_treats_negative_tiers_as_zero() -> bool:
	assert_eq(UpgradesSim.visual_tier(_tiers(-3, 0)), 0,
		"a bad value is inert rather than a negative frame index")
	return true

# --------------------------------------------------------------------------
# sprite_frame_for
# --------------------------------------------------------------------------

func test_sprite_frame_for_indexes_the_kinds_own_frame_list() -> bool:
	# basic's upgrade_frames are [8, 9, 11, 17].
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(0, 0)), 8, "unupgraded basic")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(1, 0)), 9, "one tier in")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(2, 1)), 11, "three tiers in")
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(4, 2)), 17, "fully committed")
	return true

func test_sprite_frame_for_uses_each_kinds_distinct_frames() -> bool:
	assert_eq(UpgradesSim.sprite_frame_for(&"fast", _tiers(0, 0)), 1, "fast starts at frame 1")
	assert_eq(UpgradesSim.sprite_frame_for(&"mortar", _tiers(0, 0)), 5, "mortar at 5")
	assert_eq(UpgradesSim.sprite_frame_for(&"long", _tiers(0, 0)), 2, "long at 2")
	return true

# The frame list is data and could be shortened; clamping to its length keeps
# a short list from indexing off the end rather than crashing mid-render.
func test_sprite_frame_for_clamps_to_the_available_frames() -> bool:
	var frames: Array = Towers.DEFS[&"basic"]["upgrade_frames"]
	assert_eq(UpgradesSim.sprite_frame_for(&"basic", _tiers(4, 2)), int(frames[frames.size() - 1]),
		"never indexes past the last frame")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `visual_tier` and `sprite_frame_for` do not exist. The tests abort and the sentinel reports them as failures.

- [ ] **Step 3: Implement**

Append to `sim/upgrades.gd`:

```gdscript
## How many distinct looks a tower has, from unupgraded to fully committed.
##
## Four, not seven. A tower can hold six tiers in total, but six silhouettes
## are not readable at tile size - and the useful signal is "how much is
## invested here", not the exact tier.
const VISUAL_TIERS := 4

## Which look a tower should be wearing, from its purchased tiers. Driven by
## total investment across both branches, so a tower taken deep down one path
## and one taken evenly both look like what they are: expensive.
static func visual_tier(tiers: Dictionary) -> int:
	var total := maxi(0, int(tiers.get(&"sustained", 0))) + maxi(0, int(tiers.get(&"burst", 0)))
	# 0 -> 0, 1-2 -> 1, 3-4 -> 2, 5-6 -> 3.
	return mini(VISUAL_TIERS - 1, int(ceil(float(total) / 2.0)))

## The sprite frame a tower should be showing.
static func sprite_frame_for(kind: StringName, tiers: Dictionary) -> int:
	var frames: Array = Towers.DEFS[kind]["upgrade_frames"]
	var tier := mini(visual_tier(tiers), frames.size() - 1)
	return int(frames[tier])
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0. No import pass needed — no new `class_name`.

- [ ] **Step 5: Mutation-test**

Replace `ceil` with `floor` and confirm the odd-total boundaries fail. Remove the `mini(...)` cap and confirm `test_visual_tier_maps_total_investment_onto_four_looks`'s last case fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add sim/upgrades.gd test/test_upgrades.gd
git commit -m "Derive a tower's sprite frame from its total upgrade investment"
```

---

### Task 4: Stat resolution

**Files:**
- Modify: `sim/upgrades.gd`
- Test: `test/test_upgrades.gd`

**Interfaces:**
- Consumes: `UpgradesSim` (Tasks 2-3), `Towers.DEFS`, `Upgrades.DEFS`.
- Produces: `UpgradesSim.resolve_tower_stats(kind: StringName, tiers: Dictionary) -> Dictionary` returning keys `damage: float`, `fire_rate: float`, `range: float`, `pierce: int`, `splash_radius: float`, `detection: bool`, `slow_factor: float`, `slow_duration_ms: float`, `gold_multiplier: float`, `bonus_gold_per_kill: int`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_upgrades.gd`:

```gdscript
# --------------------------------------------------------------------------
# resolve_tower_stats
# --------------------------------------------------------------------------

# Multipliers compose, flat bonuses add, and radii/slows/gold take the
# STRONGEST value rather than stacking. The last part is what keeps the number
# a tier's text promises and the number the simulation applies identical:
# stacking would add tier 4's big splash to tier 2's small one and the tower
# would quietly outperform its own description.

func test_resolve_returns_base_stats_for_an_unupgraded_tower() -> bool:
	var base: Dictionary = Towers.DEFS[&"basic"]
	var s := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	assert_almost_eq(s["damage"], float(base["damage"]), 0.0001, "base damage")
	assert_almost_eq(s["fire_rate"], float(base["fire_rate"]), 0.0001, "base fire rate")
	assert_almost_eq(s["range"], float(base["range"]), 0.0001, "base range")
	assert_eq(s["pierce"], int(base["pierce"]), "base pierce")
	assert_almost_eq(s["splash_radius"], float(base["base_splash_radius"]), 0.0001, "base splash")
	assert_eq(s["detection"], bool(base["detection"]), "base detection")
	assert_almost_eq(s["slow_factor"], 1.0, 0.0001, "no slow by default")
	assert_almost_eq(s["gold_multiplier"], 1.0, 0.0001, "no gold bonus by default")
	assert_eq(s["bonus_gold_per_kill"], 0, "no flat gold by default")
	return true

# basic/sustained tiers 1 and 2 are 0.8 fire-rate multipliers each: they must
# compose to 0.64, not overwrite to 0.8 or add to 1.6.
func test_resolve_composes_multipliers_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"basic"]["fire_rate"])
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(2, 0))
	assert_almost_eq(s["fire_rate"], round(base * 0.8 * 0.8), 0.5,
		"two 20% cuts compose to 0.64 of the base gap")
	return true

# mortar/sustained tier 1 sets splash 70, tier 3 sets 95. The larger wins; they
# must not sum to 165.
func test_resolve_takes_the_strongest_splash_rather_than_stacking() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(3, 0))
	assert_almost_eq(s["splash_radius"], 95.0, 0.0001, "the largest radius wins")
	return true

# The tower's own base splash must not be lost when a tier sets a smaller one.
func test_resolve_never_lowers_splash_below_the_towers_base() -> bool:
	var base := float(Towers.DEFS[&"mortar"]["base_splash_radius"])
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(1, 0))
	assert_true(s["splash_radius"] >= base, "a tier can raise splash, never lower it")
	return true

func test_resolve_adds_pierce_bonuses() -> bool:
	# long/burst tier 3 grants 5, tier 4 grants 10 more.
	var s := UpgradesSim.resolve_tower_stats(&"long", _tiers(0, 4))
	assert_eq(s["pierce"], int(Towers.DEFS[&"long"]["pierce"]) + 15, "pierce bonuses add")
	return true

func test_resolve_turns_detection_on_and_never_off() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 3))
	assert_true(s["detection"], "basic/burst tier 3 grants detection")
	return true

# fast/sustained tier 3 slows to 0.7, tier 4 to 0.45. Lower is stronger, and
# the duration must travel with the factor that won.
func test_resolve_takes_the_strongest_slow_with_its_own_duration() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", _tiers(4, 0))
	assert_almost_eq(s["slow_factor"], 0.45, 0.0001, "the stronger slow wins")
	assert_almost_eq(s["slow_duration_ms"], 2500.0, 0.0001, "and brings its own duration")
	return true

func test_resolve_takes_the_strongest_gold_multiplier_and_flat_bonus() -> bool:
	# fast/burst: tier 2 grants +1 flat, tier 3 grants x1.6, tier 4 x2 and +2.
	var s := UpgradesSim.resolve_tower_stats(&"fast", _tiers(0, 4))
	assert_almost_eq(s["gold_multiplier"], 2.0, 0.0001, "the largest multiplier wins")
	assert_eq(s["bonus_gold_per_kill"], 2, "the largest flat bonus wins, rather than summing")
	return true

# Damage is applied per hit and compared against integer health, so the number
# the player is shown and the number the sim applies have to be the same one.
func test_resolve_rounds_damage_fire_rate_and_range() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 1))
	assert_almost_eq(s["damage"], round(s["damage"]), 0.0001, "damage is whole")
	assert_almost_eq(s["fire_rate"], round(s["fire_rate"]), 0.0001, "fire rate is whole")
	assert_almost_eq(s["range"], round(s["range"]), 0.0001, "range is whole")
	return true

func test_resolve_does_not_mutate_the_tower_def() -> bool:
	var before := float(Towers.DEFS[&"basic"]["damage"])
	UpgradesSim.resolve_tower_stats(&"basic", _tiers(0, 4))
	assert_almost_eq(float(Towers.DEFS[&"basic"]["damage"]), before, 0.0001,
		"the shared tower table is untouched")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `resolve_tower_stats` does not exist.

- [ ] **Step 3: Implement**

Append to `sim/upgrades.gd`:

```gdscript
## A tower's live combat stats after upgrades.
##
## Multipliers compose, flat bonuses add, and radii, slows and gold take the
## strongest value rather than stacking - otherwise tier 4's big splash would
## be added to tier 2's small one and the numbers would drift from what the
## tier text says.
static func resolve_tower_stats(kind: StringName, tiers: Dictionary) -> Dictionary:
	var base: Dictionary = Towers.DEFS[kind]
	var stats := {
		"damage": float(base["damage"]),
		"fire_rate": float(base["fire_rate"]),
		"range": float(base["range"]),
		"pierce": int(base["pierce"]),
		"splash_radius": float(base["base_splash_radius"]),
		"detection": bool(base["detection"]),
		"slow_factor": 1.0,
		"slow_duration_ms": 0.0,
		"gold_multiplier": 1.0,
		"bonus_gold_per_kill": 0,
	}

	for branch in Upgrades.BRANCHES:
		var definition: Dictionary = Upgrades.DEFS[kind][branch]
		for tier in range(int(tiers.get(branch, 0))):
			var effects: Dictionary = definition["tiers"][tier]["effects"]

			if effects.has(&"damage_multiplier"):
				stats["damage"] *= float(effects[&"damage_multiplier"])
			if effects.has(&"fire_rate_multiplier"):
				stats["fire_rate"] *= float(effects[&"fire_rate_multiplier"])
			if effects.has(&"range_multiplier"):
				stats["range"] *= float(effects[&"range_multiplier"])
			if effects.has(&"pierce_bonus"):
				stats["pierce"] += int(effects[&"pierce_bonus"])
			if effects.has(&"splash_radius"):
				stats["splash_radius"] = maxf(stats["splash_radius"], float(effects[&"splash_radius"]))
			if effects.has(&"detection") and bool(effects[&"detection"]):
				stats["detection"] = true
			if effects.has(&"gold_multiplier"):
				stats["gold_multiplier"] = maxf(stats["gold_multiplier"], float(effects[&"gold_multiplier"]))
			if effects.has(&"bonus_gold_per_kill"):
				stats["bonus_gold_per_kill"] = maxi(
					int(stats["bonus_gold_per_kill"]), int(effects[&"bonus_gold_per_kill"]))
			# Lower is stronger, and the duration travels with the factor that won.
			if effects.has(&"slow_factor") and float(effects[&"slow_factor"]) < stats["slow_factor"]:
				stats["slow_factor"] = float(effects[&"slow_factor"])
				stats["slow_duration_ms"] = float(effects.get(&"slow_duration_ms", stats["slow_duration_ms"]))

	stats["damage"] = round(stats["damage"])
	stats["fire_rate"] = round(stats["fire_rate"])
	stats["range"] = round(stats["range"])
	return stats
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Change `maxf` to `+` for splash and confirm `test_resolve_takes_the_strongest_splash_rather_than_stacking` fails. Change the slow comparison from `<` to `>` and confirm the slow test fails. Change `*=` to `=` for `damage_multiplier` and confirm the composition test fails. Restore all three, confirm green.

- [ ] **Step 6: Commit**

```bash
git add sim/upgrades.gd test/test_upgrades.gd
git commit -m "Resolve a tower's live stats from its purchased tiers"
```

---

### Task 5: The slow rule

**Files:**
- Create: `sim/slow.gd`
- Test: `test/test_slow.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Slow.none() -> Dictionary` returning `{&"factor": 1.0, &"remaining_ms": 0.0}`; `Slow.apply(state: Dictionary, factor: float, duration_ms: float) -> Dictionary`; `Slow.tick(state: Dictionary, delta_ms: float) -> Dictionary`; `Slow.effective_speed(base_speed: float, state: Dictionary) -> float`.

**Why its own module:** both `sim/harness.gd` and `game/enemy.gd` need it, and the project's rule is that a question both answer lives in `sim/` once.

- [ ] **Step 1: Write the failing test**

Create `test/test_slow.gd`:

```gdscript
extends TestCase

# Slowing is the Fast tower's branch identity and the only mechanic here that
# changes an enemy's speed after it spawns. It lives in sim/ because the
# harness and the live game both apply it, and two copies would drift.
#
# Note for anyone touching movement: slow only ever REDUCES step size, so it
# moves away from the fixed-step oscillation hazard documented in
# sim/movement.gd, never toward it.

func test_none_is_no_slow_at_all() -> bool:
	var s := Slow.none()
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "no time left to run")
	return true

func test_effective_speed_is_the_base_when_unslowed() -> bool:
	assert_almost_eq(Slow.effective_speed(100.0, Slow.none()), 100.0, 0.0001, "untouched")
	return true

func test_apply_sets_the_factor_and_duration() -> bool:
	var s := Slow.apply(Slow.none(), 0.7, 1500.0)
	assert_almost_eq(s[&"factor"], 0.7, 0.0001, "factor taken")
	assert_almost_eq(s[&"remaining_ms"], 1500.0, 0.0001, "duration taken")
	return true

func test_effective_speed_applies_the_factor() -> bool:
	var s := Slow.apply(Slow.none(), 0.45, 2500.0)
	assert_almost_eq(Slow.effective_speed(100.0, s), 45.0, 0.0001, "speed scaled")
	return true

# Strongest wins, matching resolve_tower_stats. A weaker slow landing on an
# enemy already deeply slowed must not speed it back up.
func test_apply_keeps_the_stronger_of_two_slows() -> bool:
	var strong := Slow.apply(Slow.none(), 0.45, 2500.0)
	var after := Slow.apply(strong, 0.7, 1500.0)
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "the weaker slow did not win")
	return true

# But it must still refresh the clock: standing in a weaker tower's fire keeps
# an enemy slowed rather than letting the strong slow lapse early.
func test_apply_refreshes_the_timer_with_the_longer_remaining() -> bool:
	var nearly_done := {&"factor": 0.45, &"remaining_ms": 100.0}
	var after := Slow.apply(nearly_done, 0.7, 1500.0)
	assert_almost_eq(after[&"remaining_ms"], 1500.0, 0.0001, "the longer timer wins")
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "and the stronger factor is kept")
	return true

func test_apply_upgrades_to_a_stronger_slow() -> bool:
	var weak := Slow.apply(Slow.none(), 0.7, 1500.0)
	var after := Slow.apply(weak, 0.45, 2500.0)
	assert_almost_eq(after[&"factor"], 0.45, 0.0001, "the stronger slow takes over")
	assert_almost_eq(after[&"remaining_ms"], 2500.0, 0.0001, "with its own duration")
	return true

func test_tick_counts_the_timer_down() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 400.0)
	assert_almost_eq(s[&"remaining_ms"], 600.0, 0.0001, "decremented by delta")
	assert_almost_eq(s[&"factor"], 0.5, 0.0001, "still slowed")
	return true

# Expiry must restore full speed exactly at zero, not below it - a negative
# remainder that kept the factor would slow the enemy forever.
func test_tick_restores_full_speed_when_the_timer_runs_out() -> bool:
	var s := Slow.tick(Slow.apply(Slow.none(), 0.5, 1000.0), 1000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "back to full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "clamped at zero, not negative")
	return true

func test_tick_is_a_no_op_on_an_unslowed_enemy() -> bool:
	var s := Slow.tick(Slow.none(), 500.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "still full speed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "not driven negative")
	return true

# A factor of 1.0 is "no slow"; applying one must not start a timer that
# later "expires" and does nothing, nor register as a slow in the UI.
func test_apply_ignores_a_factor_of_one() -> bool:
	var s := Slow.apply(Slow.none(), 1.0, 2000.0)
	assert_almost_eq(s[&"factor"], 1.0, 0.0001, "still unslowed")
	assert_almost_eq(s[&"remaining_ms"], 0.0, 0.0001, "no timer started")
	return true

func test_apply_does_not_mutate_its_argument() -> bool:
	var original := Slow.none()
	Slow.apply(original, 0.5, 1000.0)
	assert_almost_eq(original[&"factor"], 1.0, 0.0001, "the caller's state is unchanged")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: load error for `test_slow.gd` — `Slow` is not declared.

- [ ] **Step 3: Write `sim/slow.gd`**

```gdscript
class_name Slow

## An enemy's slow state: a speed factor and how long it has left to run.
##
## Strongest-factor-wins matches sim/upgrades.gd's stat resolution, so a weak
## slow landing on a deeply slowed enemy cannot speed it back up. The timer is
## refreshed independently, so standing in a weak tower's fire keeps an enemy
## slowed rather than letting a strong slow lapse early.
##
## Pure: returns new dictionaries rather than mutating.

static func none() -> Dictionary:
	return {&"factor": 1.0, &"remaining_ms": 0.0}

static func apply(state: Dictionary, factor: float, duration_ms: float) -> Dictionary:
	# A factor of 1.0 or above is not a slow. Taking it would start a timer
	# that expires having done nothing, and would read as "slowed" to any UI.
	if factor >= 1.0:
		return state.duplicate()
	return {
		&"factor": minf(float(state.get(&"factor", 1.0)), factor),
		&"remaining_ms": maxf(float(state.get(&"remaining_ms", 0.0)), duration_ms),
	}

static func tick(state: Dictionary, delta_ms: float) -> Dictionary:
	var remaining := float(state.get(&"remaining_ms", 0.0)) - delta_ms
	if remaining <= 0.0:
		return none()
	return {&"factor": float(state.get(&"factor", 1.0)), &"remaining_ms": remaining}

static func effective_speed(base_speed: float, state: Dictionary) -> float:
	return base_speed * float(state.get(&"factor", 1.0))
```

- [ ] **Step 4: Run the import pass, then the tests**

Run: `godot --headless --import` then `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Change `minf` to `maxf` in `apply` and confirm `test_apply_keeps_the_stronger_of_two_slows` fails. Change `<= 0.0` to `< 0.0` in `tick` and confirm `test_tick_restores_full_speed_when_the_timer_runs_out` fails. Remove the `factor >= 1.0` guard and confirm `test_apply_ignores_a_factor_of_one` fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add sim/slow.gd test/test_slow.gd
git commit -m "Add the slow rule"
```

---

### Task 6: Kill rewards

**Files:**
- Modify: `sim/economy.gd`
- Test: `test/test_economy.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `EconomySim.kill_reward(base_reward: int, source: Dictionary) -> int`.

**Note:** `source` is the dictionary a tower already emits with `wants_to_fire` — it carries `damage` and `pierce` today, and gains `gold_multiplier` and `bonus_gold_per_kill` in Task 7. Reading them with `.get(..., default)` keeps this function correct for a source that has neither, which is what every test before Task 7 passes.

- [ ] **Step 1: Write the failing test**

Append to `test/test_economy.gd`:

```gdscript
# --------------------------------------------------------------------------
# kill_reward
# --------------------------------------------------------------------------

# The multiplier applies before the flat bonus, so a flat bonus is never
# multiplied. Order matters: the other way round, fast/burst tier 4 would pay
# (5 + 2) * 2 = 14 rather than 5 * 2 + 2 = 12, and no tier text says that.

func test_kill_reward_is_the_base_when_the_source_has_no_gold_effects() -> bool:
	assert_eq(EconomySim.kill_reward(5, {"damage": 4.0}), 5,
		"a source without gold fields pays the plain reward")
	return true

func test_kill_reward_applies_the_multiplier() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 1.6}), 8, "5 * 1.6 floors to 8")
	return true

func test_kill_reward_adds_the_flat_bonus() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"bonus_gold_per_kill": 2}), 7, "5 + 2")
	return true

func test_kill_reward_multiplies_before_adding_the_flat_bonus() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2}), 12,
		"5 * 2 + 2, not (5 + 2) * 2")
	return true

func test_kill_reward_floors_a_fractional_result() -> bool:
	assert_eq(EconomySim.kill_reward(5, {&"gold_multiplier": 1.5}), 7, "7.5 floors to 7")
	return true

func test_kill_reward_never_pays_less_than_zero() -> bool:
	assert_eq(EconomySim.kill_reward(0, {&"gold_multiplier": 2.0}), 0, "nothing from nothing")
	assert_eq(EconomySim.kill_reward(-5, {}), 0, "a bad reward is inert, not a gold sink")
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `kill_reward` does not exist.

- [ ] **Step 3: Implement**

Append to `sim/economy.gd`:

```gdscript
## Gold paid for a kill, after the killing tower's gold effects.
##
## The multiplier applies first and the flat bonus is added after, so a flat
## bonus is never itself multiplied - which is what the tier descriptions say.
## Floors, because gold is an integer and a fractional reward would drift from
## the number shown in the HUD.
static func kill_reward(base_reward: int, source: Dictionary) -> int:
	var multiplier := float(source.get(&"gold_multiplier", 1.0))
	var flat := int(source.get(&"bonus_gold_per_kill", 0))
	return maxi(0, int(floor(float(maxi(0, base_reward)) * multiplier)) + flat)
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Swap the order so the flat bonus is added before multiplying, and confirm `test_kill_reward_multiplies_before_adding_the_flat_bonus` fails. Change `floor` to `round` and confirm the flooring test fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add sim/economy.gd test/test_economy.gd
git commit -m "Pay kill rewards through the killing tower's gold effects"
```

---

### Task 7: Tower view holds tiers and reads resolved stats

**Files:**
- Modify: `game/tower.gd`
- Test: `test/test_tower.gd`

**Interfaces:**
- Consumes: `UpgradesSim.empty_tiers`, `resolve_tower_stats`, `sprite_frame_for`, `total_invested` (Tasks 2-4).
- Produces: `Tower.tiers: Dictionary`, `Tower.apply_upgrade(branch: StringName) -> void`, `Tower.get_stats() -> Dictionary`. `Tower.price_paid` now means placement plus upgrade spend. The `source` dictionary emitted by `wants_to_fire` gains `gold_multiplier: float` and `bonus_gold_per_kill: int`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_tower.gd`:

```gdscript
# --------------------------------------------------------------------------
# upgrades
# --------------------------------------------------------------------------

# The tower caches resolved stats rather than resolving per tick, so every
# path that changes tiers has to refresh the cache. These tests exist mostly
# to catch a refresh that was forgotten.

func test_setup_starts_a_tower_with_no_tiers() -> bool:
	var t := _ready_tower(&"basic")
	assert_eq(t.tiers[&"sustained"], 0, "sustained starts at zero")
	assert_eq(t.tiers[&"burst"], 0, "burst starts at zero")
	t.free()
	return true

func test_get_stats_returns_base_stats_before_any_upgrade() -> bool:
	var t := _ready_tower(&"basic")
	assert_almost_eq(t.get_stats()["damage"], float(Towers.DEFS[&"basic"]["damage"]), 0.0001,
		"unupgraded damage is the table's")
	t.free()
	return true

func test_apply_upgrade_advances_the_branch_and_refreshes_the_stats() -> bool:
	var t := _ready_tower(&"basic")
	var before := t.get_stats()["fire_rate"]
	t.apply_upgrade(&"sustained")
	assert_eq(t.tiers[&"sustained"], 1, "branch advanced")
	assert_true(t.get_stats()["fire_rate"] < before,
		"the cached stats were refreshed, not left stale")
	t.free()
	return true

func test_apply_upgrade_accumulates_into_price_paid() -> bool:
	var t := _ready_tower(&"basic")
	var placed := t.price_paid
	t.apply_upgrade(&"sustained")
	assert_eq(t.price_paid, placed + 30,
		"price_paid means everything sunk in, so sell_refund keeps its meaning")
	t.free()
	return true

func test_to_targeting_dict_reports_upgraded_range_and_detection() -> bool:
	var t := _ready_tower(&"basic")
	t.apply_upgrade(&"burst")
	t.apply_upgrade(&"burst")
	t.apply_upgrade(&"burst")  # Spotter grants detection
	assert_true(t.to_targeting_dict()["detection"], "detection comes from resolved stats")
	t.free()
	return true

func test_upgrading_advances_the_sprite_frame() -> bool:
	var t := _ready_tower(&"basic")
	var frames: Array = Towers.DEFS[&"basic"]["upgrade_frames"]
	t.apply_upgrade(&"sustained")
	assert_eq(t._sprite.texture.region, Tower.frame_region(int(frames[1])),
		"one tier in shows the second frame")
	t.free()
	return true
```

If `test_tower.gd` has no `_ready_tower` helper, add one following the pattern in that file's existing tests: instantiate `res://game/tower.tscn`, fire `notification(Node.NOTIFICATION_READY)`, then call `setup(kind, 0, 0, EconomySim.tower_price(kind, 0))`. Call `Grid.set_active(...)` first — `setup` positions through `Grid.tile_to_world_center`.

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `tiers`, `apply_upgrade` and `get_stats` do not exist.

- [ ] **Step 3: Implement**

In `game/tower.gd`, add the field and cache:

```gdscript
var tiers := {}

var _stats := {}
```

At the end of `setup()`, after the existing body:

```gdscript
	tiers = UpgradesSim.empty_tiers()
	_refresh_stats()
```

Add:

```gdscript
## Buys a tier and refreshes everything derived from it. The board gates on
## UpgradesSim.can_upgrade and affordability before calling.
func apply_upgrade(branch: StringName) -> void:
	price_paid += UpgradesSim.upgrade_cost(kind, branch, int(tiers[branch]))
	tiers = UpgradesSim.with_upgrade(tiers, branch)
	_refresh_stats()

func get_stats() -> Dictionary:
	return _stats

## Stats are resolved on change rather than per tick: tick() runs for every
## tower every physics frame, and resolution walks both branches' tiers.
func _refresh_stats() -> void:
	_stats = UpgradesSim.resolve_tower_stats(kind, tiers)
	var atlas := AtlasTexture.new()
	atlas.atlas = TOWER_SHEET
	atlas.region = frame_region(UpgradesSim.sprite_frame_for(kind, tiers))
	_sprite.texture = atlas
	_range_indicator.radius = float(_stats["range"])
	_range_indicator.queue_redraw()
```

Replace the two `_def` readers. `to_targeting_dict`:

```gdscript
func to_targeting_dict() -> Dictionary:
	return {
		"position": position, "range": float(_stats["range"]),
		"priority": _priority, "detection": bool(_stats["detection"]),
	}
```

and the body of `tick` after the cooldown check:

```gdscript
	_cooldown = float(_stats["fire_rate"])
	wants_to_fire.emit(target["node"],
		{
			"damage": _stats["damage"],
			"pierce": _stats["pierce"],
			&"gold_multiplier": _stats["gold_multiplier"],
			&"bonus_gold_per_kill": _stats["bonus_gold_per_kill"],
			&"slow_factor": _stats["slow_factor"],
			&"slow_duration_ms": _stats["slow_duration_ms"],
		},
		float(_stats["splash_radius"]))
```

`setup()` keeps setting the sprite and range from the table before
`_refresh_stats()` runs — leave those lines alone; the refresh overwrites them
with the same values for an unupgraded tower.

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0. Existing tower and board tests must still pass — an unupgraded tower resolves to exactly its table values.

- [ ] **Step 5: Mutation-test**

Delete the `_refresh_stats()` call from `apply_upgrade` and confirm `test_apply_upgrade_advances_the_branch_and_refreshes_the_stats` fails. Remove the `price_paid +=` line and confirm the accumulation test fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add game/tower.gd test/test_tower.gd
git commit -m "Give towers tiers and resolve their stats through sim/upgrades"
```

---

### Task 8: Buying an upgrade

**Files:**
- Modify: `game/game_board.gd`
- Test: `test/test_game_board.gd`

**Interfaces:**
- Consumes: `Tower.apply_upgrade`, `Tower.tiers` (Task 7), `UpgradesSim.can_upgrade`, `upgrade_cost` (Task 2).
- Produces: `GameBoard.upgrade_selected_tower(branch: StringName) -> void` and `signal tower_upgraded(branch: StringName)`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_game_board.gd`:

```gdscript
# --------------------------------------------------------------------------
# upgrades
# --------------------------------------------------------------------------

func _place_and_select(b: GameBoard, kind: StringName) -> Tower:
	b._gold = 5000
	var tile := _find_buildable_tile(b)
	b.select_tower_kind(kind)
	b._try_place(tile.x, tile.y)
	b._handle_tap(Grid.tile_to_world_center(tile.x, tile.y))
	return b._selected_tower

func test_upgrade_selected_tower_advances_the_branch_and_charges_for_it() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	var gold_before := b.get_gold()

	b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 1, "the branch advanced")
	assert_eq(b.get_gold(), gold_before - 30, "and the tier's cost was deducted")
	b.free()
	return true

func test_upgrade_selected_tower_is_a_no_op_with_nothing_selected() -> bool:
	var b := _ready_board()
	b._gold = 5000
	var gold_before := b.get_gold()

	b.upgrade_selected_tower(&"sustained")

	assert_eq(b.get_gold(), gold_before, "no selection means no purchase")
	b.free()
	return true

func test_upgrade_selected_tower_refuses_when_gold_is_short() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	b._gold = 5

	b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 0, "the branch did not advance")
	assert_eq(b.get_gold(), 5, "and nothing was spent")
	b.free()
	return true

# The cross-path rule has to be enforced at the purchase point, not only in
# the UI - a board method that trusts its caller is one bug away from a tower
# with both branches maxed.
func test_upgrade_selected_tower_enforces_the_cross_path_rule() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	for i in 3:
		b.upgrade_selected_tower(&"burst")
	assert_eq(tower.tiers[&"burst"], 3, "precondition: burst is committed")

	for i in 3:
		b.upgrade_selected_tower(&"sustained")

	assert_eq(tower.tiers[&"sustained"], 2,
		"sustained stopped at the cross-path cap despite ample gold")
	b.free()
	return true

func test_upgrade_selected_tower_emits_tower_upgraded() -> bool:
	var b := _ready_board()
	_place_and_select(b, &"basic")
	var seen: Array = []
	b.tower_upgraded.connect(func(branch): seen.append(branch))

	b.upgrade_selected_tower(&"sustained")

	assert_eq(seen.size(), 1, "one signal per purchase")
	assert_eq(seen[0], &"sustained", "carrying the branch bought")
	b.free()
	return true

func test_upgrade_selected_tower_reports_why_it_refused() -> bool:
	var b := _ready_board()
	_place_and_select(b, &"basic")
	b._gold = 5
	var messages: Array = []
	b.placement_rejected.connect(func(text): messages.append(text))

	b.upgrade_selected_tower(&"sustained")

	assert_eq(messages.size(), 1, "the player is told why")
	b.free()
	return true

func test_selling_an_upgraded_tower_refunds_half_of_everything_sunk_in() -> bool:
	var b := _ready_board()
	var tower := _place_and_select(b, &"basic")
	b.upgrade_selected_tower(&"sustained")   # 30
	b.upgrade_selected_tower(&"sustained")   # 60
	var invested := tower.price_paid
	var gold_before := b.get_gold()

	b.sell_selected_tower()

	assert_eq(b.get_gold(), gold_before + EconomySim.sell_refund(invested),
		"refund covers placement and upgrades together")
	b.free()
	return true
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `upgrade_selected_tower` and `tower_upgraded` do not exist.

- [ ] **Step 3: Implement**

Add the signal beside the others at the top of `game/game_board.gd`:

```gdscript
signal tower_upgraded(branch: StringName)
```

and the method beside `sell_selected_tower`:

```gdscript
## Buys the next tier on a branch of the selected tower.
##
## Gating lives here rather than only in the UI: the cross-path rule is a game
## rule, and a board method that trusted its caller would be one bug away from
## a tower with both branches maxed.
func upgrade_selected_tower(branch: StringName) -> void:
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	var tower := _selected_tower
	if not UpgradesSim.can_upgrade(tower.tiers, branch):
		placement_rejected.emit("That branch is locked - the other path is already committed.")
		return
	var price := UpgradesSim.upgrade_cost(tower.kind, branch, int(tower.tiers[branch]))
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		return

	_gold -= price
	gold_changed.emit(_gold)
	tower.apply_upgrade(branch)
	tower_upgraded.emit(branch)
	_play_sound(&"place")
```

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Delete the `can_upgrade` gate and confirm `test_upgrade_selected_tower_enforces_the_cross_path_rule` fails. Delete the `can_afford` gate and confirm the short-gold test fails. Move `_gold -= price` after `apply_upgrade` — it should still pass, which tells you the ordering is not load-bearing; leave it where it reads clearest. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add game/game_board.gd test/test_game_board.gd
git commit -m "Add buying an upgrade, gated on the cross-path rule and gold"
```

---

### Task 9: Slow and gold reach the running game

**Files:**
- Modify: `game/enemy.gd`, `game/game_board.gd`, `sim/harness.gd`
- Test: `test/test_enemy.gd`, `test/test_harness.gd`

**Interfaces:**
- Consumes: `Slow` (Task 5), `EconomySim.kill_reward` (Task 6), the extended `source` dictionary (Task 7).
- Produces: `Enemy.current_speed() -> float`, `Enemy.tick_slow(delta_ms: float) -> void`; `Enemy.sim` gains a `"slow"` key; `Harness.run_wave` accepts `tiers` per tower in its config and applies slow.

**Three facts about `game/enemy.gd` that the code, not the docs, is authority on — check them before writing:**

1. **All enemy state lives in one `sim` dictionary**, not in separate fields. Speed is `sim["speed"]`, seeded in `setup()`. The slow state joins it as `sim["slow"]`.
2. **`signal died(reward: int, kind: StringName)` takes two arguments.** CONTINUE.md §7 currently claims "the shipped signal takes reward only — trust the code"; the code says otherwise, and the code wins. **Keep both arguments** when changing the emission, or every listener breaks.
3. **`_die()` does not currently receive the killing `source`**, and it needs it to apply gold effects. Change it to `_die(source: Dictionary)` and pass the source through from `take_damage`. Note `_die()` is a coroutine (it awaits `animation_finished`), which is fine — but the emission must happen *before* the await, as it already does.

`test/test_enemy.gd`'s helper is `_ready_enemy()` and takes **no arguments**.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_enemy.gd`:

```gdscript
# --------------------------------------------------------------------------
# slow and gold
# --------------------------------------------------------------------------

func test_taking_a_hit_from_a_slowing_source_slows_the_enemy() -> bool:
	var e := _ready_enemy()
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, &"slow_factor": 0.5, &"slow_duration_ms": 1000.0})
	assert_almost_eq(e.current_speed(), full * 0.5, 0.0001, "moving at half speed")
	e.free()
	return true

func test_a_slow_expires_after_its_duration() -> bool:
	var e := _ready_enemy()
	var full: float = e.sim["speed"]
	e.take_damage({"damage": 0.0, &"slow_factor": 0.5, &"slow_duration_ms": 1000.0})
	e.tick_slow(1000.0)
	assert_almost_eq(e.current_speed(), full, 0.0001, "back to full speed")
	e.free()
	return true

func test_an_unslowed_enemy_moves_at_its_full_speed() -> bool:
	var e := _ready_enemy()
	assert_almost_eq(e.current_speed(), float(e.sim["speed"]), 0.0001, "untouched by default")
	e.free()
	return true

# died() carries (reward, kind) - both arguments, despite what CONTINUE.md §7
# says. The handler below takes both deliberately; a one-argument lambda would
# fail to connect and this test would abort rather than fail.
func test_a_lethal_hit_pays_the_sources_gold_effects() -> bool:
	var e := _ready_enemy()
	var rewards: Array = []
	e.died.connect(func(reward, _kind): rewards.append(reward))

	e.take_damage({"damage": 9999.0, &"gold_multiplier": 2.0, &"bonus_gold_per_kill": 1})

	var base := int(Enemies.DEFS[e.kind]["reward"])
	assert_eq(rewards[0], EconomySim.kill_reward(base, {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 1}),
		"the killing tower's gold effects applied")
	assert_true(rewards[0] > base, "and it is more than the plain reward")
	e.free()
	return true

func test_a_lethal_hit_from_a_plain_source_pays_the_base_reward() -> bool:
	var e := _ready_enemy()
	var rewards: Array = []
	e.died.connect(func(reward, _kind): rewards.append(reward))

	e.take_damage({"damage": 9999.0})

	assert_eq(rewards[0], int(Enemies.DEFS[e.kind]["reward"]),
		"a source with no gold effects still pays exactly the table's reward")
	e.free()
	return true
```

Append to `test/test_harness.gd`:

```gdscript
# A slowed enemy must take measurably longer over the same path. This is the
# proof that slow is a real mechanic rather than a number nothing reads.
func test_a_slowing_tower_makes_a_wave_take_longer() -> bool:
	var path := _demo_path()
	var plain := Harness.run_wave({"wave": 1, "path": path, "towers": []})
	var slowed := Harness.run_wave({
		"wave": 1, "path": path,
		"towers": [{"kind": &"fast", "position": path[path.size() / 2],
			"tiers": {&"sustained": 4, &"burst": 0}}],
	})
	assert_true(slowed["ticks"] > plain["ticks"],
		"the slowing tower held the wave up")
	return true

# The termination guard from the soft-lock fix, re-run with slowing in play.
# Slow only ever reduces step size, so it moves away from the fixed-step
# oscillation hazard - but that is an argument, and this is the check.
func test_every_wave_with_a_slowing_tower_still_terminates() -> bool:
	var path := _demo_path()
	for wave in range(1, Waves.MAX_WAVES + 1):
		var result := Harness.run_wave({
			"wave": wave, "path": path,
			"towers": [{"kind": &"fast", "position": path[path.size() / 2],
				"tiers": {&"sustained": 4, &"burst": 0}}],
		})
		assert_true(result["ticks"] < Harness.DEFAULT_MAX_TICKS,
			"wave %d terminates with a slowing tower present" % wave)
	return true

func test_harness_resolves_tower_stats_through_the_upgrade_rules() -> bool:
	var path := _demo_path()
	var base := Harness.run_wave({
		"wave": 5, "path": path,
		"towers": [{"kind": &"basic", "position": path[path.size() / 2]}],
	})
	var upgraded := Harness.run_wave({
		"wave": 5, "path": path,
		"towers": [{"kind": &"basic", "position": path[path.size() / 2],
			"tiers": {&"sustained": 0, &"burst": 4}}],
	})
	assert_true(upgraded["kills"] >= base["kills"],
		"a fully upgraded tower kills at least as much as a bare one")
	return true
```

Use whatever helper `test_harness.gd` already has for the demo path rather than a new `_demo_path` if one exists.

- [ ] **Step 2: Run and confirm they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `current_speed`, `tick_slow` and the harness's `tiers` support do not exist.

- [ ] **Step 3: Implement**

In `game/enemy.gd`, seed the slow state in `setup()` by adding one key to the
`sim` dictionary literal, beside `"path_index"`:

```gdscript
		"slow": Slow.none(),
```

Add the two accessors:

```gdscript
## Speed after any active slow. Movement reads this, never sim["speed"].
func current_speed() -> float:
	return Slow.effective_speed(float(sim["speed"]), sim["slow"])

func tick_slow(delta_ms: float) -> void:
	sim["slow"] = Slow.tick(sim["slow"], delta_ms)
```

In `_physics_process`, after the `sim.is_empty()` and alive guards and before
`Movement.advance`, add `tick_slow(delta * 1000.0)`, then change the movement
call's speed argument from `sim["speed"]` to `current_speed()`:

```gdscript
	tick_slow(delta * 1000.0)

	var result := Movement.advance(position, sim["path_index"], _path,
		current_speed(), delta * 1000.0)
```

In `take_damage`, apply an incoming slow before resolving damage, and pass the
source down to `_die` — a dead enemy needs to know which tower killed it:

```gdscript
func take_damage(source: Dictionary) -> Dictionary:
	if source.has(&"slow_factor"):
		sim["slow"] = Slow.apply(sim["slow"], float(source[&"slow_factor"]),
			float(source.get(&"slow_duration_ms", 0.0)))
	var result := Damage.resolve(source, sim)
	sim["health"] = result["remaining_health"]
	_update_health_bar()
	if result["lethal"]:
		_die(source)
	return result
```

and in `_die`, keep **both** signal arguments — `died` is
`(reward: int, kind: StringName)`:

```gdscript
func _die(source: Dictionary) -> void:
	sim["dying"] = true
	sim["alive"] = false
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
```

leaving the rest of `_die` — the health-bar hide, the death animation and the
`await` — exactly as it is.

In `sim/harness.gd`, replace the tower-building block at lines 26-39:

```gdscript
	var towers: Array = []
	for t in config.get("towers", []):
		var tiers: Dictionary = t.get("tiers", UpgradesSim.empty_tiers())
		var stats := UpgradesSim.resolve_tower_stats(t["kind"], tiers)
		towers.append({
			"position": t["position"],
			"range": stats["range"],
			"fire_rate": stats["fire_rate"],
			"damage": stats["damage"],
			"pierce": stats["pierce"],
			"detection": stats["detection"],
			"splash": stats["splash_radius"],
			"slow_factor": stats["slow_factor"],
			"slow_duration_ms": stats["slow_duration_ms"],
			"gold_multiplier": stats["gold_multiplier"],
			"bonus_gold_per_kill": stats["bonus_gold_per_kill"],
			"priority": Targeting.DEFAULT_PRIORITY,
			"cooldown": 0.0,
		})
```

Give each harness enemy a `"slow"` key seeded with `Slow.none()` at spawn, tick
it each loop with `Slow.tick`, use `Slow.effective_speed(e["speed"], e["slow"])`
where movement currently reads `e["speed"]`, apply the firing tower's slow on
hit with `Slow.apply`, and pay `gold_earned` through `EconomySim.kill_reward`.

- [ ] **Step 4: Run the tests**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0. Every existing balance pin in `test_harness.gd` must still hold — an unupgraded tower resolves to its table values and `Slow.none()` leaves speed untouched, so nothing about the existing waves changes. **If any existing pin moves, stop and investigate before adjusting it.**

- [ ] **Step 5: Mutation-test**

Change `current_speed()` back to `_speed` in the movement call and confirm `test_a_slowing_tower_makes_a_wave_take_longer` fails. Drop the `kill_reward` call and confirm the gold test fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add game/enemy.gd game/game_board.gd sim/harness.gd test/test_enemy.gd test/test_harness.gd
git commit -m "Wire slow and kill-reward effects through the game and the harness"
```

---

### Task 10: The tower inspector

**Files:**
- Create: `ui/tower_inspector.tscn`, `ui/tower_inspector.gd`
- Modify: `ui/tower_panel.tscn`, `ui/hud.tscn`, `ui/hud.gd`, `game/game.tscn`, `test/test_hud.gd`
- Test: `test/test_tower_inspector.gd`

**Interfaces:**
- Consumes: `GameBoard.upgrade_selected_tower`, `tower_upgraded`, `sell_selected_tower`, `gold_changed` (Task 8); `UpgradesSim.can_upgrade`, `upgrade_cost` (Task 2).
- Produces: `TowerInspector.bind(board: GameBoard) -> void`, `TowerInspector.show_tower(tower: Tower) -> void`, `TowerInspector.clear() -> void`.

**Layout:** the inspector sits below the build list inside the sidebar. Sell moves out of the HUD into the inspector, so `hud.tscn` loses its `SellButton` and `hud.gd` loses `_sell` and its `bind()` connection. `test_hud.gd`'s `test_start_and_sell_buttons_meet_the_44x44_minimum_tap_target` becomes a Start-only test.

**The board must tell the UI about selection.** `GameBoard._select_tower` / `_deselect_tower` currently only toggle the range indicator. Add `signal tower_selected(tower: Tower)` and `signal tower_deselected()`, emitted from those two methods, and have the inspector bind to them.

- [ ] **Step 1: Write the failing test**

Create `test/test_tower_inspector.gd`:

```gdscript
extends TestCase

# The inspector is a view over the board: it decides nothing about legality or
# affordability, it asks UpgradesSim and the board. These tests pin that it
# asks, and that it refreshes when the answers change.

func _ready_inspector() -> TowerInspector:
	var i: TowerInspector = load("res://ui/tower_inspector.tscn").instantiate()
	i.notification(Node.NOTIFICATION_READY)
	return i

func _ready_board() -> GameBoard:
	var b: GameBoard = load("res://game/game_board.tscn").instantiate()
	b.notification(Node.NOTIFICATION_READY)
	return b

func test_starts_empty_with_no_tower_shown() -> bool:
	var i := _ready_inspector()
	assert_false(i.has_tower(), "nothing selected at start")
	i.free()
	return true

func test_show_tower_lists_one_row_per_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	assert_true(i.has_tower(), "a tower is shown")
	assert_eq(i.branch_rows().size(), Upgrades.BRANCHES.size(), "one row per branch")
	i.free(); b.free()
	return true

func test_a_row_shows_the_next_tiers_label_and_cost() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	var row: Button = i.branch_rows()[&"sustained"]
	assert_true(row.text.contains("Quick Loader"), "names the tier being bought")
	assert_true(row.text.contains("30"), "and its price")
	i.free(); b.free()
	return true

func test_a_row_is_disabled_when_the_player_cannot_afford_it() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 0
	i.bind(b)
	var t := _ready_tower_on(b)

	i.show_tower(t)

	assert_true(i.branch_rows()[&"sustained"].disabled, "cannot buy what you cannot afford")
	i.free(); b.free()
	return true

# The reference carries a comment recording this exact bug: its panel was drawn
# once on selection, so a tower selected while broke stayed greyed out after a
# wave paid out and the player had to reselect to see it.
func test_rows_re_enable_when_gold_arrives_without_reselecting() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 0
	i.bind(b)
	var t := _ready_tower_on(b)
	i.show_tower(t)
	assert_true(i.branch_rows()[&"sustained"].disabled, "precondition: greyed out")

	b._gold = 500
	b.gold_changed.emit(500)

	assert_false(i.branch_rows()[&"sustained"].disabled,
		"the row re-enabled on the gold signal alone")
	i.free(); b.free()
	return true

func test_a_row_is_disabled_when_the_cross_path_rule_locks_the_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	t.tiers = {&"sustained": 2, &"burst": 3}

	i.show_tower(t)

	assert_true(i.branch_rows()[&"sustained"].disabled,
		"locked by commitment, not by price")
	i.free(); b.free()
	return true

func test_pressing_a_row_asks_the_board_to_buy_that_branch() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	b._gold = 5000
	i.bind(b)
	var t := _ready_tower_on(b)
	b._selected_tower = t
	i.show_tower(t)

	i.branch_rows()[&"sustained"].pressed.emit()

	assert_eq(t.tiers[&"sustained"], 1, "the board bought the tier")
	i.free(); b.free()
	return true

func test_clear_empties_the_inspector() -> bool:
	var i := _ready_inspector()
	var b := _ready_board()
	i.bind(b)
	i.show_tower(_ready_tower_on(b))

	i.clear()

	assert_false(i.has_tower(), "nothing shown after deselection")
	assert_eq(i.branch_rows().size(), 0, "and no stale rows left behind")
	i.free(); b.free()
	return true

func _ready_tower_on(b: GameBoard) -> Tower:
	b._gold = 5000
	var tile := Vector2i(0, 0)
	for r in b._tiles.size():
		for c in b._tiles[r].size():
			if b._tiles[r][c] == Tiles.BUILDABLE:
				tile = Vector2i(c, r)
				break
	b.select_tower_kind(&"basic")
	b._try_place(tile.x, tile.y)
	return b._towers_root.get_child(0)
```

- [ ] **Step 2: Run and confirm it fails**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: load error — `TowerInspector` is not declared.

- [ ] **Step 3: Build the scene and script**

`ui/tower_inspector.tscn`: a `Control` named `TowerInspector` with `class_name TowerInspector` on `ui/tower_inspector.gd`, containing a `VBoxContainer` named `Rows` (anchors preset 15, separation 8). Rebuild rows in `show_tower` the same way `tower_panel.gd` builds its buttons — `free()` the old children first, never `queue_free()`, for the reason documented there.

`ui/tower_inspector.gd`:

```gdscript
class_name TowerInspector
extends Control

## Selected-tower view: per-branch tier counts, the next tier on each branch
## with its price, and Sell. Decides nothing - legality comes from
## UpgradesSim, affordability and the purchase itself from the board.

const MIN_TAP_SIZE := Vector2(120, 56)

var _board: GameBoard
var _tower: Tower = null
var _rows := {}

@onready var _rows_root: VBoxContainer = $Rows

func bind(board: GameBoard) -> void:
	_board = board
	board.gold_changed.connect(_on_gold_changed)
	board.tower_upgraded.connect(_on_tower_upgraded)
	board.tower_selected.connect(show_tower)
	board.tower_deselected.connect(clear)

func has_tower() -> bool:
	return _tower != null and is_instance_valid(_tower)

func branch_rows() -> Dictionary:
	return _rows

func show_tower(tower: Tower) -> void:
	_tower = tower
	_rebuild()

func clear() -> void:
	_tower = null
	_rebuild()

func _on_gold_changed(_gold: int) -> void:
	_refresh_gating()

func _on_tower_upgraded(_branch: StringName) -> void:
	_rebuild()

func _rebuild() -> void:
	# free(), not queue_free() - same reasoning as ui/tower_panel.gd's bind().
	for child in _rows_root.get_children():
		child.free()
	_rows.clear()
	if not has_tower():
		return

	var header := Label.new()
	header.text = "%s\nsustained %d/%d   burst %d/%d" % [
		Towers.DEFS[_tower.kind]["label"],
		int(_tower.tiers[&"sustained"]), UpgradesSim.MAX_TIER,
		int(_tower.tiers[&"burst"]), UpgradesSim.MAX_TIER,
	]
	_rows_root.add_child(header)

	for branch in Upgrades.BRANCHES:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.pressed.connect(_on_branch_pressed.bind(branch))
		_rows_root.add_child(button)
		_rows[branch] = button

	var sell := Button.new()
	sell.custom_minimum_size = MIN_TAP_SIZE
	sell.text = "Sell  %dg" % EconomySim.sell_refund(_tower.price_paid)
	sell.pressed.connect(_board.sell_selected_tower)
	_rows_root.add_child(sell)

	_refresh_gating()

func _refresh_gating() -> void:
	if not has_tower():
		return
	for branch in _rows:
		var tier := int(_tower.tiers[branch])
		var button: Button = _rows[branch]
		var legal := UpgradesSim.can_upgrade(_tower.tiers, branch)
		if not legal:
			button.text = "%s\nmaxed or locked" % Upgrades.DEFS[_tower.kind][branch]["label"]
			button.disabled = true
			continue
		var next: Dictionary = Upgrades.DEFS[_tower.kind][branch]["tiers"][tier]
		var price := UpgradesSim.upgrade_cost(_tower.kind, branch, tier)
		button.text = "%s\n%s — %dg\n%s" % [
			Upgrades.DEFS[_tower.kind][branch]["label"],
			next["label"], price, next["description"],
		]
		button.disabled = not EconomySim.can_afford(_board.get_gold(), price)

func _on_branch_pressed(branch: StringName) -> void:
	_board.upgrade_selected_tower(branch)
```

Add to `game/game_board.gd`, beside the other signals and emitted from
`_select_tower` / `_deselect_tower`:

```gdscript
signal tower_selected(tower: Tower)
signal tower_deselected()
```

Instance `TowerInspector` under the sidebar in `ui/tower_panel.tscn` below the
`Buttons` container, and bind it where `game.gd` binds the panel. Remove
`SellButton` from `ui/hud.tscn`, drop `_sell` and its connection from
`ui/hud.gd`, and update `test_hud.gd`'s tap-target test to cover Start only.

- [ ] **Step 4: Run the import pass, then the tests**

Run: `godot --headless --import` then `godot --headless --quit --script test/run_tests.gd`
Expected: PASS, exit 0.

- [ ] **Step 5: Mutation-test**

Disconnect `gold_changed` from the inspector and confirm `test_rows_re_enable_when_gold_arrives_without_reselecting` fails. Drop the `can_upgrade` check from `_refresh_gating` and confirm the cross-path row test fails. Restore, confirm green.

- [ ] **Step 6: Commit**

```bash
git add ui/tower_inspector.tscn ui/tower_inspector.gd ui/tower_panel.tscn ui/hud.tscn ui/hud.gd game/game_board.gd game/game.tscn test/test_tower_inspector.gd test/test_hud.gd
git commit -m "Add the tower inspector and move Sell beside the tiers it refunds"
```

---

### Task 11: Visual verification

**Files:** none changed unless a defect is found.

**Why a task of its own:** from Task 16 of the original build onward, rendering cannot be mutation-tested. A sprite at the wrong scale, a frame off by a row, a panel that overflows — none fail a test. Task 15 of the core slice proved it: 5 of 8 atlas rects were wrong and every one was found by looking at the image.

- [ ] **Step 1: Run the game at the design resolution**

```bash
godot --path . --resolution 1244x672 res://game/game.tscn
```

- [ ] **Step 2: Check the inspector**

Place a Basic tower, tap it. Confirm: the inspector fills the lower sidebar, both branch rows show label, tier name, price and description, Sell shows a refund, and nothing overflows the 140px-wide column at the design size.

- [ ] **Step 3: Check the sprite progression**

Buy `sustained` four times, screenshotting after each. Confirm the tower's sprite changes at 1 tier and again at 3 and 5 total tiers, and does not change at 2, 4 or 6 — that is `visual_tier`'s `ceil(total / 2)` on screen.

- [ ] **Step 4: Check the cross-path rule in the UI**

On a fresh tower, buy `burst` three times, then confirm the `sustained` row goes disabled once it would pass tier 2 — and reads as locked rather than as unaffordable.

- [ ] **Step 5: Check at a wide resolution**

```bash
godot --path . --resolution 1760x870 res://game/game.tscn
```

Confirm the inspector still fills the widened sidebar with no bare background band, per the layout model in README §"How the layout responds to window size".

- [ ] **Step 6: Re-export and play in a browser**

```bash
godot --headless --export-release "Web" export/web/index.html
python3 -m http.server 8000 --directory export/web
```

Place a tower, buy a tier, run a wave. This is also the still-outstanding item from the core slice: nobody has played the web build in a browser.

- [ ] **Step 7: Commit any fixes**

If the checks pass, nothing to commit. If they find a defect, fix it with a test where a test is possible, and commit that.

---

## Final: documentation

- [ ] **Step 1: Update `README.md`**

Move "Upgrade branches and the escalation frames beyond `upgradeFrames[0]`" out of "What is deliberately deferred". Add a short section on the upgrade system: two branches, four tiers, the cross-path rule, and that pierce and detection remain dormant until enemy properties land.

- [ ] **Step 2: Update `CONTINUE.md`**

§2's state table gains an upgrades row. §4's remaining work drops upgrades. §5 gains a note that tower stats are resolved through `UpgradesSim.resolve_tower_stats` and that both the harness and the game must keep going through it. §10 records the Tungsten Core divergence as a known temporary.

- [ ] **Step 3: Refresh the test count**

Both files quote a check count. Run the suite and update both to the real number.

- [ ] **Step 4: Commit**

```bash
git add README.md CONTINUE.md
git commit -m "Document the upgrade system"
```
