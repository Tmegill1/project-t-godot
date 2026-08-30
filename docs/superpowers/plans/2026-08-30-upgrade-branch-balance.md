# Upgrade Branch Balance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close a measured 37× gap between the best and worst legal fully-upgraded board by returning area damage to the Mortar, replacing multiplicative damage and fire rate with flat per-tower amounts, and showing what each tier does in the panel without hovering.

**Architecture:** Two new flat effect keys join `pierce_bonus` in `sim/upgrades.gd`, which already documents the rule *"multipliers compose, flat bonuses add"*; `damage_multiplier` and `fire_rate_multiplier` are then deleted outright so no tier can reintroduce compounding. `splash_radius` appears only on Mortar tiers. A pure `Upgrades.effect_summary` renders an effects dictionary to a short line, which a wrapping `Label` shows under each branch button — generated rather than written, so the number on screen cannot drift from the number applied.

**Tech Stack:** Godot 4.7.1, GDScript. No new dependencies, no new assets.

**Spec:** [`docs/superpowers/specs/2026-08-30-upgrade-branch-balance-design.md`](../specs/2026-08-30-upgrade-branch-balance-design.md)

## Global Constraints

- **Godot 4.7.1**, GDScript only. Static typing throughout, matching the codebase.
- **Run the suite with** `godot --headless --quit --script test/run_tests.gd`. Exit code 0 means pass. A green run prints many `SCRIPT ERROR` lines to stderr by design — **judge by the exit code, never by stderr**.
- **Every `test_*` method must be declared `-> bool` and end with `return true`**, including every early return. This is an enforced crash-detection contract, not a style rule.
- **`data/` and `sim/` are pure.** `test/test_sim_purity.gd` bans scene types, clocks, RNG and platform state. `effect_summary` returns a `String` and touches nothing else — that is why it may live in `data/`.
- **A new `class_name` needs an import pass.** After adding one, run `godot --headless --import` or the suite fails with `Parse Error: Identifier "X" not declared`. That pass also writes the script's `.uid`; every other `.gd.uid` here is tracked, so commit it with its script.
- **NO NEW ASSETS.** Standing owner rule in `.ai/handoff.md`: if any visual, audio, animation, sprite, texture or icon turns out to be needed, **stop and return to Codex.** The inspector change uses `Label` nodes and the existing theme.
- **The sidebar is 140px and must not grow.** `CONTINUE.md` §14: the inspector already uses 465px of a 672px viewport, the viewport height is the *shortest* map's pixel height, and `test_tower_panel.gd` pins it. If generated lines do not fit, shorten the phrasing — never widen the column.
- **Do not commit `test/test_balance_tuning.gd.uid`.** It is untracked deliberately.
- **Another agent may be working in this tree.** Before every commit, run `git status` and stage only the files the task names. Never `git add -A`.
- **Pushing to `master` redeploys the live site.** Do not push without the owner asking.

---

## File Structure

| File | Responsibility |
|---|---|
| `sim/upgrades.gd` | **Modify.** Resolve `damage_bonus` and `fire_rate_bonus_ms`; hold `MIN_FIRE_RATE_MS`; lose both multiplier keys. |
| `data/upgrades.gd` | **Modify.** All 32 tiers convert to flat; splash leaves Basic and Long Range; gains `effect_summary`. |
| `data/difficulty.gd` | **Modify.** Hard and Nightmare re-swept against the rebalanced roster. |
| `ui/tower_inspector.gd` | **Modify.** A wrapping `Label` under each branch button. |
| `test/test_upgrades.gd` | **Modify.** Flat resolution, the floor, splash confined to the Mortar. |
| `test/test_upgrade_tables.gd` | **Modify.** All 32 tiers' effects and four tier labels re-pinned; the `effect_summary` anti-drift test. |
| `test/test_balance_tuning.gd` | **Modify.** The branch-parity bound. |
| `test/test_tower_inspector.gd` | **Modify.** The summary label shows the next tier's effects. |
| `test/test_tower_panel.gd` | **Modify.** The fit check covers the new labels. |
| `update.md`, `CONTINUE.md` | **Modify.** Task 9. |

---

## Task 1: Flat damage and fire rate, and a floor under it

**Files:**
- Modify: `sim/upgrades.gd` — `resolve_tower_stats`, plus a new constant
- Test: `test/test_upgrades.gd`

**Interfaces:**
- Produces: `UpgradesSim.MIN_FIRE_RATE_MS: float`; `resolve_tower_stats` honours `damage_bonus: float` and `fire_rate_bonus_ms: float` in a tier's `effects`.
- Both multiplier keys still resolve after this task. Task 4 deletes them, once no tier uses them.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_upgrades.gd`:

```gdscript
# --------------------------------------------------------------------------
# Flat damage and fire rate
# --------------------------------------------------------------------------

# Flat bonuses ADD rather than compose. That is the whole point of the change:
# two tiers of +6 is +12, where two tiers of x1.4 was +96%, and the deeper the
# branch went the worse the shape got.
func test_resolve_adds_flat_damage_bonuses() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	var base: float = stats["damage"]
	var bumped := UpgradesSim._apply_effect_for_test(stats.duplicate(),
		{&"damage_bonus": 6.0})
	bumped = UpgradesSim._apply_effect_for_test(bumped, {&"damage_bonus": 6.0})
	assert_almost_eq(bumped["damage"], base + 12.0, 0.0001,
		"two flat bonuses add rather than compose")
	return true

# Lower is faster, so a fire-rate bonus is SUBTRACTED from the interval.
func test_resolve_subtracts_flat_fire_rate_bonuses() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"basic", UpgradesSim.empty_tiers())
	var base: float = stats["fire_rate"]
	var faster := UpgradesSim._apply_effect_for_test(stats.duplicate(),
		{&"fire_rate_bonus_ms": 200.0})
	assert_almost_eq(faster["fire_rate"], base - 200.0, 0.0001,
		"a fire-rate bonus shortens the interval")
	return true

# Flat bonuses do not compound, but they do not asymptote either: without a
# floor a deep branch walks the interval to zero and then negative, and a
# tower firing every -50ms is an infinite damage source.
func test_a_tower_can_never_out_fire_the_floor() -> bool:
	var stats := UpgradesSim.resolve_tower_stats(&"fast", UpgradesSim.empty_tiers())
	var absurd := UpgradesSim._apply_effect_for_test(stats.duplicate(),
		{&"fire_rate_bonus_ms": 999999.0})
	assert_almost_eq(absurd["fire_rate"], UpgradesSim.MIN_FIRE_RATE_MS, 0.0001,
		"the interval floors rather than going negative")
	assert_true(UpgradesSim.MIN_FIRE_RATE_MS > 0.0, "and the floor is positive")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `_apply_effect_for_test` and `MIN_FIRE_RATE_MS` do not exist.

- [ ] **Step 3: Implement**

In `sim/upgrades.gd`, add the constant below `PIERCE_PER_TIER`:

```gdscript
## Floor under a tower's firing interval, in milliseconds.
##
## Flat bonuses do not compound, which is why they replaced multipliers - but
## they do not asymptote either. Without a floor a deep branch walks the
## interval to zero and then negative, and a tower firing every -50ms is an
## infinite damage source rather than a fast one. 100.0 is well below the
## fastest tower the shipped table can produce, so it guards a mistake rather
## than binding a build.
const MIN_FIRE_RATE_MS := 100.0
```

Extract the per-effect application so a test can drive one effect at a time
without inventing a tier. Add to `sim/upgrades.gd`:

```gdscript
## Applies ONE tier's effects to a stats dictionary, in place, and returns it.
##
## Split out of resolve_tower_stats so a test can exercise a single effect
## without adding a fictitious tier to the shipped table. Named for the test
## rather than hidden behind it: this is the same code the real path runs, not
## a parallel implementation.
static func _apply_effect_for_test(stats: Dictionary, effects: Dictionary) -> Dictionary:
	return _apply_effects(stats, effects)

static func _apply_effects(stats: Dictionary, effects: Dictionary) -> Dictionary:
	if effects.has(&"damage_multiplier"):
		stats["damage"] *= float(effects[&"damage_multiplier"])
	if effects.has(&"damage_bonus"):
		stats["damage"] += float(effects[&"damage_bonus"])
	if effects.has(&"fire_rate_multiplier"):
		stats["fire_rate"] *= float(effects[&"fire_rate_multiplier"])
	if effects.has(&"fire_rate_bonus_ms"):
		stats["fire_rate"] = maxf(MIN_FIRE_RATE_MS,
			stats["fire_rate"] - float(effects[&"fire_rate_bonus_ms"]))
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
	return stats
```

Then replace the body of the tier loop in `resolve_tower_stats` with a call to it:

```gdscript
	for branch in Upgrades.BRANCHES:
		var definition: Dictionary = Upgrades.DEFS[kind][branch]
		for tier in range(int(tiers.get(branch, 0))):
			_apply_effects(stats, definition["tiers"][tier]["effects"])
```

Leave the three `round(...)` calls at the end of `resolve_tower_stats` as they are.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`. No tier uses the flat keys yet, so every existing balance number must be unchanged. If any moved, the extraction changed behaviour and is wrong.

- [ ] **Step 5: Commit**

```bash
git add sim/upgrades.gd test/test_upgrades.gd
git commit -m "Resolve flat damage and fire rate, with a floor"
```

---

## Task 2: Convert every tier to flat damage and fire rate

Values below are **derived, not invented**: each is chosen so the branch's fully-bought endpoint matches what the multiplicative table produces today, measured tier by tier. Task 5 tunes them; this task changes the *shape* (no compounding) while holding the endpoints still, so the two effects can be told apart.

Today's endpoints, for reference — damage and interval with one branch fully bought:

| Tower | Branch | damage 0→4 | interval 0→4 |
|---|---|---|---|
| basic | sustained | 4 → 6 | 1000 → 576 |
| basic | burst | 4 → 24 | 1000 |
| fast | sustained | 2 | 500 → 225 |
| fast | burst | 2 → 4 | 500 |
| mortar | sustained | 5 → 8 | 2000 → 1275 |
| mortar | burst | 5 → 51 | 2000 |
| long | sustained | 15 | 1500 → 1050 |
| long | burst | 15 → 76 | 1500 |

**Files:**
- Modify: `data/upgrades.gd` — the `effects` and `description` of every tier that carries a damage or fire-rate multiplier
- Test: `test/test_upgrade_tables.gd`, `test/test_upgrades.gd`

**Interfaces:**
- Consumes: `damage_bonus`, `fire_rate_bonus_ms` (Task 1).
- Produces: no tier anywhere carries `damage_multiplier` or `fire_rate_multiplier`. Task 4 depends on this.

- [ ] **Step 1: Rewrite the effects and descriptions**

In `data/upgrades.gd`, apply exactly these. Splash, slow, gold, pierce, detection and `range_multiplier` entries are unchanged; only the damage and fire-rate keys move, and the descriptions that quoted percentages.

**basic / sustained** — tiers 3 and 4 keep their splash for now; Task 3 removes it.

```gdscript
{"label": "Quick Loader", "description": "Fires 0.2s faster.",
	"cost": 30, "effects": {&"fire_rate_bonus_ms": 200.0}},
{"label": "Drum Feed", "description": "Fires 0.16s faster.",
	"cost": 60, "effects": {&"fire_rate_bonus_ms": 160.0}},
{"label": "Fragmentation", "description": "Shots splash for 45px, and fire 0.064s faster.",
	"cost": 130, "effects": {&"splash_radius": 45.0, &"fire_rate_bonus_ms": 64.0}},
{"label": "Saturation", "description": "Splash grows to 75px and hits for 2 more.",
	"cost": 260, "effects": {&"splash_radius": 75.0, &"damage_bonus": 2.0}},
```

**basic / burst**

```gdscript
{"label": "Heavy Rounds", "description": "Hits for 2 more.",
	"cost": 30, "effects": {&"damage_bonus": 2.0}},
{"label": "Rifled Barrel", "description": "Hits for 2 more again.",
	"cost": 65, "effects": {&"damage_bonus": 2.0}},
{"label": "Spotter",
	"description": "Reveals and targets phased enemies (no effect yet). Hits for 4 more.",
	"cost": 145, "effects": {&"detection": true, &"damage_bonus": 4.0}},
{"label": "Executioner", "description": "Hits for 12 more and reaches a quarter further.",
	"cost": 290, "effects": {&"damage_bonus": 12.0, &"range_multiplier": 1.25}},
```

**fast / sustained**

```gdscript
{"label": "Hair Trigger", "description": "Fires 0.125s faster.",
	"cost": 40, "effects": {&"fire_rate_bonus_ms": 125.0}},
{"label": "Overclocked", "description": "Fires 0.094s faster.",
	"cost": 80, "effects": {&"fire_rate_bonus_ms": 94.0}},
{"label": "Cryo Rounds", "description": "Hits slow enemies to 70% speed for 1.5s.",
	"cost": 165, "effects": {&"slow_factor": 0.7, &"slow_duration_ms": 1500}},
{"label": "Deep Freeze", "description": "Slows to 45% speed for 2.5s and fires 0.056s faster.",
	"cost": 330, "effects": {&"slow_factor": 0.45, &"slow_duration_ms": 2500, &"fire_rate_bonus_ms": 56.0}},
```

**fast / burst**

```gdscript
{"label": "Machined Rounds", "description": "Hits for 1 more.",
	"cost": 40, "effects": {&"damage_bonus": 1.0}},
{"label": "Scavenger", "description": "Kills pay 1 extra gold.",
	"cost": 85, "effects": {&"bonus_gold_per_kill": 1}},
{"label": "Bounty Board", "description": "Kills pay 60% more gold, and hits land 1 harder.",
	"cost": 175, "effects": {&"gold_multiplier": 1.6, &"damage_bonus": 1.0}},
{"label": "War Profiteer", "description": "Kills pay double gold, plus 2 extra each.",
	"cost": 350, "effects": {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2}},
```

**mortar / sustained**

```gdscript
{"label": "Wide Bore", "description": "Blast radius grows to 70px.",
	"cost": 50, "effects": {&"splash_radius": 70.0}},
{"label": "Quick Crew", "description": "Fires 0.5s faster.",
	"cost": 100, "effects": {&"fire_rate_bonus_ms": 500.0}},
{"label": "Cluster Shell", "description": "Blast radius grows to 95px and fires 0.225s faster.",
	"cost": 200, "effects": {&"splash_radius": 95.0, &"fire_rate_bonus_ms": 225.0}},
{"label": "Firestorm", "description": "Blast radius grows to 130px and hits for 3 more.",
	"cost": 400, "effects": {&"splash_radius": 130.0, &"damage_bonus": 3.0}},
```

**mortar / burst**

```gdscript
{"label": "Packed Charge", "description": "Hits for 3 more.",
	"cost": 50, "effects": {&"damage_bonus": 3.0}},
{"label": "Heavy Shell", "description": "Hits for 5 more.",
	"cost": 105, "effects": {&"damage_bonus": 5.0}},
{"label": "Siege Charge", "description": "Hits for 13 more and reaches a fifth further.",
	"cost": 210, "effects": {&"damage_bonus": 13.0, &"range_multiplier": 1.2}},
{"label": "Bunker Buster", "description": "Hits for 25 more.",
	"cost": 420, "effects": {&"damage_bonus": 25.0}},
```

**long / sustained** — tiers 3 and 4 keep their splash for now; Task 3 removes it.

```gdscript
{"label": "Long Barrel", "description": "Range up by 20%.",
	"cost": 60, "effects": {&"range_multiplier": 1.2}},
{"label": "Rapid Loader", "description": "Fires 0.45s faster.",
	"cost": 120, "effects": {&"fire_rate_bonus_ms": 450.0}},
{"label": "Shellburst", "description": "Shots splash for 55px.",
	"cost": 240, "effects": {&"splash_radius": 55.0}},
{"label": "Carpet Fire", "description": "Splash grows to 90px and range extends by a third.",
	"cost": 450, "effects": {&"splash_radius": 90.0, &"range_multiplier": 1.33}},
```

**long / burst**

```gdscript
{"label": "Dense Slug", "description": "Hits for 6 more.",
	"cost": 60, "effects": {&"damage_bonus": 6.0}},
{"label": "Shaped Charge", "description": "Hits for 8 more.",
	"cost": 130, "effects": {&"damage_bonus": 8.0}},
{"label": "Tungsten Core",
	"description": "Ignores 5 armour (no effect yet). Hits for 9 more.",
	"cost": 260, "effects": {&"pierce_bonus": 5, &"damage_bonus": 9.0}},
{"label": "Siege Cannon",
	"description": "Hits for 38 more and ignores 10 more armour (no effect yet).",
	"cost": 500, "effects": {&"damage_bonus": 38.0, &"pierce_bonus": 10}},
```

- [ ] **Step 2: Re-pin the table test**

In `test/test_upgrade_tables.gd`, replace `EXPECTED_EFFECTS` with the same
dictionaries, in the same key order the table now carries. Costs and tier
labels do not move in this task, so `EXPECTED_COSTS` and
`EXPECTED_TIER_LABELS` stay exactly as they are.

- [ ] **Step 3: Replace the two composition tests**

Two tests in `test/test_upgrades.gd` assert composition for stats that no longer
compose. Replace them:

```gdscript
# basic/sustained tiers 1 and 2 take 200ms and 160ms off the interval. They
# must ADD to 360, not compose and not overwrite. This is the test that would
# fail if multiplicative fire rate crept back in.
func test_resolve_adds_fire_rate_bonuses_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"basic"]["fire_rate"])
	var s := UpgradesSim.resolve_tower_stats(&"basic", _tiers(2, 0))
	assert_almost_eq(s["fire_rate"], base - 360.0, 0.5,
		"two flat cuts add to 360ms off the interval")
	return true

# mortar/burst tiers 1 and 2 (Packed Charge, Heavy Shell) add 3 and 5 damage
# with no other effects: 8 more, not a multiple.
func test_resolve_adds_damage_bonuses_across_tiers() -> bool:
	var base := float(Towers.DEFS[&"mortar"]["damage"])
	var s := UpgradesSim.resolve_tower_stats(&"mortar", _tiers(0, 2))
	assert_almost_eq(s["damage"], base + 8.0, 0.5,
		"two flat bonuses add to +8, not a product")
	return true
```

Delete `test_resolve_composes_multipliers_across_tiers` and
`test_resolve_composes_damage_multipliers_across_tiers`. **Keep**
`test_resolve_composes_range_multipliers_across_tiers` — range still
multiplies, and it is now the only stat that does.

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

Several balance pins may move, because intermediate tiers now sit at different
values even where the endpoints match. Re-measure each one that fails and
re-pin it to what it now reports; note in the commit that it moved because the
tier curve changed shape.

- [ ] **Step 5: Commit**

```bash
git add data/upgrades.gd test/test_upgrade_tables.gd test/test_upgrades.gd
git commit -m "Make every damage and fire-rate tier a flat amount"
```

---

## Task 3: Return area damage to the Mortar

**Files:**
- Modify: `data/upgrades.gd` — `basic/sustained` tiers 3–4, `long/sustained` tiers 3–4, and both branch summaries
- Test: `test/test_upgrades.gd`, `test/test_upgrade_tables.gd`

**Interfaces:**
- Produces: `splash_radius` appears only under `Upgrades.DEFS[&"mortar"]`. Task 5's sweep measures the result.

- [ ] **Step 1: Write the failing test**

Append to `test/test_upgrades.gd`:

```gdscript
# The Mortar's own comment in data/upgrades.gd states the rule: area damage
# belongs to it, and "a tower that could take them would answer everything."
# Basic and Long Range both used to reach for it, and a board that took them
# did answer everything - eleven of the sixteen legal maxed boards shut the
# hardest tier out with zero leaks.
#
# Asserted on RESOLVED stats rather than on the table, so a tier that grants
# splash by some other route is caught too.
func test_only_the_mortar_ever_resolves_splash() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			var s := UpgradesSim.resolve_tower_stats(kind,
				{branch: UpgradesSim.MAX_TIER, _other(branch): UpgradesSim.CROSS_PATH_CAP})
			var splashes: bool = float(s["splash_radius"]) > 0.0
			assert_eq(splashes, kind == &"mortar",
				"%s/%s splash, got %s" % [kind, branch, s["splash_radius"]])
	return true

func _other(branch: StringName) -> StringName:
	return &"burst" if branch == &"sustained" else &"sustained"
```

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — Basic and Long Range still resolve splash.

- [ ] **Step 3: Replace the four tiers**

In `data/upgrades.gd`, **basic / sustained** tiers 3 and 4:

```gdscript
{"label": "Open Bolt", "description": "Fires 0.14s faster and reaches 15% further.",
	"cost": 130, "effects": {&"fire_rate_bonus_ms": 140.0, &"range_multiplier": 1.15}},
{"label": "Sustained Fire", "description": "Fires 0.15s faster and hits for 2 more.",
	"cost": 260, "effects": {&"fire_rate_bonus_ms": 150.0, &"damage_bonus": 2.0}},
```

**long / sustained** tiers 3 and 4:

```gdscript
{"label": "Autoloader", "description": "Fires 0.25s faster.",
	"cost": 240, "effects": {&"fire_rate_bonus_ms": 250.0}},
{"label": "Overwatch", "description": "Fires 0.2s faster and range extends by a third.",
	"cost": 450, "effects": {&"fire_rate_bonus_ms": 200.0, &"range_multiplier": 1.33}},
```

Update both branch summaries, which currently promise splash:

```gdscript
# basic / sustained
"summary": "Faster fire and longer reach. Clears crowds by volume, not by blast.",
# long / sustained
"summary": "Reach and cadence. Covers ground nothing else can.",
```

Add the rule to the file's header comment, beside the Mortar's existing note:

```gdscript
## AREA DAMAGE BELONGS TO THE MORTAR, and to nothing else. Basic and Long Range
## both used to buy splash on their deep sustained tiers; measured 2026-08-30,
## eleven of the sixteen legal fully-upgraded boards then shut the hardest
## difficulty out with zero leaks, because a splash hit carries its WHOLE
## payload - the Magic tower's slow included - to everything it catches. One
## Magic tower plus any splasher slowed the entire wave. test_upgrades.gd's
## test_only_the_mortar_ever_resolves_splash pins this on resolved stats.
```

- [ ] **Step 4: Re-pin the labels and effects**

In `test/test_upgrade_tables.gd`, update `EXPECTED_TIER_LABELS` for the four
renamed tiers:

```gdscript
&"basic": {
	&"sustained": ["Quick Loader", "Drum Feed", "Open Bolt", "Sustained Fire"],
	&"burst": ["Heavy Rounds", "Rifled Barrel", "Spotter", "Executioner"],
},
...
&"long": {
	&"sustained": ["Long Barrel", "Rapid Loader", "Autoloader", "Overwatch"],
	&"burst": ["Dense Slug", "Shaped Charge", "Tungsten Core", "Siege Cannon"],
},
```

and `EXPECTED_EFFECTS` for the same four, to match Step 3 exactly.

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

Expected: **failures in `test_balance_tuning.gd` are likely and are not a
defect** — removing splash from two towers weakens every board that took them,
and the difficulty rows were swept against boards that had it. Fix only
non-balance failures here. Task 5 and Task 6 settle the balance ones; if
`test_no_legal_maxed_board_shuts_out_the_hardest_tier` or
`test_every_maxed_board_still_wins_on_normal` fail, carry them forward and say
so in the commit rather than weakening either assertion.

- [ ] **Step 6: Commit**

```bash
git add data/upgrades.gd test/test_upgrades.gd test/test_upgrade_tables.gd
git commit -m "Give area damage back to the Mortar"
```

---

## Task 4: Delete the multiplier keys

A key that still resolves is a key someone adds back.

**Files:**
- Modify: `sim/upgrades.gd` — `_apply_effects`
- Test: `test/test_upgrade_tables.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/test_upgrade_tables.gd`:

```gdscript
# Damage and fire rate are flat now, and the multiplier keys are gone from the
# resolver. A tier carrying one would be silently ignored, which is worse than
# a crash - so the table is checked rather than trusted.
func test_no_tier_carries_a_dead_multiplier_key() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				var effects: Dictionary = tier["effects"]
				assert_false(effects.has(&"damage_multiplier"),
					"%s/%s %s has no damage_multiplier" % [kind, branch, tier["label"]])
				assert_false(effects.has(&"fire_rate_multiplier"),
					"%s/%s %s has no fire_rate_multiplier" % [kind, branch, tier["label"]])
	return true
```

- [ ] **Step 2: Run to verify it passes already**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

This one passes immediately — Task 2 removed the last use. That is expected and
the test still earns its place: it is what stops the key coming back. Confirm it
runs and records assertions rather than being skipped.

- [ ] **Step 3: Delete the resolver branches**

In `sim/upgrades.gd`'s `_apply_effects`, delete these four lines:

```gdscript
	if effects.has(&"damage_multiplier"):
		stats["damage"] *= float(effects[&"damage_multiplier"])
	if effects.has(&"fire_rate_multiplier"):
		stats["fire_rate"] *= float(effects[&"fire_rate_multiplier"])
```

Update the function's doc comment on `resolve_tower_stats`:

```gdscript
## A tower's live combat stats after upgrades.
##
## Damage and fire rate are FLAT: bonuses add, and the interval floors at
## MIN_FIRE_RATE_MS. They used to be multipliers, and compounding is what made
## the deep tiers explode - two tiers of x1.4 is +96%, not +80%, and it got
## worse the deeper a branch went. Range is the one stat that still multiplies,
## because a percentage of reach is what reach means.
##
## Radii, slows and gold take the strongest value rather than stacking -
## otherwise tier 4's big splash would be added to tier 2's small one and the
## numbers would drift from what the tier text says.
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: the same result as the end of Task 3 — deleting a branch no tier
reaches must change nothing.

- [ ] **Step 5: Commit**

```bash
git add sim/upgrades.gd test/test_upgrade_tables.gd
git commit -m "Delete the damage and fire-rate multipliers"
```

---

## Task 5: Close the branch spread, and pin a bound

**Files:**
- Modify: `data/upgrades.gd` — flat values only, tuned
- Test: `test/test_balance_tuning.gd`

**Interfaces:**
- Consumes: `_every_legal_maxed_board()`, `_full_path()` (already in `test_balance_tuning.gd`).
- Produces: `test_balance_tuning.gd`'s `MAX_BRANCH_SPREAD` constant.

- [ ] **Step 1: Write the sweep probe**

Create `probe_branch_spread.gd` in the project root — **throwaway, deleted in
Step 4**:

```gdscript
extends SceneTree

## Throwaway: the spread between the best and worst legal fully-upgraded board.

const SUSTAINED := {&"sustained": 4, &"burst": 2}
const BURST := {&"sustained": 2, &"burst": 4}
const SPOTS := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
	[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]

func _board(splits: Array) -> Array:
	var towers: Array = []
	var i := 0
	for k in Towers.KINDS.size():
		for n in 3:
			towers.append({"kind": Towers.KINDS[k],
				"position": Grid.tile_to_world_center(SPOTS[i][0], SPOTS[i][1]),
				"tiers": splits[k]})
			i += 1
	return towers

func _init() -> void:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	var path := PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))
	var best := 1 << 30
	var worst := 0
	for mask in 16:
		var splits: Array = []
		var name := ""
		for k in Towers.KINDS.size():
			var is_burst := ((mask >> k) & 1) == 1
			splits.append(BURST if is_burst else SUSTAINED)
			name += "B" if is_burst else "S"
		var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": _board(splits),
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		var lost := int(r["lives_lost"])
		best = mini(best, lost)
		worst = maxi(worst, lost)
		print("PROBE %s leaks %3d lives %3d" % [name, r["leaks"], lost])
	print("PROBE SPREAD best %d worst %d ratio %.2f"
		% [best, worst, 0.0 if best == 0 else float(worst) / float(best)])
	quit(0)
```

- [ ] **Step 2: Sweep and tune**

Run: `godot --headless --quit --script probe_branch_spread.gd 2>/dev/null | grep PROBE`

Read the ratio. Then adjust **only the flat `damage_bonus` and
`fire_rate_bonus_ms` values** in `data/upgrades.gd` and re-run, until:

- every board leaks on Nightmare's last wave (`leaks > 0` for all sixteen), and
- the ratio is **3.0 or below**.

Which direction to move, from the measurement that produced this plan: the
`sustained` branch was the strong one, so if it still leads, take fire-rate
bonuses down or damage bonuses on `burst` up. Move one tower at a time and
re-measure — four towers changed at once cannot be attributed.

**If the ratio will not reach 3.0**, pin what it did reach and say so in the
commit. A worse bound honestly recorded still fails the 37× it replaces. Do not
widen it past the measured value to leave headroom.

- [ ] **Step 3: Pin the bound**

Append to `test/test_balance_tuning.gd`:

```gdscript
## The two upgrade branches must stay close to each other.
##
## Pinned as a RATIO, not a pair of figures, so re-tuning the difficulty rows
## moves both sides together and leaves the claim intact. Measured 2026-08-30
## at 37x before this work: the all-sustained board lost 9 lives across a
## Nightmare run where the all-burst board lost 336, which made the branch
## choice not a choice.
##
## This is the third attempt at an assertion that catches a runaway build, and
## the first that pins a BOUND rather than a board. The six-tower benchmark
## missed it, then the twelve-tower single-split benchmark missed it. A bound
## cannot be satisfied by picking a convenient example.
const MAX_BRANCH_SPREAD := 3.0

func test_no_upgrade_branch_runs_away_from_the_other() -> bool:
	var path := _full_path()
	var best := 1 << 30
	var worst := 0
	var worst_name := ""
	for board in _every_legal_maxed_board():
		var r := Harness.run_wave({"wave": Waves.MAX_WAVES, "towers": board["towers"],
			"path": path, "difficulty": Difficulty.NIGHTMARE})
		var lost := int(r["lives_lost"])
		if lost > worst:
			worst = lost
			worst_name = board["name"]
		best = mini(best, lost)
	assert_true(best > 0, "every legal board loses something on Nightmare's last wave")
	assert_true(float(worst) <= float(best) * MAX_BRANCH_SPREAD,
		"worst board %s lost %d against the best board's %d, over the %.1fx bound"
			% [worst_name, worst, best, MAX_BRANCH_SPREAD])
	return true
```

Replace `3.0` with the measured ratio if Step 2 could not reach it.

- [ ] **Step 4: Delete the probe**

```bash
rm -f probe_branch_spread.gd probe_branch_spread.gd.uid
```

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`

`test_every_maxed_board_still_wins_on_normal` may still fail here — Normal was
never re-checked after the roster moved. If it does, carry it into Task 6; that
task owns the difficulty rows and Normal's row is one of them.

- [ ] **Step 6: Commit**

```bash
git add data/upgrades.gd test/test_balance_tuning.gd
git commit -m "Bring the two upgrade branches within a measured bound"
```

---

## Task 6: Re-sweep Hard and Nightmare

Their rows were measured against boards carrying splash on three towers. That board no longer exists.

**Files:**
- Modify: `data/difficulty.gd` — the `hard` and `nightmare` rows and their comments
- Test: `test/test_balance_tuning.gd` (no new tests; the existing ones are the target)

- [ ] **Step 1: Write the sweep probe**

Create `probe_resweep.gd` in the project root — **throwaway, deleted in Step 4**:

```gdscript
extends SceneTree

## Throwaway: candidate tier rows against the strongest and weakest legal
## fully-upgraded boards.

const SUSTAINED := {&"sustained": 4, &"burst": 2}
const BURST := {&"sustained": 2, &"burst": 4}
const SPOTS := [[3, 3], [5, 3], [7, 3], [9, 3], [11, 3], [13, 3],
	[3, 5], [5, 5], [7, 5], [9, 5], [11, 5], [13, 5]]

func _board(tiers: Dictionary) -> Array:
	var towers: Array = []
	var i := 0
	for kind in Towers.KINDS:
		for n in 3:
			towers.append({"kind": kind,
				"position": Grid.tile_to_world_center(SPOTS[i][0], SPOTS[i][1]),
				"tiers": tiers})
			i += 1
	return towers

func _init() -> void:
	Grid.set_active(Maps.cols(Maps.FIRST), Maps.rows(Maps.FIRST))
	var path := PathFinder.get_path_from_spawn_to_goal(Maps.build_tiles(Maps.FIRST))
	var row: Dictionary = Difficulty.DEFS[Difficulty.NIGHTMARE]
	print("PROBE ROW count %.2f interval %.2f health %.2f speed %.2f" % [
		row["count_multiplier"], row["interval_multiplier"],
		row["health_multiplier"], row["speed_multiplier"]])
	for build in [{"n": "SUSTAINED", "t": SUSTAINED}, {"n": "BURST    ", "t": BURST}]:
		var total := 0
		var first_leak := 0
		for wave in range(1, Waves.MAX_WAVES + 1):
			var r := Harness.run_wave({"wave": wave, "towers": _board(build["t"]),
				"path": path, "difficulty": Difficulty.NIGHTMARE})
			total += int(r["lives_lost"])
			if first_leak == 0 and int(r["leaks"]) > 0:
				first_leak = wave
		print("PROBE   %s run lives %4d | first leak wave %2d" % [build["n"], total, first_leak])
	quit(0)
```

- [ ] **Step 2: Sweep both rows**

`Difficulty.DEFS` is a `const` and cannot be mutated at runtime, so edit the
`nightmare` row in `data/difficulty.gd` between runs and re-run the probe. Sweep
`health_multiplier` and `speed_multiplier`; leave `count_multiplier` and
`interval_multiplier` at 1.0 — the comment in that file records why raising
density feeds a splash build rather than threatening it, and the Mortar still
splashes.

Targets, unchanged from the previous sweep:

- **Nightmare:** every legal maxed board leaks on wave 20, and the strongest
  board loses most but not all of its 12 lives across a run — beatable by the
  best build, and only that one.
- **Hard:** the strongest board loses real lives on the last wave and finishes
  with some of its 15 left.
- **Both:** `test_difficulty.gd`'s monotonicity must hold — every lever moves
  the same direction across Normal → Hard → Nightmare, and Nightmare grants no
  more lives than Hard.

- [ ] **Step 3: Write the rows and rewrite their comments**

Put the chosen values in `data/difficulty.gd` and **replace the measurement
tables in the `hard` and `nightmare` comments** with the new sweep's figures.
The old tables describe a roster that no longer exists; leaving them is worse
than having none, because they read as current.

Keep the lever commentary above `DEFS` — the reason count and interval sit at
1.0 has not changed.

- [ ] **Step 4: Delete the probe**

```bash
rm -f probe_resweep.gd probe_resweep.gd.uid
```

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`, including every assertion carried forward from Tasks 3 and 5.

- [ ] **Step 6: Commit**

```bash
git add data/difficulty.gd
git commit -m "Re-sweep the tiers against the rebalanced roster"
```

---

## Task 7: A stat line generated from the effects

**Files:**
- Modify: `data/upgrades.gd` — new `effect_summary`
- Test: `test/test_upgrade_tables.gd`

**Interfaces:**
- Produces: `Upgrades.effect_summary(effects: Dictionary) -> String`. Task 8 consumes it.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_upgrade_tables.gd`:

```gdscript
# --------------------------------------------------------------------------
# effect_summary
# --------------------------------------------------------------------------

func test_effect_summary_renders_flat_damage_and_fire_rate() -> bool:
	assert_eq(Upgrades.effect_summary({&"damage_bonus": 12.0}), "+12 damage",
		"flat damage reads as a plain addition")
	assert_eq(Upgrades.effect_summary({&"fire_rate_bonus_ms": 400.0}),
		"fires 0.4s faster", "a fire-rate bonus reads in seconds")
	return true

func test_effect_summary_joins_several_effects() -> bool:
	assert_eq(
		Upgrades.effect_summary({&"damage_bonus": 2.0, &"fire_rate_bonus_ms": 150.0}),
		"+2 damage · fires 0.15s faster",
		"effects join in a fixed order regardless of dictionary order")
	return true

func test_effect_summary_is_empty_for_no_effects() -> bool:
	assert_eq(Upgrades.effect_summary({}), "", "nothing to say about nothing")
	return true

# THE anti-drift test. A hand-written description drifts the first time a value
# is tuned, and this slice tuned all thirty-two of them. Generating the line
# means the number on screen is the number the tier applies - but only while
# every key the table uses is one the renderer knows.
func test_every_tier_renders_a_summary() -> bool:
	for kind in Towers.KINDS:
		for branch in Upgrades.BRANCHES:
			for tier in Upgrades.DEFS[kind][branch]["tiers"]:
				var summary := Upgrades.effect_summary(tier["effects"])
				assert_true(summary.length() > 0,
					"%s/%s %s renders" % [kind, branch, tier["label"]])
				assert_false(summary.contains("?"),
					"%s/%s %s has no unrendered key" % [kind, branch, tier["label"]])
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `effect_summary` does not exist.

- [ ] **Step 3: Implement**

Add to `data/upgrades.gd`:

```gdscript
## The order effects are rendered in, so two tiers carrying the same effects
## read the same way whatever order their dictionaries happen to iterate in.
const _SUMMARY_ORDER: Array[StringName] = [
	&"damage_bonus", &"fire_rate_bonus_ms", &"range_multiplier", &"splash_radius",
	&"slow_factor", &"pierce_bonus", &"gold_multiplier", &"bonus_gold_per_kill",
	&"detection",
]

## A tier's effects as a short line for the panel: "+2 damage · fires 0.15s
## faster".
##
## GENERATED rather than written beside the tier, so the number a player reads
## is the number the simulation applies. A hand-written description drifts the
## first time a value is tuned, and the tier's own `description` field - which
## stays, as the tooltip - is where flavour and dormant-effect notes live.
##
## An unknown key renders as "?" rather than vanishing, which is what
## test_every_tier_renders_a_summary detects: adding an effect without teaching
## this function about it fails the suite instead of blanking a row.
static func effect_summary(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in _SUMMARY_ORDER:
		if effects.has(key):
			parts.append(_render_effect(key, effects))
	for key in effects:
		if not _SUMMARY_ORDER.has(key) and key != &"slow_duration_ms":
			parts.append("?")
	return " · ".join(parts)

static func _render_effect(key: StringName, effects: Dictionary) -> String:
	match key:
		&"damage_bonus":
			return "+%d damage" % int(effects[key])
		&"fire_rate_bonus_ms":
			return "fires %ss faster" % _trim(float(effects[key]) / 1000.0)
		&"range_multiplier":
			return "+%d%% range" % int(round((float(effects[key]) - 1.0) * 100.0))
		&"splash_radius":
			return "%dpx blast" % int(effects[key])
		&"slow_factor":
			return "slows to %d%% for %ss" % [
				int(round(float(effects[key]) * 100.0)),
				_trim(float(effects.get(&"slow_duration_ms", 0)) / 1000.0)]
		&"pierce_bonus":
			return "ignores %d armour" % int(effects[key])
		&"gold_multiplier":
			return "+%d%% gold" % int(round((float(effects[key]) - 1.0) * 100.0))
		&"bonus_gold_per_kill":
			return "+%d gold a kill" % int(effects[key])
		&"detection":
			return "reveals phased"
	return "?"

## Seconds without trailing zeroes: 0.40 -> "0.4", 1.00 -> "1".
static func _trim(seconds: float) -> String:
	var text := "%.3f" % seconds
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")
```

- [ ] **Step 4: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 5: Commit**

```bash
git add data/upgrades.gd test/test_upgrade_tables.gd
git commit -m "Generate a tier's stat line from its effects"
```

---

## Task 8: The panel says what the tier does

**Files:**
- Modify: `ui/tower_inspector.gd` — `_build_rows`, `_refresh_gating`
- Test: `test/test_tower_inspector.gd`, `test/test_tower_panel.gd`

**Interfaces:**
- Consumes: `Upgrades.effect_summary` (Task 7).
- Produces: `TowerInspector.summary_text(branch: StringName) -> String`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_tower_inspector.gd`:

```gdscript
# The tier's effect used to be a tooltip, because the sidebar is 140px and a
# Button does not wrap. A Label does, which is what makes this fit at all - and
# this game is touch-first, where hover does not exist.
func test_the_panel_shows_what_the_next_tier_does() -> bool:
	var board := _ready_board()
	var inspector := _ready_inspector(board)
	var tower := _place(board, &"basic")
	inspector.show_tower(tower)
	var expected := Upgrades.effect_summary(
		Upgrades.DEFS[&"basic"][&"sustained"]["tiers"][0]["effects"])
	assert_eq(inspector.summary_text(&"sustained"), expected,
		"the sustained row names the next tier's effect")
	assert_true(expected.length() > 0, "and that is not the empty string")
	inspector.free()
	board.free()
	return true

# A maxed or locked branch has no next tier, so there is nothing to describe.
func test_a_branch_with_no_next_tier_shows_no_summary() -> bool:
	var board := _ready_board()
	var inspector := _ready_inspector(board)
	var tower := _place(board, &"basic")
	tower.tiers = {&"sustained": UpgradesSim.MAX_TIER, &"burst": UpgradesSim.CROSS_PATH_CAP}
	inspector.show_tower(tower)
	assert_eq(inspector.summary_text(&"sustained"), "",
		"a maxed branch describes nothing")
	inspector.free()
	board.free()
	return true
```

Use whatever helpers `test_tower_inspector.gd` already defines for building a
board, an inspector and a placed tower — read the top of that file first and
match them rather than adding new ones.

- [ ] **Step 2: Run to verify it fails**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: non-zero — `summary_text` does not exist.

- [ ] **Step 3: Add the labels**

In `ui/tower_inspector.gd`, add a field beside `_rows`:

```gdscript
var _summaries := {}
```

In `_build_rows`, inside the loop that creates each branch button, add a
wrapping label immediately after adding the button:

```gdscript
	for branch in Upgrades.BRANCHES:
		var button := Button.new()
		button.custom_minimum_size = MIN_TAP_SIZE
		button.clip_text = true
		button.pressed.connect(_on_branch_pressed.bind(branch))
		_rows_root.add_child(button)
		_rows[branch] = button

		# A Label, not a second line on the Button: the sidebar is 140px and a
		# Button does not wrap its text, which is why the tier's effect was a
		# tooltip until now. Labels wrap, so the same 140px holds three short
		# lines instead of clipping one long one.
		var summary := Label.new()
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override(&"font_size", SUMMARY_FONT_SIZE)
		summary.add_theme_color_override(&"font_color", SUMMARY_COLOR)
		_rows_root.add_child(summary)
		_summaries[branch] = summary
```

Add the two constants beside `COUNTER_FONT_SIZE`:

```gdscript
## Smaller and dimmer than the branch counter: this is detail under a control,
## not a heading of its own.
const SUMMARY_FONT_SIZE := 11
const SUMMARY_COLOR := Color(0.72, 0.76, 0.72)
```

In `_refresh_gating`, set the text in both paths. In the `not can_upgrade`
branch, before `continue`:

```gdscript
			_summaries[branch].text = ""
```

and after the `button.tooltip_text` line in the buyable path:

```gdscript
		_summaries[branch].text = Upgrades.effect_summary(next["effects"])
```

Add the accessor:

```gdscript
## What the panel is currently saying the next tier on a branch does. Empty
## when there is no next tier.
func summary_text(branch: StringName) -> String:
	if not _summaries.has(branch):
		return ""
	return (_summaries[branch] as Label).text
```

- [ ] **Step 4: Extend the fit check**

`test/test_tower_panel.gd`'s `_inspector_content_height` already sums every
child of `Rows`, so the new labels are counted with no change to that helper.
What must change is the comment above
`test_the_selected_tower_inspector_fits_inside_the_shortest_map`, which should
now name what is being measured:

```gdscript
# Rows now carries two wrapping summary Labels as well as the buttons. They are
# the reason this test matters more than it did: CONTINUE.md section 14 records
# that the inspector already used 465px of a 672px viewport before they were
# added, and the viewport height is the SHORTEST map's pixel height.
```

If the assertion fails, **shorten the generated phrasing in
`Upgrades._render_effect`** — "+2 dmg" rather than "+2 damage", say — and
re-run. Do not widen the sidebar, and do not raise the viewport.

- [ ] **Step 5: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 6: See it in the running game**

```bash
godot --path . res://game/game.tscn
```

Place a tower, select it, and confirm both branch rows show a stat line under
them and that nothing overflows the sidebar. If a screenshot comes back blank on
this machine (`glx: failed to create dri3 screen`), read the layout back with
the Godot MCP server's `game_get_ui` instead — it reports every control's real
rect, which is what matters here.

- [ ] **Step 7: Commit**

```bash
git add ui/tower_inspector.gd test/test_tower_inspector.gd test/test_tower_panel.gd
git commit -m "Show what an upgrade does without hovering"
```

---

## Task 9: Update the docs

**Files:**
- Modify: `update.md`, `CONTINUE.md`

- [ ] **Step 1: Record the finding and the fix in `update.md`**

The section *"The two upgrade branches are not close, and that is a tower
problem"* currently ends by saying nothing here fixes it. Replace that with what
was done: splash returned to the Mortar, damage and fire rate made flat, the
measured spread before and after, and the bound now pinned in
`test_balance_tuning.gd`. Update the tier table with Task 6's rows.

- [ ] **Step 2: Bring `CONTINUE.md` §15 up to the roster**

Its tier table and its *"before touching the tiers"* note both describe the old
roster. Replace both, and add the two standing rules this work established:
area damage belongs to the Mortar, and damage and fire rate are flat because
compounding is what made the deep tiers explode.

- [ ] **Step 3: Note the panel change in `CONTINUE.md` §14**

§14 explains why the sidebar is tight. Add that the inspector now carries two
wrapping summary labels, what that costs against the budget, and that the fix
for a future overflow is shorter phrasing rather than a wider column.

- [ ] **Step 4: Commit**

```bash
git add update.md CONTINUE.md
git commit -m "Bring the docs up to the rebalanced upgrade branches"
```

---

## Self-review

**Spec coverage.** §3 splash to the Mortar → Task 3. §4.1 the two flat keys →
Task 1; §4.2 per-tower values and the floor → Tasks 1–2; §4.3 no mixed stats →
Task 4 deletes the multipliers outright; §4.4 no invented numbers → Task 2's
values are derived from measured endpoints and Task 5 tunes them by sweep. §5.1
`effect_summary` → Task 7; §5.2 the anti-drift test → Task 7 Step 1; §5.3 the
inspector and the fit budget → Task 8. §6 success criteria → Task 3 (splash
confined), Task 1 (floor), Task 5 (parity bound), Task 7 (every tier renders),
Task 8 (panel fits); the two existing shut-out assertions are carried through
Tasks 3, 5 and 6 without being weakened. §7 sequencing → task order, with Task 3
Step 5 and Task 5 Step 5 naming exactly which failures are expected to persist
and forbidding the assertions being loosened to hide them.

**Placeholders.** None. Task 2's values are listed in full; Task 5's and Task 6's
come from probes whose code is given and whose acceptance targets are stated,
which is the same measure-then-pin shape the difficulty plan used.

**Type consistency.** `damage_bonus` and `fire_rate_bonus_ms` are floats
throughout. `UpgradesSim.MIN_FIRE_RATE_MS` is defined in Task 1 and referenced in
Tasks 1 and 4. `Upgrades.effect_summary(Dictionary) -> String` is defined in
Task 7 and consumed in Tasks 7 and 8. `TowerInspector.summary_text(StringName)
-> String` is defined in Task 8 and used only by its own tests.
`_every_legal_maxed_board()` and `_full_path()` already exist in
`test_balance_tuning.gd` and are consumed unchanged by Task 5.
