# Claude Handoff — Upgrade Branch Balance

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten at the start
and end of every task so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/upgrade-branch-balance`**, merged to `master` as `fe97546` on
  the owner's instruction. Both branches pushed; the Pages deploy succeeded, so
  the rebalance is live.
- **All nine tasks are complete, merged and deployed.** Suite green on the
  merged result at **13,763 checks across 45 files, exit 0**.

### What a Codex takeover would pick up

1. **Play it.** Three rounds of tuning have now happened without a human
   touching the game. Every number came from the harness, which has no
   projectile travel time and is therefore kinder than the live board.
2. **The one thing not verified on screen:** the two new summary labels under
   each branch button. They are covered by `test_tower_inspector.gd` and the
   panel height was measured two ways, but nobody has looked at them. Drive it
   with `game_click` on real coordinates — `game_call_method` cannot pass a
   `Vector2` through the MCP bridge.
3. **Still open, and recorded in `update.md`:** the opening cannot be given a
   pulse with enemy health — the lever is the Basic tower's damage or fire rate,
   or wave 1's composition.
- All 32 generated lines were printed and read. The longest is
  `fires 0.056s faster · slows to 45% for 2.5s` at 42 characters.
- **The panel fits, measured two ways.** Summing minimum sizes gives 476px
  against the 465px it was before the labels; computing the labels' real wrapped
  height at the sidebar's 124px of usable width gives 474px. The minimum-size
  sum is the larger, so the existing fit check stays an over-estimate, which is
  the safe direction. Both are well inside the shortest map's 672px.
- **The in-game check was inconclusive, for a tooling reason.** The Godot MCP
  bridge cannot marshal a Dictionary into a `Vector2`
  (`Cannot convert argument 1 from Dictionary to Vector2`), so `_try_place`
  never ran and no tower was ever selected. The behaviour is covered by
  `test_tower_inspector.gd` on the real `show_tower` -> `_refresh_gating` path,
  and the heights above were measured off the same path. **If you want the live
  look, drive it with `game_click` on real screen coordinates rather than
  `game_call_method` with a Vector2 argument.**

### Two corrections made during Task 6, both worth knowing

**The parity bound was measuring the wrong thing.** Task 5 pinned the
best-to-worst ratio at wave 20 and got 2.01×. Re-sweeping the difficulty rows
moved it to 6.90×, and a quarter-point of health swung it from 12.40× to
undefined — because at the wave where a tier is actually decided, the best board
loses almost nothing and the ratio measures where the threshold sits rather than
how far apart the branches are. It now measures at **wave 30**, past anything a
board can hold, where the comparison is graded: 1.68× for this roster, stable
across rows.

**And it was verified, not assumed.** Splash was temporarily put back on Basic
and Long Range and the metric re-run: **3.18×**, over the 3.0 bound. So the
assertion catches the defect it was written for rather than merely describing
the fix.

**"The strongest board" is now found, not named.** `_strongest_board()`
hardcoded all-sustained, which was true when splash sat on three towers and
false the moment it went back to one. It is `_best_board_result(tier, wave)`
now, which measures. The first-bend claim is asked of all sixteen boards rather
than one.

### The shipped rows

| Tier | health | speed | gold | lives |
|---|---|---|---|---|
| Normal | 1.00 | 1.00 | 1.00 | 20 |
| Hard | 2.35 | 1.30 | 0.90 | 15 |
| Nightmare | 2.50 | 1.30 | 0.85 | 12 |

Count and interval stay at 1.0 — the Mortar still splashes, and density is what
splash is for. Hard costs the best legal board 5 of its 15 lives on wave 20;
Nightmare costs it 10 of 12 across a run, so it survives with two. The threshold
where the last board stops shutting wave 20 out sits between 2.25 and 2.35
health, and both tiers sit just past it.

## What the owner asked for, in their own terms

Three things, all in the plan:

1. **Fix the branch imbalance.** Splash returns to the Mortar; Basic's and Long
   Range's deep sustained tiers get reach and cadence instead.
2. **Show descriptions next to the upgrades**, so you do not have to hover. They
   are a tooltip today because the sidebar is 140px and a `Button` does not wrap.
   A wrapping `Label` under each branch button does, and the line is **generated
   from the effects dictionary** so the number on screen cannot drift from the
   number applied.
3. **Flat amounts instead of percentages** — "fires 0.4s faster", "+12 damage".
   Adopted for damage and fire rate, with per-tower values, because base rates
   run 500ms to 2000ms and a shared flat value would take Magic to zero. Range
   keeps its multiplier; splash, slow and gold already take the strongest value
   rather than stacking, so they never compounded.

## Three things that will bite an executor

1. **Task 3 will break balance tests, and that is expected.** Removing splash
   from two towers weakens every board that took them, and the difficulty rows
   were swept against boards that had it. The plan says which failures to carry
   forward into Tasks 5 and 6, and forbids weakening either shut-out assertion
   to hide them.
2. **The sidebar budget is real.** `CONTINUE.md` §14: the inspector already uses
   465px of a 672px viewport, and the viewport height is the *shortest* map's
   pixel height. If the generated lines do not fit, shorten the phrasing — never
   widen the column.
3. **Screenshots come back blank on this machine** (`glx: failed to create dri3
   screen`). Read layout back with the Godot MCP server's `game_get_ui`, which
   reports every control's real rect. That is how the difficulty selector's
   layout was verified.

## Standing rules that govern this work

- Run the suite with `godot --headless --quit --script test/run_tests.gd`.
  **Exit code 0 is the only pass signal**; a green run prints many `SCRIPT ERROR`
  lines to stderr by design.
- Every `test_*` method is declared `-> bool` and ends with `return true`,
  including every early return. Enforced crash detection, not style.
- `data/` and `sim/` are pure — `test/test_sim_purity.gd` bans scene types,
  clocks, RNG and platform state. `effect_summary` returns a `String` and touches
  nothing else, which is why it may live in `data/`.
- **Adding a new `class_name` needs `godot --headless --import`** before the
  suite will see it, or it fails with `Parse Error: Identifier "X" not
  declared`. That pass also writes the `.uid`; every other `.gd.uid` here is
  tracked, so commit it with its script.
- **NO NEW ASSETS.** Owner's standing rule: if any visual, audio, animation,
  sprite, texture or icon turns out to be needed, stop and return to Codex.
- **No invented numbers.** Both of this week's misses — the six-tower benchmark
  and the first difficulty rows — came from figures written down before they
  were measured. The spec deliberately contains none; the plan derives Task 2's
  from measured endpoints and sweeps for the rest.
- Do not commit `test/test_balance_tuning.gd.uid`. Another agent may share this
  tree: `git status` before every commit, stage only what the task names, never
  `git add -A`.
- **Pushing `master` redeploys the live site.** Do not push without the owner
  asking. They have asked twice so far, each time explicitly.

## What landed on `master` before this branch

- `Merge feat/difficulty-selector` — three tiers chosen per run, difficulty
  threaded as a parameter, `deepest_progress` and `progress_at_death` on the
  harness result, the full twelve-tower benchmark.
- `Merge feat/difficulty-benchmark-splits` — the benchmark walks all sixteen
  legal maxed boards after eleven of them were found shutting Nightmare out;
  tiers re-swept against the strongest board; count and interval returned to 1.0
  because raising density feeds a splash build rather than threatening it.
- Two findings recorded there and still open: the opening cannot be given a
  pulse with enemy health (the lever is the Basic tower or wave 1's
  composition), and this branch's imbalance, which it named and did not fix.
