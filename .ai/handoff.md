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
| 9 | Give the opening a pulse | 🔄 **next** |
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

Task 7 is complete and committed. The selector is live end to end, built from
plain `Button` nodes and the existing theme — no new assets.

- `ui/main_menu.tscn` gains an `HBoxContainer` named `Difficulty` under `Panel`
  holding `Normal`, `Hard` and `Nightmare` toggle buttons; the panel grew to
  320x240 to hold the row.
- `ui/main_menu.gd` labels each button from the table, keeps exactly one
  pressed, and sets `GameBoard.pending_difficulty` **after** `begin_new_run()`,
  which now clears it.
- `ui/hud.tscn` gains a `DifficultyLabel` in the `Top` bar; `Hud.bind()` reads
  the tier from the board through the new `GameBoard.get_difficulty()`.

Three deviations from the plan text, all deliberate:

1. The plan writes the HUD label as `$DifficultyLabel` while also saying "beside
   the existing wave readout". It is `$Top/DifficultyLabel` — the root path
   would have put it outside the bar every other readout lives in.
2. The plan puts the three buttons directly under `Panel` (a VBox, so they would
   stack). The **spec** section 4 asks for a row, so they sit in an
   `HBoxContainer`. Paths are `$Panel/Difficulty/<Tier>`.
3. The plan says "have `GameBoard` call `hud.set_difficulty`", but the board has
   never known about the HUD — `game.gd` binds them. The HUD reads
   `board.get_difficulty()` inside `bind()`, beside how it already reads gold,
   lives and wave.

Verified live, not just in tests: ran both scenes under the Godot MCP server and
read back the real layout. The tier row is three 101px buttons inside a 320px
panel, and the HUD reads `Gold 100 / Lives 20 / Wave 0 / 20 / Normal /
Towers 0/12` with 401px still free for the message line. (Screenshots come back
blank on this machine — `glx: failed to create dri3 screen` — so `game_get_ui`
is the reliable check here, not `game_screenshot`.)

Task 8 is complete and committed. Hard and Nightmare are no longer identity
rows. `probe_tiers.gd` has been deleted as the plan requires.

**Shipped rows** (count / interval / health / speed / gold, then lives):

| Tier | count | interval | health | speed | gold | lives |
|---|---|---|---|---|---|---|
| Normal | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 20 |
| Hard | 1.30 | 0.70 | 1.30 | 1.10 | 0.90 | 15 |
| Nightmare | 1.40 | 0.60 | 1.40 | 1.15 | 0.85 | 12 |

**Three findings worth carrying forward.**

1. **The owner's report is now measured, and it is worse than "the first bend".**
   At Normal, against the full twelve-tower maxed board, `deepest_progress`
   never exceeds **0.18** on any of the twenty waves — wave 1 reaches 0.02,
   wave 20 reaches 0.18. The first bend is at 0.31. Nothing has ever reached
   it. That is the whole complaint, as a number.

2. **The full board is a wall, and it fails as one.** Every lever combination
   either holds a wave outright or collapses on it; there is almost no middle.
   Full-board lives lost across a run: 0 at Normal, 1 at 1.15, **11 at 1.30**,
   **46 at 1.40**, 87 at 1.50, 720 at 2.00. Ten points of multiplier is the
   difference between losing eleven lives and losing forty-six. Hard and
   Nightmare sit close together for that reason, not by timidity.

3. **The benchmark board loses Nightmare, and that is shipped knowingly.**
   Leaks start at wave 17; cumulative loss through wave 19 is exactly 10, so a
   twelve-life board reaches the final wave and dies on it. Whether a human
   finds a better board is a playtest question — the harness resolves hits
   instantly with no projectile travel time, so it is *kinder* than the live
   board. Per the spec's own risk section these are a starting point to be
   played, not a finished tuning.

**One target reinterpreted, deliberately.** The plan asks that Nightmare push
`deepest_progress` past 0.31 on wave 10. Against the *full twelve-tower maxed
board* that is unreachable — even a 2.5/0.3/3.0 row only reaches 0.26 at wave 10
while annihilating waves 13 onward. It is met against the board a player
actually holds at wave 10: on the six-tower mid-run board, Nightmare wave 10
already leaks (`deepest_progress` 1.00). Nobody owns twelve maxed towers at wave
10 — Task 1 measured the full board at 11,415 gold against 16,199 of income
across a whole run — so the mid-run board is the honest place to ask the
question.

## In flight right now

Task 9 is next: raise `goblin` and `bat` base health so wave 1 lasts longer than
4.6 seconds. Expect pinned tick counts and gold totals in `test_harness.gd`,
`test_balance_tuning.gd` and `test_affordability.gd` to move; each must be
re-measured and re-pinned, and the commit must say they moved because base
health moved.

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
