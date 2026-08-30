# Claude Handoff — Upgrade Branch Balance

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten at the start
and end of every task so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/upgrade-branch-balance`**, off `master` at `6582655`.
- Executing the plan inline. Tasks 1-2 done; Task 3 next.
- **Task 2 came out behaviour-identical**, which is better than the plan
  predicted. Every tower's damage and fire-rate curve is unchanged at *every*
  tier, not merely at the maxed endpoint, because each flat value equals the
  delta its multiplier produced at that step. Nothing about current balance
  moved; what changed is that future edits no longer compound.
- **One deviation from the plan, deliberate:** it specified a
  `_apply_effect_for_test` wrapper around `_apply_effects`. The wrapper was
  dropped — GDScript's leading underscore is convention, not access control, so
  the tests call `UpgradesSim._apply_effects` directly. A production function
  existing only to be called by a test is worse than the thing it was avoiding.
- Spec: `docs/superpowers/specs/2026-08-30-upgrade-branch-balance-design.md`
- Plan: `docs/superpowers/plans/2026-08-30-upgrade-branch-balance.md` (9 tasks)

`master` is green, merged and deployed at
<https://tmegill1.github.io/project-t-godot/>, carrying the difficulty selector
and the sixteen-board benchmark fix. Suite there: **13,599 checks across 45
files, exit 0**.

## Why this work exists

The owner asked whether a fully upgraded board survives Nightmare's wave 20.
It does — or does not — depending almost entirely on **which upgrade branch was
taken**, by a margin that makes the choice not a choice. Lives lost across a
twenty-wave Nightmare run, twelve maxed towers:

| Board | Run lives lost |
|---|---|
| All sustained | **9** |
| …but Mortar on burst | **6** |
| …but Basic on burst | 40 |
| …but Magic on burst | 100 |
| …but Long Range on burst | **200** |
| All burst | **336** |

**A 37× spread.** No difficulty number closes it, because it is not a difficulty
problem.

**Two mechanisms, both measured.** Three of four towers can buy splash, and a
splash hit applies its *whole payload* — the Magic tower's slow included — to
everything it catches, so one Magic tower plus any splasher slows the entire
wave. Long Range is worst: 90px splash at 239px range, wider effective area than
the Mortar, which is meant to be *the* area specialist. Separately, every damage
and fire-rate tier is a multiplier, and multipliers compound: 1.4 × 1.4 is +96%,
not +80%, and the shape worsens the deeper a branch goes.

The Mortar's own comment in `data/upgrades.gd` already stated the rule this
breaks: area belongs to it, and *"a tower that could take them would answer
everything."*

## Task progress

| # | Task | State |
|---|---|---|
| — | Spec | ✅ committed — `Design the upgrade branch rebalance` |
| — | Plan | ✅ committed — this handoff's commit |
| 1 | Flat damage and fire rate, and a floor under it | ✅ done |
| 2 | Convert every tier to flat damage and fire rate | ✅ done |
| 3 | Return area damage to the Mortar | 🔄 **next** |
| 4 | Delete the multiplier keys | ⬜ |
| 5 | Close the branch spread, and pin a bound | ⬜ |
| 6 | Re-sweep Hard and Nightmare | ⬜ |
| 7 | A stat line generated from the effects | ⬜ |
| 8 | The panel says what the tier does | ⬜ |
| 9 | Update the docs | ⬜ |

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
