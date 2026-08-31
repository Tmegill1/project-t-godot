# Multi-lane harness, and a benchmark for every map

**Date:** 2026-08-30
**Target:** Godot 4.7.1, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

`sim/harness.gd` says of itself:

> It reuses the game's own sim modules, so there is no second rules
> implementation to drift. Every balance claim in this project is a test rather
> than an assertion because of this file.

That claim holds for **one map out of three**. Its header lists "one lane" among
its deliberate simplifications, and `run_wave` takes a single `path`. The Pass
has one lane; The Fork has two.

The gap became load-bearing on 2026-08-30, when The Fork's opening purse was
raised from 250 to 400. Every other number this week was swept, pinned, and in
two cases verified by restoring the defect and watching the assertion fail. That
one could not be. It rests on what a purse buys and on measured route geometry,
and its own comment says so:

> NOT simulated, unlike The Pass's purse. Harness.run_wave takes a single path
> and is one-lane by design; running each of this map's lanes separately with
> the same towers would have every tower firing down both at full rate, which
> over-counts coverage.

**Two of the three shipped maps cannot be measured at all**, and the project's
central claim quietly means "on The Pass".

### What the live board actually does

The behaviour to mirror is in `game/game_board.gd`, and it is specific:

- `start_next_wave` builds **one** schedule and gives every path its own cursor
  — `_spawn_queues` holds the same array per lane, `_spawned_per_path` holds the
  progress. Sharing the array is safe because it is only ever read.
- So **each lane runs the full wave.** Two entrances means twice the enemies of
  the same wave number, which is what The Fork's map comment has always claimed.
- `_spawn(kind, path_index, boss)` hands the enemy `_paths[path_index]`, so
  every enemy carries its own route.
- Towers see every enemy regardless of lane: `_physics_process` builds one
  `candidates` array from all of them.
- A wave clears only when **every** lane has issued its whole schedule and no
  enemies remain — `_all_spawns_issued()` exists precisely because checking one
  queue is not enough.

---

## 2. Goals and non-goals

**Goals**

1. `Harness.run_wave` simulates any number of lanes, matching the board's model
   above rather than approximating it.
2. Every existing call site keeps working, unedited, with byte-identical
   results. There are 64 of them across three test files, and they are the
   project's entire measured corpus.
3. `test_balance_tuning.gd` benchmarks **every** map, not only The Pass.
4. The suite stays fast enough that people run it.

**Non-goals**

- **Rebalancing anything.** This measures; it does not tune. If The Fork turns
  out badly balanced that is a finding to report, and fixing it is separate
  work with its own decision.
- **Per-lane spawn variation.** The board sends the same schedule down every
  lane. A future map wanting different waves per entrance is a different
  feature, and inventing the interface for it now would be guessing.
- **Removing the harness's other simplifications.** It still resolves hits
  instantly with no projectile travel time, which makes it kinder than the live
  board. That is untouched here and remains the standing caveat on every number
  it produces.
- **New assets.** Nothing here draws anything.

---

## 3. Lanes are an index, not a path per enemy

The one real architectural decision.

`run_wave` gains `config["paths"]`, an `Array` of `PackedVector2Array`.
`config["path"]` remains and means exactly `paths: [path]`. Each enemy dictionary
gains `"lane": int`; movement reads `paths[e["lane"]]`; route metrics are
precomputed once per lane and indexed the same way.

This mirrors the board directly — `_paths` plus a per-enemy path — which is the
property the whole file exists to preserve.

**Rejected: a `PackedVector2Array` on every enemy.** Closer to `game/enemy.gd`,
which stores `_path` on the node, but the harness holds enemies as dictionaries
in a hot loop and an integer is cheaper to carry than a packed array. It also
makes per-lane route metrics a straight lookup rather than a search.

**Rejected, on correctness: running each lane as a separate simulation and
summing the results.** It needs no change to the core loop at all, which is
exactly why it is tempting. It is also wrong: every tower would fire down every
lane at full rate, inventing coverage that does not exist. This is the same
reasoning that stopped The Fork's purse being "measured" that way in the first
place, and shipping it would produce numbers that look rigorous and are not.

---

## 4. What changes inside `run_wave`

**Spawning.** One schedule, one cursor per lane, mirroring `_spawn_queues` and
`_spawned_per_path`. Every lane issues the whole schedule, so an N-lane map
fields N times the enemies of the same wave number.

**Wave clear.** Today the loop ends when `spawned >= schedule.size()` and no
enemies remain. It becomes: every lane's cursor exhausted, and no enemies
remain — `_all_spawns_issued()` in another form, and for the same reason.

**Route progress.** `deepest_progress` stays "the furthest any enemy reached, as
a fraction of the route" — now a fraction of **its own** lane, maxed across
lanes. `progress_at_death` averages over every death the same way. Both keep
their current meaning for a single lane, which is what makes existing pins hold.

**Untouched.** Targeting, damage, splash, slow, the shaman aura and leak
resolution all iterate `enemies` and never look at a path. They need no changes,
and that they need none is worth stating: it is evidence the lane belongs to the
enemy rather than to the rules.

---

## 5. Backward compatibility is the load-bearing guarantee

Every balance number this project has measured came through the single-path
interface. The change is only safe if that interface is provably unchanged.

Two assertions carry it:

1. `run_wave({"path": p, ...})` returns a dictionary **equal** to
   `run_wave({"paths": [p], ...})` for the same config. Not "similar" — equal,
   including tick counts and both progress fields.
2. **The entire existing suite passes with no call site edited.** 13,782 checks,
   64 of them calling `run_wave`. If one number moves, the change is wrong.

The second is the real net. The first exists so that a failure points at the
right place.

---

## 6. A benchmark for every map, and the placement problem

`test_balance_tuning.gd` hardcodes tower positions — `[[3, 3], [5, 3], …]` —
that are legal on The Pass and meaningless elsewhere. A per-map benchmark cannot
carry them.

**Where twelve towers land decides what the benchmark says.** A naive "first
twelve legal tiles" would cluster them in a corner and make a map look far worse
than it plays; the difficulty work of 2026-08-29 already measured that clustering
and spreading give identical results *on The Pass*, but that is a finding about
one route, not a licence to place carelessly on others.

So the rule is stated rather than left implicit: **walk the route and space the
towers along it**, taking the first legal position near each of twelve evenly
spaced points, asked of `Placement.can_place` — the same rule the board enforces,
not a reimplementation. Twelve because every shipped map carries the same
`tower_budget` of 12; the helper takes the budget from the map rather than
assuming it.

On a multi-lane map the twelve are **divided between the lanes** — six and six
on a two-lane map — and spaced along each, so both entrances get cover. Dividing
rather than walking a concatenated route matters: a single walk over both lanes
end to end would space by total distance and could leave the shorter lane with
fewer towers than its share of the threat, when both lanes carry the same wave.

A test pins the rule itself: every position the helper returns is one the board
would accept, and it returns the full twelve on every shipped map. A benchmark
whose placement is not stated is a number nobody can argue with.

---

## 7. Runtime, budgeted rather than discovered

The full-board sweep already walks sixteen boards twice — once on Nightmare's
last wave, once at the reference wave. Extending it to three maps triples that,
and The Fork's two lanes make each of its runs heavier than a single-lane run of
the same wave.

The suite currently takes about 70 seconds.

**Budget: three minutes.** If the honest implementation lands past it, the
per-map sweep drops to the two extreme builds — all sustained and all burst —
while The Pass keeps all sixteen. That keeps the branch-spread bound, which
needs the full set, where it already lives, and asks the other maps the
narrower question they exist to answer: does a good board hold this map.

Stated in advance because the alternative is discovering it afterwards and
quietly shipping a suite nobody runs.

---

## 8. Testing

| Area | What is pinned |
|---|---|
| Compatibility | `path` and `paths: [path]` return equal dictionaries; the whole existing suite passes unedited |
| Spawning | An N-lane wave fields N times the enemies; each lane issues the entire schedule |
| Wave clear | A wave does not clear while any lane still has spawns pending |
| Progress | `deepest_progress` and `progress_at_death` stay 0.0–1.0 and keep their single-lane values |
| Determinism | Same config, same lanes, same result |
| Placement | Every generated position is one `Placement.can_place` accepts; twelve are found on every shipped map |
| Balance | Every map benchmarked at Normal and at the hardest tier |

---

## 9. Risks

**The Fork may turn out badly balanced.** It is the most likely outcome — it has
never been measured, and it fields twice the enemies down lanes barely half as
long. That is a finding to report, not to fix here; §2 says why, and quietly
retuning a map inside a change that exists to make measurement possible would
destroy the evidence it was built to produce.

**A per-map benchmark can be honest or fast, and this one has to be both.** §6
and §7 name the two ways it goes wrong — careless placement, and a runtime
nobody tolerates — and pick a rule and a budget for each in advance.

**The single-lane path must not become a special case.** If `paths: [p]` and
`path: p` ever diverge, every number this project has measured is in question.
That is why §5's equality assertion is written as equality and not as a
tolerance.
