# Kenney art swap — replacing the map and tower art, and adding a biome layer

**Date:** 2026-08-16
**Source:** [Kenney, *Tower Defense (Top-Down)*](https://kenney.nl/assets/tower-defense-top-down), CC0
**Target:** Godot 4.7.1.stable, GDScript, on top of the merged core + upgrades slices and `feat/free-placement`
**Branch:** `feat/kenney-art-swap`
**Status:** design approved, ready for planning

---

## 1. Why this document exists

Every non-enemy asset in the game is replaced with art from Kenney's CC0
*Tower Defense (Top-Down)* pack, and the renderer gains a **biome layer** so a
map can declare itself forest, ice or desert.

Tyler asked for three themed maps — forest, ice, desert. That is two pieces of
work, and this document is only the first:

- **This branch:** the art swap plus the biome layer. Map 1 becomes forest. Ice
  and desert are proven by rendering the *existing* layout under those biomes.
- **A later branch:** the map 2 and map 3 layouts, map-to-map progression, and
  the balance work that comes with them.

The split is deliberate. The art half is the half this project's verification
actually covers — screenshots and the asset-acceptance gates in
`test/test_map_assets.gd`. Bundling two brand-new map layouts and a progression
flow into the same branch would put unverifiable work behind verifiable work.

This work is sequenced **after** free placement, for the reason
`2026-08-15-free-placement-design.md` §1 gives: free placement changed what the
art has to be. Props are now collision objects with footprints, and tile-edge
matching between adjacent ground tiles stopped mattering. §6 below is where that
bill comes due.

## 2. The pack, as measured rather than as advertised

Tyler's original request linked [Kenney's *Tower Defense
**Kit***](https://kenney-assets.itch.io/tower-defense-kit). That kit is **3D
only** — 160+ models in OBJ/FBX/DAE/STL/glTF, with no PNGs and no pre-rendered
sprites. This codebase is 2D throughout. Using it would have meant either a
Node3D rewrite of everything in `game/`, or building a model-baking pipeline.
Tyler chose the 2D *Tower Defense (Top-Down)* pack instead: same author, same
art voice, same CC0 licence, and it drops onto the existing `Sprite2D` renderer.

The following were measured off the downloaded archive, not read off a store
page:

| Property | Value |
|---|---|
| Tiles | 299, `towerDefense_tile001…299.png` |
| Default size | 64×64 |
| Retina size | 128×128 |
| Tilesheet | 1472×832 = 23 cols × 13 rows of 64px, row-major |
| Licence | CC0 (`License.txt`, vendored) |

**The tilesheet's packing order is NOT the individual-PNG numbering.** Comparing
every tile pixel-for-pixel, 229 of 299 match and **70 do not** — the divergence
starts at tile 15 and includes the whole 130–137 prop range. An index read off
the tilesheet is therefore not usable against `towerDefense_tileNNN.png`.

**Every index in this document is an individual-PNG index**, because that is
what the bake tool reads. Nothing here may be cross-checked against a tilesheet
contact sheet without re-deriving it.

**The pack ships exactly four terrains.** Every solid, fully-opaque, near-uniform
tile was sampled and clustered by mean colour:

| Terrain | RGB |
|---|---|
| Grass | `(45, 202, 111)` |
| Sand | `(229, 213, 179)` |
| Dirt | `(187, 128, 68)` |
| Stone (grey-blue) | `(136, 162, 164)` |

**There is no snow and no ice**, and there is no castle and no cave. §7 and §8
are the consequences.

Two measurements that matter later:

- **Ground tiles are opaque at alpha 255 across the whole tile.** 232 of the
  299 tiles measure a minimum alpha of 255, and every terrain and blend tile is
  among them. `test_map_assets.gd` requires `>= 249` and its header explains
  that 249 was the best the *old* source sheet could achieve anywhere. The new
  art clears the gate outright, so the seam class of defect that gate was
  written for cannot recur.
- **Props are free-standing with large transparent margins.** `tile130` (bush)
  is 128×128 with an alpha bbox of 62×62 — it fills 48% of its canvas. §6.

## 3. What is explicitly not changing

- **Enemies.** The slime/ogre/bee sheets under `assets/enemies/**`,
  `game/enemy.tscn`'s `AnimatedSprite2D`, its `TEXTURE_FILTER_NEAREST`, and
  `data/enemies.gd` are all untouched. Tyler is adding monster variety later and
  wants that decided separately.
- **Audio.** No sound in this pack is used.
- **Any rule in `sim/`.** This branch changes what is drawn, never what is
  decided. `sim/placement.gd` in particular is not edited — §6 keeps its
  contract true by changing the *art*, not the rule.
- **The tower atlas contract.** See §5.
- **`MIN_TOWER_SPACING = 44`.** Tower art keeps its current footprint, so the
  spacing that was tuned against it still holds.
- **`Tiles.TILE_SIZE`, which stays 48.** The pack is 64px and the Retina set is
  128px, but moving to a 64px grid would resize the canvas from 1104×672 to
  1472×896, move the tower panel (`ui/tower_panel.gd:30` offsets by the map's
  pixel width), and invalidate the free-placement tunables that were chosen to
  preserve the old feel. There is no visual gain: we downscale from 128px
  sources either way.

**`PATH_HALF_WIDTH` is the one exception, and it is a deliberate amendment to
this section.** An earlier draft froze it at 26 alongside `MIN_TOWER_SPACING`.
§7.3 explains why that is no longer tenable: the new road draws 23px wide, so a
26px half-width would refuse tower placement across a 14px band of
open-looking ground on each side of it. It moves to **14**. This is the same
principle as §6 — art and collision must agree — arriving from the road side
instead of the prop side. Signed off by Tyler after seeing the three candidate
renders measured.
- **`sim/economy.gd:42`'s `limit_bonus_map2`.** It stays dormant until a second
  map exists to trigger it.

## 4. The biome layer

### 4.1 `data/biomes.gd`

A new data table in the same shape as `data/towers.gd` and `data/enemies.gd` —
a `DEFS` dictionary, a `KINDS` array, a `get_def` accessor. Each biome names
six textures:

The four prop slots keep their existing names — `tree`, `stone`, `spike`,
`fire` — because `MapRenderer`'s scatter rules are written in those terms and
none of those rules change. Only the texture behind each name does. Source tiles
per biome, in individual-PNG indices (see §2):

| biome | ground↔road | tree | stone | spike | fire |
|---|---|---|---|---|---|
| forest | grass↔dirt | 130 (bush) | 136 (rock) | 132 (shrub) | 296 |
| ice | snow↔stone | 181 (crystal) | 135 (rock) | 183 (shard) | 297 |
| desert | sand↔dirt | 134 (spiked plant) | 137 (rock) | 131 (small bush) | 295 |

Each of the three ground/road pairings — grass↔dirt, sand↔dirt, sand↔stone —
already exists in the pack as a complete blend set. That is what makes three
biomes cheap.

### 4.2 Wiring

`data/maps.gd`'s `DEFS[&"demoMap"]` gains `"biome": &"forest"`.
`MapRenderer.render()` gains a biome argument and resolves textures from
`Biomes` instead of the eight `preload` constants at `map_renderer.gd:7-14`,
which are deleted. `GameBoard._ready` passes `def["biome"]`.

Ice and desert are exercised this branch by rendering the demo map's tiles under
them — in tests and in screenshots. No new map layout is authored.

## 5. Towers

**The atlas contract is unchanged**, and this is the single most important
constraint in the branch. `assets/towers.png` is replaced with a newly baked
file at the same geometry: 5 columns × 96px frames, 20 frames, 480×384.

Unchanged as a result: `Tower.TOWER_SHEET`, `Tower.SHEET_COLUMNS`,
`Tower.FRAME_SIZE`, `Tower.frame_region`, every `sprite_frame` and
`upgrade_frames` value in `data/towers.gd`, `UpgradesSim.sprite_frame_for`, and
`ui/tower_panel.gd:68`'s `icon_for`. A heavily-tested contract gets a pure file
swap.

Each frame composites a platform tile and a turret sprite. Sixteen of the twenty
frames are referenced by `data/towers.gd` (3, 4, 14 and 15 are unused today);
the tier progression reads as larger and more numerous weapons, drawn from
turrets **203–206** and **245–252**.

Towers are **not** biome-themed. They are player objects rather than scenery,
and a tower that changed appearance per map would read as a different tower.

## 6. Props, and the footprint bill from free placement

`MapRenderer.prop_footprints()` (`map_renderer.gd:70-84`) derives each prop's
blocking radius from **the texture's full dimensions** times the sprite scale.
Its doc comment justifies deliberately over-covering: "blocking slightly too
much reads as level design, while a tower clipping into a rock reads as a bug."

Kenney art breaks the "slightly". The bush `tile130` occupies 62×62 of a
128×128 canvas. Fitted into a 48px tile it draws about 23px wide but would
claim the full 24px radius — a blocking circle over twice the area of the
visible art. Players would hit invisible walls in open grass.

**The fix is in the bake, not in the code.** Each prop is trimmed to its alpha
bounding box and then padded back by exactly 1px of transparency. The padding is
not cosmetic: a bare bbox crop has opaque edge pixels and would fail
`test_map_assets.gd`'s margin gate, which is correct to reject it.
`sim/placement.gd` is not touched, and `prop_footprints()`'s "radius from
displayed size" rule becomes *true* rather than merely conservative.

One code change is unavoidable: `_PROP_TEXTURES` (`map_renderer.gd:18`) is a
`const` array of `preload`s, which cannot express a per-biome prop set. `_place`
will record prop sprites into a set as it creates them, and `prop_footprints()`
will read that set instead of comparing against a constant list.

## 7. Ground rendering with blended edges

The pack is drawn for organic terrain blending — every terrain pair ships edge
and corner tiles. `_draw_ground()` currently places one flat texture per tile,
which would give this art hard square road edges it was never drawn for.

### 7.1 The lattice

Terrain is sampled at **tile centres**, and each drawn sprite spans the square
between four adjacent centres. Drawn sprite `(c, r)` therefore takes its four
corners from tiles `(c-1, r-1)`, `(c, r-1)`, `(c-1, r)`, `(c, r)`, and is
positioned at `(c * 48 - 24, r * 48 - 24)`. Out-of-bounds corners count as
ground.

Consequences, all deliberate:

- The grid is `(cols + 1) × (rows + 1)` = **360 sprites**, not 322. The
  one-sprite-per-tile invariant in `test_map_renderer.gd` becomes
  one-sprite-per-lattice-point.
- Sprites overhang the map rect by 24px on every side. Left and top land at
  negative coordinates and bottom at y > 672, all outside the 1244×672 viewport;
  the right-hand 24px sits under `TowerPanel`, whose background is 95% opaque.
  Harmless on all four sides, and the alternative — skipping the outer ring —
  would leave a 24px unpainted border.
- The road stays centred on tile centres, which is what keeps it under the
  world-space path points `PathFinder` emits. A lattice anchored anywhere else
  draws the road half a tile off the route enemies actually walk.

The two rejected alternatives are recorded because both look reasonable on
paper. Sampling at grid **intersections** (a corner is road if any adjacent tile
is road) draws a 70px road and keeps one sprite per tile, but it floods the
one-tile grass strip between the row-8 and row-10 legs and paints buildable
ground as road. Sampling on **half-tiles** draws 36px and preserves that strip,
but at 24px per sprite the blend detail minifies away, the boundary reads as a
straight bar, and the sprite count quadruples to 1363.

### 7.2 Deriving the mask→tile table

The 16 masks map onto tiles per biome: mask 0 is pure ground, mask 15 pure road,
the rest blends. **The table is derived by script, not transcribed** — the bake
tool classifies each tile's four corner regions against the four measured
terrain colours in §2 and groups by mask.

**Corner classification alone is not sufficient**, and this is the trap. Each
terrain pairing appears **twice** in the pack: once with the road terrain drawn
as a small overlay lobe on a ground base, and once with the roles reversed. Both
families classify identically by corner colour, so a naive derivation picks a
self-consistent table that tiles *wrongly* — mismatched wave phases at concave
corners, and road flooding ground it should not touch.

The families are separated by a measurement, not by index position. For a
single-corner mask, the fraction of road-coloured pixels is **~0.04** in the
correct family and **~0.46** in the wrong one — a 10× gap, consistent across all
three pairings. Index position is *not* a usable rule: for grass↔dirt the
correct family is the higher indices, for sand↔stone the lower.

The derivation is therefore two-stage:

1. For each of the four single-corner masks (1, 2, 4, 8), take the candidate
   whose road-pixel fraction is below 0.25. These four are the family anchors.
2. For every other mask, take the candidate whose index is closest to the mean
   of those anchors. Verified to select correctly for all 14 masks in all three
   pairings.

Masks 0 and 15 are solid tiles and are chosen as the lowest-variance candidate
of the correct terrain.

The derived tables, for reference — these are outputs to be regenerated, not
inputs to be trusted:

| mask | 0 | 1 | 2 | 3 | 4 | 5 | 7 | 8 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| forest (grass↔dirt) | 119 | 117 | 115 | 116 | 71 | 94 | 72 | 69 | 92 | 73 | 70 | 95 | 96 | 50 |
| desert (sand↔dirt) | 188 | 191 | 189 | 190 | 145 | 168 | 146 | 143 | 166 | 147 | 144 | 169 | 170 | 50 |
| ice (sand↔stone) | 188 | 196 | 194 | 195 | 150 | 173 | 151 | 148 | 171 | 152 | 149 | 174 | 175 | 257 |

### 7.3 The two missing masks, and road width

**Masks 6 (`0110`) and 9 (`1001`) do not exist in the pack**, in any pairing.
They are the diagonal-only cases — two opposite corners road — which blob
tilesets omit because the connection is genuinely ambiguous.

The demo map produces **zero** of them: its path legs are orthogonal runs joined
at shared corner tiles, so no two road tiles touch only diagonally. It uses
exactly the 14 masks the pack supplies. A future map could differ, so
`Biomes.blend_texture(biome, mask)` substitutes mask 15 for 6 and 9 — the
resolution that connects both diagonals rather than neither — and a test asserts
the shipped map never reaches that branch.

**The road draws 23px wide**, measured on the rendered output, centred on the
tile centre line to within half a pixel. Kenney draws roads as ~3-tile
corridors; this map's are one tile with a one-tile gap between legs, and no
lattice reconciles that geometry with the pack's intent. 23px is the cost of
keeping the organic edges and the buildable strip. `PATH_HALF_WIDTH` follows the
art down to 14 — see §3.

**Blend tiles are baked as individual PNG files**, one per mask per biome, not
as regions of a runtime atlas. This is forced by
`test_map_renderer.gd:54`, which identifies ground textures by
`Texture2D.resource_path` — its header explains that reading `resource_path` is
what keeps those tests dependent only on public state. Individual files preserve
that, and they also keep `_place`'s `texture.get_width()` arithmetic honest.

That test's assertion has to change in kind: "path tiles use `path.png`" becomes
"this lattice point's texture is the one its mask names", and its count
assertion moves from `cols × rows` to `(cols + 1) × (rows + 1)` per §7.1.

## 8. Endpoints, and the ice recolour

### 8.1 Endpoints

The pack has no castle and no cave. Two PNGs are baked from pack pieces: the
goal as a fortified base built from structure tiles **226–229, 249 and 268**;
the spawn as a dark rock mouth from boulders **135–137**. `_draw_endpoints()`
changes only which texture it loads — the 3-tile width, the `(-TILE_SIZE,
-TILE_SIZE - 20)` offset and the `_Z_OVERLAY` layer all stay.

They are shared across biomes rather than themed per biome. Per-biome endpoints
would look better and would make each map feel authored, but they triple the
endpoint art and add two assets per future biome; that is a decision to revisit
when maps 2 and 3 are actually built.

They read as a generic fortified base and a rock portal rather than a literal
castle and cave. That is the accepted cost of style consistency.

### 8.2 The ice recolour

Ice is the one biome the pack cannot supply. It is derived as a **single-family
palette remap**: across the sand↔stone blend set, pixels in the sand palette
shift to snow white; the stone half is left untouched and serves as the frozen
road. The four terrain palettes in §2 are far enough apart in RGB that
targeting exactly one is unambiguous.

Concretely: a pixel within a squared-distance of 2600 of sand `(229, 213, 179)`
is rewritten as `(236, 242, 248) + (pixel - sand)`, preserving the speckle
detail as a delta rather than flattening it to a solid fill. Only the 14 tiles
of the sand↔stone table need it, because a biome uses only its own ground, road
and the blends between them.

Ice props need no recolouring at all: tiles **180–183** are already pale-blue
crystal plates.

CC0 permits derivative work without restriction, so this raises no licence
question.

## 9. The bake tool

A new `tools/bake_kenney.gd`, following the pattern `tools/slice_atlas.gd`
established: a Godot tool script, run headlessly, that turns source art into
committed assets under `assets/kenney/`. GDScript rather than Python keeps the
repo on one toolchain and adds no dependency to a Godot project.

It performs, in order:

1. Extract the tiles each biome needs from the **Retina 128×128** set. Starting
   at 128px and landing at 48px is sharper after mipmapping than starting at
   64px, and `_place` already downscales uniformly with
   `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`.
2. Derive the corner-mask→tile table per biome pairing (§7).
3. Recolour the ice set (§8.2).
4. Trim and 1px-pad the props (§6).
5. Composite the tower atlas (§5) and the two endpoints (§8.1).

The 3.2MB source archive is **not** committed. It is CC0 at a stable public URL,
which the tool's header records, and the extracted subset we actually use is
what lives in `assets/kenney/`. `License.txt` is vendored alongside and credited
in the README.

`tools/slice_atlas.gd` is retired and the old `assets/map/*.png` and
`assets/towers.png` are deleted. Git keeps them.

## 10. Testing

The project's standing lesson is that a green suite sees neither layout nor
filtering, and that every rules-layer defect so far came from mutation testing
rather than from reading code. Both apply here.

**Asset-acceptance gates** — `test/test_map_assets.gd` is rewritten against
`assets/kenney/`. Its two gates survive unchanged in spirit: props must have an
effectively transparent outermost row and column; ground tiles must be opaque
everywhere. Its `_EDGE_PIXEL_BUDGET` exemptions are **deleted rather than
carried over** — they record flaws in the old reference sheet (a castle packed
against neighbouring rocks, a campfire clipped by its neighbour), and
free-standing Kenney art has none of them. Budgets go to zero. Per that file's
own instruction, a budget is a record of a limit in the artwork, not a tolerance
for a worse crop.

**New `test/test_biomes.gd`** — all three biomes exist and are exactly forest,
ice and desert; every texture path in every biome resolves to a real resource;
each biome's ground differs from its road; ice's ground is provably not the
pack's sand (which is what a silently skipped recolour would produce).

**New blend-table test** — for each mask in each biome, re-derive the committed
tile's four corners from the PNG and assert they match the mask the table
claims. Same self-verifying spirit as the asset gates: nobody has to be believed
about the table being right.

**New family test** — the corner check above passes for *both* families (§7.2),
so it cannot catch the wrong one. A second assertion measures the road-pixel
fraction of each single-corner blend and requires it below 0.25. This is the
only gate standing between a plausible-looking table and a map that tiles
wrongly, and it is why the corner test alone is not enough.

**New diagonal-fallback test** — asserts `blend_texture` maps masks 6 and 9 onto
mask 15's texture, and separately that rendering the shipped map never requests
either. The second half is what makes the first half a safety net rather than a
live code path.

**New road-width test** — measures the rendered road's width from the ground
layer and asserts `PATH_HALF_WIDTH` is within a small margin of half of it.
This is what keeps §3's amended tunable honest: if a future re-bake changes the
road's drawn width, the no-build corridor has to follow it or this goes red.

**New atlas test** — `assets/towers.png` is 480×384; every frame referenced by
`data/towers.gd` is non-empty; every frame has clean transparent margins.

**Footprint test** — each prop's blocking radius is within tolerance of its
visible art. This is the test that catches a bake which forgets to trim, and it
is the only automated guard on the §6 defect.

**Renderer tests** — `test_map_renderer.gd`'s ground-texture assertion is
rewritten per §7. Its scatter tests (spike counts, fire caps, the
adjacent-to-walkable direction cases) are texture-agnostic and stay as they are.

**Screenshots** — all three biomes captured through the Godot MCP, plus a read
of the suite's expected stderr. Neither the blend seams nor the mipmap filtering
nor the tower atlas alignment can be seen by any assertion above.

**Reimport gotcha** — new `.import` files require `godot --headless --import`
before the suite sees them, and that reimport scribbles a stray blank line into
`project.godot` under `[autoload]` which must be reverted
(`git checkout -- project.godot`). It will also block a `git stash pop`.

## 11. Deliverable

Branch `feat/kenney-art-swap` off `master`, pushed, left unmerged for Tyler to
merge when he chooses. The suite is green, all three biomes are screenshotted,
and the map 2 / map 3 layouts and progression are explicitly out of scope and
left to a follow-up branch.
