# Claude Handoff — Multi-lane Harness

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/multi-lane-harness`**, off `master` at `4998840`. Spec and plan
  committed; **execution starting**.
- Everything before it in this session is merged and deployed. Suite on
  `master`: **13,782 checks across 46 files, exit 0**.
- Spec: `docs/superpowers/specs/2026-08-30-multi-lane-harness-design.md`
- Plan: `docs/superpowers/plans/2026-08-30-multi-lane-harness.md` (6 tasks)

## Why this work exists

`sim/harness.gd` claims every balance number in this project is a test rather
than an assertion. That holds for **one map out of three** — its header lists
"one lane" among its simplifications and `run_wave` takes a single `path`.

It became load-bearing when The Fork's purse moved to 400 earlier today. Every
other number this week was swept and pinned, two of them verified by restoring
the defect and watching the assertion fail. That one could not be, and its own
comment says so.

## The shape

`config["paths"]` joins `config["path"]`, which keeps meaning exactly one lane.
Enemies carry a `lane` index; routes are precomputed per lane; spawning uses one
shared schedule with a cursor per lane — mirroring `GameBoard._spawn_queues` and
`_spawned_per_path` rather than approximating them. Every lane runs the whole
wave, so two entrances field twice the enemies.

**Rejected on correctness: running each lane separately and summing.** No core
loop change at all, which is why it is tempting, and wrong — every tower would
fire down every lane at full rate. That is the exact error that stopped The
Fork's purse being "measured" that way in the first place.

## Task progress

| # | Task | State |
|---|---|---|
| — | Spec | ✅ committed |
| — | Plan | ✅ committed |
| 1 | `run_wave` accepts `paths`, one lane unchanged | ✅ done |
| 2 | Two lanes are two lanes | ✅ done |
| 3 | Twelve towers on any map, by a stated rule | ✅ done |
| 4 | Benchmark every map | 🔄 **next** |
| 5 | Measure The Fork and The Coils, and report | ⬜ |
| 6 | Docs | ⬜ |

## Three things that will bite an executor

1. **No call site may be edited to make a test pass.** The 64 existing
   `run_wave` calls are the project's measured corpus. If one of their numbers
   moves, the change is wrong — fix the change, not the pin.
2. **Task 4 is expected to fail, and that is a finding, not a defect.** The Fork
   and The Coils have never been measured. If one shuts out Nightmare or leaks
   on Normal, carry it forward to Task 5 and **do not retune a map** — retuning
   inside the change that made measurement possible destroys the evidence.
3. **The suite has a three-minute budget** with the fallback named in advance
   (two builds per map instead of sixteen; then Normal drops to burst alone).
   Whichever cut is taken goes in the test's own comment with the runtime that
   forced it.

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
