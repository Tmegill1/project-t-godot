# Claude Handoff — Splitting the Wave

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`fix/unclickable-tower-palette`**, merged to `master` as `afd4b8e` on
  the owner's instruction. Both branches pushed; the Pages deploy succeeded.
  Suite green on the merged result at **13,772 checks across 47 files, exit 0**.
- **Nothing is in flight.** Everything in this session is merged and deployed.

## The single most useful thing to do next

**Play one run.** It is now possible - it was not, until this branch. Everything
else on the open list is measured, documented and can wait behind twenty minutes
of somebody actually holding the thing.

## The game could not be played with a mouse, and this fixes it

Driving the real game through its own input for the first time - rather than
through the harness - found the build palette **completely unclickable**.
`TowerInspector`'s root is a full-column Control, always visible (only its Rows
child toggles), with no `mouse_filter` - so it defaulted to STOP and swallowed
every click meant for the palette. It shipped that way with `ce41a08`.

Proven with an A/B/A on identical coordinates: STOP -> nothing, IGNORE ->
`basic` selected, STOP -> nothing.

**Why 13,772 assertions missed it:** the existing test asserted the palette's
visibility flag flips, which it always did. Nothing checked the node doing the
covering - **it watched the node that hides, not the node that hides it.**

Three fixes, all verified:

1. `TowerInspector` root is `MOUSE_FILTER_IGNORE`. **Do not tidy this back to
   the default.** Its own buttons are picked independently and still work.
2. `test_nothing_drawn_over_the_palette_can_swallow_its_clicks` asserts no
   sibling drawn above the palette is both visible and mouse-stopping - written
   generally, and **verified by reverting the fix and watching it fail**.
3. `GameBoard._world_of` reads the event position instead of
   `get_global_mouse_position()`. Identical for a person; the global position is
   the OS cursor, so synthesised clicks could never place a tower - which is why
   placement had never been exercised end to end.

**Verified live after the fix:** two real clicks place a Basic (gold 200 -> 165);
clicking it opens the inspector; clicking the upgrade row buys the tier (gold
165 -> 135, fire rate 1000 -> 800) and the generated summary updates from "fires
0.2s faster" to "fires 0.16s faster".

Also confirmed working live: difficulty selection (20/15/12 lives), the whole
wave loop, the pause menu, and **Retry preserving map and difficulty** - the fix
from the day before, until now only tested headlessly.

**Still unreachable by any automation here:** art, animation, audio audibility,
projectile flight, victory -> next-map chaining, touch. Screenshots are blank on
this machine (`glx: failed to create dri3 screen`).

## Standing rules that govern this work

- Run the suite with `godot --headless --quit --script test/run_tests.gd`.
  **Exit code 0 is the only pass signal**; a green run prints many `SCRIPT ERROR`
  lines to stderr by design.
- Every `test_*` method is declared `-> bool` and ends with `return true`,
  including every early return. Enforced crash detection, not style.
- `data/` and `sim/` are pure — `test/test_sim_purity.gd` bans scene types,
  clocks, RNG and platform state.
- **Adding a new `class_name` needs `godot --headless --import`** before the
  suite will see it. That pass also writes the `.uid`; every other `.gd.uid`
  here is tracked, so commit it with its script.
- **NO NEW ASSETS.** Owner's standing rule: if any visual, audio, animation,
  sprite, texture or icon turns out to be needed, stop and return to Codex.
- **No invented numbers.** Three misses this week came from figures written down
  before they were measured. Sweep, then pin.
- Do not commit `test/test_balance_tuning.gd.uid`. `git status` before every
  commit, stage only what the step names, never `git add -A`.
- **Pushing `master` redeploys the live site.** Do not push without the owner
  asking. They have asked three times so far, each time explicitly.

## Two findings still open, recorded in `update.md`

- Enemy health cannot give the opening a pulse — a Basic tower deals exactly 4,
  so a goblin at 5 through 8 dies to the same two shots, and at 9 wave 1 starts
  leaking rather than lasting longer. The lever is the Basic tower or wave 1's
  composition.
- The two new upgrade summary labels in the inspector have never been seen on
  screen. Tests cover them and the panel height was measured two ways, but the
  in-game check failed because the Godot MCP bridge cannot marshal a Dictionary
  into a `Vector2`. Drive it with `game_click` on real coordinates instead.
