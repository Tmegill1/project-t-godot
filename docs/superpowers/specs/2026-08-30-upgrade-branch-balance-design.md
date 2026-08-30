# Upgrade branch balance: splash, flat numbers, and a legible panel

**Date:** 2026-08-30
**Target:** Godot 4.7.1, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

The owner asked whether a fully upgraded board survives wave 20 on Nightmare.
Measuring it found that the answer depends almost entirely on **which upgrade
branch you took**, and by a margin that makes the choice not a choice.

A tower may take one branch deep only while the other stays at 2, so a fully
upgraded tower is either `sustained 4 / burst 2` or `sustained 2 / burst 4`, and
a board picks one per kind: **sixteen legal fully-upgraded boards.** Lives lost
across a twenty-wave Nightmare run, twelve maxed towers on The Pass:

| Board | Run lives lost |
|---|---|
| All sustained | **9** |
| …but Mortar on burst | **6** |
| …but Basic on burst | 40 |
| …but Magic on burst | 100 |
| …but Long Range on burst | **200** |
| All burst | **336** |

**A 37× spread between the best build and the worst.** No difficulty number
closes it, because it is not a difficulty problem.

### The mechanism, measured rather than assumed

Two effects multiply each other.

**Three of the four towers can buy splash** — Basic to 75px, Mortar to 130px,
Long Range to 90px. And a splash hit applies its **whole payload** to everyone
caught, slow included; `sim/harness.gd` says so explicitly and
`Projectile.applyTo` does the same on the live board. So one Magic tower holding
*Deep Freeze* (45% speed for 2.5s) plus any splash tower slows the **entire
wave**, continuously.

**Long Range is the worst offender.** Its sustained branch gives it 90px splash
at 150 × 1.2 × 1.33 = **239px range** — wider effective area coverage than the
Mortar, which is supposed to be the area specialist. Dropping Long Range to
burst costs the board 191 lives, the largest single swing of the four.

The Mortar's own comment in `data/upgrades.gd` already states the rule this
breaks:

> Both branches widen or deepen area damage rather than reaching for pierce,
> detection or slowing — those belong to the other three, and a tower that could
> take them would answer everything.

Basic and Long Range both reach for area. A board that takes them does answer
everything.

### The second mechanism: multiplicative compounding

Every damage and fire-rate tier is a **multiplier**, and multipliers compose:

| Path | Composition | Result |
|---|---|---|
| Basic burst 4 | 1.4 × 1.4 × 1.5 × 2.0 | **×5.88 damage** |
| Long Range burst 4 | 1.4 × 1.4 × 1.3 × 2.0 | ×5.10 damage |
| Basic sustained 4 | 0.8 × 0.8 × 0.9 | fires **1.74× as often** |
| Long Range sustained 2+4 | 0.7 | fires 1.43× as often |

Compounding is what makes the deep tiers explode and the branches diverge: two
tiers of ×1.4 is not 80% more damage, it is 96%, and the shape gets worse the
deeper the branch goes. It also makes the tier text unreadable — *"Damage up by
40% again"* requires the player to remember what it was 40% of.

### The third problem, which the owner raised directly

**The tier description is a tooltip.** `ui/tower_inspector.gd` records why: the
sidebar is 140px, a `Button` does not wrap its text, and *"Quick Loader — 30g"*
on one line was measured overflowing it. So what a tier actually does is
invisible unless you hover — and on a touch-first game, hover does not exist.

---

## 2. Goals and non-goals

**Goals**

1. Return area damage to the Mortar, so the roster's stated roles are the roles
   it has.
2. Replace multiplicative damage and fire rate with flat, per-tower amounts, so
   the deep tiers stop compounding and the numbers stop needing mental
   arithmetic.
3. Show what each tier does **in the panel**, without hovering.
4. Bring the sixteen-board spread from 37× to roughly **3×**, and pin a bound so
   it cannot silently reopen.

**Non-goals**

- **Changing how splash delivers its payload.** Making splash victims take
  reduced damage or no slow was considered and rejected for this slice: with
  only the Mortar splashing, the board-wide slow dies anyway, and changing the
  rule as well would retune the Mortar by accident. It stays available as a
  later lever.
- **Redesigning the difficulty tiers.** Hard and Nightmare keep their shape and
  their levers. Their *values* must be re-measured — see §7 — because they were
  swept against boards that had splash on three towers.
- **New assets.** Per the standing owner rule in `.ai/handoff.md`, the inspector
  change uses existing `Label` nodes and the existing theme. If any part turns
  out to need art, it stops and returns to Codex.
- **Widening the sidebar.** The 140px column is load-bearing — `CONTINUE.md` §14
  records that the inspector already uses 465px of a 672px viewport and that the
  shortest shipped map is the binding constraint. The design fits the budget
  instead of raising it.
- **Rebalancing tower base stats.** Only upgrade tiers move.

---

## 3. Rule one: area damage belongs to the Mortar

`splash_radius` appears only on Mortar tiers. Basic's *Fragmentation* and
*Saturation* and Long Range's *Shellburst* and *Carpet Fire* lose it and gain
flat damage, fire rate or range in its place, keeping each branch's stated
identity:

| Tower | Branch summary today | What replaces splash |
|---|---|---|
| Basic | *"Faster fire, then splash. Clears crowds."* | more rate and reach — a generalist that clears crowds by firing, not by blasting |
| Long Range | *"Reach and cadence, then splash. Covers ground nothing else can."* | more reach and cadence — it covers ground by seeing further, which is what its name promises |

Labels and flavour descriptions are rewritten to match. **Costs do not move** —
retuning price and effect in the same pass would leave neither measurable.

`test_data_tables.gd` already asserts that only the Mortar has base splash. This
extends that rule to upgrades, where it was silently broken.

---

## 4. Rule two: flat damage and fire rate

### 4.1 The two new effect keys

`sim/upgrades.gd` already documents the convention — *"Multipliers compose, flat
bonuses add, and radii, slows and gold take the strongest value"* — and already
resolves one flat key, `pierce_bonus`. Two more join it:

| Key | Meaning |
|---|---|
| `damage_bonus` | flat damage added to the tower's base |
| `fire_rate_bonus_ms` | milliseconds removed from the firing interval |

`damage_multiplier` and `fire_rate_multiplier` are **removed from the codebase
entirely**, not merely unused — a key that still resolves is a key someone adds
back. All 32 tiers convert.

Everything else stays: `range_multiplier`, `splash_radius`, `slow_factor`,
`slow_duration_ms`, `gold_multiplier`, `bonus_gold_per_kill`, `pierce_bonus`,
`detection`. Splash, slow and gold already take the **strongest** value rather
than stacking, so they never compounded and need no change.

### 4.2 Per-tower values, and why that is not a nicety

Base fire rates run from 500ms (Magic) to 2000ms (Mortar), and base damage from
2 (Magic) to 15 (Long Range). A single flat value shared across the roster would
be a rounding error on one tower and a rewrite of another: *"fires 0.5s faster"*
takes the Mortar from 2000ms to 1500ms and takes Magic to **zero**.

So every tower's flat values are scaled to its own base, and the resolver
carries a floor:

```gdscript
## No tower may fire faster than this, whatever it buys. Flat bonuses do not
## compound, but they do not asymptote either - without a floor a deep branch
## walks the interval to zero and then negative.
const MIN_FIRE_RATE_MS := ...
```

The floor's value comes from the sweep, not from this document.

### 4.3 Order of operations

There is none to decide, and that is deliberate. Damage and fire rate become
flat-only; range stays multiplier-only. No stat takes both kinds of effect, so
no tier's result depends on the order tiers are applied in. Keeping one stat
mixed would reintroduce exactly the reasoning this change exists to remove.

### 4.4 No numbers in this document

The flat values, and the floor, are set by the sweep in the implementation plan.

This is a rule the project learned the hard way twice in one week: the six-tower
benchmark and the first difficulty rows both shipped figures that were written
down before they were measured. A plausible number in a design document becomes
the shipped number by inertia. The plan measures, then pins.

---

## 5. The panel says what the tier does

### 5.1 A generated stat line, not a written one

New pure function in `data/upgrades.gd`:

```gdscript
static func effect_summary(effects: Dictionary) -> String
```

It renders an effects dictionary to a short line — `"+12 damage · fires 0.4s
faster"`, `"95px blast"`, `"slows to 45% for 2.5s"` — in a fixed key order so
two tiers with the same effects read the same way.

**Generated rather than written, for one reason:** the number on screen is then
the number the tier applies, permanently. A hand-written description drifts the
first time a value is tuned, and this slice tunes all 32 of them.

The hand-written `description` field stays, as the tooltip. It carries flavour
and the things numbers cannot say — *"Reveals and targets phased enemies"* — and
is no longer the only way to see what a tier costs you.

### 5.2 The anti-drift test

A test walks every tier in `Upgrades.DEFS` and asserts that its effects render
to a non-empty summary containing no unrecognised key. Adding an effect without
teaching `effect_summary` about it therefore fails the suite, rather than
silently rendering a tier as blank in the panel.

### 5.3 The inspector

A wrapping `Label` under each of the two branch buttons, showing
`effect_summary` for the **next** tier — the one the button would buy. A `Label`
is used precisely because a `Button` is not: labels wrap, which is what makes
140px workable at all.

When a branch is maxed or locked the line is empty, because there is no next
tier to describe.

**The fit budget is real and already measured.** `CONTINUE.md` §14: the
inspector uses 465px of a 672px viewport, the viewport height is the shortest
map's pixel height, and `test_tower_panel.gd` pins it. Two wrapped lines must
land inside the remaining headroom, and the fit test is extended to cover them.
If the generated lines do not fit, the answer is shorter phrasing — not a wider
column.

---

## 6. Success criteria

Directional and pinned, so they survive later retuning:

| Claim | How it is pinned |
|---|---|
| No legal maxed board shuts out the hardest tier | existing, `test_balance_tuning.gd` |
| Every legal maxed board wins Normal | existing, `test_balance_tuning.gd` |
| **The branches are close** | **new:** worst-board lives lost is at most a pinned multiple of best-board, over a full Nightmare run |
| Only the Mortar splashes | `test_upgrades.gd`, resolved stats not just the table |
| A tower cannot out-fire the floor | `test_upgrades.gd` |
| Every tier renders in the panel | `test_upgrade_tables.gd` |
| The panel still fits the shortest map | `test_tower_panel.gd` |

The branch-parity bound is the one that matters. The last two rounds of this
work both failed by pinning a *board* rather than a *bound*: the six-tower
benchmark, then the single-split twelve-tower benchmark. A bound cannot be
satisfied by picking a convenient example.

**The multiple itself is set by the plan, from what the sweep achieves**, with 3×
as the target. Two constraints on it, so it cannot be quietly widened into
meaninglessness: it must fail against today's roster, where the spread is 37×;
and it is written as a ratio rather than as a pair of absolute figures, so
retuning the difficulty rows in step 4 moves both sides together and leaves the
claim intact. If the sweep cannot reach 3×, the plan pins what it did reach and
says so — a worse bound honestly recorded still fails the 37× it replaced.

---

## 7. Sequencing, and the one risk in it

1. Flat keys and the floor in `sim/upgrades.gd`, tests first.
2. Convert all 32 tiers; splash to the Mortar alone.
3. Sweep the sixteen boards; tune the flat values until the spread closes.
4. **Re-sweep Hard and Nightmare.**
5. `effect_summary`, the inspector labels, the fit test.
6. Docs.

**The risk:** steps 3 and 4 interact. Retuning towers changes what the difficulty
rows need, and retuning the rows changes how the towers read. The order above
settles tower parity **first**, measured at Normal where every build currently
wins, and sets the difficulty rows last against the finished roster. If that
ordering does not converge — if closing the spread at Normal reopens it at
Nightmare — that is a finding to bring back, not something to fix by loosening
the bound.

**A second, smaller risk:** removing splash from two towers weakens the strongest
board substantially, so Nightmare's current 4.5× health is very likely to be too
harsh afterwards. That is expected work in step 4, not a surprise.

---

## 8. Deliberately not fixed here

- **Splash carrying its full payload to every victim**, slow included. Left as a
  future lever; §2 says why it is not pulled now.
- **The dormant tiers.** *Spotter*'s detection and Long Range's `pierce_bonus`
  are inert until phased and armoured enemies land. They convert like everything
  else and stay dormant.
- **Tower base stats and costs.** Only tier effects move, so the sweep measures
  one thing at a time.
