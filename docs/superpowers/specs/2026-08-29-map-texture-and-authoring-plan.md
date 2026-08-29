# Making the map look fleshed out, and authoring new ones

**Date:** 2026-08-29
**Status:** plan, not yet approved

---

## Part A — why it still reads as a grid

Prior art matters here: the ground already draws at **one of four orientations
from six variants per biome**, which cut the periodicity 61%, and
`TILE_BLEED` already crops the painted card border so the board is not
literally cards in gutters. Those were the right fixes and they are done. What
remains is a different problem.

**The dominant cause is that every prop sits on the 48px lattice.**
`MapRenderer._place` positions every sprite at
`col * Tiles.TILE_SIZE + offset + slack`. Trees, stones, spikes and fires are
all pinned to cell origins, so even with perfect ground the *objects* draw a
grid. Nothing in the scene ever crosses a cell boundary.

Ranked by how much each contributes, and how cheap it is to fix:

| # | Cause | Fix | Effort |
|---|---|---|---|
| 1 | Every prop centred on its cell | Jitter position within the cell, allow overhang | tiny |
| 2 | Every prop of a slot is identical — same texture, scale, orientation | Per-instance scale jitter, rotation, horizontal flip | tiny |
| 3 | Nothing crosses a cell boundary | A sparse **detail layer** placed in world space, not per cell | small |
| 4 | Decoration density is uniform-random | Cluster it — pick seed points and scatter around them | small |
| 5 | The road silhouette is geometrically perfect | Verge props straddling the road/ground edge | small |
| 6 | No large-scale variation — nowhere is rockier than anywhere else | Low-frequency noise driving local density | medium |

### A1. Jitter prop position *(biggest win, smallest change)*

`_place_prop` gains a per-prop offset drawn from the decoration RNG, up to
roughly a third of a tile in each axis. Props may then overhang their cell,
which is what breaks the lattice.

**This changes where the player can build.** `prop_footprints()` feeds
`Placement.can_place`, and it derives a blocking radius from displayed size and
position — so a jittered prop blocks a jittered spot. That is correct and is
the rule the free-placement work already established (*what blocks you is what
you can see*), but it means every placement test that assumes a prop is at a
cell centre has to be re-derived rather than nudged.

### A2. Vary each instance

Scale jitter of roughly ±15%, a small rotation, and a horizontal flip. Trees
and stones take rotation happily; **fire should not rotate** — flame art has an
up direction — and the road must keep its existing no-flip rule, because a
mirrored piece draws a north-east corner where the mask says north-west.

Scale jitter interacts with footprints for the same reason as A1.

### A3. A detail layer that ignores the grid

A new, **non-blocking** layer of small sprites — tufts, pebbles, cracks —
scattered in continuous world space rather than per cell, deliberately
straddling boundaries. Two rules make it safe:

- It is **never recorded in `_prop_sprites`**, so `prop_footprints()` never
  sees it and it changes no placement rule. Decoration only.
- It draws **below** the props and above the ground.

This is the piece that most directly answers "the ground reads as tiles",
because it is the only thing in the scene that will span a seam.

**It needs art that does not exist yet.** The illustrated sheet has no small
detail pieces; `tools/bake_sheet.gd` would need a new row, or the detail could
be cut from existing props at small scale as a placeholder.

### A4. Cluster the scatter

`_scatter_decoration` currently shuffles all buildable tiles and takes the
first 10% for spikes, then up to 7 fires from path-adjacent tiles. Uniform
random *looks* random and reads as noise; real terrain clumps.

Replace with: pick a handful of seed cells, then scatter around each with
falling probability by distance. Same counts, different distribution.

### A5. Break the road edge

Props placed deliberately on the boundary between road and ground — a stone
half on the verge, grass overhanging the edge. The road's 16-mask silhouette is
currently perfect and reads as vector art laid over terrain.

### A6. Large-scale variation *(optional, most work)*

Low-frequency value noise over the map deciding local decoration density and
which ground variants are preferred, so one corner is rocky and another is
open. This is the difference between "randomly scattered" and "a place".

Must go through `sim/rng.gd` to stay reproducible — the project bans engine RNG
outright, and a map that renders differently per run breaks the golden-board
tests.

### What Part A does *not* touch

Tile size, the pathfinder, the edge-mask road system, or `data/`'s tile arrays.
This is entirely `game/map_renderer.gd` plus new art. The rules layer never
learns that the map got prettier.

---

## Part B — authoring new maps

### The problem today

A map is **GDScript**: `data/demo_map.gd`, `map2.gd`, `map3.gd` are algorithmic
builders that push path coordinates and scatter blocked tiles. Adding a map
means writing code, and the shape of the map is not visible in the source.

### Recommendation: the format first, the editor second

The valuable half is a **plain-text map format**. It is the contract; an editor
is sugar on top of it, and every hour spent on the format pays off whether or
not the editor ever gets built.

**The format:** one character per tile, one line per row.

```
#############################
#...........................#
S=========================..#
#........................=..#
#........................=..#
#....#####...............=..#
#........................=G.#
#############################
```

`S` spawn · `G` goal · `=` road · `.` buildable · `#` blocked

**Why plain text:**
- Editable in any text editor, immediately, with no tool at all
- Diffable in git — you can *review* a map change
- Trivially parseable, and the parser is a pure function that belongs in `data/`
- It is the same thing the editor would read and write, so neither depends on
  the other existing

**One wrinkle, already checked:** `export_presets.cfg` has
`export_filter="all_resources"` and `include_filter=""`, so a `.txt` under
`res://` would **not** be packed into a web build. Either add `*.txt` to
`include_filter` (one line, but verify in a real export — this project's own
history says assume nothing about export behaviour), or store each layout as a
`const` string inside a small `.gd`, which is always packed and needs no
export change. The second is uglier and certain; the first is cleaner and needs
one verification.

### Then the editor

A scene under `tools/` — GDScript, no addon, no third-party dependency, and
`tools/` is already excluded from the export so it cannot bloat the shipped
build. It would:

- draw the grid and let you paint tile types with the mouse
- validate live: exactly one goal, at least one spawn, every spawn reachable
  (it can call the real `PathFinder`, which is the point of it living in-repo)
- save the text format, and load it back

**Validation is the feature that earns it.** A map with an unreachable goal or
two goals is currently something you discover by running the game; the editor
can refuse to save it, using the same pathfinder the game uses.

### Alternatives considered

- **Tiled** (the standard external map editor). Genuinely good, exports JSON,
  and would work. Rejected as the primary route because it adds an external
  authoring dependency to a project whose stated rule is *GDScript only, no
  addons, no external dependencies* — and because its tile-property model is
  far richer than five characters need.
- **A Godot `EditorPlugin`.** Better integrated, but it is an addon under
  `addons/`, which the same rule excludes.
- **Painting a PNG** where colour means tile type. Zero new tooling and works
  in any paint program, but a 28×16 map is 28×16 pixels — fiddly to author, and
  not diffable.

### The fork worth deciding before any of this

**Do the three existing maps migrate to the new format, or does the format sit
alongside the builders?**

- **Migrate** — one way to define a map, and the text file is the truth. But
  `DemoMap`, `Map2` and `Map3` each have golden-board tests pinning their exact
  output, including the seeded blocked-tile scatter. Migration means either
  reproducing that scatter exactly in text (possible — bake it once and paste
  the result) or re-pinning all three.
- **Alongside** — new maps are text, old ones stay code. No migration risk,
  but two ways to define a map forever, and the older, worse one is the one
  with all the examples.

I would migrate, and bake the existing scatter into the text rather than
re-pinning. But it is the decision that changes the size of the work, so it is
yours.

---

## Suggested order

1. **A1 + A2** — prop jitter and per-instance variation. Half a day, biggest
   visible change, no new art.
2. **A4 + A5** — clustered scatter and road-edge breaking. Still no new art.
3. **B format + parser + one hand-authored map.** Proves the pipeline end to
   end and gives you a way to make maps immediately.
4. **A3** — the detail layer, once there is art for it.
5. **B editor.** Once the format has earned its keep.
6. **A6** — large-scale variation, if it still feels flat after the rest.

Steps 1 and 2 are the ones that answer *"it looks like a grid"*. Step 3 is the
one that answers *"I want to make maps"*. They are independent and can be done
in either order.
