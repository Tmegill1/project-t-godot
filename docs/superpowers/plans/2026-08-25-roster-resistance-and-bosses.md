# Roster, Resistance and Bosses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Name every enemy after the art it draws, use all five creatures, order health against speed, give each tower a job through armour and shields, put bosses on waves 10 and 20, and stop a maxed board trivialising the late game.

**Architecture:** Every new rule is a pure static function in `sim/` or a table in `data/`, consumed by both `game/game_board.gd` and `sim/harness.gd`. Armour and shields already exist in `sim/damage.gd` and are simply never populated — most of Phase B is threading data into machinery that is already tested. Resistance visuals and boss scale are render-layer only; no rule reads them.

**Tech Stack:** Godot 4.7.1, GDScript only. No C#, no addons, no external dependencies.

**Spec:** [`docs/superpowers/specs/2026-08-25-roster-resistance-and-bosses-design.md`](../specs/2026-08-25-roster-resistance-and-bosses-design.md)

## Global Constraints

- **GDScript only.** No C#, no addons, no external dependencies.
- **`sim/` and `data/` must never touch the engine** — no `Node`, `get_tree()`, `preload`, `@onready`, `@export`, scene types, `load(`, `ResourceLoader`, `$`/`%` node shorthand, engine RNG, or `Time.` / `Engine.` / `OS.`. `test/test_sim_purity.gd` enforces this.
- **Sim time is milliseconds.** Callers convert with `delta * 1000.0`.
- **One rule, one home.** If the harness and the board both need an answer, it lives in `sim/` and both call it. A rule only the board runs makes every balance number in the suite a fiction.
- **All randomness goes through `sim/rng.gd`.**
- **Every `test_*` method is declared `-> bool` and ends `return true`**, at every early return too. That is the crash sentinel.
- **No `await` in a test method.**
- **`add_child()` does not resolve `@onready` in tests.** Call `node.notification(Node.NOTIFICATION_READY)` explicitly.
- **Run the suite:** `godot --headless --quit --script test/run_tests.gd` (exit 0 = pass). A green run prints ~118 `SCRIPT ERROR` lines to stderr by design — judge by the summary line and exit code. *New* noise is a defect.
- **Adding a new `class_name` requires `godot --headless --import` first**, or you get "Identifier not declared".
- **`godot --headless --import` scribbles a stray blank line into `project.godot` under `[autoload]`.** Strip it before committing. Running the game through the Godot MCP additionally injects an `McpInteractionServer` autoload — strip that too. The `AudioManager` entry is legitimate.
- **Rendering and layout cannot be mutation-tested.** Verify with screenshots through the Godot MCP.

**Baseline at plan time:** suite green at 9,495 checks across 39 files. Every task must leave it green.

---

# Phase A — the roster and the towers

No new mechanics. Naming, data, and art placement only. Ends somewhere fully playable.

## Task 1: Swap the Fast and Mortar sprites, and rename Fast to Magic

**Files:**
- Modify: `data/towers.gd`
- Test: `test/test_data_tables.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Towers.DEFS[&"fast"]["label"] == "Magic"`. The `&"fast"` **key does not change** — it joins the tower table, the upgrade table, the `fire-fast` audio event, the sprite lookup and every test.

- [ ] **Step 1: Write the failing tests**

```gdscript
# Measured on the atlas: the frames Fast pointed at draw a CANNON and the ones
# Mortar pointed at draw CRYSTALS. They were simply on the wrong towers.
func test_the_magic_tower_wears_the_crystal_frames() -> bool:
	assert_eq(Towers.DEFS[&"fast"]["upgrade_frames"], [5, 6, 12, 13],
		"Magic wears what Mortar used to")
	assert_eq(int(Towers.DEFS[&"fast"]["sprite_frame"]), 5, "and its base frame")
	return true

func test_the_mortar_tower_wears_the_cannon_frames() -> bool:
	assert_eq(Towers.DEFS[&"mortar"]["upgrade_frames"], [1, 0, 7, 16],
		"Mortar wears what Fast used to")
	assert_eq(int(Towers.DEFS[&"mortar"]["sprite_frame"]), 1, "and its base frame")
	return true

func test_the_fast_tower_is_labelled_magic() -> bool:
	assert_eq(Towers.DEFS[&"fast"]["label"], "Magic", "renamed for the crystals it now wears")
	return true

# The key is the join to the upgrade table, the audio event and the sprite
# lookup. Renaming the label is one word; renaming the key is five files.
func test_the_fast_key_survives_the_rename() -> bool:
	assert_true(Towers.DEFS.has(&"fast"), "the key is unchanged")
	assert_true(Upgrades.DEFS.has(&"fast"), "so the upgrade table still joins")
	return true

# Nothing about how the tower PLAYS moves. Art and a name only.
func test_swapping_the_art_moved_no_stats() -> bool:
	assert_eq(int(Towers.DEFS[&"fast"]["cost"]), 50, "Magic still costs 50")
	assert_eq(float(Towers.DEFS[&"fast"]["fire_rate"]), 500.0, "and still fires every 500ms")
	assert_eq(float(Towers.DEFS[&"fast"]["base_splash_radius"]), 0.0, "and still does not splash")
	assert_eq(float(Towers.DEFS[&"mortar"]["base_splash_radius"]), 55.0, "Mortar still splashes")
	assert_eq(float(Towers.DEFS[&"mortar"]["fire_rate"]), 2000.0, "and still fires every 2000ms")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: FAIL on the frame and label assertions.

- [ ] **Step 3: Implement**

In `data/towers.gd`, in the `&"fast"` entry set `"label": "Magic"`, `"sprite_frame": 5`, `"upgrade_frames": [5, 6, 12, 13]`. In the `&"mortar"` entry set `"sprite_frame": 1`, `"upgrade_frames": [1, 0, 7, 16]`. Add above the `DEFS` block:

```gdscript
## The `fast` key is a JOIN, not a name. It ties this table to Upgrades.DEFS,
## to the `fire-fast` audio event, to the sprite lookup and to every test that
## names a kind. The tower is called "Magic" in the `label` field, which is the
## only thing a player ever sees. Renaming the key would be a rename across
## five files for no player-visible gain.
##
## Fast and Mortar swapped sprite frames because they were wearing each
## other's art: measured on assets/towers.png, frames 1/0/7/16 draw a cannon
## and 5/6/12/13 draw crystals. No stat, cost, range or rate moved with them.
```

- [ ] **Step 4: Run to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: PASS, exit 0. `test_tower_atlas.gd` may pin frame indices per kind — read it and update any expectation that names Fast's or Mortar's frames.

- [ ] **Step 5: Verify by screenshot**

Launch through the Godot MCP. The build panel's second button must read **Magic** and show a crystal icon; the third must read **Mortar** and show a cannon. Place one of each and confirm the placed sprite matches the button.

- [ ] **Step 6: Commit**

```bash
git diff project.godot   # must be empty
git add data/towers.gd test/test_data_tables.gd test/test_tower_atlas.gd
git commit -m "Put the cannon on Mortar and the crystals on Magic"
```

---

## Task 2: Rename `slime` to `goblin` and `bee` to `bat`

**Files:**
- Rename: `assets/art/enemies/slime/` → `goblin/`, `assets/art/enemies/bee/` → `bat/`
- Rename: `assets/audio/death-slime.ogg` → `death-goblin.ogg`, `death-bee.ogg` → `death-bat.ogg` (and their `.import` files)
- Modify: `data/enemies.gd`, `data/waves.gd`, `audio/audio_manager.gd`, `tools/bake_sheet.gd`
- Test: `test/test_enemy.gd`, `test/test_enemy_sprites.gd`, `test/test_waves.gd`, `test/test_data_tables.gd`, `test/test_game_board.gd`, `test/test_audio_manager.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `Enemies.KINDS == [&"goblin", &"bat", &"ogre"]` (order changes in Task 4). Audio events become `death-goblin` and `death-bat`.

**This is a mechanical rename with one trap:** renaming an asset directory invalidates every `.import` beneath it. Delete them and re-import rather than editing them — `game/enemy.gd` loads by path string, not by UID, so regenerated UIDs are harmless.

- [ ] **Step 1: Move the files**

```bash
cd ~/Projects/project-t-godot
git mv assets/art/enemies/slime assets/art/enemies/goblin
git mv assets/art/enemies/bee   assets/art/enemies/bat
git mv assets/audio/death-slime.ogg assets/audio/death-goblin.ogg
git mv assets/audio/death-slime.ogg.import assets/audio/death-goblin.ogg.import
git mv assets/audio/death-bee.ogg assets/audio/death-bat.ogg
git mv assets/audio/death-bee.ogg.import assets/audio/death-bat.ogg.import
# The .import files under the renamed art dirs point at the OLD paths.
rm -f assets/art/enemies/goblin/*.import assets/art/enemies/bat/*.import
# The audio .import files carry the old source path too.
sed -i 's/death-slime/death-goblin/g' assets/audio/death-goblin.ogg.import
sed -i 's/death-bee/death-bat/g'      assets/audio/death-bat.ogg.import
godot --headless --import >/dev/null 2>&1
git checkout -- project.godot 2>/dev/null || true
```

- [ ] **Step 2: Rename every reference in code**

```bash
cd ~/Projects/project-t-godot
for f in data/enemies.gd data/waves.gd audio/audio_manager.gd tools/bake_sheet.gd \
         test/test_enemy.gd test/test_enemy_sprites.gd test/test_waves.gd \
         test/test_data_tables.gd test/test_game_board.gd test/test_audio_manager.gd \
         test/test_harness.gd test/test_leak.gd; do
  [ -f "$f" ] && sed -i 's/&"slime"/\&"goblin"/g; s/&"bee"/\&"bat"/g; s/"slime"/"goblin"/g; s/"bee"/"bat"/g; s/death-slime/death-goblin/g; s/death-bee/death-bat/g' "$f"
done
grep -rn 'slime\|"bee"\|death-bee' --include="*.gd" . | grep -v "Slime\|Bee" | head
```

That last `grep` must come back empty except for prose in comments. Fix any survivor by hand.

- [ ] **Step 3: Fix the labels and the comments**

`sed` will not have touched the human-facing `"label"` values or the prose. In `data/enemies.gd` set `"label": "Goblin"` and `"label": "Bat"`, and correct the docstring, which currently discusses "the bat" and "slime" interchangeably. Add:

```gdscript
## The kind keys name what the ART DRAWS. They used to say slime and bee while
## the sprites drew a goblin with a knife and a bat - measured by rendering
## them - so every reader had to hold a translation table. The names are the
## art's now: goblin, bat, ogre, shaman, troll.
```

In `tools/bake_sheet.gd`, the `WALK_ROWS` keys must match the new directory names, or a re-bake writes to the old paths.

- [ ] **Step 4: Run the suite**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: PASS, exit 0. `test_enemy_sprites.gd` walks the asset directories by name and is the test most likely to catch a missed rename.

- [ ] **Step 5: Verify by screenshot**

Launch through the MCP, start wave 1 and confirm creatures still render and animate — a broken `.import` shows as a missing texture, which no test can see.

- [ ] **Step 6: Commit**

```bash
git diff project.godot   # must be empty
git add -A assets/art/enemies assets/audio data test tools
git commit -m "Name the enemies after what their art actually draws"
```

---

## Task 3: Add the goblin shaman as a fourth enemy

**Files:**
- Move: `assets/art/enemies/_unused/shaman/` → `assets/art/enemies/shaman/`
- Modify: `data/enemies.gd`, `data/waves.gd`, `audio/audio_manager.gd`, `tools/bake_sheet.gd`
- Add: `assets/audio/death-shaman.ogg` (copy of `death-goblin.ogg` — see below)
- Test: `test/test_data_tables.gd`, `test/test_waves.gd`, `test/test_enemy_sprites.gd`

**Interfaces:**
- Consumes: the rename from Task 2.
- Produces: `Enemies.KINDS` gains `&"shaman"`. `Waves` composition includes shamans from wave 6.

- [ ] **Step 1: Move the art and give it a death sound**

```bash
cd ~/Projects/project-t-godot
git mv assets/art/enemies/_unused/shaman assets/art/enemies/shaman
rm -f assets/art/enemies/shaman/*.import
# A shaman is a goblin; reusing its death sound is honest placeholder audio and
# beats a silent death. Replace when real audio arrives.
cp assets/audio/death-goblin.ogg assets/audio/death-shaman.ogg
godot --headless --import >/dev/null 2>&1
git checkout -- project.godot 2>/dev/null || true
```

Update `tools/bake_sheet.gd`'s `WALK_ROWS` key from `&"_unused/shaman"` to `&"shaman"`, so a re-bake writes where the game now reads.

- [ ] **Step 2: Write the failing tests**

```gdscript
func test_the_shaman_is_in_the_roster() -> bool:
	assert_true(Enemies.DEFS.has(&"shaman"), "the shaman has a definition")
	assert_true(Enemies.KINDS.has(&"shaman"), "and is in KINDS")
	return true

func test_every_kind_has_art_on_disk() -> bool:
	for kind in Enemies.KINDS:
		var path := "res://assets/art/enemies/%s/walk_0.png" % kind
		assert_true(FileAccess.file_exists(path), "%s has a walk frame" % kind)
	return true

func test_every_kind_has_a_death_sound() -> bool:
	for kind in Enemies.KINDS:
		assert_true(AudioManager.SOUNDS.has(StringName("death-%s" % kind)),
			"%s has a death sound registered" % kind)
	return true

func test_shamans_appear_in_the_waves() -> bool:
	var found := false
	for entry in Waves.get_composition(10):
		if entry["kind"] == &"shaman":
			found = true
	assert_true(found, "wave 10 fields shamans")
	assert_eq(_count_of(&"shaman", 5), 0, "but none before wave 6")
	return true

func _count_of(kind: StringName, wave: int) -> int:
	for entry in Waves.get_composition(wave):
		if entry["kind"] == kind:
			return int(entry["count"])
	return 0
```

- [ ] **Step 3: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: FAIL — no shaman definition.

- [ ] **Step 4: Implement**

Add to `Enemies.DEFS` (values are set properly in Task 4; this task only makes it exist):

```gdscript
	&"shaman": {
		"label": "Goblin Shaman", "base_speed": 80.0, "base_health": 7, "reward": 15,
		"life_loss": 3, "walk_frames": 8, "death_frames": 4, "sprite_px": 44.0,
		"stride_px": 36.0, "flip_horizontally": false,
	},
```

Add `&"shaman"` to `KINDS`. Add `&"death-shaman"` to `AudioManager.SOUNDS` — that array is what the manager preloads, so a file on disk that is not listed there is never loaded and `play()` silently no-ops.

In `data/waves.gd`, introduce shamans at wave 6 and put them in the endless bundle. The shaman is a support unit, so it arrives in small numbers:

```gdscript
	6: [{"kind": &"shaman", "count": 1}],
```

and raise `LAST_AUTHORED_WAVE` to 6, adding `{"kind": &"shaman", "count": 1}` to `_ENDLESS_BUNDLE`.

**Read `test_waves.gd` before changing `LAST_AUTHORED_WAVE`.** Composition totals, the modifier boundary and the ogre spawn delay are all pinned against it, and several tests assert exact counts per wave. Every one of those expectations moves; update them deliberately rather than deleting them.

- [ ] **Step 5: Run to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: PASS, exit 0.

- [ ] **Step 6: Verify by screenshot**

Play to wave 6 through the MCP (or force it with `board.set_wave_for_test(5)` then start) and confirm a shaman spawns, walks and dies with animation.

- [ ] **Step 7: Commit**

```bash
git add -A assets data audio tools test
git commit -m "Bring the goblin shaman off the bench"
```

---

## Task 4: Order health against speed across the roster

**Files:**
- Modify: `data/enemies.gd`
- Test: `test/test_data_tables.gd`

**Interfaces:**
- Consumes: Tasks 2 and 3.
- Produces: final base health and speed values.

- [ ] **Step 1: Write the failing tests**

These pin the *relationship* the owner asked for, not just the numbers, so a future tweak cannot quietly invert it:

```gdscript
# The owner's rule: health descends ogre > shaman > goblin > bat, and speed is
# its exact inverse. Asserted as an ordering rather than as four numbers so a
# rebalance has to keep the shape.
func test_health_descends_ogre_shaman_goblin_bat() -> bool:
	var h := func(k): return int(Enemies.DEFS[k]["base_health"])
	assert_true(h.call(&"ogre") > h.call(&"shaman"), "ogre out-tanks the shaman")
	assert_true(h.call(&"shaman") > h.call(&"goblin"), "shaman out-tanks the goblin")
	assert_true(h.call(&"goblin") > h.call(&"bat"), "goblin out-tanks the bat")
	return true

func test_speed_is_the_exact_inverse_of_health() -> bool:
	var by_health := [&"ogre", &"shaman", &"goblin", &"bat"]
	for i in range(by_health.size() - 1):
		var tougher: StringName = by_health[i]
		var frailer: StringName = by_health[i + 1]
		assert_true(
			float(Enemies.DEFS[tougher]["base_speed"]) < float(Enemies.DEFS[frailer]["base_speed"]),
			"%s is slower than %s" % [tougher, frailer])
	return true

func test_the_roster_values() -> bool:
	assert_eq(int(Enemies.DEFS[&"bat"]["base_health"]), 3, "bat health")
	assert_eq(int(Enemies.DEFS[&"goblin"]["base_health"]), 5, "goblin health")
	assert_eq(int(Enemies.DEFS[&"shaman"]["base_health"]), 7, "shaman health")
	assert_eq(int(Enemies.DEFS[&"ogre"]["base_health"]), 10, "ogre health")
	assert_eq(float(Enemies.DEFS[&"bat"]["base_speed"]), 150.0, "bat speed")
	assert_eq(float(Enemies.DEFS[&"goblin"]["base_speed"]), 100.0, "goblin speed")
	assert_eq(float(Enemies.DEFS[&"shaman"]["base_speed"]), 80.0, "shaman speed")
	assert_eq(float(Enemies.DEFS[&"ogre"]["base_speed"]), 55.0, "ogre speed")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — the ogre is 8 health / 60 speed today.

- [ ] **Step 3: Implement**

Set ogre to `"base_health": 10, "base_speed": 55.0`. Leave goblin (5/100) and bat (3/150) as they are; set shaman to 7/80 as Task 3 already did. Add:

```gdscript
## Health descends ogre > shaman > goblin > bat and speed is its exact
## inverse, so every creature trades one for the other and no kind is
## strictly better than another. test_data_tables.gd pins the ORDERING as
## well as the values, so a rebalance has to keep the shape.
```

- [ ] **Step 4: Run and re-pin the balance tests**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -30`

Raising ogre health and lowering ogre speed moves every exact-value harness assertion involving ogres — `test_splash_radius_boundary_at_wave_ten`, `test_later_waves_are_harder_for_the_same_board`, and the leak counts. **Re-derive each from a probe run and update it with the new number; do not delete the assertion.** These pins exist because a `>` comparison passes for several genuinely wrong implementations.

- [ ] **Step 5: Commit**

```bash
git add data/enemies.gd test/
git commit -m "Trade health against speed across the whole roster"
```

---

# Phase B — resistance, the aura, and bosses

## Task 5: Give enemies armour and shields

**Files:**
- Modify: `data/enemies.gd` (per-kind resistance), `game/enemy.gd` (`setup`), `sim/harness.gd` (spawn block)
- Test: `test/test_enemy.gd`, `test/test_harness.gd`, `test/test_data_tables.gd`

**Interfaces:**
- Consumes: the roster from Phase A.
- Produces: `Enemies.DEFS[kind]["armor"]` and `["shield"]`; `Enemies.resistance_for(kind, wave) -> Dictionary` returning `{"armor": int, "shield": int}`. `Enemy.sim` and the harness's enemy dictionaries both carry `armor` and `shield` keys.

**`sim/damage.gd` already reads `target["armor"]` and `target["shield"]` and is covered by 68 assertions. Nothing in it changes. This task only populates what it reads.**

- [ ] **Step 1: Write the failing tests**

```gdscript
# Split by COUNTER, not sprinkled: armour folds to few large hits, shields to
# many cheap ones. The goblin carries neither on purpose - it is the control
# every other enemy is read against.
func test_resistance_is_split_by_counter() -> bool:
	assert_true(int(Enemies.DEFS[&"ogre"]["armor"]) > 0, "ogres are armoured")
	assert_eq(int(Enemies.DEFS[&"ogre"]["shield"]), 0, "and unshielded")
	assert_true(int(Enemies.DEFS[&"bat"]["shield"]) > 0, "bats are shielded")
	assert_eq(int(Enemies.DEFS[&"bat"]["armor"]), 0, "and unarmoured")
	assert_true(int(Enemies.DEFS[&"shaman"]["shield"]) > 0, "shamans are shielded")
	assert_eq(int(Enemies.DEFS[&"goblin"]["armor"]), 0, "the goblin is the control")
	assert_eq(int(Enemies.DEFS[&"goblin"]["shield"]), 0, "in both dimensions")
	return true

# Resistance arrives partway through the run, so the early game stays legible.
func test_no_resistance_before_the_onset_wave() -> bool:
	for w in range(1, Enemies.RESISTANCE_ONSET_WAVE):
		var r := Enemies.resistance_for(&"ogre", w)
		assert_eq(int(r["armor"]), 0, "wave %d ogre is unarmoured" % w)
	return true

func test_armour_grows_with_the_wave() -> bool:
	var early := int(Enemies.resistance_for(&"ogre", Enemies.RESISTANCE_ONSET_WAVE)["armor"])
	var late := int(Enemies.resistance_for(&"ogre", 20)["armor"])
	assert_true(late > early, "a wave 20 ogre is harder than a wave 8 one")
	return true

# Shields step rather than scale: half a charge means nothing.
func test_shield_charges_are_whole_numbers_that_step() -> bool:
	var seen := {}
	for w in range(1, 21):
		seen[int(Enemies.resistance_for(&"bat", w)["shield"])] = true
	assert_true(seen.size() >= 2, "the count changes across the run")
	assert_true(seen.size() <= 4, "but steps, rather than climbing every wave")
	return true

func test_an_enemy_carries_its_resistance_into_its_sim_state() -> bool:
	var e := _ready_enemy(&"ogre", 20)
	assert_true(int(e.sim["armor"]) > 0, "the ogre spawned armoured at wave 20")
	assert_eq(int(e.sim["shield"]), 0, "and unshielded")
	e.free()
	return true

func test_a_shielded_enemy_survives_a_hit_that_would_kill_it() -> bool:
	var e := _ready_enemy(&"bat", 20)
	var before: float = e.sim["health"]
	e.take_damage({"damage": 9999.0})
	assert_eq(e.sim["health"], before, "the shield ate the whole hit")
	assert_true(e.sim["alive"], "so it is still alive")
	e.free()
	return true
```

Add `_ready_enemy(kind, wave)` beside the file's existing helpers, following its idiom (instantiate, `notification(NOTIFICATION_READY)`, `setup(kind, path, wave)`).

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — no `armor`/`shield` keys, no `resistance_for`, no `RESISTANCE_ONSET_WAVE`.

- [ ] **Step 3: Implement the table**

In `data/enemies.gd`, add `"armor": 0, "shield": 0` to goblin; `"armor": 0, "shield": 1` to bat and shaman; `"armor": 2, "shield": 0` to ogre. Then:

```gdscript
## The wave from which resistance appears at all.
##
## Not wave 1: armour on the first goblin a new player meets teaches nothing
## except that their tower is broken. The early game is where the base rules
## are learned, so resistance starts once they are.
const RESISTANCE_ONSET_WAVE := 8

## Armour added per wave past the onset, on kinds that carry armour at all.
const ARMOR_PER_WAVE := 0.6

## How many waves apart each additional shield charge lands. Shields step
## rather than scale because half a charge absorbs nothing - the whole point
## of a shield is that it eats one hit regardless of size.
const WAVES_PER_SHIELD_CHARGE := 6

## Armour and shields for a spawn of this kind at this wave.
##
## A kind with 0 in the table gets 0 forever: resistance SCALES what a kind
## has, it never grants what it lacks. That is what keeps the goblin a control
## and keeps armour and shields answering different towers.
static func resistance_for(kind: StringName, wave: int) -> Dictionary:
	var def: Dictionary = DEFS[kind]
	var base_armor := int(def.get("armor", 0))
	var base_shield := int(def.get("shield", 0))
	var past: int = maxi(0, wave - RESISTANCE_ONSET_WAVE)
	return {
		"armor": 0 if base_armor <= 0 else base_armor + int(floor(float(past) * ARMOR_PER_WAVE)),
		"shield": 0 if base_shield <= 0 else base_shield + int(past / WAVES_PER_SHIELD_CHARGE),
	}
```

- [ ] **Step 4: Thread it into both callers**

In `game/enemy.gd`'s `setup`, add to the `sim` dictionary — **before** the first `@onready` access, per this file's existing rule about rules state landing first:

```gdscript
		"armor": int(Enemies.resistance_for(kind, wave)["armor"]),
		"shield": int(Enemies.resistance_for(kind, wave)["shield"]),
```

`Enemy.take_damage` already calls `Damage.resolve(source, sim)`, which reads both. It must also write the shield back, or a shield absorbs every hit forever:

```gdscript
	sim["shield"] = int(result["remaining_shield"])
```

In `sim/harness.gd`'s spawn block, add the same two keys to the enemy dictionary, and write `remaining_shield` back where it writes `remaining_health`.

- [ ] **Step 5: Run to verify they pass**

Expected: PASS, exit 0.

- [ ] **Step 6: Mutation-test**

At minimum: make `resistance_for` grant armour to a kind with 0 in the table (the goblin test must fail); drop the `remaining_shield` write-back in `Enemy.take_damage` (the shield test must fail — if it does not, the test is checking one hit where it needs two); remove the onset guard. Report survivors honestly.

- [ ] **Step 7: Commit**

```bash
git add data/enemies.gd game/enemy.gd sim/harness.gd test/
git commit -m "Give ogres armour and bats shields, and scale both by wave"
```

---

## Task 5b: Damage types, with soft edges

**Files:**
- Modify: `data/towers.gd` (a `damage_type` per tower), `sim/damage.gd`, `game/tower.gd` (put it in the fired `source`), `sim/harness.gd`
- Test: `test/test_damage.gd`, `test/test_data_tables.gd`

**Interfaces:**
- Consumes: armour and shields from Task 5.
- Produces: `Towers.DEFS[kind]["damage_type"]` of `&"physical"` or `&"magic"`; `Damage.ARMOR_VS_MAGIC`, `Damage.MIN_DAMAGE_FRACTION`, `Damage.SHIELD_LEAK_MAGIC`, `Damage.SHIELD_LEAK_PHYSICAL`. `source[&"damage_type"]` is read by `Damage.resolve`, defaulting to `&"physical"` so every existing caller keeps its current behaviour on the armour path.

**This changes tested behaviour on purpose.** A shield currently absorbs the *whole* hit and several of the 68 assertions in `test_damage.gd` pin exactly that. They move. **Update them deliberately — do not delete them**, and keep the ones that pin the parts which do not change (a corpse absorbing nothing, negative damage not healing, a zero-damage source not stripping a charge).

- [ ] **Step 1: Write the failing tests**

```gdscript
# Rock-paper-scissors with SOFT edges. The whole point of the owner's rule is
# that neither damage type is ever reduced to nothing - a tower with a
# speciality is a choice, a tower that reads zero is a dead button.

func test_magic_is_stronger_against_shields_than_physical() -> bool:
	var target := {"health": 100.0, "shield": 1, "armor": 0, "alive": true}
	var magic := Damage.resolve({"damage": 20.0, "damage_type": &"magic"}, target)
	var physical := Damage.resolve({"damage": 20.0, "damage_type": &"physical"}, target)
	assert_true(magic["damage_dealt"] > physical["damage_dealt"],
		"magic leaks more through a shield")
	return true

func test_physical_still_damages_a_shielded_target() -> bool:
	var target := {"health": 100.0, "shield": 1, "armor": 0, "alive": true}
	var r := Damage.resolve({"damage": 20.0, "damage_type": &"physical"}, target)
	assert_true(r["damage_dealt"] > 0.0,
		"reduced, not absorbed outright - the owner's soft-edge rule")
	return true

func test_both_damage_types_still_cost_the_shield_a_charge() -> bool:
	var target := {"health": 100.0, "shield": 2, "armor": 0, "alive": true}
	for kind in [&"magic", &"physical"]:
		var r := Damage.resolve({"damage": 20.0, "damage_type": kind}, target)
		assert_eq(int(r["remaining_shield"]), 1, "%s spent a charge" % kind)
	return true

func test_physical_is_stronger_against_armour_than_magic() -> bool:
	var target := {"health": 100.0, "shield": 0, "armor": 10, "alive": true}
	var physical := Damage.resolve({"damage": 20.0, "damage_type": &"physical"}, target)
	var magic := Damage.resolve({"damage": 20.0, "damage_type": &"magic"}, target)
	assert_true(physical["damage_dealt"] > magic["damage_dealt"],
		"armour bites magic harder")
	return true

# The guarantee that makes the whole design safe.
func test_armour_can_never_reduce_a_hit_to_nothing() -> bool:
	var target := {"health": 100.0, "shield": 0, "armor": 9999, "alive": true}
	for kind in [&"magic", &"physical"]:
		var r := Damage.resolve({"damage": 4.0, "damage_type": kind}, target)
		assert_true(r["damage_dealt"] > 0.0,
			"%s still gets through absurd armour" % kind)
	return true

func test_the_damage_floor_is_a_fraction_of_the_incoming_hit() -> bool:
	# A floor that is flat would make a 1-damage tower and a 100-damage tower
	# equal against a wall. It scales with the hit instead.
	var target := {"health": 1000.0, "shield": 0, "armor": 9999, "alive": true}
	var small := Damage.resolve({"damage": 4.0, "damage_type": &"magic"}, target)
	var large := Damage.resolve({"damage": 80.0, "damage_type": &"magic"}, target)
	assert_true(large["damage_dealt"] > small["damage_dealt"],
		"a bigger hit still gets more through the floor")
	return true

func test_an_absent_damage_type_reads_as_physical() -> bool:
	var target := {"health": 100.0, "shield": 0, "armor": 10, "alive": true}
	var typed := Damage.resolve({"damage": 20.0, "damage_type": &"physical"}, target)
	var untyped := Damage.resolve({"damage": 20.0}, target)
	assert_eq(untyped["damage_dealt"], typed["damage_dealt"],
		"every pre-existing caller keeps its behaviour")
	return true

func test_every_tower_declares_a_damage_type() -> bool:
	for kind in Towers.KINDS:
		var t: StringName = Towers.DEFS[kind]["damage_type"]
		assert_true(t == &"physical" or t == &"magic", "%s declares one" % kind)
	assert_eq(Towers.DEFS[&"fast"]["damage_type"], &"magic", "the Magic tower is magic")
	assert_eq(Towers.DEFS[&"long"]["damage_type"], &"physical", "Long Range is physical")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: FAIL, and **several pre-existing shield assertions fail too** — that is the intended behaviour change, not a mistake. Note which, so Step 4 updates exactly those.

- [ ] **Step 3: Implement**

In `data/towers.gd` add `"damage_type": &"magic"` to `&"fast"` and `"damage_type": &"physical"` to the other three.

In `sim/damage.gd`:

```gdscript
## How much harder armour bites magic than physical. Physical is the armour
## answer; magic is reduced against it but never stopped (see MIN_DAMAGE_FRACTION).
const ARMOR_VS_MAGIC := 1.6

## The floor under every hit, as a FRACTION of the incoming damage.
##
## A fraction, not a flat number: a flat floor would make a 4-damage tower and
## an 80-damage tower equally good against a wall, which inverts the whole
## point of building the big one. This is what guarantees no tower is ever a
## dead button, whatever armour it faces.
const MIN_DAMAGE_FRACTION := 0.15

## How much of a hit leaks past a shield charge. Magic strips shields fastest;
## physical still gets something through rather than being wholly absorbed.
const SHIELD_LEAK_MAGIC := 0.5
const SHIELD_LEAK_PHYSICAL := 0.15
```

Replace the shield branch so it leaks rather than absorbing everything, and the armour branch so it scales by type and respects the floor. Both read
`source.get(&"damage_type", &"physical")`, so every existing caller is unchanged on the armour path.

In `game/tower.gd`'s `wants_to_fire` payload add `"damage_type": get_def()["damage_type"]`, and add the same key to the harness's `source` dictionary. Both must carry it or the harness and the board disagree, which is the one thing this project's whole structure exists to prevent.

- [ ] **Step 4: Update the pre-existing shield assertions**

Read each failure from Step 2. The ones pinning "a shield absorbs the whole hit" now pin "a shield leaks this fraction". The ones pinning corpse handling, negative damage, and zero-damage-does-not-strip-a-charge must still pass untouched — if any of those broke, the implementation is wrong, not the test.

- [ ] **Step 5: Run to verify everything passes**

Expected: PASS, exit 0.

- [ ] **Step 6: Mutation-test**

At minimum: set `MIN_DAMAGE_FRACTION` to 0 (the never-reduced-to-nothing test must fail); swap `SHIELD_LEAK_MAGIC` and `SHIELD_LEAK_PHYSICAL` (the magic-beats-shields test must fail); set `ARMOR_VS_MAGIC` to 1.0 (the physical-beats-armour test must fail); drop the `damage_type` from the tower's payload (a board-level test must fail — if none does, add one). Report survivors.

- [ ] **Step 7: Commit**

```bash
git add data/towers.gd sim/damage.gd game/tower.gd sim/harness.gd test/
git commit -m "Give damage a type, and give every wall a way through"
```

---

## Task 5c: Penetration scales with tower level

**Files:**
- Modify: `sim/upgrades.gd`
- Test: `test/test_upgrades.gd`

**Interfaces:**
- Consumes: Task 5b.
- Produces: `UpgradesSim.PIERCE_PER_TIER`; `resolve_tower_stats(...)["pierce"]` includes a term derived from total tiers bought.

- [ ] **Step 1: Write the failing tests**

```gdscript
# The owner's rule: every tower gets better at getting through as it levels,
# not just the two Long Range tiers that name pierce explicitly.

func test_an_unupgraded_tower_has_no_penetration() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", UpgradesSim.empty_tiers())
	assert_eq(int(s["pierce"]), 0, "level one pierces nothing")
	return true

func test_penetration_grows_with_total_tiers_bought() -> bool:
	var one := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 1, &"burst": 0})
	var many := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(many["pierce"]) > int(one["pierce"]),
		"a maxed tower gets through more than a barely-upgraded one")
	return true

# The point of the rule: the Magic tower has no pierce tier in either branch
# and must still end up able to hurt an armoured target.
func test_a_maxed_magic_tower_carries_penetration_it_never_bought() -> bool:
	var s := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(s["pierce"]) > 0,
		"neither Magic branch mentions pierce, but levelling still grants it")
	return true

# Long Range must stay the specialist rather than being levelled down to
# everyone else: its explicit tiers stack ON TOP of the scaling term.
func test_the_pierce_tiers_stack_on_top_of_the_level_term() -> bool:
	var specialist := UpgradesSim.resolve_tower_stats(&"long", {&"burst": 4, &"sustained": 2})
	var generalist := UpgradesSim.resolve_tower_stats(&"fast", {&"sustained": 4, &"burst": 2})
	assert_true(int(specialist["pierce"]) > int(generalist["pierce"]),
		"same tier count, but Long Range bought pierce as well")
	return true

func test_penetration_counts_both_branches() -> bool:
	var lopsided := UpgradesSim.resolve_tower_stats(&"basic", {&"sustained": 4, &"burst": 0})
	var spread := UpgradesSim.resolve_tower_stats(&"basic", {&"sustained": 2, &"burst": 2})
	assert_eq(int(lopsided["pierce"]), int(spread["pierce"]),
		"four tiers is four tiers, however they were spent")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — pierce is 0 for everything without an explicit `pierce_bonus`.

- [ ] **Step 3: Implement**

In `sim/upgrades.gd`:

```gdscript
## Penetration every tower gains per tier bought, in either branch.
##
## Owner's rule: levelling a tower should make it better at getting THROUGH,
## not only at hitting harder. It is what stops a low-damage tower being walled
## by late-game armour when neither of its branches mentions pierce - the Magic
## tower is the case this exists for.
##
## The explicit pierce_bonus tiers stack on top, so Long Range stays the
## specialist rather than being levelled down to everyone else.
const PIERCE_PER_TIER := 1
```

Add `total_tiers * PIERCE_PER_TIER` to the resolved `pierce`, where `total_tiers` is the sum across both branches. `total_invested` already walks both branches — read it before writing a second walker.

- [ ] **Step 4: Run to verify they pass**

Expected: PASS, exit 0. `test_upgrade_tables.gd`'s `EXPECTED_EFFECTS` pins all thirty-two tiers' effect values — it should be unaffected, since this adds a term at resolution rather than changing any tier. If it fails, that is a real signal: read it before changing it.

- [ ] **Step 5: Mutation-test**

Set `PIERCE_PER_TIER` to 0 (three tests must fail); count only one branch (the both-branches test must fail); apply the term *instead of* the explicit bonus rather than in addition (the specialist test must fail). Report survivors.

- [ ] **Step 6: Commit**

```bash
git add sim/upgrades.gd test/test_upgrades.gd
git commit -m "Let every tower level into penetration"
```

---

## Task 6: The shaman's shield aura

**Files:**
- Create: `sim/aura.gd`
- Modify: `game/game_board.gd`, `sim/harness.gd`
- Test: `test/test_aura.gd`

**Interfaces:**
- Consumes: shields from Task 5.
- Produces: `class_name Aura` with `Aura.RADIUS`, `Aura.COOLDOWN_MS`, `Aura.MAX_GRANTED_CHARGES`, and
  `Aura.grant(shamans: Array, enemies: Array, elapsed_ms: float) -> Array` returning the **ids** of enemies that should gain a charge this tick.

**New `class_name` — run `godot --headless --import` before the suite.**

- [ ] **Step 1: Write the failing tests**

```gdscript
extends TestCase

# The shaman makes itself a priority target: kill the escort and the wave dies
# normally, ignore it and everything takes an extra hit. Pure module, so both
# the live board and the headless harness run the identical rule.

func _shaman(id: int, at: Vector2) -> Dictionary:
	return {"id": id, "position": at, "alive": true, "dying": false, "kind": &"shaman"}

func _mob(id: int, at: Vector2, shield: int = 0) -> Dictionary:
	return {"id": id, "position": at, "alive": true, "dying": false,
		"kind": &"goblin", "shield": shield}

func test_an_enemy_in_range_is_granted_a_charge() -> bool:
	var granted := Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, Vector2(10, 0))], 0.0)
	assert_true(granted.has(2), "the neighbour was shielded")
	return true

func test_an_enemy_out_of_range_is_not() -> bool:
	var far := Vector2(Aura.RADIUS + 1.0, 0.0)
	var granted := Aura.grant([_shaman(1, Vector2.ZERO)], [_mob(2, far)], 0.0)
	assert_false(granted.has(2), "out of range, no charge")
	return true

# The shaman carries its own shield from the table. Letting the aura top it up
# too would make a lone shaman unkillable by any rapid-fire tower.
func test_a_shaman_does_not_shield_itself() -> bool:
	var s := _shaman(1, Vector2.ZERO)
	var granted := Aura.grant([s], [s], 0.0)
	assert_false(granted.has(1), "the aura is for the escort, not the caster")
	return true

func test_an_enemy_at_the_cap_is_not_topped_up() -> bool:
	var granted := Aura.grant([_shaman(1, Vector2.ZERO)],
		[_mob(2, Vector2(10, 0), Aura.MAX_GRANTED_CHARGES)], 0.0)
	assert_false(granted.has(2), "already at the cap")
	return true

func test_a_dead_enemy_is_not_shielded() -> bool:
	var corpse := _mob(2, Vector2(10, 0))
	corpse["alive"] = false
	assert_false(Aura.grant([_shaman(1, Vector2.ZERO)], [corpse], 0.0).has(2),
		"corpses take no buffs")
	return true

func test_a_dying_enemy_is_not_shielded() -> bool:
	var dying := _mob(2, Vector2(10, 0))
	dying["dying"] = true
	assert_false(Aura.grant([_shaman(1, Vector2.ZERO)], [dying], 0.0).has(2),
		"nor do enemies mid-death-animation")
	return true

func test_the_aura_only_fires_on_its_cooldown() -> bool:
	var s := [_shaman(1, Vector2.ZERO)]
	var m := [_mob(2, Vector2(10, 0))]
	assert_true(Aura.grant(s, m, 0.0).has(2), "fires at zero")
	assert_false(Aura.grant(s, m, Aura.COOLDOWN_MS * 0.5).has(2), "not mid-cooldown")
	assert_true(Aura.grant(s, m, Aura.COOLDOWN_MS).has(2), "fires again on the beat")
	return true

func test_no_shamans_means_no_grants() -> bool:
	assert_eq(Aura.grant([], [_mob(2, Vector2.ZERO)], 0.0), [],
		"nothing to cast it")
	return true

func test_the_result_never_repeats_an_id() -> bool:
	# Two shamans covering one enemy must not grant it two charges in a tick.
	var granted := Aura.grant(
		[_shaman(1, Vector2.ZERO), _shaman(3, Vector2(20, 0))],
		[_mob(2, Vector2(10, 0))], 0.0)
	assert_eq(granted.size(), 1, "one enemy, one grant, however many casters")
	return true

func test_grant_does_not_mutate_its_arguments() -> bool:
	var mobs := [_mob(2, Vector2(10, 0))]
	var snapshot := mobs.duplicate(true)
	Aura.grant([_shaman(1, Vector2.ZERO)], mobs, 0.0)
	assert_eq(mobs, snapshot, "pure: it reports, it does not apply")
	return true
```

- [ ] **Step 2: Run to verify they fail**

Run: `godot --headless --import && godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: FAIL — `Aura` does not exist.

- [ ] **Step 3: Implement**

```gdscript
class_name Aura

## The goblin shaman's shield aura: it grants shield charges to the enemies
## around it, which makes it a priority target. Kill the escort and the wave
## dies normally; ignore it and everything takes an extra hit.
##
## Pure, like sim/slow.gd beside it. It REPORTS which enemies should gain a
## charge and never applies anything - the caller owns its own enemy state,
## and a rule that mutated the live board's dictionaries could not also be run
## by the harness. Both callers run this, per the project's standing rule that
## one question gets one answer in sim/.

## How far the aura reaches. Comfortably wider than a creature but far short
## of a tower's range, so a shaman shields its own column rather than the
## whole board.
const RADIUS := 90.0

## How often it fires. Not every tick: a per-tick aura would refill a charge
## the instant a tower stripped it, which is not a buff, it is invulnerability.
const COOLDOWN_MS := 2500.0

## The most charges the aura will stack on one enemy. Without a cap, a slow
## wave walking beside a shaman arrives at the towers unkillable.
const MAX_GRANTED_CHARGES := 2

## Ids of the enemies that should gain a shield charge this tick.
##
## `elapsed_ms` is the caller's own wave clock, so the beat is shared by every
## shaman on the board rather than each tracking its own - which keeps this
## function stateless and therefore reproducible.
static func grant(shamans: Array, enemies: Array, elapsed_ms: float) -> Array:
	var out: Array = []
	if shamans.is_empty():
		return out
	if not _on_the_beat(elapsed_ms):
		return out

	for enemy in enemies:
		if not enemy.get("alive", true) or enemy.get("dying", false):
			continue
		# A shaman carries its own shield from the table. Topping it up here
		# too would make a lone shaman unkillable by any rapid-fire tower,
		# which is the one build that is supposed to answer it.
		if enemy.get("kind", &"") == &"shaman":
			continue
		if int(enemy.get("shield", 0)) >= MAX_GRANTED_CHARGES:
			continue
		for shaman in shamans:
			if shaman.get("id") == enemy.get("id"):
				continue
			var d: float = Vector2(shaman["position"]).distance_to(enemy["position"])
			if d <= RADIUS:
				out.append(enemy["id"])
				# One grant per enemy per beat, however many shamans cover it.
				break
	return out

## Whether this tick lands on the aura's beat.
##
## fposmod against the cooldown rather than a stored timer, so the function
## stays stateless: two runs with the same clock produce the same result,
## which is what the harness's reproducibility claim rests on.
static func _on_the_beat(elapsed_ms: float) -> bool:
	if elapsed_ms < 0.0:
		return false
	return is_zero_approx(fposmod(elapsed_ms, COOLDOWN_MS))
```

**Note on `_on_the_beat`:** exact modulo equality is fragile against a float clock that steps by 16.67ms. If the tests show the beat being missed, change it to track the last-fired beat index — `int(elapsed_ms / COOLDOWN_MS)` — and have the caller pass the previous index. Prefer whichever keeps `grant` stateless.

- [ ] **Step 4: Wire both callers**

In `game/game_board.gd`'s `_physics_process`, after the enemy candidate list is built, gather shamans from the same list, call `Aura.grant(...)` with `_wave_clock`, and add a charge to each returned id's `sim["shield"]`, clamped to `Aura.MAX_GRANTED_CHARGES`.

In `sim/harness.gd`, do the same against its own `enemies` array using its `elapsed` clock, in the same position in the tick order — **before the Fire block**, so a charge granted this tick is available to absorb this tick's shot, identically in both.

- [ ] **Step 5: Run to verify they pass**

Expected: PASS, exit 0, and `test_sim_purity.gd` still green.

- [ ] **Step 6: Prove both callers agree**

Add to `test/test_harness.gd`:

```gdscript
# The aura's whole point is that the harness and the board run it identically.
# A wave with shamans must be measurably harder than the same wave without.
func test_shamans_make_a_wave_harder_in_the_harness() -> bool:
	var towers := [{"kind": &"fast", "position": Grid.tile_to_world_center(5, 3)}]
	var with_shamans := Harness.run_wave({"wave": 12, "towers": towers, "path": _path()})
	assert_true(with_shamans["leaks"] > 0,
		"a wave carrying shielded escorts gets bodies through a single tower")
	return true
```

- [ ] **Step 7: Commit**

```bash
git add sim/aura.gd game/game_board.gd sim/harness.gd test/
git commit -m "Let the shaman shield its escort"
```

---

## Task 7: Bosses on waves 10 and 20

**Files:**
- Create: `data/bosses.gd`
- Move: `assets/art/enemies/_unused/troll/` → `assets/art/enemies/troll/`
- Modify: `data/enemies.gd`, `data/waves.gd`, `game/game_board.gd`, `sim/harness.gd`, `audio/audio_manager.gd`
- Test: `test/test_bosses.gd`, `test/test_waves.gd`

**Interfaces:**
- Consumes: resistance from Task 5.
- Produces: `class_name Bosses` with `Bosses.on_wave(wave: int) -> Dictionary` (empty when there is none) and `Bosses.WAVES`. `Waves.build_schedule` appends a boss entry carrying `"boss": true`.

- [ ] **Step 1: Move the art and add the kind**

```bash
cd ~/Projects/project-t-godot
git mv assets/art/enemies/_unused/troll assets/art/enemies/troll
rmdir assets/art/enemies/_unused 2>/dev/null || true
rm -f assets/art/enemies/troll/*.import
cp assets/audio/death-ogre.ogg assets/audio/death-troll.ogg
godot --headless --import >/dev/null 2>&1
git checkout -- project.godot 2>/dev/null || true
```

Update `tools/bake_sheet.gd`'s `WALK_ROWS` key from `&"_unused/troll"` to `&"troll"`. Add a `&"troll"` entry to `Enemies.DEFS`, and add **both** `&"death-troll"` and `&"boss"` to `AudioManager.SOUNDS`.

**`boss.ogg` is not merely unplayed — it is not in `SOUNDS` at all**, so the manager never loads it and `play(&"boss")` would silently no-op. Same for `insignia.ogg`, which stays unlisted because nothing in this slice earns Insignia. **Do not add troll to `Enemies.KINDS`** — it is boss-only, and `KINDS` is what wave composition iterates.

- [ ] **Step 2: Write the failing tests**

```gdscript
extends TestCase

func test_bosses_land_on_waves_ten_and_twenty() -> bool:
	assert_true(Bosses.on_wave(10).is_empty() == false, "wave 10 has a boss")
	assert_true(Bosses.on_wave(20).is_empty() == false, "wave 20 has a boss")
	assert_true(Bosses.on_wave(9).is_empty(), "wave 9 does not")
	assert_true(Bosses.on_wave(11).is_empty(), "nor does wave 11")
	return true

func test_the_final_boss_is_far_worse_than_the_first() -> bool:
	var first := Bosses.on_wave(10)
	var last := Bosses.on_wave(20)
	assert_true(int(last["health"]) > int(first["health"]) * 2,
		"the wave 20 boss has more than twice the health")
	assert_true(int(last["armor"]) > int(first["armor"]), "and more armour")
	assert_true(float(last["display_scale"]) > float(first["display_scale"]),
		"and draws bigger, so it reads as worse before it arrives")
	return true

func test_a_boss_is_an_ordinary_enemy_with_different_numbers() -> bool:
	# Everything a boss needs must be a field the normal pipeline already
	# reads. Anything requiring a special case in sim/ is out of scope.
	for wave in Bosses.WAVES:
		var b := Bosses.on_wave(wave)
		assert_true(Enemies.DEFS.has(b["kind"]), "%s is a real kind" % b["kind"])
		for key in ["health", "speed", "armor", "reward"]:
			assert_true(b.has(key), "wave %d boss declares %s" % [wave, key])
	return true

func test_the_boss_is_appended_to_its_waves_schedule() -> bool:
	var schedule := Waves.build_schedule(10)
	var bosses := 0
	for entry in schedule:
		if entry.get("boss", false):
			bosses += 1
	assert_eq(bosses, 1, "exactly one boss in wave 10's schedule")
	return true

func test_no_boss_in_an_ordinary_waves_schedule() -> bool:
	for entry in Waves.build_schedule(9):
		assert_false(entry.get("boss", false), "wave 9 schedules no boss")
	return true

# A boss that arrives with the first goblin is a boss nobody sees coming.
func test_the_boss_arrives_after_the_wave_it_headlines() -> bool:
	var schedule := Waves.build_schedule(10)
	var boss_at := 0.0
	var last_ordinary := 0.0
	for entry in schedule:
		if entry.get("boss", false):
			boss_at = float(entry["at_ms"])
		else:
			last_ordinary = maxf(last_ordinary, float(entry["at_ms"]))
	assert_true(boss_at >= last_ordinary, "the boss comes in last")
	return true
```

- [ ] **Step 3: Run to verify they fail**

Run: `godot --headless --import && godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: FAIL — `Bosses` does not exist.

- [ ] **Step 4: Implement**

```gdscript
class_name Bosses

## Which waves carry a boss, and what it is.
##
## A TABLE rather than special cases in Waves, so waves 30 and 40 in endless
## play - and any new sprite the owner drops in later - are data entry. A boss
## is an ORDINARY ENEMY WITH DIFFERENT NUMBERS: it moves with sim/movement.gd,
## is targeted by sim/targeting.gd, takes damage through sim/damage.gd and
## leaks through sim/leak.gd exactly as everything else does. Anything that
## would need a special case in those modules does not belong here.
##
## Both bosses are trolls because the troll is the largest creature the art
## carries and it was otherwise unused. display_scale is what separates them
## visually; it is a RENDER field and no rule reads it.

const WAVES: Array[int] = [10, 20]

const DEFS := {
	10: {
		"kind": &"troll", "label": "Troll Chieftain",
		"health": 220, "speed": 45.0, "armor": 6, "shield": 0,
		"reward": 150, "display_scale": 1.6,
	},
	# The run's final fight. Health well past twice the first boss's, armour
	# heavy enough that only pierce or the largest per-hit damage in the game
	# gets through, and drawn half again as large.
	20: {
		"kind": &"troll", "label": "Troll Warlord",
		"health": 900, "speed": 40.0, "armor": 14, "shield": 0,
		"reward": 500, "display_scale": 2.2,
	},
}

## The boss for a wave, or an empty dictionary when there is none.
## Returns a copy, so a caller cannot edit the table.
static func on_wave(wave: int) -> Dictionary:
	if not DEFS.has(wave):
		return {}
	return (DEFS[wave] as Dictionary).duplicate(true)

static func has_boss(wave: int) -> bool:
	return DEFS.has(wave)
```

In `Waves.build_schedule`, after the existing sort, append the boss:

```gdscript
	# The boss comes in LAST, after every ordinary spawn. A boss arriving
	# beside the first goblin is a boss nobody sees coming, and it also stops
	# the player from ever fighting it with a fresh board.
	if Bosses.has_boss(wave):
		var last_at := 0.0
		for entry in schedule:
			last_at = maxf(last_at, float(entry["at_ms"]))
		schedule.append({
			"kind": Bosses.on_wave(wave)["kind"],
			"at_ms": last_at + BOSS_DELAY_MS,
			"boss": true,
		})
```

with `const BOSS_DELAY_MS := 4000.0` beside the other timing constants.

- [ ] **Step 5: Spawn it as a boss in both callers**

`GameBoard._spawn` and the harness's spawn block both read the schedule entry. When `entry.get("boss", false)`, override health, speed, armour, shield and reward from `Bosses.on_wave(_wave)` instead of the kind's table, and set the render scale from `display_scale`. Play `&"boss"` on spawn in the board — `assets/audio/boss.ogg` has been in the repo since the core slice, unlisted and therefore never loaded (see Step 1).

- [ ] **Step 6: Run to verify they pass**

Expected: PASS, exit 0.

- [ ] **Step 7: Sweep for termination**

Bosses are the slowest thing in the game and the waypoint oscillation was speed-dependent. Re-run the existing sweeps on all three maps and confirm waves 10 and 20 still terminate at the doubled tick size. **Do not raise the tick cap if one fails.**

- [ ] **Step 8: Verify by screenshot**

Force wave 10 through the MCP and confirm the troll spawns, draws markedly larger than an ogre, animates, and takes visible effort to kill.

- [ ] **Step 9: Commit**

```bash
git add -A data sim game audio assets test tools
git commit -m "Put a troll at the end of waves 10 and 20"
```

---

## Task 8: Show resistance on the sprite

**Files:**
- Modify: `game/enemy.gd`
- Test: `test/test_enemy.gd`

**Interfaces:**
- Consumes: resistance from Task 5, `display_scale` from Task 7.
- Produces: `Enemy.resistance_tint() -> Color`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# Display only. Every rule reads Enemies.DEFS and Enemies.resistance_for; this
# is what the player sees, and no test in sim/ may depend on it - the same
# separation Tower.DISPLAY_SCALE keeps from Placement.tower_radius.
func test_an_unresisting_enemy_is_drawn_untinted() -> bool:
	var e := _ready_enemy(&"goblin", 1)
	assert_eq(e.resistance_tint(), Color.WHITE, "the control is drawn plain")
	e.free()
	return true

func test_an_armoured_enemy_reads_colder_than_an_unarmoured_one() -> bool:
	var plain := _ready_enemy(&"ogre", 1)
	var armoured := _ready_enemy(&"ogre", 20)
	assert_true(armoured.resistance_tint().r < plain.resistance_tint().r,
		"armour drains warmth from the sprite")
	plain.free(); armoured.free()
	return true

func test_a_shielded_enemy_reads_bluer() -> bool:
	var e := _ready_enemy(&"bat", 20)
	var t := e.resistance_tint()
	assert_true(t.b > t.r, "a shield casts blue")
	e.free()
	return true

func test_the_tint_never_goes_fully_dark() -> bool:
	# A wave-40 ogre in endless play must still be a readable sprite.
	var e := _ready_enemy(&"ogre", 40)
	assert_true(e.resistance_tint().v > 0.35, "still legible however armoured")
	e.free()
	return true
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `resistance_tint` does not exist.

- [ ] **Step 3: Implement**

```gdscript
## How this enemy's sprite is tinted for the resistance it carries.
##
## Armour drains warmth toward cold steel; a shield casts pale blue. Both are
## clamped so a deep endless wave stays a readable sprite rather than a
## silhouette.
##
## DISPLAY ONLY. sim/damage.gd reads sim["armor"] and sim["shield"]; nothing
## reads this. It exists because the owner will replace it with real art, and
## because a player needs to know a thing is tough BEFORE it reaches the
## towers. modulate rather than a shader deliberately: modulate can only
## multiply, so it cannot truly desaturate, but it is a one-line render change
## with no new files and no .import churn, and this is placeholder signalling.
func resistance_tint() -> Color:
	var armor := float(sim.get("armor", 0))
	var shield := float(sim.get("shield", 0))
	if armor <= 0.0 and shield <= 0.0:
		return Color.WHITE
	# Each point of armour cools the sprite, to a floor that stays legible.
	var warmth := clampf(1.0 - armor * 0.035, 0.45, 1.0)
	var blue := clampf(1.0 - shield * 0.12, 0.6, 1.0)
	return Color(warmth, warmth * 0.97, clampf(warmth + shield * 0.06, 0.0, 1.0) * blue + (1.0 - blue))
```

Apply it in `setup` and after any change to `sim["shield"]`, alongside the existing `apply_sprite_height()` call:

```gdscript
	_sprite.modulate = resistance_tint()
```

Bosses additionally multiply `_frame_scale` by their `display_scale`.

- [ ] **Step 4: Run to verify they pass**

Expected: PASS, exit 0.

- [ ] **Step 5: Verify by screenshot — the suite cannot see this**

Force a late wave through the MCP and capture it. A wave-20 ogre must read as visibly colder than a wave-1 one, a shielded bat must read blue, and the boss must be unmistakable. **Judge whether it reads at gameplay size, not zoomed in** — the enemies draw between 28 and 58 pixels tall. If it does not read, say so and try scale or an outline rather than pushing the tint darker.

- [ ] **Step 6: Commit**

```bash
git add game/enemy.gd test/test_enemy.gd docs/screenshots/
git commit -m "Tint a sprite for the resistance it carries"
```

---

## Task 9: Measure the rebalance and set the numbers

**Files:**
- Modify: `data/waves.gd`, and `data/enemies.gd` / `data/upgrades.gd` only if the sweep says so
- Test: `test/test_harness.gd`

**This task is a measurement, not an implementation.** The numbers in Tasks 4, 5 and 7 are starting proposals. This is where they are checked against the thing they exist to fix.

- [ ] **Step 1: Build the measurement**

Write a throwaway script (in the job's tmp dir, not the repo) that reports, for waves 10, 15 and 20 on map 1:

- a **maxed 16-tower board**: kills, leaks, lives lost
- a **half-built board** (8 towers, tier 2 only): the same
- per-tower **effective DPS against each kind**, after armour and shields

Baseline to beat, measured before this slice: a maxed board cleared wave 20 with **zero leaks** and out-damaged the wave's whole HP pool by 28×.

- [ ] **Step 2: Sweep `HEALTH_PER_WAVE`**

Try `0.10` (today), `0.15`, `0.20`, `0.25`, `0.30`. Report the table.

**Target:** a maxed board clears wave 20 with real losses but survives; a half-built board fails. If no value of `HEALTH_PER_WAVE` produces both, say so and report what it would take — that is the signal to reach for the upgrade-damage ceiling the spec lists as the last lever.

- [ ] **Step 3: Check the risk the spec names**

A maxed Magic tower hits for 4. Ogre armour at wave 20 under Task 5's constants is `2 + floor(12 * 0.6) = 9`, which **zeroes it outright**. Measure Magic's actual damage against every kind at waves 10, 15 and 20 and report whether it is a useful tower, a specialist, or dead.

If dead, the spec's stated fallbacks are a small innate pierce on every tower, or a minimum-damage floor in `Damage.resolve`. **Report the measurement and the recommendation; do not pick one silently.**

- [ ] **Step 4: Apply the chosen values, with the sweep table in the comment**

Follow `Waves.GOLD_PER_WAVE`'s precedent from slice 0 — the constant carries the measurement that produced it, so nobody re-derives it.

- [ ] **Step 5: Re-pin every exact-value harness assertion**

Changing health scaling moves them all. Re-derive each from a probe run; do not delete assertions.

- [ ] **Step 6: Commit**

```bash
git add data/ test/
git commit -m "Set the health curve against what a maxed board can actually do"
```

---

## Task 10: Update the orientation docs

**Files:**
- Modify: `CONTINUE.md`

- [ ] **Step 1: Update**

- §2 state table: the five-creature roster, bosses, the new test count.
- §7 domain facts: enemy kinds are named after their art; armour and shields are split by counter and why; the shaman aura is a shared rule both callers run; a boss is an ordinary enemy with different numbers.
- §9: record that the leak-cost flattening (every leak costs 4 past wave 5) is **still open and is the strongest candidate for the next slice**, and that the gold curve wants re-measuring when powers land.
- Note that `assets/art/enemies/_unused/` is gone — both creatures are in use.

- [ ] **Step 2: Run the full suite**

Run: `godot --headless --quit --script test/run_tests.gd 2>&1 | tail -20`
Expected: exit 0. Record the check and file counts.

- [ ] **Step 3: Commit**

```bash
git add CONTINUE.md
git commit -m "Bring the orientation doc up to the roster and the bosses"
```

---

## Self-review notes

**Spec coverage:** §3 roster → Tasks 2, 3, 7. §3.1 damage types → Task 5b. §3.2 penetration → Task 5c. §4 health/speed → Task 4; rebalance → Task 9. §5 aura → Task 6. §6 bosses → Task 7. §7 visuals → Task 8. §8 towers → Task 1. §9 non-goals → Task 10 records them.

**Ordering constraints:** Task 4 depends on 2 and 3 (all four kinds must exist before their ordering can be asserted). Task 6 depends on 5 (shields must exist before an aura can grant them). Task 7 depends on 5 (bosses carry armour). Tasks 8 and 9 depend on everything before them. Task 1 is independent and can be done first or last.

**Interface consistency:** `armor` (US spelling) is the key everywhere, matching `sim/damage.gd`'s existing `target.get("armor")` — prose says "armour", code says `armor`. `Aura.grant` returns ids, never mutates. `Bosses.on_wave` returns `{}` for no boss, never null.

**The Magic-tower risk is now addressed by design, not left open.** Task 5b's damage floor and Task 5c's level-scaled penetration are both there to stop armour zeroing it. Task 9 step 3 still measures whether they are *enough* — a tower technically dealing 1 damage is not walled, but it is not a choice either.

**Ordering:** 5b depends on 5 (resistance must exist to be typed against). 5c depends on 5b (penetration is only meaningful once armour scales by type). 6 depends on 5. 7 depends on 5. 8 and 9 depend on everything before them.
