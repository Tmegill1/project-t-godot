# Turret tracking, upgrade legibility, targeting priorities, and board depth

**Date:** 2026-08-20
**Target:** Godot 4.7.1.stable, GDScript, on top of `feat/kenney-art-swap`
**Status:** design approved, ready for planning

---

## 1. What this covers, and why it is two plans

Four features were requested together:

1. Turrets rotate to face the enemy they are shooting.
2. Upgrades produce a more noticeable change to the tower.
3. Towers accept a player-chosen targeting priority.
4. Props gain depth so the board reads as dimensional rather than flat.

They decompose into **three packages**, and the dependency structure is not the
one the feature list implies:

| Package | Contents | Depends on |
|---|---|---|
| **A — Turret split** | base/turret separation, rotation, two-channel upgrade look | nothing |
| **B — Targeting** | `weakest` priority, per-tower setter, inspector picker | nothing |
| **C — Depth** | drop shadows, Y-sorted board | nothing, but touches A's output |

Features 1 and 2 are one package because separating the turret from the base —
which rotation requires — is also the thing that makes a richer upgrade read
possible. §4 explains why.

**Two plans come out of this:**

- **Without the graphics work:** A + B.
- **With it:** A + B + C.

C is a clean append rather than an alternative, so the second plan is the first
plus additional tasks. There is no duplicated content and no divergence to
maintain.

## 2. What is already built

**The targeting system exists in full, and has never been reachable.**
`sim/targeting.gd` implements `first`, `last`, `strongest` and `closest` with
per-priority scoring, a deterministic lowest-id tie-break, and a phasing gate,
all mutation-tested. It also carries a `LABELS` table for a UI and a
`next_priority()` cycler.

But `Tower._priority` (`game/tower.gd:41`) is initialised to
`Targeting.DEFAULT_PRIORITY` and **never written by anything**, and
`next_priority()` has **no production caller** — its only callers are its own
tests. Every tower ever placed in this game has silently used `closest`.

So feature 3 is a UI control and a setter, not rules work. Of the priorities
requested: "first" and "last" exist, "highest health" is the existing
`strongest`, and only "lowest health" is new.

**`to_candidate()` already carries what the new scorer needs.**
`game/enemy.gd:102-107` exposes `health` in every candidate dictionary, so
`weakest` requires no new plumbing between the enemy and the targeting rules.

## 3. What is explicitly not changing

- **`sim/targeting.gd`'s existing scorers, tie-break and phasing gate.** They
  are correct and heavily tested. `weakest` is added beside them.
- **`sim/placement.gd`.** Package C moves prop anchoring, and §7 is how that
  is kept from changing collision. The rule itself is not edited.
- **`ui/tower_panel.gd` and its icons.** The composited `assets/towers.png`
  survives untouched purely to serve the build panel, so the panel needs no
  change even though the in-world tower is now two sprites.
- **`visual_tier`'s meaning** (`sim/upgrades.gd:75-78`): the base still reads
  as total investment across both branches, in four steps. §4 adds a second
  channel rather than redefining the first.
- **Enemy art, audio, map layouts, map progression.** Map 2 and map 3 remain a
  separate branch.

## 4. Package A — turret split, rotation, upgrade legibility

### 4.1 Why the split unlocks the upgrade problem

`sim/upgrades.gd:67-70` records a deliberate constraint: a tower can hold six
tiers, but the sprite shows only four looks, because "six silhouettes are not
readable at tile size." `visual_tier` therefore collapses tiers to four *and*
discards which branch the investment went into — a tier-2 Barrage tower and a
tier-2 Marksman tower are pixel-identical today.

That constraint exists because everything had to fit one silhouette. Splitting
the sprite into a fixed base and a rotating turret creates a second independent
channel, and the two carry different information:

- **Base** — total investment, the existing four-step `visual_tier` read.
- **Turret** — which branch leads, so a maxed Barrage tower visibly carries a
  different weapon from a maxed Marksman one.

The upgrade legibility feature is therefore free once rotation is built, which
is why they are one package.

### 4.2 The atlases, and why the turret is composed rather than cut

`tools/bake_kenney.gd` emits two further atlases at the **same geometry the
existing one uses** — 5 columns × 96px frames, 20 frames, 480×384, row-major —
so `Tower.frame_region` serves all three unchanged:

- `assets/tower_bases.png` — the base plate alone (source tiles 226–229),
  selected by the existing `visual_tier`.
- `assets/tower_turrets.png` — a rotating head, **composed**, not cut.

`assets/towers.png` keeps being baked exactly as it is now. It is no longer
what the in-world tower draws; it exists solely so `ui/tower_panel.gd:68`'s
`icon_for` keeps working unchanged.

**The pack does not ship separable turret heads, and this was verified by
rendering rather than assumed.** An earlier draft of this design claimed every
Kenney turret piece points north and could simply be split out of the existing
composite. That is false, and the three cases behave differently:

| Source | Rotates? | Why |
|---|---|---|
| 251, 252 (bare rockets) | **yes, cleanly** | a barrel pivoting on a static base — exactly right |
| 203–206, 249, 250 | **no** | each carries its own integrated plate, which visibly spins and pokes its corners past the base |
| 245–248 (round modules) | effectively not | rotationally ambiguous, so tracking is invisible |
| 291, 292 (guns) | yes, but point **east** | usable only with a 90° authoring correction |

So the turret atlas is composed in the bake from the bare rocket shapes — the
same technique the endpoints already use — rather than sliced out of tiles that
were never separable.

### 4.3 What the two channels encode

Each composed head carries both signals at once:

- **Branch is colour.** Barrage heads are tinted warm, Marksman cool. The
  values validated in the design mock are Barrage `(214, 88, 74)` and Marksman
  `(86, 140, 214)`, blended at `0.55` against the source sprite so the shape's
  own shading survives the tint. Tint is baked into the atlas rather than
  applied with `modulate` at runtime, so the asset gates can see it and the
  renderer stays dumb about branch identity.
- **Tier band is form, and the form differs per branch in a way that matches
  what the branch does.** Barrage gains a *second* rocket; Marksman's single
  rocket grows *larger*. More shots versus bigger shots, read straight off the
  silhouette.

The base continues to carry total investment in four steps. A maxed Barrage
tower and a maxed Marksman tower therefore share a fortified base and differ
visibly in both colour and weapon — which is the legibility feature's whole
point, and is impossible with one silhouette.

This does change how towers look relative to what `feat/kenney-art-swap`
shipped: the rockets-on-a-plate look is replaced by bare tinted rockets on the
base plate. That is intended. It is also what makes upgrades noticeable.

### 4.4 The one data addition

Rotation alone needs no data change — the new atlases are indexed by the frame
numbers `data/towers.gd` already holds.

Branch-aware turrets do need new data, and this is a correction to what was
implied during design discussion. `data/towers.gd` gains one field per kind
naming which turret frames that kind uses:

```
"turret_frames": {&"sustained": [low_band, high_band], &"burst": [low_band, high_band]},
```

Two frames per branch rather than four, because the base already carries the
fine-grained investment read and the turret only answers "which path, and how
far down it." The implementation plan assigns the concrete frame indices when
it lays out the turret atlas; the shape above is what the table must hold.

`sprite_frame` and `upgrade_frames` are **unchanged**. They keep driving the
base sprite and the panel icon.

### 4.5 Selection and rotation

`sim/upgrades.gd` keeps `visual_tier` and `sprite_frame_for` as they are, and
gains `turret_frame_for(kind, tiers)`: it picks the leading branch by purchased
tier count, breaks a tie toward `sustained` (the first entry in
`Upgrades.BRANCHES`, so the tie-break is stable rather than arbitrary), and
selects the band from that branch's tier count.

`game/tower.tscn` gains a `Turret` sprite above the existing sprite, which is
renamed `Base`. `Tower._refresh_visuals` sets both textures.

Rotation lives in `Tower.tick`, which already resolves a target every physics
tick via `Targeting.select`. When a target exists, the turret's rotation is set
to the angle from the tower to it. When none does, the turret **holds its last
angle** rather than snapping back to north — a tower that whips to a default
between shots reads as broken.

Rotation is instantaneous rather than eased. A traverse speed is a tuning
lever, and adding one now would mean the turret can be aimed somewhere the shot
did not come from, which is a worse lie than instant traverse.

## 5. Package B — targeting priorities

### 5.1 The rule

`sim/targeting.gd` gains `&"weakest"`, scored `-health`, beside the existing
`strongest`. `PRIORITIES` becomes five entries and `LABELS` gains "Lowest
Health"; `strongest`'s label becomes "Highest Health" so the pair reads as a
pair.

**Insertion position is load-bearing, and chosen so nothing existing changes.**
`next_priority()` cycles `PRIORITIES`, and `test_next_priority_cycles` asserts
`first → last` and `closest → first`. Placing `weakest` directly after
`strongest` keeps `closest` last, so both assertions still hold and **no
existing test is edited**. Appending it instead would break the wrap assertion
and force a change that is indistinguishable from weakening a test. The
cycle-completeness test already walks `PRIORITIES.size()` and adapts either
way.

### 5.2 The control

`Tower` gains `set_priority` and `get_priority` for the field that has been
read-only since it was written. `GameBoard` gains a pass-through mirroring the
existing `upgrade_selected_tower`, so the inspector talks to the board rather
than reaching into a tower.

The inspector picker is **a single button that cycles**, not five buttons and
not a dropdown. `ui/tower_inspector.gd:90-96` carries a hard-won warning: the
sidebar is 140px, a `Label` reports its longest line as its minimum width, and
the panel once grew 37px out over the map before that was measured. Five
side-by-side controls would reintroduce exactly that. A cycling button is also
what `next_priority()` was written for and never used by.

The button shows the current priority's label and advances on press. It carries
`MIN_TAP_SIZE` like the other rows.

Priority is per-tower, set on the selected tower, and survives upgrades and
re-selection. There is no save system, so it needs no persistence.

## 6. Package C — depth

### 6.1 Layering

Today only `game/map_renderer.gd:124` sets a z-index in code: ground −1, props
and endpoints +1. `$Towers` and `$Enemies` set none, so both sit at the default
0. (`game/game_board.tscn:21`'s `z_index = 2` belongs to `PlacementPreview`,
not to the towers — an earlier draft of this section misread it.)

The consequence is that **props currently draw above both towers and
enemies**: a tree covers a tower standing beside it, and an enemy walking past
one, whatever their positions, because z-index beats position and nothing
sorts.

The new model:

- **Ground stays at z −1**, unsorted, always behind. The lattice and its
  half-tile offset are unaffected.
- **Props, endpoints, towers and enemies move to a shared z 0**, and their
  containers enable Y-sorting so they interleave by position.

### 6.2 The assumption this rests on

Godot 4 is documented to merge a `y_sort_enabled` child container's children
into its parent's sort, which would let `MapRenderer`, `$Towers` and `$Enemies`
interleave without being reparented into one node.

**This was probed and only partially confirmed.** The API surface
(`y_sort_enabled`, `is_y_sort_enabled`) exists on this build, but draw order is
a rendering-server detail and is not observable from the scene tree, so the
interleaving itself was not verified. The implementation plan's first depth
task must verify it in the running game — place an enemy above and below a prop
and look — before anything is built on it.

If it does not hold, the fallback is reparenting props, towers and enemies
under a single Y-sorted node. That is a larger change to `game_board.tscn` and
to how the board finds its children, and it is the reason this is a gate rather
than an assumption.

### 6.3 Sort anchoring, and the collision coupling

Props are placed with `centered = false`, so `position` is the sprite's
top-left. Y-sorting on that value would sort a tall tree as though it stood
where its canopy is, which is wrong in the direction that looks worst: tall
props would sort behind things they should occlude.

Props therefore need to sort by their **base**, not their top-left.

**This is load-bearing for collision, not only for looks.**
`MapRenderer.prop_footprints()` derives each blocking circle's centre from
`sprite.position` plus half its displayed size, and `sim/placement.gd` refuses
tower placement against those circles. Any change to prop anchoring moves the
collision geometry with it.

This is the third time on this codebase that art and collision have turned out
to share a coupling — untrimmed prop footprints and the road-width corridor
were the first two. It is therefore pinned by a test rather than trusted: prop
footprint positions and radii must be **identical before and after** the
anchoring change, captured as explicit expected values.

### 6.4 Shadows

Each prop, tower and enemy gains a shadow drawn beneath it as a child, so the
shadow sorts with its owner rather than needing its own layer. A single soft
ellipse texture, scaled to the owner's footprint and offset to its base, is
enough — the art is flat vector and a matched silhouette would read as heavier
than the style supports.

Enemies get one too. A shadow that appears under scenery but not under moving
units makes the units look pasted on.

## 7. Testing

Beyond the per-task tests each package carries, four properties get explicit
gates because they are the ones that fail silently:

**Turret angle matches the target.** A tower with a known target at a known
offset has a turret rotation equal to the angle between them. This is what
catches a sign error or a degrees/radians mix-up, neither of which any other
test would see.

**The turret holds its angle when no target is in range.** Asserted directly,
because "snaps north between shots" is the failure mode a reviewer would
otherwise have to notice by eye.

**Prop footprints are unchanged by the Y-sort anchoring.** Expected positions
and radii captured before the change and asserted after. §6.3 is why.

**A maxed Barrage tower differs from a maxed Marksman tower.** The upgrade
legibility feature's whole point, and it is invisible to every other assertion
in the suite — both towers have identical stats-resolution paths and identical
base frames.

The 10 z-index assertions in `test_map_renderer.gd` are rewritten as layering
assertions in **package C only**. Packages A and B leave them alone.

Package C also ends with a screenshot pass, per this project's standing rule
that a green suite sees neither layout nor draw order: an enemy walking past a
prop, and a maxed tower of each branch side by side.

## 8. Branching

This work depends on `feat/kenney-art-swap`, which is pushed and unmerged: the
turret split rebakes atlases that branch produced, and the depth work sorts the
props it introduced.

The new branch is cut from `feat/kenney-art-swap` rather than `master`. If the
art branch is merged first, the new branch rebases onto `master` cleanly; if it
is not, the two stay stacked in order. Either way the dependency is honoured
and no work is duplicated.
