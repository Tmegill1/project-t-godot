# Claude Handoff — Splitting the Wave

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/split-the-wave`**, off `master` at `cbf7c83`. **Complete**,
  suite green at **13,855 checks across 46 files, exit 0**. Nothing pushed.

## Result: Normal fixed, the harder tiers still open

| The Fork, completed board | Normal | Hard | Nightmare |
|---|---|---|---|
| Before | **101 / 128** | 508 / 439 | 530 / 458 |
| **After** | **0 / 5** | 132 / 93 | 144 / 103 |

**Sixteen towers would fix Hard and Nightmare** (3-4 and 3-7 lives, nothing shut
out); fourteen is not enough and eighteen shuts them out. Two blockers, both
decisions rather than measurements:

1. `limit_bonus_map2` applies to every map but the first, so it cannot give The
   Fork more towers without also giving The Coils more - and The Coils measures
   well at twelve. **Per-map tower limits are needed first.**
2. The Fork's income halved with the split, 30,371 -> 16,632, because it no
   longer fields double the enemies. Sixteen maxed towers cost 20,920, so the
   map cannot afford the board its own tiers require.
- Everything before it this session is merged and deployed.

## Why: budgets could not fix The Fork, and measurement said so

The owner asked to fix the tower budgets. Measured first, and they are not the
lever:

| The Fork, a player who spends | Normal | Hard | Nightmare |
|---|---|---|---|
| 12 towers / 400 gold *(shipped)* | dies wave 3 | dies wave 2 | dies wave 2 |
| **23 towers** / 400 gold | dies wave 3 | dies wave 2 | dies wave 2 |
| 23 towers / **1,800** gold | dies wave 13 | dies wave 5 | dies wave 3 |

The budget never binds - the player is dead long before reaching twelve towers,
let alone twenty-three - and 4.5x the purse does not rescue it. The maxed
23-tower board that *does* hold costs **33,605** against the map's **30,371** of
income, so even the endgame board was unaffordable.

Raising the budget would have turned `NORMAL_COMFORT_UNDECIDED` green over a map
that stays unplayable: a benchmark passing on a board nobody plays, which is the
exact failure this whole session has been chasing.

**Owner's decision (2026-08-31): split the wave between entrances.**

## What this branch changes

`Waves.split_schedule(schedule, lane_count)` distributes one wave's spawns
round-robin across lanes - spawn 0 to lane 0, spawn 1 to lane 1 - so both
entrances field a mix arriving together rather than one taking all the goblins.
**Both `game_board.gd` and `sim/harness.gd` call it**, which is the invariant the
harness exists to protect: one implementation, two callers.

A second entrance stops meaning *twice the enemies* and starts meaning *the same
enemies, two approaches*. That inverts a documented decision, so several things
must move with it:

- `test_harness.gd`'s "each lane runs the whole wave" - committed an hour before
  this - inverts. That test doing its job is why it was written.
- The Fork's map comment claims "twice the enemies"; no longer true.
- `NORMAL_COMFORT_UNDECIDED` and the "The Fork is unwinnable" pin come out **if**
  the map now holds. That pin exists to force exactly this moment.
- The Fork's purse of 400 was doubled this morning *because* it faced double the
  threat. If the threat halves, re-measure it.

**Out of scope, deliberately:** Hard and Nightmare are also unsurvivable from
the opening on The Pass - two different simulated strategies die on wave 2-3 of
the easiest map, because every tier was swept against completed maxed boards and
never against a build-out. Real, separate, and bundling it here would tangle two
findings.

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
