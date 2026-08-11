# CONTINUE HERE

**Point an assistant at this file and say "continue this project."** It contains
everything needed to resume with no prior conversation.

Last updated: 2026-08-11 · Branch `feat/core-slice` · `master` merged through Task 14

---

## 1. What this project is

A port of [Tmegill1/project-t](https://github.com/Tmegill1/project-t) — a Phaser 3
tower-defence game — to **Godot 4.7.1 in GDScript**.

This pass builds the **core slice**, not the whole game: one map, four towers, three
enemies, twenty waves, win and lose. Upgrade branches, enemy properties, bosses,
powers, currencies and meta-progression are deliberately deferred so there is
something playable in the middle rather than only at the end.

Two documents hold the reasoning:
- [`docs/superpowers/specs/2026-08-09-godot-port-design.md`](docs/superpowers/specs/2026-08-09-godot-port-design.md) — the design and why
- [`docs/superpowers/plans/2026-08-09-godot-core-slice.md`](docs/superpowers/plans/2026-08-09-godot-core-slice.md) — the 23-task plan, **with full code for every remaining task**

---

## 2. Where things stand

**15 of 23 tasks complete. The game does not run yet** — `godot` reports
"no main scene defined", because `game/` and `ui/` are still empty.

| Layer | State |
|---|---|
| `sim/` — 9 modules | ✅ complete, reviewed |
| `data/` — 8 modules | ✅ complete, reviewed |
| `assets/` — 61 files | ✅ imported, sliced, verified visually |
| `game/` — rendering | ❌ empty |
| `ui/` — interface | ❌ empty |
| Tests | ✅ 2159 checks, exit 0 |

The complete rules layer runs headlessly. `sim/harness.gd` will simulate a real
wave — pathing, targeting, damage, leaks — with no window open.

---

## 3. Quick start

```bash
cd ~/Projects/project-t-godot

# Run the whole suite. Exit 0 = pass, 1 = fail.
godot --headless --quit --script test/run_tests.gd

# ALWAYS run this after adding a new class_name, BEFORE the tests,
# or you get a misleading "Identifier not declared" parse error.
godot --headless --import

# Open in the editor
godot --path .
```

The Godot binary is `~/.local/bin/godot`, a symlink to
`~/Desktop/Godot_v4.7.1-stable_linux.x86_64`. **The Godot MCP hardcodes that
symlink path**, so if it breaks, both the CLI and the MCP break together. It has
broken once already when the binary moved.

---

## 4. What is left, and how each piece is meant to work

**Every remaining task has complete code in the plan document** at the line numbers
below. Read the task's section before implementing it.

### Task 16 — Map renderer (plan line 2476)
`game/map_renderer.gd`, `extends Node2D`. Draws the tile grid as `Sprite2D`
children — **not** a `TileMapLayer`, because the spawn and goal artwork is drawn
3 tiles wide with a pixel offset and the decoration layer is scattered rather than
grid-aligned; a tilemap fights both. Ground first, then spawn/goal at
`TILE_SIZE * 3` offset by `(-TILE_SIZE, -TILE_SIZE - 20)`, then seeded decoration
(~10% of buildable tiles get a spike, up to 7 path-adjacent get fire, 3–5 blocked
tiles become stone and the rest trees), all excluding a 3×3 region around spawn and
goal. Exposes `clear_decoration_at(col, row)` so a decoration vanishes when a tower
is built on its tile.

### Task 17 — Enemy view (plan line 2651)
`game/enemy.gd` + `.tscn`: `Node2D` with an `AnimatedSprite2D` and a `ColorRect`
health bar. Builds a `SpriteFrames` per creature at runtime from the six 288×48
sheets (six 48px frames each) with animations `walk_up/side/down` and the death
trio. Calls `Movement.advance` in `_physics_process`, converting `delta * 1000.0`
to milliseconds. **Skips updating facing when `advanced_waypoint` is true** — that
tick covered no distance, so its reported direction comes from a sub-pixel delta
and would make the sprite jitter. Emits `died(reward, kind)` and `leaked(life_loss)`.

### Task 18 — Tower and projectile views (plan line 2823)
`game/tower.gd`: `Sprite2D` with an `AtlasTexture` region from `assets/towers.png`
on a **96px grid** (5×4 = 20 frames), using each tower's `upgrade_frames[0]`. A
`RangeIndicator` child draws a circle in `_draw()`. An `Area2D` exists **only for
tap-picking, never for combat**. `game/projectile.gd` homes on its target; arcing
shots offset the sprite by `-sin(t * PI) * ARC_HEIGHT` — purely cosmetic, it still
homes and still hits.

### Task 19 — Game board (plan line 3001)
`game/game_board.gd` — the hub that wires sim to views. Owns gold, lives, wave
number, the occupied-tile map and per-kind tower counts. Runs spawns from
`Waves.build_schedule`, ticks towers, resolves projectile hits including splash.
Handles taps: tile bounds → buildable → not occupied → under the map's tower budget
→ under the per-kind limit → affordable, then places. Signals out:
`gold_changed`, `lives_changed`, `wave_changed`, `wave_state_changed`, `game_over`,
`victory`, `tower_placed`, `placement_rejected`.

### Task 20 — HUD and tower panel (plan line 3285)
`ui/hud.gd` (`CanvasLayer`) shows gold/lives/wave with Start and Sell buttons and a
transient message line. `ui/tower_panel.gd` builds one button per tower kind showing
the **current escalated price**, disabled when unaffordable. Touch-first: minimum
44×44 tap targets, nothing depends on hover.

### Task 21 — Scene flow (plan line 3432) ← **first playable**
`ui/main_menu.tscn` → `game/game.tscn` → `ui/game_over.tscn` / `ui/victory.tscn`.
Sets `run/main_scene` in `project.godot`. After this task the game is playable end
to end.

### Task 22 — Audio (plan line 3532)
`audio/audio_manager.gd` as an autoload with a **pool of 12 `AudioStreamPlayer`s** —
a single player would cut off overlapping sounds once eight towers are firing. Wire
the core-slice events only. No explicit unlock call is needed: the main menu's Play
button supplies the user gesture a web build requires.

### Task 23 — Web export and README (plan line 3630)
`Web` preset with `variant/thread_support=false` (threads need COOP/COEP headers
most static hosts do not send). Expect **25–40 MB** — this was raised during design
and the web-first target confirmed anyway; the pre-sliced atlas and OGG audio are
the mitigations already applied.

---

## 5. Rules that bind every task

- **GDScript only.** No C#, no addons, no external dependencies.
- **`sim/` and `data/` must never touch the engine** — no `Node`, `get_tree()`,
  `preload`, `@onready`, `@export`, scene types, `load(`, `ResourceLoader`,
  `$`/`%` node shorthand, or any engine RNG. `test/test_sim_purity.gd` enforces
  this and its own detector is unit-tested so it cannot pass vacuously.
- **Sim time is milliseconds.** Callers convert with `delta * 1000.0`.
- **Every `test_*` method is declared `-> bool` and ends `return true`**, including
  at early returns. This is how the runner detects a test that crashes partway. It
  is self-enforcing — omit it and the test fails loudly.
- **No `await` in a test method.** `Object.call()` returns a `GDScriptFunctionState`
  instead of `true` and the crash sentinel misreads it as an aborted test.
- **Any test reading tile coordinates calls `Grid.set_active()` first** — `Grid`
  holds active dimensions in static state, so forgetting makes the result depend on
  test execution order.
- **Combat uses distance arithmetic, never physics.** `Area2D` is for tap-picking
  only. Godot's physics is frame-coupled and non-deterministic; routing combat
  through it would put rules in the engine and kill the headless harness.
- **All randomness goes through `sim/rng.gd`.**

---

## 6. How the work has been done, and why it kept finding bugs

Each task is implemented by a fresh subagent from a task brief, then independently
reviewed, then fixed until the review is clean. Progress is appended to
`.superpowers/sdd/2026-08-09-godot-core-slice/progress.md` — **that ledger is the
recovery map. Trust it and `git log` over recollection.** Resume at the first task
without a `complete` line.

**Every defect found in 15 tasks came from mutation testing** — deliberately
breaking a value and checking the suite notices — and **none from reading code**.
Dispatch implementers with two standing instructions:

1. Port **every** meaningful test from the reference module, not just the brief's
   subset. When this instruction was added at Task 9, test counts went from ~11 to
   36 and real gaps started surfacing.
2. **Mutation-test your own work**, enumerate every line first, and report survivors
   honestly. Three reports were caught claiming coverage they had not earned.

Self-testing raises the floor but does **not** replace review — an implementer
grading its own homework reported a pass it had not earned, more than once.

**From Task 16 on this changes.** Rendering cannot be mutation-tested. A sprite at
the wrong scale, an atlas off by a row, an enemy facing backwards — none fail a
test. Verification becomes **screenshots and measurement**, via the Godot MCP.
Task 15 proved the point: 5 of the 8 rects inherited from the original game were
wrong, and every one was found by looking at the image, never by a test.

---

## 7. Things already established — do not re-derive

- **`class_name` does not resolve until `godot --headless --import` has run once.**
  A fresh clone otherwise fails with a baffling "Identifier not declared".
- **`load()` does not return null on a parse error** in 4.7.1 — it returns a
  `GDScript` whose `can_instantiate()` is `false`.
- **mulberry32 ports bit-exact to GDScript.** The multiplications overflow int64,
  but two's-complement wrapping preserves the low 32 bits. Verified to 17 decimals;
  golden values are pinned in `test/test_rng.gd`.
- **The generated map is byte-identical to the reference TypeScript's output**,
  scattered blocked tiles included, pinned by a golden-board test.
- **Wave composition accumulates from wave 1** — wave 3 contains waves 1 and 2.
  Looks like a bug, is not, and tests pin the totals.
- **Two movement quirks are deliberate:** arriving at a waypoint consumes the whole
  tick without moving, and there is no clamping so a fast enemy overshoots. Both
  change arrival timing; "fixing" either shifts the pacing of the entire game.
- **`test/case.gd`'s `_values_equal` cannot distinguish `20` from `20.0`**, so no
  data-table test detects a *type* change. Known limitation.

---

## 8. Open decisions for the project owner

1. **The map tiles now look better than the original.** 5 of 8 rects were corrected
   for clipping and bleed. The spec says the original's visual quirks are preserved
   deliberately, so this is a real divergence. Every deviation is documented in a
   header block in `tools/slice_atlas.gd` with reference/used/reason — any rect is
   one edit from exact parity. **Decide whether you want parity or the better art.**
2. **The balance is unplaytested.** The original's own handoff notes say every
   number is a placeholder. "Matches Phaser" will not mean "plays well." Expect to
   tune after Task 21, and use the harness to do it.
3. **Web export will be 25–40 MB** against the Phaser build's 368 KB gzipped.

---

## 9. Known gaps

- **Task 15 never had a formal review pass.** It was verified visually by the
  controller, but the implementer's own self-check proved unreliable there. Worth a
  review.
- Deferred minors are listed throughout the ledger, each tagged
  `minor (deferred)`. Triage them before merging the finished slice.
- `master` is merged through **Task 14**; Task 15 is on `feat/core-slice` only.

---

## 10. Suggested next action

```bash
cd ~/Projects/project-t-godot
git checkout feat/core-slice
godot --headless --quit --script test/run_tests.gd   # expect 2159 checks, exit 0
```

Then implement **Task 16** from plan line 2476. It is the first task that draws
anything — after it you can render the map and look at it, though not yet play.
Verify it with a screenshot through the Godot MCP, not with assertions.
