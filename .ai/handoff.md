# Claude Handoff — Difficulty Selector

Generated: 2026-08-29 (America/Chicago). **Live document — rewritten at the start
and end of every task so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/difficulty-selector`**, branched from `master` at `b714159`.
- Nothing pushed. `master` is unchanged; pushing `master` redeploys the live site,
  so do not push without the owner asking.
- Plan: `docs/superpowers/plans/2026-08-29-difficulty-selector.md` (11 tasks)
- Spec: `docs/superpowers/specs/2026-08-29-difficulty-selector-design.md`

## Task progress

| # | Task | State |
|---|---|---|
| 1 | Measure what a run can afford | ✅ done — `Measure what a run can actually fund` |
| 2 | The difficulty table | ✅ done — `Add the difficulty tier table` |
| 3 | `Waves` takes a tier | ✅ done — `Let a wave be built at a difficulty tier` |
| 4 | The harness accepts a tier | ✅ done — `Run a harness wave at a difficulty tier` |
| 5 | Teach the harness where enemies died | ✅ done — `Teach the harness where enemies died` |
| 6 | The live board runs at a tier | ✅ done — `Run the live board at the chosen difficulty` |
| 7 | The menu selector and the HUD readout | ✅ done — `Choose a difficulty before a run, and show it during one` |
| 8 | Sweep the tiers and set their numbers | ✅ done — `Set the Hard and Nightmare rows from a measured sweep` |
| 9 | Give the opening a pulse | ⚠️ **done as a finding, no value changed** |
| 10 | Benchmark the board the game actually hands out | ✅ done — `Benchmark the full twelve-tower board, not half of it` |
| 11 | Update the docs | ✅ done — `Bring the docs up to the difficulty selector` |

## Task 9 did not raise base health, and the owner should know why

**This is the one part of the plan that did not land as written, and it is a
finding rather than a shortcut.** Task 9 asked for a base-health bump so wave 1
lasts longer than a few seconds. Its spec bound that bump by two constraints:
the roster ordering `ogre > shaman > goblin > bat` must survive, and wave 5
against three ungraded Basics must not cost *more* lives than it already does.

Swept on 2026-08-30 against exactly the board 100 starting gold buys — three
ungraded Basics at 20 + 30 + 40:

| ogre / shaman / goblin / bat | wave 1 | wave 5 |
|---|---|---|
| 10 / 7 / 5 / 3 *(shipped)* | 5.6s, 0 leaks | 21 lives |
| 10 / 7 / 6 / 4 | 5.6s, 0 leaks | 21 lives |
| 10 / 7 / 6 / 5 | 5.6s, 0 leaks | 23 lives |
| 12 / 9 / 8 / 5 | 5.6s, 0 leaks | 25 lives |
| 14 / 11 / 9 / 6 | 26.8s, **2 leaks** | 33 lives |

Two things fall out, and together they close the door:

1. **Wave 1 does not move until goblin health crosses 8.** A Basic tower deals
   exactly 4, so a goblin at anything from 5 to 8 dies to the same two shots.
   At 9 it needs three — and wave 1 stops being a walkover by *leaking*, not by
   lasting longer. There is no value in between. The opening is quantised by
   the Basic tower's damage, not tuned by hit points.
2. **Every value that changes anything makes wave 5 cost more**, which is
   exactly the constraint saying the opening cliff must not steepen.

The two constraints cannot both be met, so no number moved. The spec's own risk
section says this is a finding to bring back rather than something to fix by
quietly retuning Normal, so that is what happened: the sweep is recorded above
`Enemies.DEFS`, and `test_balance_tuning.gd` now pins the shape it failed to
move — wave 1 is a zero-leak walkover decided before the first bend, wave 5
ends a run that never built past its starting three.

**If the owner wants the opening fixed, the lever is not health.** It is the
Basic tower's damage or fire rate, or wave 1's composition — all outside this
slice.

## In flight right now

**Nothing. All eleven tasks are complete.** The branch is
`feat/difficulty-selector`, eight commits ahead of `master`, suite green at
**13,554 checks across 45 files, exit 0**. Nothing is pushed and nothing is
merged — pushing `master` redeploys the live site, and that is the owner's call.

### What a Codex takeover would pick up

1. **Merge or not.** `feat/difficulty-selector` is ready. `update.md` records it
   as built and unmerged, beside the leak model which is in the same state.
2. **Play it.** Every tier number came from the harness, which has no projectile
   travel time and is therefore kinder than the live board. The spec says
   plainly these are a starting point to be played. The selector is on the main
   menu; the active tier shows in the HUD beside the wave counter.
3. **Two findings that need an owner's decision**, both written up in
   `update.md`: the opening cannot be fixed with enemy health (the lever is the
   Basic tower or wave 1's composition), and the benchmark board loses
   Nightmare.

## Standing rules that govern this work

- Run the suite with `godot --headless --quit --script test/run_tests.gd`.
  **Exit code 0 is the only pass signal**; a green run prints many `SCRIPT ERROR`
  lines to stderr by design.
- Every `test_*` method is declared `-> bool` and ends with `return true`,
  including every early return. Enforced crash detection, not style.
- `data/` and `sim/` are pure — `test/test_sim_purity.gd` bans scene types,
  clocks, RNG and platform state. Difficulty is a **parameter**, never a global.
- Normal must stay byte-identical. Any moved Normal-path number is a bug in this
  work, not a rebalance; the existing 13,436 assertions are the detector.
- **NO NEW ASSETS.** Owner's standing rule: if any visual, audio, animation,
  sprite, texture or icon turns out to be needed, stop and return to Codex. The
  selector is plain `Button` nodes and the existing theme.
- Do not commit `test/test_balance_tuning.gd.uid` or anything under `.ai/`.
  Another agent may share this tree: `git status` before every commit and stage
  only the files the task names. Never `git add -A`.

## Prior work still standing (from the pre-branch handoff)

- `121bc7f Cap each tower kind at three` — every kind capped at 3, every map at a
  12-tower budget. Deployed.
- `2a1ac6a Give each tower a themed projectile` — four 32x32 projectile sprites
  under `assets/art/projectiles/`, four distinct fire sounds. Deployed.
- If the owner reports a visual defect, check the lower-left build stamp before
  changing code — a stale browser cache has already caused one false report.
