# Tower upgrades — the first slice beyond the core

**Date:** 2026-08-14
**Source:** [`Tmegill1/project-t`](https://github.com/Tmegill1/project-t), `td-browser/src/game/{data,sim}/upgrades.ts`
**Target:** Godot 4.7.1.stable, GDScript, on top of the completed core slice
**Status:** design approved, ready for planning

---

## 1. Why this document exists

The core slice shipped four towers that cannot be upgraded. Upgrade branches
are the first item on the port design's "Out" list (§3 of
[`2026-08-09-godot-port-design.md`](2026-08-09-godot-port-design.md)), and the
largest single thing standing between this port and the Phaser original.

This spec covers upgrades and the two mechanics they need. It does **not**
cover the five composable enemy properties, even though the reference designed
the two together — see §3.

## 2. What the reference actually is

`sim/upgrades.ts` and `data/upgrades.ts` define a complete system:

- **Two branches per tower**, `sustained` and `burst`, four tiers each.
- **A cross-path rule**: a branch may pass tier 2 only while the other branch
  sits at tier 2 or below. The reference's own header calls this "the whole
  point" — without it, gold is the only constraint and every tower converges on
  the same fully-upgraded shape.
- **Per-tier costs** rising roughly 2× per tier, from 30–60 gold at tier 1 to
  260–500 at tier 4.
- **Composition rules**: multipliers compose, flat bonuses add, and splash
  radius, slow and gold effects take the strongest value rather than stacking —
  so tier 4's big splash replaces tier 2's small one instead of summing with it.
- **Four visual tiers** driven by *total* investment across both branches
  (`ceil(total / 2)`, capped at 3), indexing the `upgrade_frames` array each
  tower already carries in `data/towers.gd`.

The artwork is already sliced: every tower def has four frames and the port
currently draws only `upgrade_frames[0]`.

## 3. Scope

### The problem this scope solves

The reference's branch identities exist to spread *scarce counters* across
towers: detection on Basic, slowing on Fast, heavy pierce on Long Range. Those
counter the phased, swift and armoured enemy properties — none of which the
core slice ported. A faithful port of all 32 tiers would therefore ship tiers
that do nothing.

Auditing what today's `sim/` can express:

| Effect | Machinery | Live? |
|---|---|---|
| damage / fire rate / range multipliers | `Tower.tick`, `Targeting` | ✅ |
| splash radius | `Damage.in_splash` | ✅ |
| pierce | `Damage.resolve` reads `source.pierce` vs `target.armor` | ⚠️ dormant — no enemy has armour |
| detection | `Targeting` gates on `phased` | ⚠️ dormant — no enemy is phased |
| slow | none | ❌ must be built |
| gold multiplier / bonus gold | none | ❌ must be built |

### In

- The full two-branch, four-tier structure, cross-path rule and cost table,
  ported verbatim.
- **Slow** and **gold-per-kill**, built here. Both are self-contained: they
  work against any enemy and need no enemy properties.
- **Pierce and detection wired but dormant.** Both already have working
  machinery that simply has no target yet; when armoured and phased enemies
  land, they start biting with no further work.
- The upgrade UI, and Sell moving to sit beside the tiers it refunds.

### Out

- The five composable enemy properties. They are a separate subsystem and get
  their own spec.
- Bosses, powers, insignia, meta-progression, currencies beyond gold, maps 2
  and 3 — unchanged from the port design's "Out" list.
- Re-balancing. Every number is carried across as-is, exactly as `data/` was in
  the core slice. The reference's own header calls its numbers placeholders.

## 4. Architecture

### `data/upgrades.gd` — the table

Ports `data/upgrades.ts` verbatim: 4 towers × 2 branches × 4 tiers with the
reference's labels, descriptions and costs. Effect keys become snake_case
(`damage_multiplier`, `fire_rate_multiplier`, `range_multiplier`,
`pierce_bonus`, `splash_radius`, `detection`, `slow_factor`,
`slow_duration_ms`, `gold_multiplier`, `bonus_gold_per_kill`).

Pure data, no engine references — it lives under `data/` and
`test_sim_purity.gd` enforces that.

### `sim/upgrades.gd` — the rules

Pure GDScript, no engine references:

```
MAX_TIER = 4, CROSS_PATH_CAP = 2, VISUAL_TIERS = 4

empty_tiers() -> Dictionary
can_upgrade(tiers, branch) -> bool          # ignores affordability
with_upgrade(tiers, branch) -> Dictionary
upgrade_cost(kind, branch, current_tier) -> int
total_invested(kind, tiers) -> int          # for sell value
visual_tier(tiers) -> int
sprite_frame_for(kind, tiers) -> int
resolve_tower_stats(kind, tiers) -> Dictionary
```

`resolve_tower_stats` is the composition rule and the only place stats are
derived. Both the game and `sim/harness.gd` call it, so the harness's balance
claims and the running game cannot disagree — the project's load-bearing
property.

**One deliberate divergence from the reference.** `withUpgrade` throws on an
illegal buy, on the reasoning that a call which should have been gated is a bug
rather than a no-op. GDScript has no exceptions, and `assert()` compiles out of
release builds. `with_upgrade` will instead `push_error` and return the tiers
unchanged, with callers gating on `can_upgrade` first. The error is loud where
it matters — the suite's crash sentinel surfaces it — without making a release
build unplayable on a bug that should be impossible.

### Slow — `sim/movement.gd` and enemy state

Enemy sim state gains `slow_factor` (default `1.0`) and `slow_remaining_ms`.
Movement multiplies its step by `slow_factor`; the timer decrements per tick and
restores the factor to 1.0 on expiry. Re-application takes the *strongest* slow,
matching `resolve_tower_stats`.

This must live in `sim/` so the harness and the game share one copy.

**Against the soft-lock warning** in CONTINUE.md §7: the removed overshoot
quirk was dangerous because a constant step above 4.0 px/tick could oscillate
around a waypoint forever. Slow only ever *reduces* step size, so it moves away
from that hazard rather than toward it. The existing guard,
`test_every_wave_undefended_terminates_at_the_default_tick_size`, still applies.

### Gold — `sim/economy.gd`

One function, `kill_reward(base_reward, source) -> int`, applying
`gold_multiplier` then adding `bonus_gold_per_kill`.

Attribution needs no new plumbing. The `source` dictionary already flows
`Tower.tick` → `wants_to_fire` → `Projectile.launch` → `hit` →
`Enemy.take_damage(source)`, and splash hits in `_on_projectile_hit` reuse the
same dictionary — so a splash kill is credited to the tower that fired, which is
correct.

### `game/tower.gd`

Gains `tiers` and a cached resolved-stats dictionary, recomputed on upgrade
rather than per tick. Its six reads of `_def` — range and detection in
`to_targeting_dict()`, fire rate, damage, pierce and splash in `tick()` —
become reads of the resolved stats, and `tick()` adds the two gold fields to
the `source` dictionary it emits.

`setup()` and a new `apply_upgrade()` both refresh the sprite frame through
`sprite_frame_for()` and the range indicator's radius.

`price_paid` accumulates upgrade spend, so `EconomySim.sell_refund`'s existing
docstring — "half of everything sunk into a tower comes back on sale" — stays
literally true with no change to that function.

### `game/game_board.gd`

Gains `upgrade_selected_tower(branch)`: gate on `can_upgrade` and
`can_afford`, deduct gold, apply, emit. Failure reuses the existing
`placement_rejected` signal so rejection messages keep one path to the HUD. A
new `tower_upgraded` signal lets the UI refresh.

The board is already ~250 lines and CONTINUE.md §10 flags it as worth splitting
if it grows. This addition is deliberately thin — the rules are all in
`sim/upgrades.gd` — but if it grows much further, extracting selection and
placement is the split to make.

### UI — a split into two scenes

The sidebar becomes two scenes rather than one growing script:

- **`ui/tower_panel.tscn`** keeps the build list, unchanged.
- **`ui/tower_inspector.tscn`** (new) owns the selected-tower section: kind,
  per-branch tier counts, the next tier on each branch with label, description
  and cost, `[+]` buttons gated by `can_upgrade` and affordability, the dormant
  marker, and Sell.

`tower_panel.gd` is ~90 lines today and would roughly triple otherwise. Two
scenes stay independently testable, matching how the rest of `ui/` is built.

Layout, using the full-height sidebar:

```
┌────────────────┐
│ 🗼 Basic    20 │
│ 🗼 Fast     50 │  build list (always shown)
│ 🗼 Mortar   70 │
│ 🗼 Long    100 │
├────────────────┤
│ BASIC          │
│ sustained 1/4  │  inspector
│ burst     0/4  │  (populated on selection,
│                │   empty otherwise)
│ Barrage        │
│ Drum Feed      │
│ 60g        [+] │
│                │
│ Marksman       │
│ Heavy Rounds   │
│ 30g        [+] │
│                │
│ [  Sell  35g ] │
└────────────────┘
```

The inspector refreshes on `gold_changed` as well as on selection and
`tower_upgraded`. The reference carries a comment recording that exact bug: its
panel was drawn once on selection, so a tower selected while broke stayed greyed
out after a wave paid out, and the player had to reselect to see it.

**Sell moves out of the HUD** into the inspector, beside the tiers it refunds.
`test_hud.gd`'s Sell coverage moves with it.

### Dormant tiers in the UI

Three tiers reach for pierce or detection. They carry a short "no effect yet"
marker on the dormant part of their text and stay purchasable. Two of them
also carry live effects, so the purchase is early rather than wasted:

| Tier | Effects | Live part |
|---|---|---|
| Basic · burst 3 · `Spotter` | detection + damage ×1.5 | the damage |
| Long · burst 4 · `Siege Cannon` | damage ×2 + pierce 10 | the damage |
| **Long · burst 3 · `Tungsten Core`** | **pierce 5 only** | **none** |

**`Tungsten Core` is the one genuinely inert purchase in the game**: 260 gold
for an effect nothing can currently feel, and it is the mandatory step to
`Siege Cannon` behind it. A marker is honest but does not make it a reasonable
buy — a player who wants tier 4 on that branch must pay 260 gold for nothing.

**This is flagged as an open decision, not settled here.** Three ways out, in
the order they are worth considering:

1. **Give it a live effect now** — the smallest sensible one is a modest damage
   or range bump, deleted when armoured enemies land. Diverges from the
   reference table by one tier's effects, and keeps the branch honest.
2. **Discount it** while dormant, restoring the reference price later. Keeps
   effects faithful; makes the cost table temporarily wrong instead.
3. **Leave it inert with the marker.** Exact parity, and the anti-armour branch
   is simply a bad buy until enemy properties land.

Implementation should not start on the Long Range burst branch until this is
decided; nothing else in the spec depends on it.

## 5. Testing

`test/test_upgrades.gd` ports `upgrades.test.ts` in full — not the brief's
subset — and is mutation-tested by its implementer, per the standing
instructions in CONTINUE.md §8. Coverage:

- **Cross-path rule** at its boundaries: tier 2→3 allowed while the other
  branch is at 2, refused at 3.
- **Cost table**, pinned per tower per branch per tier.
- **`total_invested`** across mixed tier combinations.
- **`visual_tier` boundaries**: 0→0, 1–2→1, 3–4→2, 5–6→3.
- **Composition**: multipliers compose, flats add, and splash / slow / gold take
  the strongest rather than stacking.
- **`with_upgrade` on an illegal buy** returns tiers unchanged.

Beyond that unit suite:

- **Slow** — a harness test that a slowed enemy measurably arrives later, and
  that the existing termination guard still passes.
- **Gold** — `kill_reward` tests including multiplier-and-flat together.
- **Board** — upgrade gating, gold deduction, rejection messages, and a sell
  refund that includes upgrade spend.
- **Purity** — `sim/upgrades.gd` passes `test_sim_purity.gd`.
- **Rendering** — screenshots, per CONTINUE.md §8: sprite frames advancing with
  visual tier cannot be caught by a test.

The data-table tests must pin the upgrade table's shape (exactly four tiers per
branch, every effect key recognised), because `test/case.gd`'s `_values_equal`
cannot distinguish `20` from `20.0` and so no data test detects a type change.

## 6. Slices

1. `data/upgrades.gd` + `sim/upgrades.gd` + `test_upgrades.gd`. Pure, no UI,
   no engine — the largest and most testable piece, and it lands green on its
   own.
2. Slow and gold: `sim/movement.gd`, `sim/economy.gd`, harness tests.
3. Tower and board wiring, including `price_paid` accumulation.
4. `ui/tower_inspector.tscn` and the sidebar split.
5. Screenshot verification, and a browser pass.

## 7. Definition of done

- All 32 tiers purchasable subject to the cross-path rule, at the reference's
  costs.
- Tower sprites advance through all four `upgrade_frames`.
- Slow and gold effects observably work in the harness.
- Selling refunds half of placement plus upgrade spend.
- Suite green, every new assertion mutation-tested.
- Verified by screenshot, and played once in a browser.
