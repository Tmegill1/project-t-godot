# UPDATE — what we want to do next

**Purpose:** the forward-looking backlog. What is agreed, what is decided but
not yet built, and what is still open. `CONTINUE.md` records what *is*; this
records what *should be*.

Last updated: 2026-08-30 (revised after the split finding).

---

## Status

| Slice | State |
|---|---|
| Core slice, tower upgrades, free placement, two art swaps | ✅ merged |
| **Slice 0** — wave economy, measured gold curve, visible limits, maps 2 and 3 | ✅ merged and **deployed** |
| **Slice 1** — roster, resistance, bosses | ✅ merged |
| **Leak model** — cost by kind and by how alive it arrived | ✅ done, on `feat/leak-model`, **not merged** |
| **Tower cap** — three of each kind, twelve per map | ✅ merged and **deployed** (`121bc7f`) |
| **Difficulty selector** — tiers, and the benchmark that missed | ✅ **built**, on `feat/difficulty-selector`, **not merged** |
| Slice 2 — tactical powers | ⬜ decided, not designed |
| Slice 3 — versioned save + meta-progression | ⬜ decided, not designed |
| Slice 4 — hero | ⬜ decided, not designed |

Live at <https://tmegill1.github.io/project-t-godot/>. Every push to `master`
republishes it.

---

## Slice 1 — roster, resistance and bosses *(done, unmerged)*

**Shipped:** the roster renamed to its art and the shaman and troll brought off
the bench; armour and shields split by counter; physical/magic damage types
with soft edges and a damage floor; penetration scaling with tower level; the
shaman's shield aura; bosses on waves 10 and 20; resistance visible as a sprite
tint; and a measured health curve. Suite green at **10,148 checks across 41
files**.

**What the measurement pass found, and it reframes the whole problem:**
*health scaling alone cannot threaten a maxed board at any rate.* Even at
wave-20 health ×11.5, a maxed sixteen-tower board leaks zero. The binding
constraint is board **coverage**, not hit points. At the shipped values eight
maxed towers lose wave 20 and twelve hold it, against a budget of sixteen — and
slice 0's gold curve lets a good player land right in that band.

**A correction worth carrying:** `PIERCE_PER_TIER` and `ARMOR_PER_WAVE` are a
pair. Raised to 2 to help the Magic tower, penetration erased armour outright
for every *physical* tower — a maxed Basic hit an armoured ogre exactly as hard
as an unarmoured goblin. Change one, re-measure the other.


**Spec:** [`docs/superpowers/specs/2026-08-25-roster-resistance-and-bosses-design.md`](docs/superpowers/specs/2026-08-25-roster-resistance-and-bosses-design.md)
**Plan:** [`docs/superpowers/plans/2026-08-25-roster-resistance-and-bosses.md`](docs/superpowers/plans/2026-08-25-roster-resistance-and-bosses.md)

### The problem as it stood before the slice

| | |
|---|---|
| Wave 20 total enemy HP | 1,776 |
| A maxed 16-tower board's DPS | 617 |
| Seconds to delete the whole wave's HP | **2.9** |
| Seconds the wave takes just to spawn | **80** |

**≈28× overkill.** A maxed Long Range hit for 76 against a wave-20 ogre's 20
HP; even a maxed *Basic* one-shot everything. Wave-20 health is now ×4.75
rather than ×2.5, and the coverage finding above is what actually moved the
difficulty.

### The roster

All five creatures are already baked. Three were wired under wrong names
(`slime` draws a **goblin**, `bee` draws a **bat**); two sat unused.

| Kind | Was | Role | Health | Speed | Resistance |
|---|---|---|---|---|---|
| `bat` | `bee` | fastest, flimsiest | lowest | fastest | shield |
| `goblin` | `slime` | the baseline / control | low | fast | none |
| `shaman` | *(unused)* | support caster | high | slow | shield, **and grants them** |
| `ogre` | `ogre` | the wall | highest | slowest | armour |
| `troll` | *(unused)* | **boss only** | enormous | very slow | heavy armour |

Health descends `ogre > shaman > goblin > bat`; **speed is its exact inverse**.

### Towers

- Fast and Mortar **swap sprites** — measured, they were wearing each other's
  art (Fast had the cannon, Mortar had the crystals).
- Fast is **renamed "Magic"**. The `&"fast"` key stays: it joins the tower
  table, the upgrade table, the `fire-fast` audio event and every test.

### Damage types and resistance — the owner's rule *(2026-08-25)*

**Rock-paper-scissors with soft edges. Nothing is ever fully immune.**

| | vs **armour** | vs **shield** |
|---|---|---|
| **Physical** (Basic, Mortar, Long Range) | **strong** — the answer to ogres and trolls | reduced, but still damages |
| **Magic** (the Magic tower) | reduced, but still damages | **strong** — the answer to bats and shamans |

This replaces an earlier binary design where armour would have **zeroed** a
4-damage Magic tower outright. Soft edges mean every tower stays useful
everywhere while still having a speciality.

Shipped as:

- **Armour** is flat reduction per hit, biting magic 1.6× harder, so physical
  is the armour answer — under a **minimum-damage floor** (15% of the incoming
  hit) so nothing is ever reduced to zero.
- **Shields** cost a charge and leak 50% to magic against 15% to physical, so
  magic strips them fastest while physical still gets something through.

At wave 20 that gives each tower a distinct relationship to armour: Basic 67%
through, Mortar 84%, Magic 15% (the floor), and **Long Range 100%**, because
its own pierce tiers are what make it the specialist.

A shield is a **reduction, not immunity** — a shield-met hit can be lethal,
deliberately, or a 1-health shielded enemy would be unkillable.

### Penetration scales with tower level — the owner's rule *(2026-08-25)*

**Every tower gains penetration as it upgrades**, not just the two Long Range
tiers that grant `pierce_bonus` today.

- Penetration reduces effective armour.
- It is derived from **total tiers bought** across both branches, so investment
  in any direction makes a tower better at getting through.
- The explicit `pierce_bonus` tiers stack **on top**, so Long Range stays the
  specialist.

⚠ **Shipped at 1 per tier, not 2.** See the correction note at the top of this
section — `PIERCE_PER_TIER` and `ARMOR_PER_WAVE` are a tuned pair.

### Bosses

Waves **10 and 20**, both trolls, the second far worse — more than twice the
health, heavier armour, drawn markedly larger. Structured as a table
(`data/bosses.gd`) so waves 30/40 in endless play, and any new sprite added
later, are data entry.

`assets/audio/boss.ogg` had been in the repo since the core slice and was not
even registered in `AudioManager.SOUNDS`, so it had never been loaded. It plays
on boss spawn now.

### Showing resistance

No new art. Sprite **tint** by resistance and **scale** for bosses, both
display-only. Verified by screenshot at gameplay size: it reads clearly for
armour and more subtly for shields. Honest caveat — it reads as *darker* more
than as *colder*, because `modulate` can only multiply. A shader is the upgrade
path when the real art lands.

---

## Difficulty selector, and the benchmark that missed *(built 2026-08-30)*

**Spec:** [`docs/superpowers/specs/2026-08-29-difficulty-selector-design.md`](docs/superpowers/specs/2026-08-29-difficulty-selector-design.md)
**Plan:** [`docs/superpowers/plans/2026-08-29-difficulty-selector.md`](docs/superpowers/plans/2026-08-29-difficulty-selector.md) — eleven tasks, affordability measured first

**The finding.** Measured against `b00b695`, *after* the tower cap landed:

| Maxed towers, cross-path legal | Wave 18 | Wave 20 |
|---|---|---|
| 6 — *what `test_balance_tuning.gd` benchmarks* | 19 leaks | 55 leaks, 74 lives |
| 8 | 0 | 10 |
| 9 | 0 | 3 |
| **10** | **0** | **0** |
| **12 — the full map budget** | **0** | **0** |

**The zero-leak threshold is ten; the budget is twelve.** Filling the budget
shuts the game out entirely. Two more measurements pin the shape:

- **Waves 1–15 leak zero even at six towers.** Three-quarters of a run has no
  pressure at any board a player actually reaches.
- **The back half of the map is decorative.** Twelve maxed towers crammed onto
  the first straight and the same twelve spread over the whole route give an
  identical result — all 177 wave-20 enemies dead, zero leaks, both ways. The
  route is 2,448px and the first bend is at 768px, **31% in**.

**Why the suite missed it.** `test_balance_tuning.gd` benchmarks a *six*-tower
board — one the player passes through on the way to the one they finish with.
Its `leaks > 0` assertion stays true however easy the game gets for a full
board. And more fundamentally, **the harness cannot see where an enemy died**:
`run_wave` returns kills, leaks, lives, gold and ticks, so "they don't reach the
first bend" was not expressible against it. That is why a regression this
obvious to a player was invisible to 13,436 assertions.

**Owner's decision (2026-08-29):** Normal stays *comfortable* — a full maxed
board should win wave 20 — and the teeth go in a **selector**. Hard and
Nightmare are where enemies get more numerous and tougher.

**The design.** Difficulty is a **parameter**, not a global: `data/difficulty.gd`
holds a tier table, and `Waves.get_modifiers`, `Waves.build_schedule` and
`Harness.run_wave` all take a tier defaulting to Normal. Normal is the identity
transform, so the whole existing suite stays green and becomes the regression
net. An autoload was rejected because it would break `sim/` purity and the
harness's determinism guarantee; a wave-offset scheme was rejected because it
only fast-forwards a flat curve and never touches spawn spacing.

Levers, chosen against the coverage finding rather than guessed:
`interval_multiplier` (concurrency — the sharpest), `count_multiplier`,
`health_multiplier` (weak alone, real in combination), `speed_multiplier`,
`gold_multiplier`, `starting_lives`.

### What shipped

**The tiers, measured rather than invented.** The spec deliberately left Hard
and Nightmare blank so no plausible figure could become the shipped one by
inertia. They came from a sweep of the full legal roster across all twenty
waves:

| Tier | count | interval | health | speed | gold | lives |
|---|---|---|---|---|---|---|
| Normal | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 20 |
| Hard | 1.00 | 1.00 | 4.00 | 1.40 | 0.90 | 15 |
| Nightmare | 1.00 | 1.00 | 4.50 | 1.40 | 0.85 | 12 |

**The open risk did not bite.** A twenty-wave run earns **16,199 gold** against
an **11,415** full-board cost, so twelve maxed towers are affordable with 4,784
to spare and the tiers are set against the board the game actually hands out.
`test/test_affordability.gd` pins both numbers, so a change to the gold curve or
the tower caps has to move them deliberately.

**These are the SECOND set of numbers, and the first set was wrong.** The owner
asked whether a fully upgraded board survives wave 20 on Nightmare. Measuring it
found that **eleven of the sixteen legal fully-upgraded boards shut that wave out
with zero leaks** — the exact failure the benchmark existed to catch, still
present after the benchmark had been rewritten to catch it. See *"A full maxed
board is sixteen boards"* below.

**Nightmare is beatable, but only by the best build there is.** The strongest
legal board loses 9 of its 12 lives and survives with 3. Every board that leaves
a tower on the burst branch loses badly. The harness resolves hits instantly,
with no projectile travel time, so it is *kinder* than the live board — these
remain a starting point to be played.

**Carried with it, and worth more than the tuning:**

1. The harness learned `deepest_progress` and `progress_at_death`, so *"they
   don't make it to the first bend"* is an assertion against
   `FIRST_BEND_FRACTION := 0.31` rather than an observation. It immediately paid
   for itself: at Normal, against the full twelve-tower maxed board,
   `deepest_progress` **never exceeds 0.18 on any of the twenty waves**. The
   bend is at 0.31. Nothing has ever reached it. That is the owner's complaint,
   as a number.
2. `test_balance_tuning.gd` now covers the **full twelve-tower maxed board** at
   every tier, beside the six-tower one it used to benchmark exclusively. The
   assertion that matters is directional — *a full maxed board must not shut out
   the highest tier* — so it survives future retuning. Normal's comfort and
   Hard's brief are pinned too, so a tier change cannot make the default harder
   as a side effect.

### A full maxed board is sixteen boards, not one

The cross-path rule lets exactly one branch pass tier 2, so a fully upgraded
tower is either `sustained 4 / burst 2` or `sustained 2 / burst 4`, and a board
picks one per kind — **2⁴ = 16 legal maxed boards.** The first benchmark pinned
one of them, the burst split, which turns out to be the weaker by two orders of
magnitude. Extending the benchmark from six towers to twelve while never
questioning the upgrade split was the same mistake one level down.

**Why sustained wins.** The first tier rows raised `count_multiplier` and
lowered `interval_multiplier`, both of which raise enemy *density*. The sustained
branch buys fire rate and then **splash** — 45px, then 75px — whose value scales
with density. The two levers chosen to attack coverage were precisely the ones a
splash build answers best.

So both go back to 1.0 and the teeth moved to health and speed. Lives lost across
a whole run, strongest board against weakest:

| count | interval | health | speed | strongest | weakest |
|---|---|---|---|---|---|
| 1.40 | 0.60 | 1.40 | 1.15 *(first Nightmare)* | **0 — shut out** | 46 |
| 1.00 | 1.00 | 3.50 | 1.30 | **0 — shut out** | 146 |
| 1.00 | 1.00 | 4.00 | 1.35 | **0 — shut out** | 246 |
| 1.00 | 1.00 | 4.00 | 1.40 *(Hard)* | 3 | 258 |
| 1.00 | 1.00 | 4.50 | 1.40 *(Nightmare)* | 9 | 336 |
| 1.00 | 1.00 | 5.00 | 1.40 | 27 | 441 |

**Speed 1.40 is a threshold, not a dial.** Below it the strongest board leaks
nothing at all, at any health up to 4.0. `test_balance_tuning.gd` now walks all
sixteen boards on Nightmare *and* on Normal, so no single build can hide a
shut-out again.

### The two upgrade branches are not close, and that is a tower problem

The spread between best and worst build is **two orders of magnitude at every
tier row**, and no tier value closes it — `sustained` (fire rate → splash)
dominates `burst` (damage → pierce) against late waves, because splash kills a
cluster in one hit however many are in it.

The selector **revealed** this rather than causing it. It is invisible on Normal
because every build shuts Normal out, and the old six-tower benchmark could not
see it either. Nothing here fixes it: rebalancing the branches against each other
is its own piece of work, and it should probably happen before any further tier
tuning, because every tier number is measured against a build asymmetry this
large.

### The opening still has no pulse, and health cannot give it one

The one part of the design that did not land. It asked for a base-health bump
so wave 1 lasts longer than a few seconds, bounded by two constraints: the
roster ordering `ogre > shaman > goblin > bat` survives, and wave 5 against
three ungraded Basics does not cost *more* than the lives it already does.

Measured against exactly the board 100 starting gold buys:

| ogre / shaman / goblin / bat | wave 1 | wave 5 |
|---|---|---|
| 10 / 7 / 5 / 3 *(shipped)* | 5.6s, 0 leaks | 21 lives |
| 10 / 7 / 6 / 4 | 5.6s, 0 leaks | 21 lives |
| 10 / 7 / 6 / 5 | 5.6s, 0 leaks | 23 lives |
| 12 / 9 / 8 / 5 | 5.6s, 0 leaks | 25 lives |
| 14 / 11 / 9 / 6 | 26.8s, **2 leaks** | 33 lives |

**Wave 1 does not move until goblin health crosses 8**, because a Basic tower
deals exactly 4 and a goblin at anything from 5 to 8 dies to the same two shots.
At 9 it needs three — and wave 1 stops being a walkover by *leaking* rather than
by lasting longer. There is nothing in between: the opening is quantised by the
Basic tower's damage, not tuned by hit points. And every value that changes
anything makes wave 5 cost more, which is the constraint that says the cliff
must not steepen.

So nothing moved, per the spec's own instruction to bring such a finding back
rather than quietly retune Normal. **The lever for the opening is the Basic
tower's damage or fire rate, or wave 1's composition — not enemy health.** The
shape it failed to move is pinned in `test_balance_tuning.gd`.

---

## Known problems, not yet scheduled

### 1. ~~Every leak costs the same, past wave 5~~ ✅ FIXED

`Leak.resolve` used to switch to `min(4, remaining health)` after wave 5, and
every enemy has ≥4 health from wave 10 on, so the cap always bound: goblin,
bat, shaman and ogre all cost exactly 4, `life_loss` was dead data at every
wave that mattered, and the run was always exactly five leaks from over
whatever leaked.

**The rule is now `ceil(life_loss × remaining ÷ max_health)`**, floored at one.
The flat cap, the wave-5 boundary and the `wave` parameter are all deleted —
the rule cannot compound, because it is bounded by a number from the table
rather than by one that grows with the wave. Two properties fall out: *which*
kind leaked decides the damage, and an enemy that limps in nearly dead costs
less than one that walks through untouched.

| Arriving at | Goblin | Bat | Shaman | Ogre | Boss |
|---|---|---|---|---|---|
| full health | 1 | 2 | 3 | **5** | 6 / 10 |
| 30% health | 1 | 1 | 1 | 2 | 6 / 10 |

(The boss override was already correct before this — added by `ba6b484` during
the camps pass — and is untouched. It is a *declared* figure from
`data/bosses.gd`, never derived from health, which is the whole lesson the cap
was there to enforce.)

**The measurement said not to retune anything.** Waves 1–20 were run back to
back against boards of 4/8/12/16 towers, ungraded and maxed, under both rules:

| Board | Old rule ends | New rule ends | Lives per leak |
|---|---|---|---|
| 4 ungraded | wave 6 | wave 6 | 3.92 → 2.27 |
| 8 ungraded | wave 9 | wave 9 | 3.88 → 2.34 |
| 12 ungraded | wave 10 | wave 10 | 3.79 → 2.45 |
| 16 ungraded | wave 12 | wave 12 | 3.79 → 2.53 |
| 4 maxed | wave 19 | **wave 20** | 3.58 → 1.64 |
| 8 / 12 / 16 maxed | survives | survives | — |

Per-leak cost falls by about 37%, and **the wave a run ends on is unchanged in
seven of eight boards**, moving by one in the eighth. Once a board is being
overrun the leak volume compounds far faster than the price falls, so a third
off the price buys at most one wave. `Economy.STARTING_LIVES` therefore stays
at **20**, which still affords exactly four worst-case ordinary leaks — pinned
by `test_the_life_budget_affords_several_worst_case_ordinary_leaks`.

**One redundancy removed by mutation testing.** The first implementation
clamped both the incoming health to `max_health` *and* the result to
`life_loss`. Both survived mutation, because each masked the other; clamping
the health alone is what bounds the rule, and the second clamp was unreachable
dead code.

### 2. ~~The web build has never actually been played~~ ✅ PLAYED — and it reported a real defect

The owner played it on 2026-08-29 and the first report back was a balance
finding, not a crash: *"Enemies don't stand a chance, they don't make it to the
first bend"* — holding **every wave, all the way through**. It boots, it plays,
and clicks go through it.

Two lessons worth keeping:

**Diagnose against the build stamp first.** The same session produced a false
alarm about white-square projectiles that was purely a stale browser cache; the
lower-left build label is what settles it. See `.ai/handoff.md`.

**The report was correct and the suite could not see it.** That became the
difficulty selector work below.

### 3. Audio settings do not persist

Mute and volume drive `AudioManager` directly; nothing writes them to disk.
There is no settings file in this project. Slice 3 owns it.

### 4. The gold curve will need re-measuring

Slice 0 set `Waves.GOLD_PER_WAVE = 0.025` by sweeping against a 17,170 spend
ceiling. **Powers as an expensive gold sink will move that ceiling**, so
re-measure when they land.

---

## Later slices, in dependency order

### Slice 2 — tactical powers

**Owner's decision (2026-08-24):** powers are **bought with gold and priced
expensively** as a late-run sink, and/or **tied to particular tower kinds** —
*not* bought with Insignia as the upstream Phaser build does.

Upstream has `data/powers.ts`, `sim/powers.ts` and `ui/PowerBar.ts` to port:
four tactical powers (Barrage, Time Dilation, Overcharge, Bounty Strike) plus
persistent command upgrades.

This is the slice that fixes *"once you press Start, you have nothing to do."*

### Slice 3 — versioned save + meta-progression

Upstream has `meta/saveSchema.ts` + `SaveStore.ts` + `profile.ts` (versioned,
with migrations, storage-agnostic) and `data/metaUpgrades.ts` +
`sim/metaProgression.ts` + `ui/MetaShop.ts`. Passives are **hard-capped at 10%
in code** upstream — keep that, or grinding replaces skill.

Also closes the audio-settings gap above.

### Slice 4 — the hero

The one ask with **no upstream reference** — genuine new design. Recommended
model: tap a spot, the hero walks there, auto-attacks, dies, respawns on a
timer. Reuses `sim/movement.gd`, `sim/targeting.gd` and `sim/damage.gd` nearly
as-is; free placement already put everything in world space.

**Open recommendation, not yet ruled on:** the hero should *be* the ability
delivery mechanism rather than a second parallel system, or the game ends up
with two ability bars.

---

## Camps, and the settlement they are heading towards

Fences and fires no longer scatter. They appear only as **camps**: a palisade
run of 3-5 sections with one or two fire pits standing behind it, sited 2-3
tiles back from the road and one tile clear of the map border. Everything that
used to be a lone fence is now a tree or a rock.

**This is forest-only, and the reason is the art.** The `spike` slot is a
different object in every biome - forest ships a 95x63 wooden palisade section,
ice a 37x79 totem on a post, desert a 42x35 skull pile. Only the palisade tiles
into a wall; five totems or five skulls in a row would be a worse version of
the problem camps fix. `Biomes.has_wall_art()` carries that fact, and ice and
desert keep scattering their spike as the landmark it actually is.

### What would finish the idea

1. **Wall art for ice and desert.** One 3/4-view section per biome with flat
   ends and continuous rails, matching the forest palisade's proportions. Then
   flipping `wall_prop` to `true` in `Biomes.DEFS` is the entire change.
2. **A corner and a side-on section.** Camps are a wall with fires behind it
   rather than an enclosure purely because the horizontal piece is all there
   is. Two more sprites would allow a real compound.
3. **Authored settlements, not generated camps.** The camp siting rules are a
   decent procedural stand-in, but the thing actually wanted is *a settlement
   on the map that the player is defending* - which should be **placed by hand
   in the map text**, not rolled. The format and the editor both exist now, so
   this is a new character in `data/map_format.gd` plus a palette entry in
   `tools/map_editor_io.gd`. Doing it that way also removes the last piece of
   build-space denial that varies with the decoration seed.

Camps cost some build space, measured rather than assumed: legal tower
positions on a half-tile lattice went 46.3% -> 42.1% on the demo map, 54.7% ->
51.7% on map2, 50.1% -> 45.5% on map3. Against a 16-tower limit and 542 legal
spots on the tightest map, nowhere near binding - but worth re-measuring if
camp counts or widths grow.

---

## Deferred deliberately

- **Phased enemies.** `Targeting.is_targetable` already gates on `phased` and
  Basic's *Spotter* tier already grants `detection`. A third property on top of
  armour and shields is more than one slice can balance.
- **Per-biome endpoint art.** The goal and spawn render identically in forest,
  ice and desert. Tripling the endpoint art is its own decision.
- **A map-select screen.** Maps chain by `next`; choosing one belongs with the
  save.
- **The decorative back half of every map.** Measured 2026-08-29: twelve maxed
  towers on The Pass's first straight kill exactly as much as twelve spread
  over the whole route, so everything past the first bend (31% in) is scenery.
  Making late route matter needs spawn points, flying paths or enemies that
  must be handled twice — a slice of its own, not a rider on the difficulty
  selector.
