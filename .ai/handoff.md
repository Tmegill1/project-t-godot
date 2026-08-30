# Claude Handoff — Difficulty Selector

Generated: 2026-08-29 (America/Chicago). **Live document — rewritten at the start
and end of every task so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- **Merged and deployed.** `feat/difficulty-selector` was merged to `master` as
  `b0263a9` on the owner's instruction and both branches are pushed. The Pages
  workflow republishes <https://tmegill1.github.io/project-t-godot/> on every
  push to `master`, so the selector is live.
- The branch is kept rather than deleted, matching how `feat/leak-model` and the
  other feature branches are kept.
- Plan: `docs/superpowers/plans/2026-08-29-difficulty-selector.md` (11 tasks)
- Spec: `docs/superpowers/specs/2026-08-29-difficulty-selector-design.md`

## Follow-up in progress: the benchmark still missed

The owner asked whether a fully upgraded board survives wave 20 on Nightmare.
Measuring it exposed a defect in the work that was just merged and deployed.

**Eleven of the sixteen legal fully-upgraded boards shut out Nightmare's wave 20
with zero leaks.** The cross-path rule allows exactly two maxed splits per tower
(`sustained 4 / burst 2` or `sustained 2 / burst 4`) and a board picks one per
kind, so there are 2^4 = 16 legal maxed boards. `test_balance_tuning.gd` pinned
**one** of them — the burst split — which happens to be the weakest. Extending
the benchmark from six towers to twelve and never questioning the upgrade split
is the same mistake one level down.

**Why sustained wins.** The tiers raised `count_multiplier` and lowered
`interval_multiplier`, both of which raise enemy *density*. The sustained branch
grants fire rate and then **splash** (45px, then 75px). Splash scales with
density, so the two levers chosen to attack coverage are precisely the ones a
splash build answers best. The selector did not create this imbalance — it
revealed a pre-existing one between the two upgrade branches, invisible on
Normal because every build shuts Normal out.

Branch: **`feat/difficulty-benchmark-splits`**, off `master` at `45a48ac`.

## Task progress

| # | Task | State |
|---|---|---|
| A | Benchmark every legal maxed board, not one | 🔄 **in progress** |
| B | Re-sweep Hard and Nightmare against the strongest board | 🔄 **in progress** |
| C | Correct the lever documentation and the docs | ⬜ |

### The re-sweep, measured 2026-08-30

Strongest board = every kind on sustained; weakest = every kind on burst.
Run totals are lives lost across all twenty waves.

| count | interval | health | speed | strongest | weakest |
|---|---|---|---|---|---|
| 1.40 | 0.60 | 1.40 | 1.15 | **0 — shut out** | 46 |
| 1.20 | 0.80 | 2.50 | 1.30 | **0 — shut out** | 120 |
| 1.00 | 1.00 | 3.50 | 1.30 | **0 — shut out** | 146 |
| 1.00 | 1.00 | 4.00 | 1.35 | **0 — shut out** | 246 |
| 1.00 | 1.00 | 4.00 | 1.40 | 3 | 258 |
| 1.00 | 1.00 | 4.50 | 1.40 | 9 | 336 |
| 1.00 | 1.00 | 4.75 | 1.40 | 12 | 380 |
| 1.00 | 1.00 | 5.00 | 1.40 | 27 | 441 |

Two things fall out. **Speed 1.40 is a floor**: below it the strongest board
leaks nothing at all, at any health up to 4.0. And **count and interval are
counter-productive** — raising density widens the gap between a splash build and
a non-splash one, so both go back to 1.0 and the teeth move to health and speed.

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
