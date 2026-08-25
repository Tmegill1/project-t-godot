# Slice 0 — wave economy, visible limits, and maps 2 and 3

**Date:** 2026-08-24
**Source:** [`Tmegill1/project-t`](https://github.com/Tmegill1/project-t), `td-browser/` at `main`
**Target:** Godot 4.7.1, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

The core slice, tower upgrades, free placement and two art swaps are merged.
The game is playable end to end and nobody has a reason to play it twice.

Three problems are visible in the code rather than in a playtest:

1. **Once the player presses Start, they have nothing to do.** Towers fire
   themselves. The only inputs during a wave are placing, upgrading, selling
   and a speed toggle.
2. **Waves 6–20 are the same fight fifteen times.** `Waves._ENDLESS_BUNDLE`
   repeats one bundle with +10% health and +5% speed per wave.
3. **Nothing is saved.** A run ends and returns to the menu having changed
   nothing, including the mute button.

This slice takes the cheapest bite out of (1) and (2) and leaves (3) alone.
It does four things:

- Ports the wave economy — wave-clear bonus, interest, and calling a wave
  early against a prep countdown.
- Surfaces the per-kind tower limits and map budget that **already exist and
  are already enforced** but are invisible to the player.
- Adds The Fork and The Coils, which requires fixing multi-spawn and the
  viewport.
- Fixes the HUD text that is illegible on ice and desert, which the two new
  maps make reachable.

Later slices, in dependency order: bosses and enemy properties, tactical
powers, the versioned save and meta-progression, and a hero.

**Recorded for the powers slice, decided by the owner on 2026-08-24 and not
built here:** powers are to be **bought with gold and priced expensively**, as
a late-run sink, and/or **tied to particular tower kinds** rather than bought
from a separate currency. That diverges from upstream, where powers cost
Insignia earned from lieutenants and bosses. It also changes the arithmetic in
§4.6 when it lands — a large gold sink at the end of a run is exactly what the
surplus analysis says is missing — so the gold curve should be re-measured
then rather than assumed to still hold.

## 2. Goals and non-goals

**Goals**

1. Give the player a decision between waves that is not "press Start".
2. Make the constraints the game already enforces legible before they bite.
3. Two more boards, and the ice and desert art becoming reachable.
4. Every new rule lands in `sim/` and is exercised by both the harness and
   the game, per the standing rule.

**Non-goals**

- Broad rebalancing. Tower costs, upgrade costs, enemy health and enemy speed
  are all ported as-is and stay unplaytested. **The one exception is the gold
  curve**, which this slice must touch because adding income on top of the
  existing faucet measurably breaks it — see §4.6.
- Persistence of any kind. No settings file, no save. Slice 3 owns that.
- A map-select screen. Maps chain through `next` within a session, which is
  what the existing `Maps.DEFS` field already anticipates.
- New enemies, bosses, properties or currencies.

## 3. Scope

### In

| Area | Detail |
|---|---|
| Economy data | `WAVE_CLEAR`, `CALL_EARLY`, `INTEREST` constant groups in `data/economy.gd` |
| Economy rules | `wave_clear_bonus`, `interest_on`, `call_early_bonus` in `sim/economy.gd` |
| Gold curve | Decreasing `gold_modifier` in `Waves.get_modifiers`, applied in `EconomySim.kill_reward` (§4.6) |
| Prep timer | 20s countdown between waves, auto-starting the next; not before wave 1 |
| HUD | Prep countdown, call-early button with live payout, `Towers n/N` budget readout, backing plate |
| Build panel | Per-kind `n/N` count beside each price |
| Maps | `data/map2.gd` (The Fork), `data/map3.gd` (The Coils), registry entries, seeds |
| Multi-spawn | The wave schedule runs once per spawn path |
| Layout | Per-map `content_scale_size` so larger boards fit |
| Biomes | The Fork → ice, The Coils → desert |

### Out

Bosses · enemy properties · lieutenants · currencies beyond gold · tactical
powers · save and meta-progression · hero · map-select UI · per-biome endpoint
art (still open, §9.1 of `CONTINUE.md`).

## 4. The economy

Three pure functions, ported from upstream `sim/economy.ts` with its constants
from `data/economy.ts`. All arithmetic below is upstream's, stated exactly.

### 4.1 Constants

```
WAVE_CLEAR: base_bonus 20, bonus_per_wave 5,
            fast_clear_ms 20000, slow_clear_ms 60000, max_speed_bonus 40
CALL_EARLY: prep_duration_ms 20000, gold_per_second 3, max_bonus 45
INTEREST:   rate_per_wave 0.05, max_per_wave 30, minimum_balance 50
```

### 4.2 `wave_clear_bonus(wave, clear_ms) -> Dictionary`

Itemised, not a single number, because the UI must be able to tell the player
*why* they were paid or the incentives stay invisible.

```
base     = base_bonus + max(0, wave) * bonus_per_wave
span     = max(1, slow_clear_ms - fast_clear_ms)
slowness = (max(0, clear_ms) - fast_clear_ms) / span
speed    = round(max_speed_bonus * clamp01(1 - slowness))
```

Returns `{base, speed}`. **Divergence from upstream, deliberate:** upstream's
`waveClearReward` also folds interest into this call and computes `interestOn`
twice in one function body. Here interest is its own function called once by
the board. Same result, one responsibility each, and the board is already
where the banked balance lives.

### 4.3 `interest_on(banked) -> int`

```
if banked < minimum_balance: 0
else: min(max_per_wave, floor(banked * rate_per_wave))
```

The cap is load-bearing. Uncapped compounding makes hoarding strictly better
than building, which inverts the game.

### 4.4 `call_early_bonus(remaining_ms) -> int`

```
seconds = floor(clamp(remaining_ms, 0, prep_duration_ms) / 1000)
return min(max_bonus, seconds * gold_per_second)
```

The cap stops rushing from dominating the wave-clear bonus and reducing the
game to a race.

### 4.5 The prep timer

`GameBoard` gains `_prep_remaining_ms`, counted down in `_physics_process`.
On reaching zero it calls `start_next_wave()` itself. `start_next_wave()` pays
`call_early_bonus(_prep_remaining_ms)` whenever it is called with time on the
clock, so one code path serves both the button and the timeout.

Two properties follow from putting the timer in `_physics_process`, and both
are correct:

- **`Engine.time_scale` scales it.** At the HUD's 1.5x the prep window passes
  1.5x faster in wall-clock terms. Fast-forwarding must not buy real thinking
  time, and this falls out rather than needing a special case.
- **It stops when the run is finished**, because `_physics_process` already
  returns early on `_run_finished`.

**The timer does not run before wave 1.** A countdown on an empty board, with
100 gold and no information, is hostile to a new player, and the payout is
meaningless when there is nothing yet to spend it on. The clock starts when
the first wave clears.

**Nor after the last one.** `_on_wave_cleared` pays the wave-clear bonus for
every wave including the twentieth — clearing the final wave is still a clear
and still earns — but it must set `_run_finished` and emit `victory` *before*
arming the timer, or a won run starts a twenty-first wave that cannot exist.
The ordering inside that method is load-bearing and gets its own test.

`clear_ms` is measured with the existing `_wave_clock`, which already
accumulates scaled delta from the wave's start.

## 4.6 The gold curve

**This slice cannot add income without also tuning the faucet.** Measured, not
estimated — the scripts are throwaway but the numbers are exact.

### What the economy does today

| | Gold |
|---|---|
| Starting gold + kill rewards over 20 waves | **15,985** |
| Most a player could possibly spend (16 towers, best mix, every tier the cross-path rule allows) | **17,170** |
| Gap | **−1,185** |

A run ends about 1,200 short of a maxed board. That is good: the player cannot
have everything, so what they buy is a choice.

### What Slice 0 would do to it, unmodified

The wave economy adds ~3,555 gold (wave-clear 1,450, speed bonus up to 800,
call-early up to 855, interest ~450) against **no new sink at all**. A 22%
income rise turns the −1,185 deficit into a **+2,370 surplus**. Gold stops
being a constraint for the last third of every run. Shipping the port
unchanged would make the game worse, measurably.

### The deeper problem: the curve, not the total

| | Kill income | Share |
|---|---|---|
| Waves 1–10 | 3,185 | 20% |
| Waves 16–20 | 7,600 | **48%** |

Wave 20 pays 1,720 against wave 1's 25 — **68.8×**. Half the run's money
arrives after the board is built and the upgrade paths are locked. The cause is
structural: composition accumulates from wave 1 (161 enemies at wave 20 against
5 at wave 1) while each kill pays a flat reward, so income tracks a compounding
enemy count. Upstream's `20 + 5 × wave` wave-clear bonus escalates too, feeding
the part of the run that is already drowning.

### The fix

A **decreasing gold modifier**, added to `Waves.get_modifiers` beside the
health and speed modifiers that already scale per wave:

```
GOLD_PER_WAVE     = 0.025
MIN_GOLD_MODIFIER = 0.40

gold_modifier = max(MIN_GOLD_MODIFIER, 1.0 - GOLD_PER_WAVE * past)
  where past = max(0, wave - LAST_AUTHORED_WAVE)
```

This is deliberately the same shape as `health_modifier` and `speed_modifier`,
in the same function, so per-wave scaling stays in one place with one idiom.

Chosen by sweeping decay and floor against the spend ceiling:

| decay | floor | Grand total | vs ceiling | wave 20 / wave 1 |
|---|---|---|---|---|
| 0.000 | — | 19,540 | **+2,370** | 68.8× |
| 0.020 | 0.45 | 16,532 | −638 | 26.5× |
| **0.025** | **0.40** | **15,780** | **−1,390** | **23.9×** |
| 0.030 | 0.40 | 15,028 | −2,142 | 21.3× |
| 0.040 | 0.35 | 13,523 | −3,647 | 27.5× |

0.025/0.40 lands the grand total at 15,780 against a 17,170 ceiling — a 1,390
deficit, essentially the 1,185 the game ships with today — while cutting the
back-loading ratio by nearly two thirds.

Income still rises across the run, from about 50 gold on wave 1 to about 1,195
on wave 20. That is intended. A wave fielding 161 enemies *should* pay more
than one fielding five; the goal was never a flat curve, only to stop it being
a 69× cliff.

**One honest note: the 0.40 floor never binds inside twenty waves.** At wave 20
the modifier is 0.625. The floor exists so endless play past roughly wave 29
cannot drive a kill reward to zero or negative. It is a safety rail, not an
active part of the tuning, and a test should pin it as such rather than
implying it shapes the 20-wave run.

**Kill rewards themselves are not touched.** Slime 5, Ogre 20, Bee 10 stay as
they are; the modifier scales them at the point of payment. That keeps the
per-enemy values readable as relative worth, and means one constant tunes the
whole curve.

`EconomySim.kill_reward` already applies a multiplier and a flat bonus from the
killing tower's upgrades. The wave modifier composes with those, and the order
matters: the **wave modifier applies to the base reward before the tower's gold
multiplier**, so the Bounty Hunter branch multiplies what the wave actually
pays rather than an unscaled figure. Pinned by its own test.

## 5. Visible limits

Nothing about the rules changes. Per-kind caps (`Towers.DEFS.base_limit`:
Basic 8, Fast 8, Mortar 5, Long Range 5), the map budget
(`Maps.DEFS.demoMap.tower_budget` 16) and cost escalation are all already
enforced in `GameBoard._try_place`, each with its own rejection message. The
player simply cannot see any of them until one refuses a placement.

- **Build panel:** each button gains the kind's `n/N` beside its price,
  from `board.get_tower_count(kind)` and `EconomySim.tower_limit(kind, map)`.
- **HUD:** a `Towers n/N` readout for the map budget.

`TowerPanel` already refreshes on `gold_changed` and `tower_placed`. Selling
happens to emit `gold_changed`, so the count would appear to update — by
coincidence, not by design. A `tower_sold` signal is added and connected, so
the panel depends on the event it actually cares about.

## 6. The maps

### 6.1 What they are

| Map | Label | Tiles | Pixels | Spawns | Budget | Gold |
|---|---|---|---|---|---|---|
| `demoMap` | The Pass | 23×14 | 1104×672 | 1 | 16 | 100 |
| `map2` | The Fork | 26×17 | 1248×816 | **2** | 20 | 250 |
| `map3` | The Coils | 28×16 | 1344×768 | 1 | 18 | 200 |

Both are algorithmic builders in upstream TypeScript, the same shape as
`demoMap.ts` — authored path legs, then a seeded scatter of blocked tiles.
They port the way `data/demo_map.gd` did, each with its own seed in
`data/seeds.gd` and a golden-board test.

### 6.2 Multi-spawn

`GameBoard._spawn` currently uses `_paths[0]` and ignores every other path.
`PathFinder.get_all_spawn_paths` has always returned all of them; the core
slice simply had one spawn and never exercised it. The Fork has two.

**The rule, ported faithfully:** the full wave composition runs down *every*
path. Upstream is explicit — `GameScene.ts:677` computes
`totalEnemies * this.enemyPaths.length`. The wave is duplicated per entrance,
not divided between them, which is why The Fork opens with 250 gold and a
budget of 20 against The Pass's 100 and 16.

### 6.3 Layout — per-map `content_scale_size`

Both new maps are larger than the 1244×672 design viewport, in both axes.

On board ready, `get_window().content_scale_size` is set to the map's pixel
size plus the panel width. The stretch system does the downscaling, and
**world space remains identical to map pixel space.**

That last property is the whole reason for this choice. Placement, targeting,
splash geometry, `TowerPanel.offset_left` and every test that reads a
coordinate all assume world == map pixels today.

Two alternatives were considered and rejected. A `Camera2D`, or scaling the
`GameBoard` node, each insert a transform between `get_global_mouse_position()`
and the rules consuming it. `Placement.can_place` is precisely the kind of
geometry code where a coordinate-space mismatch passes most tests and fails at
the corners — and this project's own history says geometry bugs are found by
screenshots, not by suites. A base-resolution change reaches the same result
with no transform at all.

`README`'s "How the layout responds to window size" model is unchanged by
this: it describes how surplus is distributed at a given base size, and this
only changes what that base size is.

### 6.4 Biomes and HUD legibility

The Fork draws in ice, The Coils in desert. All three baked sets become
reachable; today `data/maps.gd` hardcodes forest and two thirds of the art is
dead weight.

That immediately hits the open problem in `CONTINUE.md` §9.5: the HUD's white
Gold/Lives/Wave text has no backing plate and is confirmed illegible on both
ice and desert, with screenshots at `docs/screenshots/board-{ice,desert}.png`.

**Fix: a semi-transparent dark backing plate behind the `Top` bar.** §9.5
lists three candidates — a plate, a text shadow, or a per-biome tint. The
plate is chosen because it is biome-independent: one change that cannot be
wrong on a fourth biome someone adds later, where a per-biome tint needs a new
value each time and a shadow needs re-checking against every ground colour.

## 7. Testing

| Area | How |
|---|---|
| Economy functions | Port every upstream test, then mutation-test. Pure `sim/`, so `test_sim_purity.gd` keeps holding. |
| Prep timer | Board-level: counts down, auto-starts, pays on early call, does not run before wave 1, stops on run end. |
| Maps | Golden-board tests, the shape of `test_demo_map.gd`. |
| Multi-spawn | Harness test that a two-path map produces double the spawns of a one-path map at the same wave. |
| Limits UI | Assert label text against `get_tower_count` / `tower_limit`; assert the `tower_sold` connection. |
| Layout, HUD plate | **Screenshots through the Godot MCP.** The suite never puts nodes in a live tree, so it cannot see either. |

## 8. Risks

1. **The undefended-termination sweep must be re-run on both new maps.**
   `test_every_wave_undefended_terminates_at_the_doubled_tick_size` is the
   guard against the waves 19/20 soft-lock, and that bug was *path-geometry
   dependent* — a constant step oscillating around a waypoint. New paths mean
   new geometry, and The Coils is explicitly serpentine, which is bends, which
   is where the oscillation lived. This is the single highest-risk item here.

2. **The Fork's doubled spawn count compounds with wave scaling.** Double the
   enemies at wave 20's health multiplier is a load nothing has simulated. The
   harness can answer it before a human plays it, and should.

3. **`content_scale_size` at runtime is unverified on this engine.** Set before
   the first frame it is expected to behave as the project setting does, but
   this project's rule is that layout claims need a screenshot. Verify on all
   three maps.

4. **The prep timer is the first thing that starts a wave without the player.**
   Anything reading `wave_state_changed` now sees transitions it never
   initiated. The end screens are the ones to check.

## 9. Deliberately not done

- **No map-select UI.** Maps chain by `next`, which `Maps.DEFS` already
  carries and which `map3` terminates with `null`. Choosing a map is a
  progression question and belongs with the save in slice 3.
- **No per-biome endpoint art.** Still open in §9.1; the goal and spawn render
  identically in all three biomes. This slice makes that *more* visible by
  making two more biomes reachable, but tripling the endpoint art is its own
  decision.
- **The orphaned `assets/enemies/**` directory is not deleted.** Unrelated to
  this slice.
