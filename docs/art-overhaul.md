# The art overhaul, and why each change was made

A record of the work that replaced every asset in the game and then fixed what
that broke. Written for whoever picks this up next, including the owner.

Everything below is on `master` and deployed to
<https://tmegill1.github.io/project-t-godot/>.

The short version: the game's art moved from a flat vector pack to a single
illustrated sprite sheet, then to a second sheet that added real animation.
Almost every problem along the way came from assuming something about the art
instead of measuring it, and almost every fix came from rendering the result
and looking at it.

---

## 1. Where this started

The game was drawn with Kenney's flat vector tower-defense pack. It worked and
it was legible, but it was placeholder art. The owner supplied an illustrated
sheet and asked for everything to be replaced from it.

"Everything" turned out to mean: ground tiles and road pieces for three
biomes, a sixteen-level tower atlas, enemy sprites, scatter props, and the
markers at each end of the path. One bake tool, `tools/bake_sheet.gd`,
generates all of it from the sheet, and re-running it reproduces every
committed PNG byte for byte. That property is checked, and it is what makes
the art reproducible rather than a pile of files someone once exported.

---

## 2. The illustrated art swap

### Reading the sheet rather than guessing at it

The single most useful thing about the sheet turned out to be its **labels**.

The tower band is four panels — Archer, Cannon, Mage, Barracks — each with a
heading and with "LVL 1" through "LVL 4" written under the four towers. The
towers themselves cannot be separated by looking for gaps: the Mage and
Barracks towers touch, and a gap-based cut finds only two of the four mages
and one of the four barracks. **The captions can be separated.** They segment
into exactly four clean runs in every panel, each centred over its tower, so
the cut was made on the captions and the towers came along with them.

Two earlier attempts read the tower positions off the image by eye. Both were
wrong — one by up to 19 pixels, and both misplaced the whole Archer panel by
about 15. That pattern held throughout the project: **every value measured
survived, and every value read off an image failed.**

### The upgrade read

Each tower kind has four levels, and the point of drawing four is that the
player can see their tower get stronger. The first bake fitted each level
independently to its frame — and that destroyed the effect. A level that grows
taller faster than it grows wider absorbs the extra height into a smaller
scale factor and comes out *smaller on screen* than the level below it.

All sixteen towers now share **one** scale factor, taken from the largest of
them. The sheet already draws every tower at one world scale — the four kinds'
own fit factors land between 0.60 and 0.66 — so a single factor is both
simpler and truer to the art.

### Roads

The sheet ships one road "cross" per biome, not a set of connection pieces. An
early plan tried to classify the row's pieces into corners, straights and
junctions; probing it returned only three distinct shapes, both "curves" read
as the same T-junction, and one needed piece was unreachable entirely. The
demo map has four corners, so that approach could not draw the map.

Instead **all sixteen connection masks are composed from the cross**, by
masking each absent arm with material taken from an adjacent corner. That is
one technique instead of a classification scheme, and it cannot run out of
pieces.

The desert road is deliberately darker than the sheet's own dirt. Measured,
the sheet's dirt and its sand sit 15 units apart while the dirt's own shading
spread is 18 — the two materials are closer together than either varies, so
the recolour cannot tell them apart, and a dirt road on sand would have been
invisible anyway. Darkening it restores 83 units of separation.

### Enemies, first attempt

The sheet's enemy rows are **variants, not animation**. That was measured
twice rather than assumed: a real walk cycle's frame-to-frame difference
varies with lag and dips as the cycle closes, and these rows are flat at every
lag; and registering consecutive sprites on the head shows the *head* moving
more than the legs, because the helmets, shields and weapons differ.

So the rows are fifteen different goblins, not one goblin walking. They were
used for per-spawn variety, and motion was synthesised. Section 4 explains why
that was later thrown away.

### What the first rendered board looked like

Bad. Two defects dominated it, neither visible to any test:

**Every tile was drawn with its card border.** The sheet's terrain tiles are
cards with a painted dark scalloped edge. Drawn whole, every cell boundary
carried two of those edges back to back and the map read as a grid of cards in
black gutters. The renderer now crops 6 pixels from each tile edge —
`MapRenderer.TILE_BLEED` — measured as the widest near-black run reaching in
from any edge across all 66 ground and road PNGs, plus one.

**Every composed road piece had black slots cut through it.** The function
filling an absent arm copied an adjacent corner of the cross, and that corner
carries the card's dark border on its own outer edges — so the copy dragged a
near-black stripe into the middle of the tile. Tiled up it read as a bar
across the road at every cell boundary. The function's own comment had always
claimed the patch was mirrored; the code clamped instead. It mirrors now, and
never samples the border at all.

Both were found by composing the board and looking at it. Neither would ever
have gone red.

### The no-build corridor

`Placement.PATH_HALF_WIDTH` is the radius around the path inside which a tower
may not be built. It exists so players cannot build on painted road.

The plan said the new road would be "roughly 48px" wide and the corridor would
go back up. That was wrong: measured on the shipped art in all three biomes,
the road draws 22 source pixels of 66, which is **16 world pixels** — narrower
than the Kenney road it replaced, not wider. The corridor went **down**, from
14 to 11.

---

## 3. Making it playable

Four changes came from the owner watching the game.

### Towers draw at 2.4× their footprint

On the first rendered board the player's own towers were the least prominent
thing on it. A tower drew about 19 × 26 pixels against 44-pixel bright orange
campfires and 48-pixel trees.

Measured, **the towers had not shrunk** — the Kenney basic tower drew 20 × 22
and the illustrated one 19 × 26. What changed was everything around them: flat
vector props became painted ones. So this is a display-only multiplier.
`Placement` still reads the tower's `size` field directly, which means the
no-build corridor, the prop clearances and the tower-to-tower spacing are all
exactly what they were. There is a test whose only job is to fail if someone
merges the two back together.

Campfires were separately reduced to 80% of a tile for the same reason. Their
blocking footprint shrank with them, deliberately: this codebase derives a
prop's no-build radius from what it draws, so holding the footprint while
shrinking the art would have manufactured an invisible wall.

### Mute and volume

`AudioManager` had a `set_muted` flag with **no production caller**. It has a
button now, plus a volume slider driving the master bus so it moves sounds
already mid-playback. Muting and volume are independent: adjusting the slider
while muted gives you that level back when you unmute.

### Targeting priorities

The same story, worse. `sim/targeting.gd` had implemented and tested every
targeting priority for a long time, and `Tower._priority` was **never written
by anything** — so every tower in the game targeted identically and the whole
feature was unreachable. A cycling row in the tower inspector now sets it:
Closest → First → Last → Highest Health → Lowest Health.

It is one cycling button rather than five buttons or a dropdown because the
sidebar is 140px wide and a `Label` reports its longest line as its minimum
width; an earlier version pushed the column 37px over the map.

---

## 4. Real animation

The owner supplied a second sheet with drawn walk and death cycles, and chose
**animation over variety** knowingly — the two sheets cannot give both.

Before building anything on it, the same cycle test from section 2 was run
again. It reported "not a cycle" for four of the five rows, which was a **false
negative**: the test was built to separate different creatures from the same
creature, and here the creature is identical and only the pose changes, so it
was measuring registration error on a large high-contrast head. Rendering the
frames side by side settled it in seconds. All five rows are genuine cycles.

Eight walk frames and four death frames per creature. The variant system was
removed rather than left unwired.

**The bat walks on seven frames.** Its eighth came off the sheet as an
orphaned wing with no body. The bake drops broken art by **area** rather than
by index, so if that row is ever regenerated the good frame returns without
anyone having to remember a hard-coded skip.

Two things stayed and one thing went:

- **The cycle is indexed by distance travelled, not elapsed time.** This was
  the fix that made the synthesised motion read as running rather than
  sliding, and drawn frames need it just as much: a timed cycle moves a 60px/s
  ogre's legs at the same rate as a 150px/s bat's, and keeps both walking on
  the spot while they are held up.
- **The synthesised bob, squash and lean went.** The artist drew all three into
  the frames, and synthesised motion on top of drawn motion fights it.

### The bug the owner caught

Death frames drew **2.1× larger** than the walking creature. `apply_sprite_height`
divided the declared height by *each frame's own* height, which is only
sensible while the creature is upright — a death sequence ends lying down, so
its last frames are short, and dividing by a short height scaled them up. A
fallen goblin drew 100px wide against 35 walking; a fallen ogre 147 against 57.

The scale is now taken once, from the standing frame, and every frame is drawn
at it, with a vertical offset keeping each frame's bottom on one line so a
falling creature settles where its feet were.

A structured review of that branch had looked at this code and called it safe.
It was not. The owner watching the game caught it.

---

## 5. The grid look

The board still read as a grid, and the cause was not what it looked like.

**It is not the seams.** Measured on the composed board, the luminance step
across a tile boundary is *no larger* than the step inside a tile — 12.76
against 12.95. There is no edge discontinuity to remove.

**It is periodicity.** Six ground cards over 322 cells put the same picture
down about 54 times. The ground's self-similarity at a lag of exactly one tile
sits **+55.8** above its neighbouring lags, and that periodic signal is what
the eye reads as a grid.

Each ground tile is now drawn at one of four orientations, turning six cards
into twenty-four and cutting the excess to **+22.0 — a 61% reduction**, at no
cost to the art. Road pieces are excluded: their art is chosen by an edge mask,
so mirroring one draws a north-east corner where the mask says north-west.

Two alternatives were measured and rejected:

| Approach | Result |
|---|---|
| Normalise each card's mean colour toward the biome's | Moved periodicity from +22.0 to +22.6 — noise — and would have flattened the deliberate dirt patches |
| Cross-fade the tile edges | Cut the variation *inside* a tile by 42%: softening the grass, not fixing the grid |

**What cannot be fixed this way:** true flow, where a grass stroke continues
across a tile boundary, needs tileable art. These are cards. Mirroring hides
the repetition; it cannot make the strokes line up.

---

## 6. What is still open

See `CONTINUE.md` §9 for the full list. The ones that matter:

- **The HUD's white text is illegible on the ice and desert biomes.** Confirmed
  live in both. Needs a backing plate, a shadow or a per-biome tint — a design
  call rather than a bug fix.
- **`data/maps.gd` hardcodes the one map to forest**, so two thirds of the
  baked art is unreachable in game.
- **Audio settings do not persist** between runs. There is no settings file in
  this project yet, and inventing one for two values is a bigger decision than
  it looks.
- **Turret rotation** is still wanted and still unbuilt. Tasks 4–7 of
  `docs/superpowers/plans/2026-08-20-turret-tracking-and-targeting.md` are dead
  — they bake turret atlases with a tool the art swap deleted — and the
  illustrated towers are drawn as single pieces rather than a separable base
  and turret, so it needs re-planning.
- **The Goblin Shaman and Troll** are fully baked with walk and death cycles in
  `assets/art/enemies/_unused/`, referenced by no code, waiting on stats and a
  wave schedule.

---

## 7. Two things that will bite the next person

**`reference/` is git-ignored.** Both sprite sheets live there and neither is
tracked. Only the baked PNGs are committed, so the bake cannot be re-run from a
fresh clone without the sheets being put back by hand.

**Running the game rewrites `project.godot`.** The tool used to drive and
screenshot the game injects an `McpInteractionServer` autoload pointing at an
untracked script. It was committed twice during this work and reverted twice.
Never `git add -A` in this repo — stage paths explicitly, or check
`project.godot` before every commit.
