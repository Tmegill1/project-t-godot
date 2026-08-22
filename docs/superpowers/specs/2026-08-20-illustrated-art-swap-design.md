# Replacing the Kenney art with the illustrated sprite sheet

**Date:** 2026-08-20
**Source:** `~/Desktop/AI_Towerdefense_sprite_sheet.png`, 1536×1024, RGB
**Target:** Godot 4.7.1.stable, GDScript, on top of `master` (which now carries the Kenney art swap)
**Status:** design approved, ready for planning

---

## 1. What this is and what it costs

Every visual asset in the game is replaced a second time, with a single
illustrated sprite sheet: 16 tower sprites, new art for the three existing
enemy types, terrain and road tiles for three environments, and a set of decor
props.

This is the third art direction this project has worn. It supersedes the Kenney
*Tower Defense (Top-Down)* swap that merged three commits ago, and it deletes
most of what that swap built. That is not waste to be hidden — §8 lists exactly
what dies, so the decision stays revisitable.

**The honest trade.** The new art is richer: hand-drawn towers with four
distinct states each, illustrated enemies, terrain with flowers, rocks and
texture, and three-quarter perspective that gives the board depth without any
rendering work. What it costs:

- **The road loses its organic edges.** Kenney's blend lattice produced soft
  wavy boundaries between road and grass. These tiles are discrete cards, so
  the ground becomes a visible tile grid. This was mocked before the design was
  approved and the mock is what it will look like.
- **Turrets cannot rotate.** The towers are fixed-facing illustrations.
- **Enemies lose animation.** No walk cycle, no death frames.

## 2. The sheet, as measured

Everything below was measured off the file, not read off its labels.

| Property | Value |
|---|---|
| Size | 1536×1024 |
| Mode | **RGB — no alpha channel** |
| Background | uniform dark navy, `(9, 22, 28)` |
| Section rules | vertical at x 8–10, 1230–1232, 1525–1527; horizontal at y 9–10, 1015–1017 |

**Section rectangles**, bounded by those rules:

| Section | Region |
|---|---|
| Towers (4 groups) | y 12–210; groups split at x 10, 430, 863, 1234 |
| Enemies (5 rows) | y 214–588; rows split at y 290, 363, 435, 518 |
| Terrain tiles | y 600–1013, x 12–482 |
| Path tiles | y 600–1013, x 484–1228 |
| Extras / decor | x 1234–1525, below the tower band |
| Path shape legend | x 1234–1525, lower portion |

**Tile geometry:** terrain and road cells are nominally 64×64 at a pitch of
66–67px, with organic scalloped borders and painted drop shadows. The grass row
begins at x 143, the path row at x 78, both at that pitch.

**Three facts that shaped the design:**

- **The tiles are not seamless.** Tiled edge-to-edge they read as separated
  cards. A tight bounding-box crop scaled to slightly overfill each cell closes
  the gutters and leaves a thin seam grid, which is the look this ships with.
- **The path pieces are shape-based.** Sampling each piece's edge midpoints past
  the card border gives its connection mask: the solid tile and the two cross
  variants read 15, the curves read 3 (a corner), the T reads 7. There is **no
  straight piece**, and a one-tile-wide road is mostly straights — §4 composes
  one.
- **The enemy rows are not animation.** They are near-identical variants of a
  single pose — equipment changes on some rows, and legs do not alternate
  consistently. Cycling them produces a shimmer, not a walk.

## 3. Extraction

A new bake tool cuts the sheet into individual PNGs under `assets/art/`.

**Segment by projection inside known section rectangles, not by flood fill.**
Flood fill was tried and fails both ways: a tight threshold fragments a tower
into several components because its dark outlines sit near the background value,
and a loose threshold with dilation merges the densely packed enemy rows into
blobs. Projection segmentation — sum the foreground mask along an axis, split on
gaps — handled the densest block correctly, returning 16/16/15/14 sprites across
four enemy rows.

The section rectangles in §2 are hardcoded, because the sheet's borders and text
labels defeat any fully automatic layout discovery. Everything inside a section
is found by projection. That split keeps the brittle part small, explicit and
testable.

**Keying.** The sheet has no alpha, so the background is keyed by distance from
`(9, 22, 28)`. Sprite outlines sit close to that value, so the threshold is a
measured tunable rather than a guess, and each extracted sprite is trimmed to its
alpha bounding box and padded 1px — the same treatment the Kenney props needed,
for the same reason: `prop_footprints()` derives collision from displayed size.

**Text is excluded structurally.** Section headers and row labels are inside the
section rectangles and would otherwise segment as sprites — an early pass
extracted the word "BARRACKS". Each section's rectangle therefore starts below
its header, and the label column on the left of the enemy and terrain rows is
excluded by starting those rectangles past it.

## 4. Terrain and road

### 4.1 Ground

Each map cell draws one card tile, scaled to slightly overfill its 48px cell so
the gutters close. `Tiles.TILE_SIZE` stays 48; the 64px source downscales, as
the Kenney art already does.

Three environments come from the sheet directly — grass, desert, ice — which
map onto the existing `forest`, `desert` and `ice` biomes. The biome layer added
by the Kenney swap survives unchanged in shape: `data/biomes.gd` keeps naming a
directory per biome, and only the contents change.

Non-road cells pick from that environment's variant tiles, seeded so a map
renders identically every run — the existing `Rng` and `Seeds.DEFAULT_DECORATION_SEED`
already provide this.

### 4.2 The road is an edge mask, not a corner mask

This is the substantive rendering change and it is a simplification.

Kenney's road needed a 4-bit **corner** mask sampled at tile centres, a
half-tile-offset lattice, a 16-entry blend table per biome and a family
discriminator. All of that goes.

The new road uses a 4-bit **edge** mask: for each road cell, which of its four
orthogonal neighbours are also road. One sprite per cell, on the tile grid, no
offset, no lattice. The mask selects a piece and a rotation:

| Mask | Piece | Rotation |
|---|---|---|
| 15 (all four) | cross | 0 |
| 7, 14, 13, 11 (three) | T | 0/90/180/270 |
| 3, 6, 12, 9 (adjacent pair) | corner | 0/90/180/270 |
| 5, 10 (opposite pair) | **composed straight** | 0/90 |
| 1, 2, 4, 8 (one) | composed straight | nearest |
| 0 | solid | 0 |

Rotation is `(m << k | m >> (4 - k)) & 15` on the piece's own derived mask, so
the table is computed rather than transcribed — the same principle that caught
the Kenney family error.

### 4.3 The composed straight

The sheet ships cross, corner and T but no straight, and a one-tile road is
mostly straights. Using the solid dirt tile instead leaves those cells with no
grass edging, which reads inconsistently where a straight meets a curve — both
visible in the design mock.

The bake composes a straight from the **cross**: mask its east and west arms
with grass lifted from the cross's own corners, giving a north-south straight
with grass on both sides, then rotate for east-west. A rough version was built
during design and works; the bake blends the paste seams rather than leaving
them hard.

## 5. Towers

Sixteen sprites: four types × four levels, in the sheet's own order — Archer,
Cannon, Mage, Barracks.

**This maps onto the existing selector with no new data.**
`UpgradesSim.visual_tier` already collapses six purchasable tiers into four
looks driven by total investment, and `sprite_frame_for` already picks one of
four frames per kind. The sheet's four levels per tower are exactly that, so the
existing `sprite_frame` and `upgrade_frames` values keep working against a new
atlas at the same 5×96 geometry.

**No base/turret split, and no rotation.** These towers are three-quarter
illustrations with archers and cannons pointing a fixed way; rotating one reads
as the building spinning. The turret work planned in
`2026-08-20-turret-tracking-and-targeting.md` is discarded — see §8.

The upgrade legibility this was meant to deliver comes from the art instead: four
hand-drawn states per tower is a stronger read than any compositing produced.

## 6. Enemies

**The three existing kinds keep their identities and get new sprites. The
count does not change.** `data/waves.gd` schedules twenty waves by kind name,
so introducing new kinds is balance work, not an art swap, and this spec does
not do balance work.

The sheet offers five rows; three are used, mapped by what each stat profile
already is:

| Existing kind | Profile | New sprite |
|---|---|---|
| `slime` | 100 speed, 5 hp, the common early spawn | Goblin |
| `ogre` | 60 speed, 8 hp, slow and tanky | Ogre |
| `bee` | 150 speed, 3 hp, fastest and frailest | Bat |

`Enemies.KINDS`, every stat, and every wave schedule are untouched — only
`texture_key` and `sprite_scale` change.

**Goblin Shaman and Troll are extracted but unused.** They are the natural art
for the deferred enemy-variety feature, which needs its own stats, its own wave
schedule and its own balance pass. Extracting them now costs nothing and means
that feature starts with art in hand.

**The rows are variants, and they are used as per-spawn variety.** They are
not animation, and this was settled numerically rather than by eye: a real walk
cycle shows periodic structure — the current ogre's frame-to-frame difference
varies with lag and dips as the cycle returns to its start — while the sheet's
rows are perfectly flat across every lag, which is the signature of independent
variations. Consecutive frames also differ about four times less than a real
cycle's do.

So each enemy **picks one of its row's frames at random when it spawns**, drawn
from the seeded `Rng` so a run stays reproducible. A wave of eight goblins shows
eight subtly different goblins rather than eight identical ones. This uses what
the sheet actually provides and is strictly better than one static sprite per
type.

**Motion is synthesised in code.** The chosen frame is flipped horizontally by
travel direction, with a small sine bob and slight lean applied while moving so
an enemy reads as alive rather than sliding.

**Death becomes a tween.** `game/enemy.gd` currently plays `death_<facing>` and
**awaits `animation_finished`** before despawning. With no death frames it
becomes a short fade-and-shrink tween of about 250ms. This changes despawn
timing from "however long the animation runs" to a constant the code owns, and
the tests that pin the current sequence change with it.

**What is deliberately lost:** directional facing beyond horizontal flip (up and
down both draw the side pose), and per-facing death animations.
`Enemies.DEFS`'s `flip_horizontally` per-kind override survives, since the new
sprites also face one way by default.

## 7. Props, endpoints and decor

Props come from the Extras/Decor column — trees, rocks, barrels, crates,
banners, a campfire, fences. The four prop slots keep their existing names
(`tree`, `stone`, `spike`, `fire`) because `MapRenderer`'s scatter rules are
written in those terms and none of those rules change.

Endpoints have no direct equivalent on the sheet, so the composed castle and
cave from the Kenney swap are **rebuilt from the new decor** rather than
retained — keeping flat vector markers on an illustrated board would be the
style clash this swap exists to avoid.

Every prop is trimmed and 1px-padded exactly as the Kenney props are, and for
the same reason: `_place` normalises a sprite's longest axis to `TILE_SIZE`, so
the blocking radius is always 24 and the art must fill it.

## 8. What dies, what survives

**Deleted:**

- The entire Kenney blend pipeline — 42 blend tiles across three biomes, the
  corner-mask table, the family discriminator in `tools/bake_kenney.gd`, and
  `test_blend_tiles.gd`'s family gate. That gate was the hardest-won thing in
  the art-swap branch and none of it survives the move to shape-based roads.
- The half-tile-offset ground lattice in `MapRenderer._draw_ground`, and the
  `corner_mask` function with it.
- `assets/kenney/**`, `assets/towers.png`, and `tools/bake_kenney.gd`.
- The four turret tasks in
  `docs/superpowers/plans/2026-08-20-turret-tracking-and-targeting.md`: the
  base/turret atlases, `turret_frame_for`, the scene split and the rotation.

**Survives untouched:**

- **The three targeting-priority tasks** in that same plan — `weakest`, the
  per-tower setter, and the inspector's cycling row. They are rules and UI and
  touch no art. They should be executed regardless of this swap.
- The biome layer's shape: `data/biomes.gd`, `Biomes.prop_path`, the per-biome
  directory layout, and `Maps.DEFS`'s `biome` key.
- Every rule in `sim/`, the tower upgrade system, waves, economy, and the
  headless harness.
- `Tower.frame_region` and the 5×96 atlas geometry.

**Reduced:** the depth plan
(`docs/superpowers/plans/2026-08-20-board-depth.md`). Shadows are largely
redundant because these tiles and towers carry painted shadows already, but
**Y-sorting matters more**, since three-quarter towers and tall enemies must
overlap by position. That plan is re-scoped to Y-sorting alone rather than
discarded.

## 9. Tunables that move

**`PATH_HALF_WIDTH` goes back up.** It moved 26 → 14 during the Kenney swap
because that road drew only 23px wide. These road cells are full-tile dirt, so
the visible road returns to roughly 48px and the corridor follows it back toward
26. The value is measured off the committed road tile the same way
`test_road_width.gd` already measures it, not guessed.

**`MIN_TOWER_SPACING` stays 44** unless the new tower art changes footprint,
which is checked rather than assumed: the towers are taller than wide, and if
their displayed width differs from the Kenney towers' the spacing is re-derived.

## 10. Testing

The asset-gate pattern carries over intact, because it is about committed bytes
rather than about any particular art:

- **Extraction gates** — every expected sprite exists, is trimmed to its alpha
  bbox with a 1px pad, and carries a transparent margin on all four edges. The
  background-key threshold is pinned, because a threshold that drifts either
  eats outlines or leaves a dark halo.
- **Road table gate** — each committed road piece's connection mask is
  re-derived from its pixels and asserted against the mask the table claims,
  the same self-verifying approach the Kenney blend table used.
- **Rotation gate** — the mask-rotation arithmetic is asserted directly for all
  16 masks, since a wrong rotation produces a plausible-looking but wrong road.
- **Footprint parity** — prop footprints stay inside one tile and every radius
  is `TILE_SIZE / 2`, exactly as now.
- **Road width** — `PATH_HALF_WIDTH` measured against the committed road tile,
  per §9.
- **Enemy despawn** — the death tween's duration and the despawn that follows
  it, replacing the tests that currently pin `animation_finished`.

**Screenshots remain mandatory.** A green suite sees neither layout nor draw
order, and this swap's biggest risk — whether the card-tile ground reads
acceptably in motion — is invisible to every assertion above. All three
environments get captured, plus a wave in progress.

## 11. Branching

Cut from `master`, which carries the merged Kenney swap. The work deletes most
of that swap's assets, so the branch is large and its diff will be dominated by
removals and binary additions.

`feat/turret-tracking-and-targeting` currently holds two plans, of which one is
partly superseded. Rather than deleting it, the three targeting tasks are
executed from it first and merged, because they are independent of art and
useful whatever happens to this swap. This branch then starts from that result.
