# UPDATE — what we want to do next

**Purpose:** the forward-looking backlog. What is agreed, what is decided but
not yet built, and what is still open. `CONTINUE.md` records what *is*; this
records what *should be*.

Last updated: 2026-08-26.

---

## Status

| Slice | State |
|---|---|
| Core slice, tower upgrades, free placement, two art swaps | ✅ merged |
| **Slice 0** — wave economy, measured gold curve, visible limits, maps 2 and 3 | ✅ merged and **deployed** |
| **Slice 1** — roster, resistance, bosses | ✅ all ten tasks done, on `feat/slice-1-roster-resistance-bosses`, **not merged** |
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

## Known problems, not yet scheduled

### 1. Every leak costs the same, past wave 5 ⚠ highest priority

`Leak.resolve` switches to `min(4, remaining health)` after wave 5, and every
enemy has ≥4 health from wave 10 on, so **the cap always binds**:

| Wave | Goblin | Ogre | Bat |
|---|---|---|---|
| 1–5 | 1 | 4 | 2 |
| 10–20 | **4** | **4** | **4** |

The run is always exactly **5 leaks from over**, whatever leaked. **A boss
reaching the goal costs the same as a bat** — still true after slice 1, and
now more visibly wrong, because there are bosses to notice it with. Per-kind `life_loss` becomes dead
data, and the ogre's `life_loss: 5` is **never read at any wave**, because the
cap is 4.

Not a careless bug — the cap exists because the uncapped health rule meant one
wave-20 leak ended the run. Fixing it properly needs a per-kind or per-wave
leak model and its own measurement pass. **Strongest candidate for the next
slice.**

### 2. The web build has never actually been played

It boots, the menu draws, the field renders — but no click has ever gone
through it in a browser. The prep timer and call-early button are the first
mechanics that change state without a placement, and the browser is the one
environment where that path is unexercised.

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

## Deferred deliberately

- **Phased enemies.** `Targeting.is_targetable` already gates on `phased` and
  Basic's *Spotter* tier already grants `detection`. A third property on top of
  armour and shields is more than one slice can balance.
- **Per-biome endpoint art.** The goal and spawn render identically in forest,
  ice and desert. Tripling the endpoint art is its own decision.
- **A map-select screen.** Maps chain by `next`; choosing one belongs with the
  save.
