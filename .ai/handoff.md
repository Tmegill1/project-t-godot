# Claude Handoff — Splitting the Wave

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/playable-tiers`**, off `master` at `a7e1c48`. **Complete**,
  suite green at **13,770 checks across 47 files, exit 0**, about 127s against a
  180s budget. Nothing pushed.
- Everything before it this session is merged and deployed.

## What this branch did

Hard and Nightmare killed a building player on **wave 3 of 20**. Both had been
swept only against completed maxed boards. No lever bridged it - not lives (no
effect), not gold, not a bigger purse, not ramping over thirty waves - because a
maxed board is ~10x a full-but-unupgraded one and a tier is one curve across a
run spanning that range.

Owner's decision: **difficulty moves into the build-out.**

| Tier | health | speed | lives | A player who spends |
|---|---|---|---|---|
| Normal | 1.00 | 1.00 | 20 | finishes with 13 of 20 |
| Hard | 1.30 | 1.10 | 15 | finishes with 7 of 15 |
| Nightmare | 1.35 | 1.10 | 12 | dies on wave 13 of 20 |

**The cost, stated plainly: a fully maxed board now wins every tier without
losing a life.** The two shut-out assertions are gone, with their reasoning left
where they were. `test/test_playability.gd` replaced them and asks the same
question of the board a player actually has. The branch-spread bound survived;
its reference wave moved 30 -> 45.

**A mistake worth knowing about:** while reworking those tests I deleted the
branch-spread bound and the per-map placement helpers by accident, and caught it
on the next run. Both are restored. If something looks missing from
`test_balance_tuning.gd`, check `git show HEAD~1` before assuming it was
deliberate.

**Placement is worth more than the tier.** The same run dies on wave 10 clustered
and finishes with 7 lives spread. Both benchmarks recompute placement as the
board grows.

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
