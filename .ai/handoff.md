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
| 7 | The menu selector and the HUD readout | 🔄 **next** |
| 8 | Sweep the tiers and set their numbers | ⬜ |
| 9 | Give the opening a pulse | ⬜ |
| 10 | Benchmark the board the game actually hands out | ⬜ |
| 11 | Update the docs | ⬜ |

## In flight right now

Task 2 is complete and committed. `data/difficulty.gd` now exists with
`NORMAL`/`HARD`/`NIGHTMARE`, `ORDER`, `KEYS`, `DEFS`, and the accessors
`get_def`, `multiplier`, `starting_lives`, `label`, `is_valid`.

**Hard and Nightmare are identity copies of Normal right now.** That is
deliberate and must stay that way until Task 8's sweep measures real values —
a plausible number written down once becomes the shipped number by inertia,
which is exactly how the six-tower benchmark happened. The selector will be
live but inert until then; do not "fill in something reasonable".

Task 3 is complete and committed. `data/waves.gd` now reads:

    Waves.get_composition(wave_number, tier := Difficulty.NORMAL)
    Waves.get_modifiers(wave_number, tier := Difficulty.NORMAL)
    Waves.build_schedule(wave, tier := Difficulty.NORMAL)
    Waves.ogre_spawn_delay(goblin_count, interval_ms := INTERVAL_MS)
    Waves._scale_counts(composition, multiplier)        # floors each kind at 1
    Waves._build_schedule_at(wave, tier, interval_multiplier)

The whole suite still passes at 13,518 checks with nothing pre-existing moved,
which is the identity guarantee doing its job: if a Normal number ever moves,
an old assertion fails.

Task 4 is complete and committed. `Harness.run_wave` reads
`config["difficulty"]`, defaulting to `Difficulty.NORMAL`, and hands it to both
`Waves.build_schedule` and `Waves.get_modifiers`.

The plumbing was proved rather than assumed: while Hard and Nightmare are still
identity rows, a per-tier test passes whether or not the tier reaches anything.
Nightmare's `health_multiplier` was temporarily set to 2.0 with a temporary
"Nightmare differs from Normal" assertion; it failed before the change and
passed after, and both were then reverted. **If you touch this plumbing again,
prove it the same way** — a green suite alone is not evidence here until Task 8
lands real tier values.

Task 5 is complete and committed. `Harness.run_wave`'s result now carries two
more keys, both fractions of the route from 0.0 to 1.0:

- `deepest_progress` — the furthest any enemy got. A leak forces it to 1.0.
- `progress_at_death` — the mean over enemies that died; 0.0 when nothing died,
  which is the honest answer rather than a division by zero.

Both come from `path_index` and cumulative route length, which the harness
already tracks for movement, so there is no second implementation to drift.
`test_harness.gd` now pins the owner's own report as an assertion: five maxed
Long Range towers decide wave 1 before `FIRST_BEND_FRACTION := 0.31`.

Existing keys and their order were left alone on purpose — several tests compare
whole result dictionaries for equality.

Task 6 is complete and committed. The live board now carries a tier:

- `GameBoard.pending_difficulty` — a static, the same shape and lifetime as
  `pending_map`, consumed and cleared in `_ready`.
- `GameBoard.active_difficulty()` — validates through `Difficulty.is_valid`, so
  an unset or misspelled tier falls back to Normal instead of crashing a run.
- `_lives` comes from `Difficulty.starting_lives(_difficulty)`.
- The tier reaches `Waves.build_schedule` and, through `Enemy.setup`, both
  `Waves.get_modifiers` call sites in `game/enemy.gd`.

One correction to the plan text, applied: it says to "add a `difficulty` field
to the setup dictionary the board passes", but `Enemy.setup` takes positional
arguments, not a dictionary. It gained a trailing
`difficulty: StringName = Difficulty.NORMAL` instead, which keeps every existing
three-argument call site in `test/test_enemy.gd` working unchanged.

Task 7 is next: three toggle `Button`s on the main menu and a tier readout on
the HUD. **Plain buttons and the existing theme — no new assets.**

## Adding a new `class_name` script? Run the importer

Godot only registers a new global class name after an import pass. A fresh
`data/*.gd` with a `class_name` will fail the suite with
`Parse Error: Identifier "X" not declared in the current scope` until you run:

    godot --headless --import

That also generates the script's `.uid` file. Every other `.gd.uid` in this repo
is tracked, so commit a new one alongside its script.
`test/test_balance_tuning.gd.uid` is the one exception — it stays untracked, per
the owner's instruction.

## Task 1's finding — it unblocks Task 8

`test/test_affordability.gd` measures a twenty-wave run's income floor (kill
rewards and wave-clear bonuses only) against the cost of the full legal board.

**The full twelve-tower maxed board IS affordable: 16,199 gold of income against
an 11,415 cost, 4,784 to spare.** So the spec's open risk does not bite — the
shut-out threshold of ten maxed towers is a board a player genuinely reaches,
and Task 8 sets its tier targets against twelve rather than against something
smaller.

Read it as generous rather than exact: the board is fully built and fully maxed
from wave 1 in the measurement, so it collects every reward, where a real player
funds it incrementally. It is still a floor in the other direction (no interest,
no call-early bonus). The two errors run opposite ways and the margin is wide
enough that the conclusion survives either.

## One deviation from the plan, deliberate

The plan's constraints say not to commit anything under `.ai/`. That was written
from a stale belief — `.ai/handoff.md` was actually tracked by `b00b695 Record
the Codex to Claude handoff`. Since the owner asked for this file to stay current
for a Codex takeover, it is updated and committed alongside each task. Nothing
else under `.ai/` is committed, and `test/test_balance_tuning.gd.uid` stays
untracked as the plan requires.

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
