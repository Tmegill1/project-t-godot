# Claude Handoff — Splitting the Wave

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/tiers-across-maps`**, off `master` at `2e2f6d9`. Docs only -
  no game numbers changed. Suite unaffected.
- Everything before it this session is merged and deployed.

## Re-measured against the new tiers: two findings were wrong, one is new

**The Fork's Hard/Nightmare catastrophe is gone.** It lost 93-144 lives; a
completed board now loses 0-11 against budgets of 15 and 12. The "sixteen towers
would fix it" finding and the `limit_bonus_map2` blocker are **obsolete**.

**The Coils never had a Normal problem.** It was recorded as killing a spending
player on wave 10; it finishes with **19 of 20**. The original number came from a
probe placing towers at full-budget slots, which clusters an early board - the
placement artifact found later the same day, reported before the confound was.

**New, and the real remaining gap: the tiers are playable on The Pass and
nowhere else.**

| A player who has to build | Normal | Hard | Nightmare |
|---|---|---|---|
| The Pass | 13 of 20 | **7 of 15** | dies wave 13 |
| The Fork | 14 of 20 | **dies wave 10** | dies wave 10 |
| The Coils | 19 of 20 | **dies wave 10** | dies wave 7 |

Two structural causes, neither fixed:

1. **Coverage density.** Same twelve-tower budget on routes of 2,448 / 2,832 /
   3,696px - 4.9, 4.2 and 3.2 towers per 1,000px. Invisible on Normal, decisive
   on Hard.
2. **The wave-clear speed bonus punishes long maps.** Full at 20s, none at 60s,
   flat thresholds against very different routes. On Hard The Coils earns 0 speed
   bonus from wave 9 while The Pass still earns 27.

Levers: per-map tower budgets scaled to route length, and speed-bonus thresholds
scaled to the route rather than fixed in seconds. **Both are decisions, and this
is the third time a number tuned on The Pass has failed to transfer.**

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
