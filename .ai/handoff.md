# Claude Handoff — Pause Menu

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/pause-menu`**, off `master` at `22eea1f`. **Complete**, suite
  green at **13,781 checks across 46 files, exit 0**. Nothing pushed or merged.
- **Verified in the running game, not only in tests:** Escape raised the menu
  (one instance, despite two presses — the re-entry guard holds, and
  `process_mode` read 3 = `WHEN_PAUSED` live); Continue freed it and play
  resumed; Escape then Quit reached the main menu; picking Hard and pressing
  Play started a run reading **Hard** and **Lives 15**. That last step is the
  proof the tree was not left paused, since the main menu's buttons had to
  process for it to happen.
- Everything before this session's pause work is merged and deployed. Suite on
  `master`: **13,767 checks across 45 files, exit 0**.

## What this branch adds

Escape opens a pause menu with **Continue / Restart / Quit**; Quit returns to
the main menu, which is where difficulty is chosen.

**Escape shares the key, it does not take it.** It already cancels a selected
tower or a half-made placement (shipped as *"Let Escape clear whatever the
player is in the middle of"*). Owner's decision: cancel first, pause only when
there is nothing to cancel — Escape backs out one level at a time, and it never
yanks the player into a menu mid-placement.

**Pausing is `get_tree().paused`**, the Godot-native one, because it stops
`_physics_process` — which is what drives the wave clock, the prep timer and
every enemy. The menu itself runs `PROCESS_MODE_WHEN_PAUSED` or its own buttons
would stop responding the moment it paused the tree. Quit unpauses **before**
changing scene: `paused` is global tree state and survives a scene change, the
same hazard the HUD already documents for `Engine.time_scale`.

## A pre-existing bug fixed in the same pass

**`reload_current_scene()` loses the run's map and difficulty.**
`GameBoard._ready` consumes `pending_map` and `pending_difficulty` and clears
both, and `_map_name` defaults to `Maps.FIRST` — so a plain reload restarts on
The Pass at Normal wherever you were. The game-over screen's **Retry** has done
this all along: dying on The Fork on Nightmare drops you onto The Pass on
Normal. Both Restart and Retry now re-set the two statics from the board before
reloading.

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
