# Claude Handoff — Pause Menu

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/fork-gold`**, off `master` at `1a6830a`. **Complete**, suite
  green at **13,782 checks across 46 files, exit 0**. Nothing pushed or merged.
- Everything before it in this session is merged and deployed.

## This branch

The Fork's `starting_gold` goes **250 → 400**, exactly twice The Pass's 200. The
cost change earlier in the session had narrowed the gap from 2.5x to 1.25x, and
the map is harder than its own comment claimed: both lanes carry the full wave
**and** each lane is only about 59% as long (1,440px and 1,392px against The
Pass's 2,448px), so it is double the threat with less than half the time to
answer it. 400 buys four towers to The Pass's two.

The purse ladder picks the number: 250 through 399 all buy the same three towers
because the fourth costs 135, and nothing buys a fifth until 630.
`test_data_tables.gd` now asserts the **relationship** (2x The Pass) as well as
the literal, so the two numbers stay meaningful together if either moves.

**This one was NOT simulated, unlike The Pass's purse.** `Harness.run_wave`
takes a single path and is one-lane by design; running each of The Fork's lanes
separately with the same towers would have every tower firing down both at full
rate, which over-counts coverage. The number rests on what a purse buys and on
the measured geometry. **Multi-lane harness support is now the biggest hole in
this project's measurement story** — every balance claim about The Fork and any
future two-lane map is currently unmeasurable.

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
