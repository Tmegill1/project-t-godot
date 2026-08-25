# UPDATE — what we want to do next

**Purpose:** the forward-looking backlog. What is agreed, what is decided but
not yet built, and what is still open. `CONTINUE.md` records what *is*; this
records what *should be*.

Last updated: 2026-08-25.

---

## Status

| Slice | State |
|---|---|
| Core slice, tower upgrades, free placement, two art swaps | ✅ merged |
| **Slice 0** — wave economy, measured gold curve, visible limits, maps 2 and 3 | ✅ merged and **deployed** |
| **Slice 1** — roster, resistance, bosses | 📋 spec + plan written, Task 1 starting |
| Slice 2 — tactical powers | ⬜ decided, not designed |
| Slice 3 — versioned save + meta-progression | ⬜ decided, not designed |
| Slice 4 — hero | ⬜ decided, not designed |

Live at <https://tmegill1.github.io/project-t-godot/>. Every push to `master`
republishes it.

---

## Slice 1 — roster, resistance and bosses *(in progress)*

**Spec:** [`docs/superpowers/specs/2026-08-25-roster-resistance-and-bosses-design.md`](docs/superpowers/specs/2026-08-25-roster-resistance-and-bosses-design.md)
**Plan:** [`docs/superpowers/plans/2026-08-25-roster-resistance-and-bosses.md`](docs/superpowers/plans/2026-08-25-roster-resistance-and-bosses.md)

### The problem, measured

| | |
|---|---|
| Wave 20 total enemy HP | 1,776 |
| A maxed 16-tower board's DPS | 617 |
| Seconds to delete the whole wave's HP | **2.9** |
| Seconds the wave takes just to spawn | **80** |

**≈28× overkill.** A maxed Long Range hits for 76 against a wave-20 ogre's 20
HP. Even a maxed *Basic* one-shots everything.

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

Proposed model, numbers to be set by measurement:

- **Armour** is flat reduction per hit. It bites physical at full rate and
  magic at a *higher* rate, so physical is the armour answer — with a
  **minimum-damage floor** so magic is never reduced to nothing.
- **Shields** absorb most of a hit and cost a charge. Magic leaks a much larger
  fraction through than physical does, so magic strips shields fastest — but
  physical still gets *something* through, rather than being fully absorbed as
  it is today.

⚠ This changes `Damage.resolve`'s current shield behaviour, where a shield
absorbs the **whole** hit. Several of the 68 existing assertions in
`test/test_damage.gd` will move. Update them deliberately; do not delete them.

### Penetration scales with tower level — the owner's rule *(2026-08-25)*

**Every tower gains penetration as it upgrades**, not just the two Long Range
tiers that grant `pierce_bonus` today.

- Penetration reduces effective armour.
- It is derived from **total tiers bought** across both branches, so investment
  in any direction makes a tower better at getting through.
- The existing explicit `pierce_bonus` tiers stack **on top** of it, so Long
  Range stays the pierce specialist.
- This is the second reason no tower is ever walled: a maxed Magic tower
  carries penetration even though neither of its branches mentions pierce.

Wiring note: `resolve_tower_stats` already computes `pierce`, and
`Damage.resolve` already subtracts it from armour. This is a new *term* in an
existing calculation, not new machinery.

### Bosses

Waves **10 and 20**, both trolls, the second far worse — more than twice the
health, heavier armour, drawn markedly larger. Structured as a table
(`data/bosses.gd`) so waves 30/40 in endless play, and any new sprite added
later, are data entry.

`assets/audio/boss.ogg` has been in the repo since the core slice and is **not
even registered in `AudioManager.SOUNDS`**, so it has never been loaded. It
gets wired here.

### Showing resistance

No new art. Sprite **tint** by resistance (armour → cold steel, shield → pale
blue) and **scale** for bosses. Both display-only; every rule reads the data,
not the colour. A shader is the upgrade path — `modulate` can only multiply, so
it cannot truly desaturate. Placeholder until real art arrives.

---

## Known problems, not yet scheduled

### 1. Every leak costs the same, past wave 5 ⚠ highest priority

`Leak.resolve` switches to `min(4, remaining health)` after wave 5, and every
enemy has ≥4 health from wave 10 on, so **the cap always binds**:

| Wave | Goblin | Ogre | Bat |
|---|---|---|---|
| 1–5 | 1 | 4 | 2 |
| 10–20 | **4** | **4** | **4** |

The run is always exactly **5 leaks from over**, whatever leaked. A boss
reaching the goal costs the same as a bat. Per-kind `life_loss` becomes dead
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
