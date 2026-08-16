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
| Tilesheet | 1472×832 = 23 cols × 13 rows of 64px, row-major, index = tile number |
| Licence | CC0 (`License.txt`, vendored) |

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
- **Props are free-standing with large transparent margins.** `tile131` (bush)
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
- **`Tiles.TILE_SIZE`, which stays 48.** The pack is 64px and the Retina set is
  128px, but moving to a 64px grid would resize the canvas from 1104×672 to
  1472×896, move the tower panel (`ui/tower_panel.gd:30` offsets by the map's
  pixel width), and invalidate `MIN_TOWER_SPACING = 44` and
  `PATH_HALF_WIDTH = 26` — the free-placement tunables that were chosen to
  preserve the old feel. There is no visual gain: we downscale from 128px
  sources either way.
- **`sim/economy.gd:42`'s `limit_bonus_map2`.** It stays dormant until a second
  map exists to trigger it.

## 4. The biome layer

### 4.1 `data/biomes.gd`

A new data table in the same shape as `data/towers.gd` and `data/enemies.gd` —
a `DEFS` dictionary, a `KINDS` array, a `get_def` accessor. Each biome names
six textures:

```
&"forest": ground grass,  road dirt,  props: bush / rock / shrub / flame
&"ice":    ground snow,   road stone, props: crystal / rock / shard / flame
&"desert": ground sand,   road dirt,  props: desert-shrub / rock / small-bush / flame
```

The four prop slots keep their existing names — `tree`, `stone`, `spike`,
`fire` — because `MapRenderer`'s scatter rules are written in those terms and
none of those rules change. Only the texture behind each name does.

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
turrets 204–207 and 246–253.

Towers are **not** biome-themed. They are player objects rather than scenery,
and a tower that changed appearance per map would read as a different tower.

## 6. Props, and the footprint bill from free placement

`MapRenderer.prop_footprints()` (`map_renderer.gd:70-84`) derives each prop's
blocking radius from **the texture's full dimensions** times the sprite scale.
Its doc comment justifies deliberately over-covering: "blocking slightly too
much reads as level design, while a tower clipping into a rock reads as a bug."

Kenney art breaks the "slightly". The bush `tile131` occupies 62×62 of a
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

`_draw_ground()` gains a **4-bit corner mask** per tile: for each of the tile's
four corners, is the terrain there road or ground? The 16 resulting masks map
onto 16 tiles per biome (mask 0 is pure ground, mask 15 is pure road, the other
14 are blends).

**The mask→tile table is derived by script, not transcribed by hand.** The bake
tool samples each candidate tile's four corner regions, classifies each against
the four measured terrain colours in §2, and emits the table. 299 hand-copied
indices would be unverifiable and wrong somewhere; a derivation is re-runnable
per biome pairing and can be re-asserted from the committed PNGs in a test.

**Blend tiles are baked as individual PNG files**, one per mask per biome, not
as regions of a runtime atlas. This is forced by
`test_map_renderer.gd:54`, which identifies ground textures by
`Texture2D.resource_path` — its header explains that reading `resource_path` is
what keeps those tests dependent only on public state. Individual files preserve
that, and they also keep `_place`'s `texture.get_width()` arithmetic honest.

That test's assertion has to change in kind: "path tiles use `path.png`" becomes
"this tile's texture is classified road-side-correct for its mask". The
one-sprite-per-tile invariant it also guards is unaffected.

## 8. Endpoints, and the ice recolour

### 8.1 Endpoints

The pack has no castle and no cave. Two PNGs are baked from pack pieces: the
goal as a fortified base built from structure tiles 227–230, 250 and 269; the
spawn as a dark rock mouth from boulders 136–138. `_draw_endpoints()` changes
only which texture it loads — the 3-tile width, the `(-TILE_SIZE,
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

Only the ~16 tiles of one pairing need it, because a biome uses only its own
ground, road and the blends between them.

Ice props need no recolouring at all: tiles 181–183 are already pale-blue
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
