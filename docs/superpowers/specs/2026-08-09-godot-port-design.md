# Godot port of project-t — core slice

**Date:** 2026-08-09
**Source:** [`Tmegill1/project-t`](https://github.com/Tmegill1/project-t), `td-browser/` at `91f3389`
**Target:** Godot 4.7.1.stable, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

The Phaser game on `main` is ~18k lines of TypeScript across four completed
phases: upgrade branches, composable enemy properties, boss archetypes, three
currencies, tactical powers, meta-progression with a versioned save, and a
headless simulation harness backed by 615 tests.

Porting all of that in one pass is a multi-week project with no playable
milestone in the middle. This spec covers **the core slice only** — the game
as it stood at the end of Phase 0, plus the fourth tower. Later phases layer on
afterwards in the same order they did in Phaser, each with its own spec.

## 2. Goals and non-goals

**Goals**

1. A playable tower defence in Godot: one map, four towers, three enemies,
   twenty waves, win and lose states.
2. Rules preserved faithfully enough that a balance change in the Phaser build
   can be reproduced here by editing the same number.
3. The `sim/` layer stays engine-free and headlessly testable, as it is in the
   original. This is the property the whole Phase 0 effort existed to create,
   and it is the main thing being carried across.
4. Runs in a browser, and is built so a phone port is a matter of input and
   layout rather than rearchitecture.

**Non-goals**

- Rebalancing. Every number here is ported as-is. `HANDOFF.md` is explicit that
  the Phaser build was **never playtested** and that every value is a
  placeholder. This port inherits that, and "matches Phaser" must not be read as
  "plays well."
- Reproducing the original's view-layer defects (§9).
- Authentication, leaderboards, or any backend. Dropped permanently, not
  deferred — see §8.

## 3. Scope

### In

| Area | Detail |
|---|---|
| Map | `demoMap` "The Pass", 23×14 at 48px tiles, seeded generation |
| Pathing | BFS spawn→goal over path/spawn/goal tiles, multi-spawn capable |
| Towers | Basic, Fast, Mortar, Long Range — base stats, cost escalation, per-kind limits, 16-tower map budget |
| Enemies | Slime, Ogre, Bee — directional walk/death animation, health, reward, leak cost |
| Waves | 20 waves, accumulate-from-wave-1 composition, health/speed scaling, spawn timing |
| Economy | Starting gold 100, 20 lives, kill rewards, 50% sell refund |
| Combat | Projectiles (flat and lobbed), splash for Mortar, damage resolution, kill rewards |
| Leaks | Flat cost through wave 5, health-based after, capped at 4 |
| Input | Tap-to-place with affordability + buildable/occupied validation, range preview, tower selling |
| Flow | Main menu → game → victory at wave 20 / defeat at 0 lives |
| Audio | The subset of the 22 sounds the slice's events can fire |

### Out

Upgrade branches · the five enemy properties · boss archetypes · lieutenants ·
tactical powers and command upgrades · insignia and seals · meta shop and
passives · save and progression · maps 2 and 3 · call-wave-early, wave-clear
bonus and interest · auth and leaderboard.

The map registry is built to hold three maps from the start. Adding The Fork and
The Coils later is data entry against a working renderer, not new architecture.

## 4. Approach

Three options were considered:

- **Faithful everywhere** — mirror the TS module-for-module including the view
  layer. Rejected: it means deliberately reproducing known bugs (§9).
- **Clean-room Godot rebuild** — same game, idiomatic throughout. Rejected:
  nothing anchors it, so a port bug is indistinguishable from a deliberate
  change.
- **Faithful sim, native shell — chosen.** `sim/` and `data/` port
  near-verbatim with quirks and unit tests intact. Everything above that line is
  rebuilt natively in Godot.

The quirks worth preserving all live below the sim line: waypoint arrival
consuming a whole tick, no clamping on overshoot, waves accumulating from wave
1. They decide timing and feel, and the ported tests prove they still hold. The
quirks above that line are the landmines `HANDOFF.md` lists.

## 5. Architecture

### The boundary rule

**Nothing in `sim/` or `data/` may reference `Node`, `get_tree()`, `preload`,
`@onready`, or any scene type.** Enforced by `test/test_sim_purity.gd`, a direct
port of `sim/purity.test.ts`: it scans the directories for forbidden symbols and
fails on a hit. Its detector is itself unit-tested against known-positive and
known-negative samples so the guard cannot pass vacuously.

### Layout

```
project.godot            Compatibility renderer, 1104×672, canvas_items/expand
data/
  tiles.gd               TILE_SIZE = 48, TileKind
  seeds.gd               DEFAULT_DEMO_MAP_SEED, DEFAULT_DECORATION_SEED
  demo_map.gd            build_demo_map(rng) → TileKind[][], 23×14
  maps.gd                MAPS registry, per-map budget/gold/next
  towers.gd              TOWER_DEFS × 4
  enemies.gd             ENEMY_DEFS × 3
  waves.gd               MAX_WAVES, composition, scaling, spawn timing
  economy.gd             ECONOMY constants
sim/
  entities.gd            Vec2, Facing, PathPoint, enemy/tower state
  rng.gd                 mulberry32 + fork/shuffle/int
  grid.gd                set_active_grid, tile_to_world_center, world_to_tile
  pathfinder.gd          get_all_spawn_paths — BFS
  movement.gd            advance_along_path, starting_path_index
  targeting.gd           select_target, is_targetable, priorities
  damage.gd              resolve_damage → DamageResult
  leak.gd                resolve_leak_penalty
  economy.gd             currency arithmetic
  harness.gd             headless fixed-timestep wave runner
game/
  game_board.gd/.tscn    board owner, input, placement, wave scheduling
  map_renderer.gd        TileMapLayer setup + seeded decoration
  enemy.gd/.tscn         AnimatedSprite2D + health bar
  tower.gd/.tscn         Sprite2D (atlas region) + range indicator
  projectile.gd/.tscn
ui/
  hud.gd/.tscn           gold, lives, wave — CanvasLayer
  tower_panel.gd/.tscn   touch-first build buttons
  main_menu.tscn  game_over.tscn  victory.tscn
assets/                  from td-browser/public
test/                    gdUnit4 — ported sim tests + purity guard
```

### Two decisions that follow from the boundary

**No physics for combat.** Targeting and hit detection are distance arithmetic
in `sim/targeting.gd`. Godot's physics is frame-coupled and non-deterministic;
routing combat through `Area2D` overlaps would put rules in the engine and make
the harness impossible. `Area2D` is used only for picking a tower with a tap.

**Sim runs in `_physics_process`.** Godot's fixed 60 Hz tick supplies for free
the determinism the TypeScript harness had to hand-roll a scheduler for. Views
read positions after the step.

**Milliseconds, not seconds.** Sim function signatures keep the original's
millisecond convention and callers convert (`delta * 1000.0`). This lets
`fireRate: 1000`, `intervalMs: 500` and every ported test transfer unchanged.

### Data representation

Balance tables are `const` Dictionaries in GDScript, not custom `Resource`s with
`.tres` files. They stay diffable against the TypeScript source and directly
testable, which matters more here than inspector editing — and it avoids a
code-versus-resource split that would drift. Inspector tuning can be added later
as a dev-only overlay if playtesting demands it.

### Events

Godot signals on the emitting node, replacing the original's two independent
`EventEmitter`s. The Phaser build routed a single leak across the scene boundary
three times because `GameScene` and `UIScene` each owned an emitter; one node
tree with signals removes that entirely.

## 6. Rules being ported

Values below are the authority for the implementation. All are current as of
`91f3389`.

**Towers** (`data/towers.ts`)

| | cost | escalation | range | fireRate | damage | splash | projSpeed | arcs | limit |
|---|---|---|---|---|---|---|---|---|---|
| Basic | 20 | 10 | 100 | 1000 | 4 | 0 | 500 | no | 8 |
| Fast | 50 | 15 | 80 | 500 | 2 | 0 | 500 | no | 8 |
| Mortar | 70 | 35 | 120 | 2000 | 5 | 55 | 350 | yes | 5 |
| Long Range | 100 | 50 | 150 | 1500 | 15 | 0 | 500 | no | 5 |

Price is `cost + owned_of_this_kind * escalation`. Sprite frames come from each
def's `upgradeFrames[0]` on the 96px grid; the rest of the series is unused
until the upgrade phase.

**Enemies** (`data/enemies.ts`)

| | speed | health | reward | lifeLoss | scale | flip |
|---|---|---|---|---|---|---|
| Slime | 100 | 5 | 5 | 1 | 0.7 | no |
| Ogre | 60 | 8 | 20 | 5 | 1.2 | yes |
| Bee | 150 | 3 | 10 | 2 | 0.7 | no |

`scaled_health` floors and clamps to ≥1; `scaled_speed` is unrounded and clamps
to ≥1.

**Waves** (`data/waves.ts`) — `MAX_WAVES = 20`. Authored additions for waves
1–5; beyond wave 5 each wave adds `{slime 2, bee 5, ogre 2}`. Composition
**accumulates from wave 1**, so wave 3 contains waves 1 and 2 as well. This is
surprising when reading the tables and is preserved deliberately. Scaling is
`1 + (wave - 5) * 0.1` health and `* 0.05` speed, floored at wave 5. Spawn
timing: 500 ms between same-kind spawns, bees delayed 5000 ms, ogres trailing
the last slime by 3000 ms but never starting later than 10000 ms.

**Damage** (`sim/damage.ts`) — ported whole. Armour and shield terms stay in the
signature but are never set during the slice, so it reduces to health subtraction
with overkill clamping. Two behaviours in it are load-bearing even without
properties: overkill is not counted toward `damageDealt`, and **a dead or dying
target absorbs nothing** — without that guard a second projectile already in
flight pays the kill reward twice.

**Leaks** (`sim/leak.ts`) — flat `lifeLoss` through wave 5; past it,
`ceil(remaining health)`. Both capped at 4. Twenty lives is a budget of five
mistakes.

**Movement** (`sim/movement.ts`) — two quirks preserved verbatim, both affecting
arrival timing: reaching a waypoint consumes the entire tick without also
moving, and there is no clamping to the waypoint, so a fast enemy overshoots and
steers back.

**Targeting** (`sim/targeting.ts`) — the module ports whole, including all four
priorities, because it is pure and small and its tests come with it. The UI for
cycling priority is out of slice; every tower uses the default, `closest`,
matching pre-Phase-1 behaviour. Ties break on lowest id so results never depend
on iteration order.

**Economy** (`data/economy.ts`) — of the constants there, the slice uses
`startingLives: 20` and `sellRefundFraction: 0.5`. Wave-clear bonus,
call-early and interest belong to the later phase that introduced them.

**Grid** (`map/Grid.ts`) — `set_active_grid(cols, rows, tile_size)` is called
before anything reads a tile coordinate. The original's bug, where `world_to_tile`
used the first map's dimensions regardless of which map was loaded and silently
rejected 30% of the second map's tiles, is fixed by construction here.

## 7. Assets

Copied from `td-browser/public/`. Three treatments:

**Enemy sheets** — 288×48 PNGs, six 48px frames each, in
`{U,S,D}_{Walk,Death}.png` per creature. Become one `SpriteFrames` resource per
creature with animations `walk_up/walk_side/walk_down` and the death trio.
`flip_h` covers both leftward travel and the Ogre's permanently mirrored
artwork.

**towers.png** — 480×384 on a clean 96px grid, 5×4 = 20 frames. `AtlasTexture`
regions. (The original had this at 100px, which divides neither dimension, so
every frame after the first straddled its neighbour; 96 is correct and verified
against the transparent gutters.)

**map-sprites.png** — 3.9 MB at 1024×1536, of which the game uses **eight
hand-picked rects**:

| # | rect (x, y, w, h) | use | # | rect | use |
|---|---|---|---|---|---|
| 0 | 60, 150, 64, 64 | grass | 4 | 750, 600, 256, 350 | castle (goal) |
| 1 | 60, 64, 64, 64 | path | 5 | 700, 880, 300, 300 | cave (spawn) |
| 2 | 40, 250, 100, 150 | tree | 6 | 760, 530, 100, 100 | spike decor |
| 3 | 670, 230, 128, 128 | stone | 7 | 650, 500, 100, 100 | fire decor |

Those rects total ~239k pixels against the sheet's 1.57M — **about 15%**.
Pre-slicing them into a small atlas drops several megabytes from the web build.
`HANDOFF.md` names this "the biggest single load-time win available," and it
costs nothing here because the renderer is being rebuilt regardless.

The existing aspect distortion is preserved: the tree is a 100×150 rect drawn
into 48×48, and goal and spawn are drawn at 144×144 offset by
`(-TILE_SIZE, -TILE_SIZE - 20)`. That squashing is the game's actual look.

Decoration placement is seeded, not random: ~10% of buildable tiles (minimum 5)
get the spike, up to 7 path-adjacent buildable tiles get the fire, and 3–5
blocked tiles become stone with the rest trees, all excluding a 3×3 region
around spawn and goal. Decorations are removed from a tile when a tower is built
on it.

**Audio** — the 22 WAVs convert to OGG for the web build. `HANDOFF.md` notes
they are synthesised placeholders due for replacement; that is out of scope.

## 8. Web and mobile

Web first, phones after. That drives:

- **Compatibility renderer.** Forward+ is unreliable on web and mobile GPUs.
- **No threads.** Godot 4 web needs COOP/COEP headers for `SharedArrayBuffer`;
  avoiding threads avoids the hosting requirement.
- **Touch-first input.** No hover-dependent affordance anywhere, since hover
  does not exist on a phone. Placement is tap-tile-then-confirm rather than
  hover-preview.
- **Viewport** 1104×672 (map 1 exactly), `canvas_items` stretch, `expand`
  aspect, so wider or taller screens gain view rather than letterboxing.

A caveat recorded for the record: a Godot 4 web export runs roughly 25–40 MB
against the Phaser build's 368 KB gzipped. This was raised during design and the
web-first target was confirmed anyway. The atlas and audio work in §7 are the
available mitigations.

Auth is dropped rather than ported. The Cloudflare Worker exists mainly to serve
a leaderboard that does not exist yet, and a login wall in front of a web tower
defence is friction with nothing behind it. Should a leaderboard arrive, the
score-submission endpoint can be called without gating play behind an account.

## 9. Deliberately not reproduced

Faithfulness stops at the sim boundary. These are in the Phaser build and will
not be ported:

- The three-hop leak event (`BaseEnemy` → `GameScene` → re-emit → `UIScene`),
  an artifact of two scenes owning separate emitters.
- Wave completion detected in two places at once — a polling timer and an inline
  `update()` check — where the timer is never destroyed when the inline path
  wins.
- `enemiesRemainingInWave`, which counts spawns rather than survivors; the
  `enemies.size == 0` clause does the real work.
- The `W` hotkey that jumps to the final wave.
- Money and lives living as private fields on the UI scene.

## 10. Testing

`gdUnit4`, mirroring the original's split:

- **Sim unit tests**, ported from the TypeScript suite — movement, damage,
  targeting, leak, economy, rng, waves, pathfinding.
- **Purity guard**, as described in §5.
- **Harness tests**: `sim/harness.gd` runs a wave headlessly on a fixed timestep
  and reports leaks, kills and gold. This is what makes a balance claim a test
  rather than an assertion, and it is the piece most worth having early.

The original's convention holds: tests state the design claim, not the
implementation, and a test is never weakened to make it pass.

## 11. Risks

1. **The map sheet rects were eyeballed** against a Phaser display size. Some
   may need nudging. Mitigation: verify visually through the Godot MCP rather
   than trusting the numbers, exactly as the original's 96-vs-100 frame bug was
   found by measuring the file rather than reading the config.
2. **Timing parity is the thing most likely to drift.** The original scheduled
   spawns with `time.delayedCall` against Phaser's clock; this port schedules
   against a fixed 60 Hz tick. Wave composition and totals should match exactly;
   sub-frame spawn instants may not. The harness tests are the check.
3. **Ported balance is unplaytested balance.** Restating §2 because it is the
   single most important fact about the source project.

## 12. Definition of done

A browser build in which a player opens the main menu, starts The Pass, builds
from four towers against twenty accumulating waves, loses lives to leaks, wins
at wave 20 or loses at zero lives — with the sim suite and purity guard green,
and no engine import anywhere under `sim/` or `data/`.
