# Free tower placement — retiring the placement grid

**Date:** 2026-08-15
**Source:** no reference counterpart — this is a deliberate divergence from
[`Tmegill1/project-t`](https://github.com/Tmegill1/project-t), which is tile-based
**Target:** Godot 4.7.1.stable, GDScript, on top of the merged core + upgrades slices
**Status:** design approved, ready for planning

---

## 1. Why this document exists

Towers currently snap to a 48px tile and may only be built where the map data
says `Tiles.BUILDABLE`. Tyler wants to place towers anywhere on the map that is
not physically occupied — by the road, by a tree or rock, or by another tower.

The instinct behind the request was "get rid of the tile system". That framing
is one step too broad, and §2 explains why: the grid does two unrelated jobs and
only one of them is in the way.

This work is sequenced **before** the planned art overhaul, deliberately. Free
placement changes what the art has to be — props stop being tile-fillers and
become collision objects with footprints, and edge-matching between adjacent
ground tiles stops mattering. Choosing art first would mean choosing it against
constraints that are about to be deleted.

## 2. What the grid actually does today

The tile system serves two purposes that happen to share a data structure:

**Job 1 — authoring the map.** `data/demo_map.gd` builds a 23x14 array of tile
kinds; `sim/pathfinder.gd` BFS's over it to find the route from spawn to goal.
This job is fine and stays.

**Job 2 — constraining tower placement.** `_handle_tap` snaps a click to a tile,
`_try_place` gates on `_tiles[row][col] != Tiles.BUILDABLE`, and `_occupied`
(a `Vector2i -> Tower` dict) enforces one tower per tile. This job is the one
being removed.

The important discovery is how little else depends on the grid. `PathFinder`
emits a **world-space** `PackedVector2Array`; enemies follow world points and
never consult a tile again after load. `sim/targeting.gd` is pure distance math.
Damage, slow, economy, upgrades, waves and leak have no tile awareness at all,
and tower range is already a pixel radius.

| Subsystem | Grid-dependent? |
|---|---|
| `sim/pathfinder.gd` | yes — BFS over the tile array (**stays**) |
| `data/demo_map.gd`, `data/maps.gd` | yes — maps are authored as tile arrays (**stays**) |
| `game/game_board.gd` placement | yes — **this is the work** |
| `game/tower.gd` | yes — stores `grid_col`/`grid_row` (**changes**) |
| `game/map_renderer.gd` | yes — grid overlay, per-tile decoration scatter (**changes**) |
| `sim/movement.gd`, `sim/targeting.gd` | no — world-space already |
| `sim/damage.gd`, `slow.gd`, `economy.gd`, `upgrades.gd` | no |
| `data/waves.gd`, `data/enemies.gd`, `data/towers.gd` | no |

Combat and economy do not know the grid exists. That is why this is a contained
change rather than a rewrite.

## 3. Scope

### In

- A new pure rules module, `sim/placement.gd`, answering "may a tower stand
  here?" with circle-vs-circle geometry.
- Prop footprints published by `MapRenderer` in world space.
- `game/tower.gd` positioned by a world `Vector2` instead of a tile coordinate.
- `game/game_board.gd` placement and selection reworked around distance tests.
- A ghost tower preview under the cursor: translucent, green when legal, red
  when not, showing its range ring when legal.
- Removal of the grid overlay.

### Out

- **Removing `Grid` or `Tiles`.** Both survive; map authoring and pathfinding
  legitimately need them. A "full de-tiling" — authoring maps as polylines and
  prop lists — would mean rewriting `demo_map.gd`, `maps.gd`, `pathfinder.gd`
  and their tests for no gameplay benefit, since enemies already move freely.
- **Snapping to a finer sub-grid.** Considered and rejected: it reintroduces
  quantization that was not asked for.
- **Rebalancing waves.** `MIN_TOWER_SPACING` starts at a value chosen to
  preserve today's density (§4.2) precisely so that balance work can be a
  separate, later, playtest-driven pass.
- **Art replacement.** This spec makes art replacement cheaper; it does not do
  it.

## 4. Architecture

### 4.1 `sim/placement.gd` — the rules

A new `class_name Placement` of pure static functions, in the style of
`sim/targeting.gd`: no nodes, no scene tree, no engine state. This is what makes
it exhaustively testable in the synchronous headless harness.

```gdscript
static func can_place(
    pos: Vector2,
    radius: float,
    props: Array,          # [{ "pos": Vector2, "radius": float }]
    towers: Array,         # [Vector2]
    paths: Array,          # [PackedVector2Array]
    bounds: Rect2
) -> Dictionary             # { "ok": bool, "reason": StringName }
```

It returns a **reason**, not a bare bool, so `placement_rejected` keeps emitting
the specific messages it does today rather than collapsing to one generic
string. Reasons: `&"out_of_bounds"`, `&"on_path"`, `&"blocked_by_prop"`,
`&"too_close"`. Checks run in that order, cheapest and most-explanatory first.

The only real geometry is point-to-segment distance, needed to keep towers off
the road: the path is a polyline, so the test is the minimum distance from `pos`
to any segment of any spawn path. This gets its own small helper
(`_distance_to_polyline`) and its own tests, including the degenerate
zero-length-segment case that a naive projection divides by zero on.

`can_place` takes everything it needs as arguments and reads no global state.
`Grid.set_active`-style static state is deliberately not used here — which is
what lets a test construct an arbitrary board without touching engine
singletons. `bounds` is supplied by the caller from the existing
`Maps.pixel_size(name)` (`data/maps.gd:26`), as `Rect2(Vector2.ZERO, size)`;
`Placement` itself never looks a map up.

### 4.2 The numbers

New constants. Every value is derived from something real rather than picked:

| Constant | Value | Where it comes from |
|---|---|---|
| tower radius | `size * TILE_SIZE / 2` | `data/towers.gd` already carries `size` (0.75–0.85), so towers are 36–41px wide — a 18–20px radius. Not a new number. |
| `MIN_TOWER_SPACING` | `44` | Tunable. Chosen just under the old 48px tile pitch so day-one density roughly matches today's and existing wave balance still holds. |
| `PATH_HALF_WIDTH` | `26` | Half a tile (24) plus a small margin, so a tower may not encroach on the road enemies visibly walk down. |

`MIN_TOWER_SPACING` is deliberately **separate from the visual radius**. Coupling
them would mean "how big a tower looks" and "how close two may sit" could not be
tuned independently, and the second is a balance lever while the first is an art
decision.

### 4.3 Prop footprints — `game/map_renderer.gd`

`MapRenderer` already tracks scattered decorations in `_decorations`
(`Vector2i -> Sprite2D`). It gains one method:

```gdscript
func prop_footprints() -> Array   # [{ "pos": Vector2, "radius": float }]
```

Radius is derived from each sprite's **actual displayed size** — half its
longest displayed axis. Longest rather than shortest or averaged, deliberately:
it over-covers rather than under-covers, so a tower can never visually overlap a
prop even where the circle is a poor fit (a stone displays 48x22, so a
24px-radius circle is generous vertically). Blocking slightly too much reads as
intentional level design; letting a tower clip into a rock reads as a bug. This
is only correct because commit `550ed7c` fixed
`_place` to scale uniformly; under the previous stretch-to-square behaviour the
displayed size was a distortion and a footprint derived from it would have been
wrong too.

Footprints must cover trees and stones (drawn by `_draw_blocked`) **and** spikes
and fires (drawn by `_scatter_decoration`), which is every prop the player can
see. Ground tiles are not props and contribute no footprint.

`clear_decoration_at(col, row)` becomes dead code and is **deleted**: it existed
to remove a decoration when a tower was built on its tile, and under the new
rules a prop is a hard blocker that can never be built on. Its tests go with it.

### 4.4 `game/tower.gd`

`setup(kind, col, row, price)` becomes `setup(kind, world_pos: Vector2, price)`.
`grid_col` and `grid_row` are deleted; the node's own `position` is the single
source of truth for where a tower is, and `Grid.tile_to_world_center` is no
longer called.

**This is the riskiest edit in the spec.** `Tower.setup` has a documented hazard
(`game/tower.gd:55-60`): in the headless harness the tower's `@onready` fields
are unresolved, so the function aborts at the first line touching one, and
everything assigned *before* that line still lands. The tower-upgrades work
already shipped one defect from exactly this. Rule for the implementation: the
`position` assignment must sit **above** the first `@onready` access, and
`test_tower.gd`'s existing "setup lands tiers and stats even when the sprite half
aborts" test must be extended to cover position.

### 4.5 `game/game_board.gd`

- `_occupied` is **deleted outright** rather than replaced. `_towers_root`
  already parents every tower and `_towers_root.get_child_count()` is already
  the tower-budget check, so `_towers_root.get_children()` is an existing,
  authoritative tower list. A parallel dict was only ever needed for tile keying.
- `_handle_tap` stops calling `Grid.world_to_tile`. It first hit-tests for an
  existing tower — the nearest tower whose own radius contains the click — to
  preserve select-on-click, then falls through to placement. "Nearest" rather
  than "first match" is not load-bearing at the default spacing — 44px apart
  with an 18–20px radius, two hit circles cannot overlap — but it becomes
  load-bearing the moment `MIN_TOWER_SPACING` is tuned below ~40, which §9
  expects. Writing it as nearest now costs nothing and removes a
  child-order-dependent bug that would otherwise appear during balance tuning,
  far from the change that caused it.
- `_try_place(col, row)` becomes `_try_place(world_pos)` and delegates its first
  gate to `Placement.can_place`, mapping the returned reason to the existing
  rejection messages. The budget, per-kind limit and affordability checks that
  follow are unchanged.
- `sell_selected_tower`'s `_occupied.erase(...)` line simply goes away; freeing
  the node is now the whole removal.
- `_paths` is **already** `Array[PackedVector2Array]` from
  `PathFinder.get_all_spawn_paths` in `_ready`, so the polylines `can_place`
  needs are already in hand — nothing new to compute or store.

### 4.6 The ghost

A translucent tower sprite follows the cursor whenever a tower kind is selected
for purchase. It is green-tinted when `can_place` returns ok and red when it does
not, and it shows its range ring only when legal — so the ring doubles as a
planning aid and its absence is a second, redundant signal that the spot is bad.

This reuses `game/range_indicator.gd` as-is (it already takes `radius` and
`tint`). The ghost is pure view: it asks `Placement.can_place` the same question
`_try_place` will ask, and stores no state of its own.

The grid overlay (`MapRenderer._GridOverlay`) is removed along with
`_draw_grid_overlay`, `_GRID_LINE_COLOR`, and the `_Z_GRID` layer. Its z-ordering
comment in `map_renderer.gd:18-25` explains a three-layer arrangement that
becomes two, and must be updated rather than left describing a layer that no
longer exists.

### 4.7 Untouched

`sim/pathfinder.gd`, `sim/movement.gd`, `sim/targeting.gd`, `sim/damage.gd`,
`sim/slow.gd`, `sim/economy.gd`, `sim/upgrades.gd`, `sim/harness.gd`,
`sim/grid.gd`, `sim/rng.gd`, all of `data/`, and every UI scene except the
inspector's tower-selection path.

## 5. Divergence from the reference

The Phaser build is tile-based and stays that way; this port will not match it
on placement. That is intentional and is the second such divergence, after the
rendering changes in `550ed7c`.

Consequence for future work: "restore parity with the reference" is no longer a
safe blanket instruction for this codebase. Anything comparing placement
behaviour against `td-browser/` will differ by design, and the reference's
placement tests must not be ported back.

## 6. Testing

`sim/placement.gd` is pure, so it gets the full treatment: TDD per rule, then
mutation testing, per the standing project lesson that every rules-layer defect
found so far came from mutation rather than from reading code.

Cases that must exist, because each is a rule a mutation could silently break:

- each rejection reason returned for a case that triggers only it
- rejection **precedence** when two rules fail at once (a spot both on the path
  and too close to a tower reports `on_path`) — otherwise reordering the checks
  is invisible
- boundary cases at exactly `MIN_TOWER_SPACING` and exactly
  `radius + PATH_HALF_WIDTH`, on both sides, since `<` vs `<=` is a classic
  surviving mutant
- point-to-segment distance where the nearest point is a segment **endpoint**
  rather than its interior — a projection-only implementation passes the
  interior case and fails this one
- a zero-length path segment (division-by-zero guard)
- an empty prop list, an empty tower list, and a single-point path

**Test churn is the real cost of this work, not the production code.** Tile-based
placement is asserted across ten test files:

| File | References | Disposition |
|---|---|---|
| `test_game_board.gd` | 43 | mechanical rewrite: tile coords → world coords |
| `test_harness.gd` | 22 | mechanical rewrite |
| `test_map_renderer.gd` | 17 | grid-overlay tests deleted; footprint tests added |
| `test_grid.gd` | 11 | **unchanged** — `Grid` survives |
| `test_pathfinder.gd` | 10 | **unchanged** — pathfinding survives |
| `test_tower_inspector.gd` | 5 | selection-by-position rewrite |
| `test_tower_panel.gd` | 5 | mechanical rewrite |
| `test_tower.gd` | 4 | `setup` signature + the abort-safety test |
| `test_demo_map.gd` | 2 | **unchanged** |
| `test_hud.gd` | 1 | mechanical rewrite |

The suite stands at 5214 checks across 29 files and must not regress in count
without a stated reason — deleted grid-overlay and `clear_decoration_at` tests
are exactly such a reason, and should be called out when they go.

**Screenshot verification is mandatory**, per the standing lesson that a green
suite cannot see rendering or layout: the ghost's tint states, a tower placed
hard against a prop, and a tower placed at the path's edge all need eyes on them
through the Godot MCP.

## 7. Slices

Each slice ends green and is independently reviewable.

1. **`sim/placement.gd` + its suite.** Pure module, no callers yet. Nothing else
   changes; the game still uses tiles. Largest test payoff, zero risk.
2. **Prop footprints.** `MapRenderer.prop_footprints()` and its tests. Still no
   behaviour change.
3. **`Tower.setup` signature.** The riskiest edit, done alone so a regression has
   an obvious cause. Board still passes tile-derived world centres, so placement
   behaviour is unchanged and the existing tests should still describe reality.
4. **Free placement in `GameBoard`.** `_occupied` deleted, `can_place` wired in,
   selection by hit test. Behaviour changes here; the bulk of test churn lands
   here.
5. **Ghost and grid-overlay removal.** Pure view. Screenshot-verified.

## 8. Definition of done

- Towers may be placed anywhere in bounds not overlapping the road, a prop, or
  another tower, and nowhere else.
- Rejections still name their specific reason to the player.
- Selecting, upgrading and selling a tower all work by position.
- No grid overlay is drawn, and no code path that decides **where a tower may
  go** reads a tile coordinate. `map_renderer.gd` still iterates tiles to draw
  ground and scatter props, and `pathfinder.gd` still walks them to build the
  route; both are correct and out of scope.
- `sim/placement.gd` is mutation-tested, not merely covered.
- Suite green, exit 0, with any drop in check count explained.
- Screenshots taken of the ghost's legal and illegal states and of towers placed
  adjacent to a prop and to the road.

## 9. Open questions

- **`MIN_TOWER_SPACING = 44` is a guess.** It is chosen to preserve today's
  density, not because 44 is right. Expect to tune it from real play; that is a
  balance pass, not part of this work.
- **Props are approximated as circles.** A tree's canopy is not a circle, and a
  216x97 rock is poorly served by one. If this reads badly in play, the fix is a
  per-prop radius table in `data/`, not a new collision model — `can_place`'s
  signature already takes an explicit radius per prop, so nothing structural
  changes.
- **Dense packing may make the tower budget the only real constraint.** Worth
  watching once playable, but not worth pre-solving.
