# Difficulty selector, and the benchmark that missed

**Date:** 2026-08-29
**Target:** Godot 4.7.1, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

The owner played the live build and reported: *"Enemies don't stand a chance,
they don't make it to the first bend."* Asked how far that held, the answer was
**every wave, all the way through**.

That report arrived hours after `121bc7f Cap each tower kind at three`, which
had just cut every kind to three and every map budget from sixteen towers to
twelve specifically to make the late game bite. The cap landed at 19:14; the
play session was on `674b28a`, from 18:40. So the first question was whether
the complaint had already been fixed.

It had not. Measured against `b00b695`, the tree as it stands:

| Maxed towers, cross-path legal | Wave 18 | Wave 20 |
|---|---|---|
| 6 — *what `test_balance_tuning.gd` benchmarks* | 19 leaks | 55 leaks, 74 lives |
| 7 | 2 | 14 |
| 8 | 0 | 10 |
| 9 | 0 | 3 |
| **10** | **0** | **0** |
| 11 | 0 | 0 |
| **12 — the full map budget** | **0** | **0** |

**The zero-leak threshold is ten. The budget is twelve.** A player who fills
their budget shuts the game out completely and never loses a life. The
benchmark that was supposed to catch this stops two towers short of the board
the game actually hands out.

Two further measurements pin the shape of it.

**Waves 1–15 leak zero even at six towers.** Three-quarters of a run has no
pressure at any board a competent player reaches.

**The back half of the map is decorative.** Twelve maxed towers crammed onto
the first straight and the same twelve spread over the whole route produce an
identical result — all 177 wave-20 enemies dead, zero leaks, both times. The
owner's phrase was not hyperbole. The route is 2,448px; the first bend is at
768px, **31% in**. Nothing that matters happens after it.

For completeness, the opening from the player's side, three Basic towers being
exactly what 100 starting gold buys at 20 + 30 + 40:

| Wave | Kills | Leaks | Lives lost | Clear |
|---|---|---|---|---|
| 1 | 5 | **0** | 0 | 4.6s |
| 2 | 9 | 2 | 2 | 28.8s |
| 3 | 9 | 8 | 13 | 29.8s |
| 5 | 13 | 13 | **20** | 55.2s |

`Economy.STARTING_LIVES` is 20, so an unimproved three-tower board is dead at
wave 5. The curve is not flat — it is a **cliff**: wave 1 is a walkover, and
the difficulty is entirely a function of whether the player kept building.

### Why the benchmark missed it

`test_balance_tuning.gd` asserts `result["leaks"] > 0` for a six-tower board on
wave 18. That is true, and it stays true no matter how easy the game becomes
for a full board. The test measures a board the player passes through on the
way to the one they finish with. Nothing in the suite has ever run the **full
legal roster**, which is the only board the endgame is actually played on.

The deeper gap: **the harness cannot see where an enemy died.** `run_wave`
returns kills, leaks, lives lost, gold and ticks. "They don't reach the first
bend" is not expressible against that interface, which is precisely why a
regression this visible to a player was invisible to 13,436 assertions.

---

## 2. Goals and non-goals

**Goals**

1. A difficulty selector on the main menu, chosen per run.
2. Difficulty levers that attack **coverage**, which prior measurement
   established as the binding constraint — not hit points, which prior
   measurement established as a weak lever alone.
3. Give the opening a pulse: wave 1 should not die in 4.6 seconds.
4. Close the measurement gap, so this class of regression is catchable:
   benchmark the full legal board, and teach the harness where enemies die.

**Non-goals**

- **Persistence.** Difficulty is chosen per run. `update.md` records that no
  settings file exists and that Slice 3 owns saving; inventing one here would
  put a versioning problem in Slice 3's lap early and badly.
- **Retuning the default curve.** The owner's decision (2026-08-29) is that
  Normal stays comfortable and the teeth go in the selector. Section 5's health
  bump is the single exception, and it is deliberately small.
- **New assets.** Per the standing handoff rule, the selector is built from
  plain `Button` nodes and the existing theme. If any part of this work turns
  out to need art, audio or animation, it stops and returns to Codex.
- **Re-measuring the gold curve.** Already flagged in `update.md` as owed to
  Slice 2. Difficulty tiers move the gold modifier, so this design makes that
  debt slightly larger; it does not pay it.

---

## 3. Difficulty is a parameter, not a global

The one real architectural decision here.

`data/` and `sim/` are pure. `test_sim_purity.gd` bans scene types, clocks, RNG
and platform state, and `Harness.run_wave` guarantees that the same input
produces the same result — the property that makes every balance claim in this
project a test rather than an assertion.

A mutable `Difficulty` autoload read from inside `Waves` would break that. The
same `run_wave` config would return different results depending on a global set
somewhere off-screen, and the purity test would have to be weakened to allow
it. **Rejected.**

Difficulty therefore travels the same way the wave number does: as an argument.

```gdscript
Waves.get_modifiers(wave_number, tier := Difficulty.NORMAL)
Waves.build_schedule(wave_number, tier := Difficulty.NORMAL)
Harness.run_wave({"wave": …, "towers": …, "path": …, "difficulty": …})
```

Defaulting the parameter to Normal is what keeps the existing suite green
without edits: Normal is the identity transform, so every one of the 13,436
current assertions describes Normal and continues to pass unchanged. That is
also the regression net for this work — if a Normal number moves, a test fails.

A third option was considered and rejected: **wave-offset difficulty**, where
Hard plays wave N as wave N+4. It is nearly free and reuses all existing
tuning, but it only fast-forwards a curve whose problem is that it is flat, and
it leaves spawn spacing — the sharpest lever available — untouched. It also
collides with `MAX_WAVES` and with the boss waves at 10 and 20.

### 3.1 The tier table

New file, `data/difficulty.gd`, pure data in the same shape as the rest of
`data/`:

```gdscript
class_name Difficulty

const NORMAL := &"normal"
const HARD := &"hard"
const NIGHTMARE := &"nightmare"

const ORDER: Array[StringName] = [NORMAL, HARD, NIGHTMARE]

const DEFS := {
    &"normal": {
        "label": "Normal",
        "count_multiplier": 1.0,
        "interval_multiplier": 1.0,
        "health_multiplier": 1.0,
        "speed_multiplier": 1.0,
        "gold_multiplier": 1.0,
        "starting_lives": 20,
    },
    # Hard and Nightmare values are SET BY THE SWEEP IN THE PLAN, not here.
    # Placeholders in this document would become the shipped numbers by
    # inertia, which is the exact failure the coverage finding came from.
}
```

Every tier carries every key, including Normal's identity row. A tier that
omitted a key would make the lookup site decide the default, which puts
balance numbers in code instead of in the table.

### 3.2 What each lever attacks

| Lever | Attacks | Why it is here |
|---|---|---|
| `interval_multiplier` | concurrency — how many are alive at once | The sharpest available lever. `Waves.INTERVAL_MS` is 500; halving it doubles the crowd a tower must cover without changing a single enemy stat. |
| `count_multiplier` | enemies per wave | Same constraint, blunter, and it compounds with the accumulating composition. |
| `health_multiplier` | hit points | Proven weak **alone** — wave-20 health ×11.5 leaked zero against a maxed board. Real in combination, because it lengthens the window during which concurrency matters. |
| `speed_multiplier` | time under fire | The other side of coverage: less time in range is the same as less range. |
| `gold_multiplier` | the board you can afford | Indirect and strong. Ten maxed towers is the shut-out threshold; income decides whether ten is reachable. |
| `starting_lives` | forgiveness | Cheap, legible, and the only lever a player feels immediately. |

`interval_multiplier` and `count_multiplier` are the two that address the
finding. The rest are there so a tier can be shaped rather than merely scaled.

### 3.3 Carrying the choice between scenes

`GameBoard.pending_map` is the existing pattern for run state that outlives a
scene change, set by `MainMenu.begin_new_run()`. Difficulty follows it exactly:
a static var on `GameBoard`, cleared by `begin_new_run()` alongside the map, so
"Play" always means a fresh run at the chosen tier.

`GameBoard` reads `Economy.STARTING_LIVES` at line 101 today; that becomes the
tier's `starting_lives`.

---

## 4. The menu

Three `Button`s in a row on the existing `Panel`, above Play, with the current
tier shown as pressed. No new scene, no new art, no theme work.

The chosen tier is also shown on the HUD during a run, because a run whose
difficulty is invisible produces bug reports that cannot be diagnosed — which
is the same lesson `BuildStamp` exists for.

---

## 5. Normal gets a pulse, not a rebalance

The single change to the default, and the one part of the owner's original
request that lands there.

A goblin has 5 health against a Basic tower's 4 damage: two shots, and at
100px/s it walks 4.2 tiles while dying. A bat has 3 health: **one shot**. Wave
1 is over in 4.6 seconds.

Base health rises so that the opening enemies survive a beat longer under the
starting board. The exact values come from the sweep, bounded by two
constraints that the plan must hold:

- The roster ordering `ogre > shaman > goblin > bat` is pinned by
  `test_data_tables.gd` and must survive, before and after wave scaling.
- Wave 5 against three ungraded Basics must not get *harder* than the 20 lives
  it already costs. The opening is a cliff; this must not steepen it.

This is explicitly not the fix for the shut-out board. Health alone was
measured as unable to threaten a good board at any rate. It is here to stop
wave 1 being over before the player has looked at it.

---

## 6. Closing the measurement gap

The part of this work most likely to still be paying off in six months.

### 6.1 The harness learns where enemies die

`run_wave` gains two result fields:

- `deepest_progress` — the furthest fraction of the route any enemy reached,
  0.0–1.0.
- `progress_at_death` — the mean fraction reached, over enemies that died.

Both are derived from `path_index` and the cumulative route length, which the
harness already tracks for movement. No new rules, no second implementation,
nothing that can drift from the live board.

This makes the owner's sentence a test:

```gdscript
# The first bend on The Pass is 768px into a 2,448px route.
const FIRST_BEND_FRACTION := 0.31
```

A wave where `deepest_progress` never exceeds 0.31 is a wave that was decided
before the first corner. That is now an assertion instead of an observation.

### 6.2 The benchmark covers the board the game hands out

`test_balance_tuning.gd` is extended to the **full legal roster** — three of
each kind, twelve towers, maxed — and pins the shape at Normal, Hard and
Nightmare. Its existing six-tower case stays: a mid-run board is worth
benchmarking too, it simply cannot be the only one.

The assertion that matters is directional and durable rather than a magic
number: *a full maxed board must not shut out the highest tier.* Written as
`leaks > 0` at Nightmare wave 20, it fails the moment the game becomes
unlosable again, whatever else moved.

---

## 7. Testing

| Area | What is pinned |
|---|---|
| `data/difficulty.gd` | Every tier carries every key; `ORDER` covers `DEFS`; Normal is exactly the identity row. |
| `Waves` | Modifiers and schedule at Normal are byte-identical to today's — the regression net for the whole change. |
| Tier monotonicity | For each lever, Nightmare is at least as punishing as Hard, which is at least as punishing as Normal. Catches a transposed table row, which no single-tier test can. |
| Harness | `deepest_progress` and `progress_at_death` are within 0.0–1.0; an undefended wave reaches 1.0; determinism holds per tier. |
| Balance | Full twelve-tower maxed board at each tier; the Nightmare shut-out assertion from 6.2. |
| Roster | Ordering survives the health bump, before and after wave scaling. |
| Menu | The tier reaches `GameBoard`; `begin_new_run()` clears it; lives come from the tier. |

Difficulty must not break determinism: same tier, same config, same result.
`test_harness.gd` already asserts this for the default and gains a per-tier case.

---

## 8. Risks, stated up front

**The sweep may find that Normal cannot stay comfortable and interesting.**
Section 2 fixes Normal's shape by owner decision, and section 5 gives it only a
health bump. If the sweep shows the opening is still dead on arrival, that is a
finding to bring back, not something to fix by quietly retuning Normal.

**Twelve maxed towers may not be affordable.** The shut-out threshold of ten
assumes a player can fund ten fully upgraded towers inside twenty waves. The
budget dropped 16 → 12 in `121bc7f` while `GOLD_PER_WAVE` did not move, so the
spend ceiling fell and the income did not. If ten maxed towers turn out to be
unreachable, the real threshold is lower than ten and the tiers must be
measured against what is affordable, not against what is placeable. **The plan
measures this before setting any tier values.**

**Hard and Nightmare are unplayed.** Every number in them will come from the
harness, and the harness has no projectile travel time — it resolves hits
instantly, which makes it kinder to the player than the live board is. Tier
values are a starting point to be played, not a finished tuning.

---

## 9. Deliberately not fixed here

- **The back half of every map is decorative.** Measured in section 1 and not
  addressed. Making late route matter is a map and mechanics problem — spawn
  points, flying paths, or enemies that must be handled twice — and it is a
  slice of its own, not a rider on a selector.
- **The opening cliff.** Wave 1 trivial, wave 5 fatal to a three-tower board.
  Section 5 softens the first step only.
- **Gold curve re-measurement.** Owed to Slice 2 already; this makes it larger.
