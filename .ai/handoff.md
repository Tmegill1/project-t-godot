# Claude Handoff — Opening Purse

Generated: 2026-08-30 (America/Chicago). **Live document — rewritten as work
proceeds so Codex can take over at any point.**

## Where the work is

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: **`feat/opening-gold`**, off `master` at `3bb91ff`. Complete, suite
  green at **13,767 checks, exit 0**. Nothing pushed, nothing merged.
- The preceding build-out pacing work is merged and deployed (`fa01fdd`).

## This branch

The pacing change left The Pass's 100 starting gold buying exactly **one** tower,
because the second Basic escalates to 135. Measured against the same greedy
player, `starting_gold` goes **100 → 200**: two towers, a clean wave 1, and the
early cost drops from **seven lives to two** — while the build-out stays exactly
where the costs put it, full at wave 13 and maxed at 20.

170 was measured and rejected: it affords the second tower and nothing else, so
the board is thin enough to leak on wave 1. 250 buys three towers and removes the
early cost entirely, which overshoots — two towers with a mild wave-2 sting is a
curve; three and no pressure is the flat opening this work just left.

The Fork (250) and The Coils (200) already open with three towers and two, so
they were left alone. **One relationship narrowed:** The Fork's purse is
justified in its own comment as payment for two entrances, and that gap went from
2.5x to 1.25x. It still opens one tower ahead. If the gap should be restored it is
The Fork's number that moves, and it wants measuring.

**Two pins moved, both predicted:** the affordability income figure by exactly
the 100 gold added (16,199 -> 16,299), and `test_data_tables.gd`'s map
definition.
- `master` is green, merged and deployed, carrying the difficulty selector, the
  sixteen-board benchmark and the upgrade-branch rebalance. Suite there:
  **13,763 checks across 45 files, exit 0**.

## Why this work exists — and why the request's premise was wrong

The owner asked to "fix the opening cliff". **There is no opening cliff.**

The 21-lives-at-wave-5 figure that produced that phrase describes a player who
never builds anything after their starting three towers. Measured against a
player who simply spends — buy the cheapest legal thing whenever affordable, no
thought at all:

| Wave | Towers | Tiers | Lives | Gold | Deepest reached |
|---|---|---|---|---|---|
| 1 | 3 | 0/72 | 20 | 100 | 0.16 |
| 2 | 4 | 1/72 | **19** | 147 | 1.00 |
| 7 | 12 | 12/72 | 19 | 538 | 0.14 |
| 12 | 12 | 53/72 | 19 | 1,085 | 0.14 |
| 18 | 12 | **72/72** | 19 | 2,516 | 0.13 |
| 20 | 12 | 72/72 | **19** | **5,488** | 0.17 |

**One life lost across twenty waves.** The board is full by wave 7 of 20, fully
maxed by 18, and the run ends with 5,488 gold that has nothing left to buy.
Nothing ever reaches 17% of a route whose first bend is at 31%.

So the opening is not steep — it is flat, and so is everything after it. The
owner's decision (2026-08-30) was to attack **the build-out**: the board is
finished by wave 7 and the money stops mattering by wave 12.

## The approach, approved

**Raise `cost_escalation` sharply and base costs modestly in `data/towers.gd`.**
Income is already back-loaded — the greedy player has earned only ~1,600 of the
run's 16,199 by wave 7 — so the amount is not the problem; placing the entire
board for 1,050 gold is. Escalation rather than base cost alone, so the *first*
of each kind stays affordable and the opening can still build.

**Income is deliberately not cut.** The shape is wrong, not the size, and
cutting it would put the fully-maxed board out of reach — which every difficulty
tier was measured against.

### Targets the sweep must hit

- The twelve-tower budget is not full before roughly **wave 13** (today: 7).
- The full maxed board is **still affordable within a run** — Task 1's
  affordability pin moves and is re-measured, not assumed.
- Leftover gold at wave 20 is small; 5,488 is the sign money stopped mattering.
- **Every difficulty assertion still passes unchanged.** They all assume a
  fully-maxed board is reachable. If raising costs puts it out of reach, that is
  a finding to bring back, not something to fix by loosening a bound.

### The regression net

A new assertion in `test/test_affordability.gd`: **a greedy player cannot
complete the board before wave N.** A bound, not an example — the same lesson
that produced `MAX_BRANCH_SPREAD`, after two earlier assertions were satisfied
by convenient boards.

## Progress

**Complete, merged and deployed.** Suite green on the merged result at
**13,767 checks across 45 files, exit 0**.

| Step | State |
|---|---|
| Measure the greedy build-out | ✅ done |
| Sweep costs and pick values | ✅ done |
| Re-pin `test_data_tables.gd`, `test_economy.gd`, `test_affordability.gd` | ✅ done |
| Add the greedy build-out bound | ✅ done — **verified against the old costs** |
| Confirm every difficulty assertion still holds | ✅ done — costs do not touch combat |
| Docs | ✅ done |

### What shipped

| | base | escalation |
|---|---|---|
| Basic | 20 → **35** | 10 → **100** |
| Magic | 50 → **80** | 15 → **150** |
| Mortar | 70 → **115** | 35 → **270** |
| Long Range | 100 → **165** | 50 → **400** |

The greedy player now fills the board at **wave 13** (was 7), maxes at **20**
(was 18), finishes with **10 of 20 lives** (was 19) and **2,532 gold** (was
5,488). Full board costs 14,310 against 16,199 of income — 1,889 of headroom
where there used to be 4,784.

The bound in `test_affordability.gd` — no full board before wave 10, leftover
gold under 4,000, naive player survives — was **verified by restoring the old
costs and watching it fail on both counts**, not merely observed to pass.

### Two consequences the owner should hear

1. **It made the early game harder, which was not the scope.** The change was
   proposed as *slower to build, not harder*; the two turn out not to be
   separable, because a thinner board leaks. Waves 2 and 3 now cost a naive
   player about seven lives where they used to cost none. That is early-game
   texture arriving as a side effect — and it is what the original "fix the
   opening" request was reaching for.
2. **A Mortar or Long Range is no longer a first purchase.** On The Pass's 100
   starting gold you can open with one Basic (35) or one Magic (80). Three
   existing tests silently assumed otherwise and now grant themselves gold.

## Scope note the owner should hold onto

This makes the early game **slower to build**, not **harder**. Waves 1-5 stay
zero-leak walkovers; there will simply be fewer towers up while they happen. If
early-game *pressure* is what is wanted, that is separate work — wave
composition and spawn pacing in `data/waves.gd`.

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
