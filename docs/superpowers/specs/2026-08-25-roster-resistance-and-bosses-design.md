# Roster, resistance and bosses

**Date:** 2026-08-25
**Target:** Godot 4.7.1, GDScript
**Status:** design approved, ready for planning

---

## 1. Why this document exists

Slice 0 fixed the economy. This fixes the fight.

The owner asked for seven things: name the enemies after what the art actually
draws, add the goblin shaman, order health and speed against each other, swap
the Fast and Mortar tower art and rename Fast to Magic, stop towers trivially
killing everything late, show visually when an enemy is tougher, and put bosses
on waves 10 and 20.

Three measurements shaped the answer.

**Towers out-damage wave 20 by roughly 28×.**

| | |
|---|---|
| Wave 20 total enemy HP | 1,776 |
| A maxed 16-tower board's DPS | 617 |
| Seconds to delete the whole wave's HP | **2.9** |
| Seconds the wave takes just to spawn | **80** |

A maxed Long Range hits for 76 against a wave-20 ogre's 20 HP. A maxed *Basic*
one-shots every enemy in the game. The Fork sweep in slice 0 confirmed it from
the other direction: a full board killed all 161 enemies at wave 20 with zero
leaks.

**The resistance machinery already exists and is tested.** `sim/damage.gd`
implements armour (flat reduction per hit, reduced by pierce) and shields
(absorb one whole hit regardless of size) in full, with 68 assertions in
`test/test_damage.gd`. No enemy has ever carried either property. Its own
docstring states the design intent: *"Armour punishes many small hits and is
beaten by few large ones. Shields punish large hits and are beaten by rapid
cheap fire. If either could be answered by the same build as the other, enemy
properties would be decoration."*

**The art is already on disk.** `assets/art/enemies/` holds five baked
creatures. Three are wired under wrong names, two are unused:

| Directory | What the sprite actually draws |
|---|---|
| `slime/` | a **goblin** with a knife |
| `bee/` | a **bat** |
| `ogre/` | an ogre |
| `_unused/shaman/` | a **goblin shaman** — staff, skull, purple orb |
| `_unused/troll/` | a **troll**, the largest creature on the sheet |

`assets/audio/boss.ogg` also already exists and has never been played.

## 2. Goals and non-goals

**Goals**

1. Every enemy is named after what it draws, and all five creatures are used.
2. Health and speed are inverses across the roster.
3. A fully-upgraded board is threatened by wave 20 rather than trivialising it.
4. Each tower is the answer to something specific.
5. A tougher enemy is legible before it reaches the towers.
6. Bosses on waves 10 and 20, the last one genuinely hard.

**Non-goals**

- **New art.** Everything here uses sprites already baked. The owner will add
  more later; the boss and resistance tables are shaped so that dropping new
  sprites in is a data change, not a code change.
- **Phased enemies.** `Targeting.is_targetable` already gates on `phased` and
  Basic's *Spotter* tier already grants `detection`, but adding a third
  property on top of armour and shields is more than one slice can balance.
  Deferred deliberately, with the machinery left alone.
- **Meta-progression, powers, a hero.** Later slices.
- **Retuning the gold curve.** Slice 0 measured it against a 17,170 spend
  ceiling. Nothing here changes what a player can buy, so the curve stands —
  but see §9, because it will need re-measuring once powers land.

## 3. The roster

Five creatures. Health descends, speed ascends against it — the owner's rule,
applied strictly.

| Kind | Was | Role | Health | Speed | Resistance |
|---|---|---|---|---|---|
| `bat` | `bee` | fastest, flimsiest | lowest | fastest | **shield** |
| `goblin` | `slime` | the baseline | low | fast | none |
| `shaman` | *(unused)* | support caster | high | slow | **shield**, and grants them |
| `ogre` | `ogre` | the wall | highest | slowest | **armour** |
| `troll` | *(unused)* | **boss only** | enormous | very slow | **heavy armour** |

**The goblin carries no resistance on purpose.** It is the baseline every other
enemy is read against, and the enemy a new player meets first. A roster where
everything resists something has no control group.

**Resistance is split by counter, not sprinkled.** Armour is flat reduction per
hit, so it walls many-small-hits towers and folds to few-large-hits. Shields
absorb a whole hit regardless of size, so they do the reverse. Putting armour on
ogres and trolls and shields on bats and shamans gives every tower a job:

| Tower | Is the answer to | Because |
|---|---|---|
| Magic (was Fast) | bats, shamans | fastest cadence in the game strips shield charges cheapest |
| Long Range | ogres, trolls | biggest per-hit damage, and the deepest pierce |
| Mortar | packed waves | splash hits several shield-bearers at once |
| Basic | everything, adequately | the generalist, beaten at both ends |

### 3.1 Damage types, with soft edges

**Amended 2026-08-25 on the owner's instruction, and the amendment matters:**
an earlier draft made the walls hard, which would have let armour reduce a
4-damage Magic tower to *nothing*. The rule now is rock-paper-scissors with
**soft edges** — every tower stays useful everywhere while still having a
speciality.

| | vs **armour** | vs **shield** |
|---|---|---|
| **Physical** — Basic, Mortar, Long Range | **strong** | reduced, but still damages |
| **Magic** — the Magic tower | reduced, but still damages | **strong** |

Two mechanisms, numbers set by the measurement pass:

- **Armour** is flat reduction per hit, biting physical at full rate and magic
  at a higher one, with a **minimum-damage floor** so magic is never reduced to
  zero.
- **Shields** absorb most of a hit and cost a charge. Magic leaks a far larger
  fraction through than physical, so magic strips shields fastest — but
  physical gets *something* through rather than being wholly absorbed.

⚠ **That last point changes existing tested behaviour.** `Damage.resolve`
currently has a shield absorb the **whole** hit, and several of the 68
assertions in `test/test_damage.gd` pin exactly that. They move deliberately.

### 3.2 Penetration scales with tower level

**Owner's instruction, 2026-08-25.** Every tower gains penetration as it
upgrades, not just the two Long Range tiers that grant `pierce_bonus` today.

- Derived from **total tiers bought across both branches**, so investment in
  any direction improves a tower's ability to get through.
- The explicit `pierce_bonus` tiers stack **on top**, so Long Range remains the
  pierce specialist rather than being levelled down to everyone else.
- This is the second guarantee that no tower is ever walled: a maxed Magic
  tower carries penetration although neither of its branches mentions pierce.

`UpgradesSim.resolve_tower_stats` already computes `pierce` and
`Damage.resolve` already subtracts it from armour, so this is a new **term in
an existing calculation**, not new machinery.

**This redeems the weakest tower.** Measured: a maxed Fast does 14 DPS against
Long Range's 72, the worst ratio in the game. It is bad at damage and always
will be — but shields do not care about damage per hit, only about hit count, so
the tower with the shortest cooldown becomes the correct answer to a whole enemy
class. That is a better fix than raising its numbers.

## 4. Health, speed and the rebalance

### 4.1 The shape

Health descends `ogre > shaman > goblin > bat`; speed is its inverse. The
current table already half-satisfies this by accident (ogre 8/60, goblin 5/100,
bat 3/150) — the shaman slots between goblin and ogre on both axes.

### 4.2 Closing a 28× gap

**Health scaling alone cannot close it and must not try.** Multiplying wave-20
health by 28 makes early waves unchanged and late waves a wall of hit points,
which is the least interesting difficulty there is.

Three levers move together, and the plan must **measure, not guess** — the
approach that produced slice 0's gold curve:

1. **Steeper health scaling.** `Waves.HEALTH_PER_WAVE` rises from `0.10`. A
   starting proposal of `0.25` puts wave 20 at 4.75× base rather than 2.5×.
2. **Armour and shields, scaling per wave**, introduced part-way through the
   run so the early game stays legible. Proposal: armour begins at wave 8 and
   climbs; shield charges step up at intervals rather than scaling smoothly,
   because half a shield charge means nothing.
3. **A ceiling on upgrade damage if the first two are not enough.** Listed
   last deliberately — it is the lever that flattens rather than differentiates,
   and it should only be reached for if measurement says so.

**Target for the sweep:** a fully-upgraded 16-tower board should clear wave 20
with real losses rather than zero leaks, and a half-built board should fail.
The harness can answer this without a human playing it, and the plan owns
producing the table.

### 4.3 The risk this creates, stated up front

**Flat armour can zero a low-damage tower outright.** A maxed Magic tower hits
for 4. Armour of 4 or more reduces that to nothing — not "less", *nothing* —
and Magic has no pierce in either of its branches. If ogres and trolls carry
meaningful armour, Magic becomes literally useless against them.

That is acceptable *as counterplay* and unacceptable *as a dead tower*.

**Both fallbacks the first draft listed are now design, not contingency** —
§3.1's minimum-damage floor and §3.2's level-scaled penetration exist precisely
to stop this. The measurement pass still has to confirm they are *enough*: a
Magic tower that technically deals 1 damage to an ogre is not walled, but it is
not a choice either. The task reports whether Magic reads as a useful
generalist, a specialist, or a token.

## 5. The shaman's shield aura

The shaman grants shield charges to enemies near it, making it a priority
target: kill the escort first and the wave dies normally; ignore it and every
enemy takes an extra hit.

**Where the rule lives.** A new pure module, `sim/aura.gd`, alongside
`sim/slow.gd` — no nodes, no static state, no engine references, so
`test_sim_purity.gd` keeps holding. It answers one question: given the shamans
on the board and the enemies on the board, which enemies should have a shield
charge topped up this tick.

**Both callers run it.** `game/game_board.gd` each physics tick and
`sim/harness.gd` each simulated tick, per this project's standing rule that a
rule with two callers lives in `sim/` and is written once. A shaman aura that
only the live game ran would make every balance number in the suite a fiction.

**Shape, deliberately simple:** a radius, a cap on charges granted, and a
cooldown so it tops up periodically rather than every tick. A shaman does not
shield itself through the aura — it carries its own shield from the table, so
the aura's job is purely the escort.

## 6. Bosses

**Waves 10 and 20**, both trolls, the second far worse.

| | Wave 10 | Wave 20 |
|---|---|---|
| Creature | troll | troll |
| Health | large | enormous |
| Armour | moderate | heavy |
| Draw scale | above the ogre | markedly larger again |
| Leak cost | the cap | the cap |

**Structured as a table, not as special cases.** `data/bosses.gd` maps a wave
number to a boss definition, so waves 30 and 40 in endless play, and any new
sprite the owner adds later, are data entry. `Waves.build_schedule` appends the
boss to its wave; nothing else about scheduling changes.

**A boss is an enemy with different numbers, not a new entity.** It moves with
`sim/movement.gd`, is targeted by `sim/targeting.gd`, takes damage through
`sim/damage.gd`, and leaks through `sim/leak.gd`, exactly as everything else
does. Anything that needs a special case in those modules is out of scope.

**`assets/audio/boss.ogg` finally gets played**, on boss spawn. It has been
sitting unused in the repo since the core slice.

**Leak cost.** `Leak.resolve` caps every leak at 4 lives, so a boss reaching the
goal costs the same as a bat — which reads as broken. This spec does **not**
fix the wider flattening problem (see §9), but bosses must at minimum cost the
cap, and the plan should make the boss's leak visibly catastrophic rather than
identical to a bat's.

## 7. Showing that an enemy is tougher

No new art. Two signals, both on the render layer only:

1. **Tint by resistance.** Armour shifts the sprite toward cold steel; shields
   add a pale blue cast. Applied through `Sprite2D.modulate`, scaled by how much
   resistance the enemy carries, so a wave-20 ogre reads as visibly harder than
   a wave-8 one.
2. **Scale by role.** Bosses draw markedly larger than their kind's
   `sprite_px`, which is the strongest available "this one is different" signal
   given every creature shares one art style.

**Both are display only.** `Enemies.DEFS[kind]["sprite_px"]` and every rule in
`sim/` read the same values they always did — the same separation
`Tower.DISPLAY_SCALE` already keeps between how big a tower draws and how big
its footprint is, and which `test_the_display_scale_does_not_reach_the_placement_radius`
already guards.

**A shader is the upgrade path, not the first step.** True desaturation wants
one; `modulate` can only multiply. Modulate is chosen because it is a one-line
render change with no `.import` churn and no new files, and because the owner
is replacing this with real art anyway.

## 8. Towers

Two changes, both small, neither touching a rule.

1. **Fast and Mortar swap sprites.** Measured: Fast currently wears the cannon
   art and Mortar wears the crystal art — they are simply on the wrong towers.
   The fix is swapping `sprite_frame` and `upgrade_frames` between the two
   entries in `data/towers.gd`. No stat, cost, range or rate moves.
2. **Fast is renamed Magic**, matching the crystals it will now wear. This is
   the `label` field. **The `&"fast"` StringName key stays**, because it is the
   join between the tower table, the upgrade table, the audio event
   `fire-fast`, the sprite lookup and every test — renaming the key is a
   rename across five files for no player-visible gain, where renaming the
   label is one word.

## 9. Deliberately not fixed here

**Every leak costs the same past wave 5.** `Leak.resolve` switches to
`min(4, remaining health)` after wave 5, and every enemy has at least 4 health
from wave 10 on, so the cap always binds: a bat, an ogre and a boss each cost
exactly 4 lives, and the run is always exactly 5 leaks from over. The per-kind
`life_loss` values become dead data, and the ogre's `life_loss: 5` is never read
at any wave because the cap is 4.

This is a real flattening and it is **not fixed in this slice**, because the cap
exists for a good reason — CONTINUE.md records that the uncapped health rule
meant one wave-20 leak ended the run — and replacing it properly means a
per-kind or per-wave leak model that wants its own measurement pass. Bosses get
the cap and a louder presentation instead. It is the strongest candidate for the
next slice.

**Enemy `sprite_px`, `stride_px` and the walk cycle** are not retuned. The
shaman and troll inherit the same treatment the other three get.

**The gold curve is not re-measured.** Nothing here changes the spend ceiling.
It will need re-measuring when powers land as a gold sink, which the owner has
already decided on.
