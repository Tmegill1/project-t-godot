# CONTINUE HERE

**Point an assistant at this file and say "continue this project."** It contains
everything needed to resume with no prior conversation.

Last updated: 2026-08-29 · Branch `feat/leak-model` · **everything through
slice 1 is merged. Suite green at 13,425 checks across 41 files.**

**`master` is TWO COMMITS AHEAD of `origin/master`, and `feat/leak-model` is
unmerged on top of that.** `origin/master` is at `9662465`. Pushing
republishes the live public site, so confirm with the owner first — CI runs
the whole suite before it exports, but the deploy is public either way.

Since the last update: the three maps migrated to a **text format** with a
Godot painting scene (§12), fences and fires became **camps** instead of
scatter (§13), the **Sell button** was fixed — it had been rendering 38px
below the bottom edge of the viewport — and **what a leak costs was rewritten**
(§14).

> **Slice 0's spec and plan are
> [`docs/superpowers/specs/2026-08-24-slice-0-design.md`](docs/superpowers/specs/2026-08-24-slice-0-design.md)
> and
> [`docs/superpowers/plans/2026-08-24-slice-0.md`](docs/superpowers/plans/2026-08-24-slice-0.md).**
> Later slices, in dependency order: bosses and enemy properties, tactical
> powers, the versioned save and meta-progression, and a hero. The owner has
> decided powers will be **bought with gold and priced expensively** as a
> late-run sink, rather than costing the Insignia they cost upstream — which
> will move the gold curve again, so re-measure it then.

> **Picking this up after the illustrated art swap? Read §0 — it now covers
> what shipped and the traps that are still true.** Read §5 and §6 too,
> whatever you do: the engine facts and the standing rules apply to
> everything here.

> This file is the *orientation* document: state, how to run things, and the
> hard-won facts that are expensive to rediscover. The per-task status table and
> the decision log live in [`PROGRESS.md`](PROGRESS.md) and are **not** duplicated
> here — read that too, and trust it over this file for task-by-task status.

---

## 0. THE ART OVERHAUL — merged and deployed

Every asset in the game was replaced from an illustrated sprite sheet, and
then again for the enemies from a second sheet carrying real walk and death
animation. It is on `master` and live at
<https://tmegill1.github.io/project-t-godot/>.

**Read [`docs/art-overhaul.md`](docs/art-overhaul.md) before touching the art.**
It records what changed and, more importantly, *why* — including the several
things that looked obvious, were measured, and turned out to be wrong. The
short list of facts you will otherwise re-derive:

- The towers were cut on the sheet's own "LVL n" captions, not on the tower
  art, because the towers touch and cannot be separated by gaps.
- All sixteen tower frames share ONE scale factor. Fitting each to its frame
  independently makes a taller upgrade draw *smaller* than the level below it.
- All sixteen road connection masks are composed from one cross per biome. The
  sheet does not ship a usable set of connection pieces.
- `MapRenderer.TILE_BLEED` crops 6px of painted card border off every tile.
  Without it the board reads as cards in black gutters.
- The ground reads as a grid because of PERIODICITY, not seams — the step
  across a tile boundary is no larger than the step inside one. Ground tiles
  are drawn at one of four orientations, which cuts it 61%.
- Enemies animate on drawn frames indexed by DISTANCE TRAVELLED. A timed cycle
  moves a slow enemy's legs as fast as a quick one's.
- Towers draw at 2.4x and campfires at 0.8x their footprint. Both are display
  only — every placement rule reads the underlying `size` field directly.

## 1. What this project is

A port of [Tmegill1/project-t](https://github.com/Tmegill1/project-t) — a Phaser 3
tower-defence game — to **Godot 4.7.1 in GDScript**.

This pass builds the **core slice**, not the whole game: one map, four towers, three
enemies, twenty waves, win and lose. Upgrade branches, enemy properties, bosses,
powers, currencies and meta-progression are deliberately deferred so there is
something playable in the middle rather than only at the end.

Two documents hold the reasoning:
- [`docs/superpowers/specs/2026-08-09-godot-port-design.md`](docs/superpowers/specs/2026-08-09-godot-port-design.md) — the design and why
- [`docs/superpowers/plans/2026-08-09-godot-core-slice.md`](docs/superpowers/plans/2026-08-09-godot-core-slice.md) — the 23-task plan, **with full code for every remaining task**

---

## 2. Where things stand

**The game is playable end to end** — main menu → game → win or lose → next map
or menu, with sound, across three maps and twenty waves with bosses on 10
and 20.

| Layer | State |
|---|---|
| `sim/` — 11 modules | ✅ complete, reviewed |
| `data/` — 9 modules | ✅ complete, reviewed |
| `assets/` — 169 PNGs (`assets/art/` and `assets/towers.png` baked from the illustrated reference sheet, plus `assets/audio/`) | ✅ imported, baked, verified visually |
| `game/` — board, enemy, tower, projectile, map renderer | ✅ complete |
| `ui/` — menu (with a difficulty selector), HUD (1.5x speed toggle, active-tier readout), build panel, tower inspector, game-over, victory | ✅ complete |
| `audio/` — pooled playback, 17 core-slice events | ✅ complete |
| Web export | ✅ preset + build; **boots and renders in a browser; not yet played in one** |
| Deploy | ✅ live at **https://tmegill1.github.io/project-t-godot/** — every push to `master` republishes, at the address GitHub assigns (no custom domain) |
| Tests | ✅ 13,554 checks across 45 files, exit 0 |
| Map authoring | ✅ text format (`data/maps/*.txt`) + a `@tool` painting scene — see §12 |
| Decoration | ✅ camps (wall + fires) in forest; scattered landmarks in ice/desert — see §13 |
| Enemies | ✅ five — goblin, bat, shaman, ogre (rank and file) and troll (**boss only**) |
| Resistance | ✅ armour on ogres/trolls, shields on bats/shamans, both scaling by wave |
| Damage types | ✅ physical and magic, with soft edges and a damage floor |
| Bosses | ✅ waves 10 and 20, table-driven in `data/bosses.gd` |
| Health curve | ✅ measured, not ported — see §9.2 |
| Difficulty | ✅ three tiers chosen per run — Normal, Hard, Nightmare — measured, not guessed. See §15 |
| Maps | ✅ three — The Pass (forest), The Fork (ice, **two entrances**), The Coils (desert), chained by `next` on victory |
| Wave economy | ✅ clear bonus, speed bonus, interest, 20s prep timer, call-early |
| Gold curve | ✅ measured, not guessed — see §9.2 |
| Tower upgrades | ✅ **all 11 tasks done** — rules, tower, board, harness, inspector, verified in the running game. See §4 |

**The repo is public** and the game is deployed from it.
`.github/workflows/deploy-pages.yml` exports the build in CI and publishes it
to GitHub Pages on every push to `master`; it downloads the engine and the
export templates at run time pinned to `GODOT_VERSION`, runs the full suite
before publishing, and caches the 1.2GB template archive on that version. It
was put on GitHub Pages rather than Cloudflare Pages for one reason:
`index.wasm` is 37.68 MiB and Cloudflare Pages rejects any asset over 25 MiB.
Serving the wasm pre-gzipped (9.62 MiB) was tested and does work in a browser,
so that route stays open if it is ever wanted.

The web build was opened in Firefox for the first time on 2026-08-14: the wasm
compiles, the `.pck` loads, the main menu draws, and past it the play field
renders — map, HUD and build panel. **What nobody has done is *play* it in a
browser**: placing a tower and running a wave have been exercised headlessly
and in the desktop build, never through the browser. See §4.

The rules layer also runs headlessly on its own: `sim/harness.gd` simulates a real
wave — pathing, targeting, damage, splash, leaks — with no window open. That is the
project's load-bearing claim, so **any new rule goes in `sim/` and gets used by both
the harness and the game**, never written twice.

---

## 3. Quick start

```bash
cd ~/Projects/project-t-godot

# Play it
godot --path .

# Run the whole suite. Exit 0 = pass, 1 = fail.
godot --headless --quit --script test/run_tests.gd

# ONLY needed when you add a NEW class_name. Run it before the tests or you get
# a baffling "Identifier not declared" parse error. Not needed otherwise.
godot --headless --import
```

The Godot binary is `~/.local/bin/godot`, a symlink to
`~/Desktop/Godot_v4.7.1-stable_linux.x86_64`. **The Godot MCP hardcodes that
symlink path**, so if it breaks, both the CLI and the MCP break together. It has
broken once already when the binary moved.

### A green run is noisy. Do not panic.

A passing suite prints **118 `SCRIPT ERROR` lines** to stderr. All are expected:

- **6** from `test/test_harness_selfcheck.gd`, which crashes deliberately on
  purpose to prove the runner's crash sentinel works.
- **~110** from `Tower.setup` / `Tower._refresh_visuals` /
  `Tower.set_range_visible` / `Enemy.setup` aborting on unresolved `@onready` in
  nodes the *board* instantiated (see §5 — the board's own `add_child()` does
  not deliver `NOTIFICATION_READY` in a frameless test either). Documented at
  the top of `test/test_game_board.gd`. The count grew with the upgrade work
  because far more tests now place a tower through the board, and because
  `apply_upgrade` refreshes the sprite, which aborts the same way.
- **1** from `test_tower.gd`'s
  `test_setup_lands_tiers_and_stats_even_when_the_sprite_half_aborts`, which
  reproduces that state deliberately.

Judge the run by the **summary line and the exit code**, never by stderr volume.
`FAIL` lines and the counters in the summary are the signal. *New* noise is a
defect; this noise is not — **but do read it**. The bug where pressing an
upgrade row bought the tier and left the panel stale was found in these lines
and in nothing else: it failed no test and looked correct in every screenshot.

---

## 4. What is left

Both feature branches are finished. What remains is not implementation:

**1. ~~The whole-branch review~~ — done, post-merge.** 48 fresh mutations over
`sim/upgrades.gd` and the table's effect values, plus two checks in the running
game. It found no production bug and three test-only gaps, all now closed
(`96055f6`): the table's effect values were unpinned, the rounding test
compared each stat to `round()` of itself, and `with_upgrade`'s refusal path
could alias the caller's dictionary. What it could NOT close is written up in
the ledger, `.superpowers/sdd/2026-08-14-tower-upgrades/progress.md`
(git-ignored) — three latent minors that need a data shape this game does not
have yet, and a class of defensive guard this harness cannot pin at all,
because Godot's error recovery makes a crash look exactly like the no-op the
guard produces. It was a single-reviewer pass, not two.

**2. Play the web build in a browser.** Still the one thing nobody has done. It
has been *opened* in one — it boots, the menu draws and the play field renders
— but no click has ever been put through it. Placing a tower, buying a tier and
running a wave are all still unverified in a browser specifically. The build
re-exports cleanly with the upgrades in it (`index.pck` 802,084 bytes,
`index.wasm` 39.5MB — a local export now matches CI's byte for byte).

```bash
godot --headless --export-release "Web" export/web/index.html
python3 -m http.server 8000 --directory export/web   # then open http://localhost:8000
```

Expect the menu, then a run: place a tower, tap it, buy a tier, start wave 1,
hear it fire. Audio needs a user gesture in browsers — the menu's Play button
supplies it, so no explicit unlock call exists or is needed.

Worth knowing if you are driving this from an agent: the boot sequence is legible
in the server's own access log. `index.html` → `index.js` → `index.wasm` →
`index.pck` is just the download, but the two `index.audio*.worklet.js` requests
that follow are made by the engine *at runtime*, after the wasm has instantiated
and the pack has been read — so seeing them is decent evidence the engine started,
short of seeing a pixel.

**3. Decide the open art question in §9** — whether the endpoint markers
should become per-biome art.

**4. Playtest and tune.** Nothing here has been balanced, and the upgrade tiers
are as unplaytested as everything else. See §9. `sim/harness.gd` now takes
`tiers` per tower, so a build can be simulated headlessly:

```gdscript
Harness.run_wave({"wave": 20, "path": path, "difficulty": Difficulty.HARD, "towers": [
    {"kind": &"fast", "position": pos, "tiers": {&"sustained": 4, &"burst": 0}},
]})
```

`difficulty` is optional and defaults to `Difficulty.NORMAL`, which is the exact
identity transform — every balance number this project has ever measured
describes Normal. See §15.

### What the upgrade work added

Two branches of four tiers for every tower, the cross-path rule (a branch
passes tier 2 only while the other sits at 2 or below), per-tier costs, sprite
frames driven by *total* investment (`ceil(total / 2)`, capped — the look
changes at 1, 3 and 5 tiers), a tower inspector in the sidebar with Sell moved
into it, and the two mechanics the tiers needed: **slowing** (`sim/slow.gd`) and
**gold per kill** (`EconomySim.kill_reward`). Pierce and detection are wired but
dormant until armoured and phased enemies exist.

One divergence from the reference is deliberate and temporary: Long Range's
**Tungsten Core** is pierce-only upstream, which would be 260 gold for no effect
today and is a mandatory step to the tier behind it, so it carries an interim
`damage_multiplier` of 1.3 and a "(no effect yet)" note, pinned by its own test.
Delete both when enemy properties land. A second, smaller divergence: an expired
slow clears its factor here, where upstream leaves a lapsed slow's factor in
place forever and takes the strongest of it and the next slow.

Note for whoever touches `project.godot`: the `[autoload]` entry for `AudioManager`
is *legitimate*. §5's strip-before-commit warning is about the Godot MCP's
`McpInteractionServer` entry only — do not let the habit delete the real one.

## 5. Engine and harness facts — do not re-derive these

These cost real time to discover. Every one was verified empirically on 4.7.1, not
read in a doc.

- **`add_child()` does NOT resolve `@onready` in the test harness.** Tests run under
  a bare `SceneTree` with no frames, and `@onready` resolves on
  `NOTIFICATION_READY`, which never arrives. **The project-wide pattern is
  `node.notification(Node.NOTIFICATION_READY)`**, called explicitly after
  `add_child()`. See `test/test_tower.gd` and `test/test_hud.gd` for the idiom.
- **`get_tree()` returns `null` in tests**, because nodes are never actually inside
  a tree. Anything that reaches for the tree must be avoided or stubbed.
- **`class_name` does not resolve until `godot --headless --import` has run once**
  after the name is introduced. A fresh clone otherwise fails with "Identifier not
  declared". You do *not* need it for ordinary edits.
- **`load()` does not return null on a parse error** — it returns a `GDScript` whose
  `can_instantiate()` is `false`. `test/run_tests.gd` checks the latter.
- **A GDScript runtime error aborts only the enclosing function frame.** Godot does
  not unwind the stack: the aborting call returns its declared return type's default
  (`false` for `-> bool`, `null` for untyped) and the *caller keeps running*. This is
  the whole basis of the crash sentinel below — and its limit: a crash inside a
  *helper* the test calls does not abort the test. Prefer flat test bodies, and
  assert on any helper's return value.
- **Every `test_*` method is declared `-> bool` and ends `return true`**, including
  at every early return. That is the crash sentinel: a test that dies partway
  returns `false` instead, and the runner fails it. It is self-enforcing — forget
  the contract and the test fails loudly rather than silently vanishing.
- **No `await` in a test method.** `Object.call()` returns a `GDScriptFunctionState`
  instead of `true` and the sentinel misreads it as an aborted test.
- **`queue_free()` does nothing useful in a frameless context.** It only unparents
  once a frame processes, which never happens inside a single synchronous test
  method — the old children stay in `get_children()` alongside the new ones. Use
  `free()` when a node is exclusively owned and you need the removal to be
  observable now. `game/map_renderer.gd` and `ui/tower_panel.gd` both do this and
  both say why.
- **Any test reading tile coordinates calls `Grid.set_active()` first.** `Grid`
  holds active dimensions in static state, so forgetting it makes the result depend
  on test execution order.
- **`aspect="expand"` hands the surplus to the viewport, and something must claim
  it.** The design viewport is 1244×672 under `stretch/mode="canvas_items"`. Under
  `expand` the scale is `min(window.x / 1244, window.y / 672)` and the viewport
  absorbs whatever is spare on the other axis: a window wider in aspect than
  1244:672 grows viewport **width** (height stays exactly 672), a narrower one
  grows **height** (width stays exactly 1244). Anything anchored to a fixed pixel
  size does not grow with it, so surplus nobody claims renders as bare engine
  background — which is exactly how a grey band opened between the 1104px-wide map
  and a build panel pinned to the right at a fixed 140px. `TowerPanel` now anchors
  its left edge to the map's right edge and its other three sides to the viewport,
  so it absorbs the surplus at any window size. **Note the corollary: the map
  cannot be scaled up to fill space instead** — it already fills the viewport
  height exactly, so a uniform upscale crops the bottom rows and a width-only
  stretch distorts the tiles. README §"How the layout responds to window size"
  has the full model.
- **`content_scale_size` is set PER MAP, in `GameBoard._ready`.** Both maps past
  the first are larger than the 1244×672 design box in both axes (The Fork
  1248×816, The Coils 1344×768), so the base resolution becomes the map's pixels
  plus `GameBoard.PANEL_WIDTH` and the stretch system does the downscaling.
  **The point is that world space stays identical to map pixel space** — every
  placement, targeting and splash calculation, and `TowerPanel.offset_left`, all
  assume that. A `Camera2D`, or a scale on the board node, would put a transform
  between `get_global_mouse_position()` and `Placement.can_place`, which is
  exactly the code where a coordinate-space mismatch passes tests and fails at
  the corners. Verified live: three towers placed at (408,360), (456,360) and
  (504,360) on The Coils landed at exactly those coordinates.
- **A map whose aspect differs from the window's leaves a band nothing draws
  into**, and that band is now filled by
  `rendering/environment/defaults/default_clear_color`, matched to
  `TowerPanel`'s `bg_color`. The Coils leaves about 28px under the board at the
  design window size. This was invisible before slice 0 because map 1 fits the
  design viewport exactly and never produced any surplus.
- **A screenshot is the only way to catch a layout regression here.** The test
  harness never puts nodes in a live tree, so containers never lay out and every
  child's computed rect stays at its unlaid-out default. Layout tests therefore
  assert *anchors and offsets*, not positions (`test_hud.gd`,
  `test_tower_panel.gd`). One trap that follows: a property set as an **instance
  override** in a composing scene is invisible to a test that instantiates the
  sub-scene alone — `TowerPanel`'s vertical placement lived in `game.tscn`, so the
  standalone test read the panel's own value and passed regardless. Assert on the
  composed scene when the value being pinned lives on the instance.
- **A tower's live stats come from `UpgradesSim.resolve_tower_stats(kind, tiers)`,
  never from `Towers.DEFS`.** `game/tower.gd` caches the result and refreshes it
  whenever its tiers change; `sim/harness.gd` resolves the same way from the
  `tiers` in its config. An unupgraded tower resolves to exactly its table
  values, which is why every pre-existing balance pin still holds. Reading the
  table directly is the mistake to watch for — it compiles, it passes most
  tests, and it silently ignores every upgrade the player bought. `get_def()`
  survives for the two things no tier touches: projectile speed and arc.
- **A tower's `setup()` assigns its rules state BEFORE anything visual**, and it
  has to stay that way. A board-instantiated tower aborts `setup()` at the first
  `@onready` field it touches (below), and `tiers`/`_stats` must land before
  that point or every board-placed tower is unupgradeable in tests.
- **Godot refuses to `free()` an object while it is emitting a signal** —
  "Object is locked and can't be freed" — and the failure aborts the enclosing
  call, so a teardown that starts inside a button's own `pressed` handler stops
  halfway. This is why `ui/tower_inspector.gd` builds its rows once and rewrites
  them in place: a rebuild triggered by pressing a row bought the tier and then
  left the panel advertising it. `ui/tower_panel.gd`'s rebuild is safe only
  because it runs from `bind()`, never from a press.
- **`Engine.time_scale` scales the physics DELTA on 4.7.1; it does not change
  the tick rate.** Measured directly: at `time_scale = 2` the delta handed to
  `_physics_process` goes from 0.01667s to 0.03333s while 120 ticks still take
  ~2 seconds of wall clock. So the HUD's fast-play button grows every enemy's
  step, which is the oscillation shape that soft-locked waves 19 and 20 — safe
  only because of the waypoint clamp, and held by
  `test_every_wave_undefended_terminates_at_the_doubled_tick_size`. That sweep
  runs at DOUBLE the step size while the button applies 1.5x, deliberately:
  the setting keeps headroom over what is tested. Anything that changes
  movement must keep passing that sweep as well as the 1x one, and raising
  `Hud.FAST_TIME_SCALE` past 2.0 would leave its cover.
- **Running the game through the Godot MCP rewrites `project.godot`.** It injects an
  `[autoload] McpInteractionServer` entry, and leaves an empty `[autoload]` section
  behind on stop. That is local debug tooling — committing it breaks the project for
  anyone without the MCP. **`git diff project.godot` and strip it before every
  commit made after running the game.**
- **The MCP's injected clicks reach Control nodes but NOT
  `GameBoard._unhandled_input`.** Clicking a build button works; clicking the map
  never places a tower, with `_selected_kind` and the tile both verified correct.
  Drive the board through `_handle_tap()` / `upgrade_selected_tower()` with
  `game_eval` instead — the same path the tests take — and use clicks for the UI.

---

## 6. Rules that bind every task

- **GDScript only.** No C#, no addons, no external dependencies.
- **`sim/` and `data/` must never touch the engine** — no `Node`, `get_tree()`,
  `preload`, `@onready`, `@export`, scene types, `load(`, `ResourceLoader`,
  `$`/`%` node shorthand, engine RNG, or `Time.` / `Engine.` / `OS.`.
  `test/test_sim_purity.gd` enforces this and its own detector is unit-tested so it
  cannot pass vacuously. The ban covers two failure modes: scene types would break
  the *headless* claim, and clocks/RNG/platform state would break the
  *reproducible* one — which is worse, because it still passes every test until the
  day two runs disagree.
- **Sim time is milliseconds.** Callers convert with `delta * 1000.0`.
- **Combat uses distance arithmetic, never physics.** `Area2D` is for tap-picking
  only. Godot's physics is frame-coupled and non-deterministic; routing combat
  through it would put rules in the engine and kill the headless harness.
- **All randomness goes through `sim/rng.gd`.**
- **One rule, one home.** If the harness and the board both need to answer the same
  question, the answer lives in `sim/` and both call it (see `Damage.in_splash`).

---

## 7. Domain facts already established — do not re-derive

- **mulberry32 ports bit-exact to GDScript.** The multiplications overflow int64,
  but two's-complement wrapping preserves the low 32 bits. Verified to 17 decimals;
  golden values are pinned in `test/test_rng.gd`.
- **The generated map is byte-identical to the reference TypeScript's output**,
  scattered blocked tiles included, pinned by a golden-board test.
- **Wave composition accumulates from wave 1** — wave 3 contains waves 1 and 2.
  Looks like a bug, is not, and tests pin the totals.
- **One movement quirk is deliberate and preserved:** arriving at a waypoint
  consumes the whole tick without moving. Changing it shifts every enemy's arrival
  time across the whole game.
- **⚠️ The other movement quirk — no clamping, so a fast enemy overshoots — was
  REMOVED, deliberately, and must not be restored.** It is faithful to
  `movement.ts`, and it is only survivable there because Phaser passes a *measured*
  frame delta that jitters the step. Godot's `_physics_process` delta is fixed at
  1/60s, making each enemy's step a constant, and a constant step above 4.0 px/tick
  can oscillate around a waypoint forever. Waves 19 and 20 did exactly that
  (bees at 4.25 and 4.375 px/tick), which **soft-locked the game**: a stuck enemy
  never leaks, never frees, so the wave never clears and victory is unreachable.
  Read the comment at the arrival test in `sim/movement.gd` before touching it.
  `test_harness.gd::test_every_wave_undefended_terminates_at_the_default_tick_size`
  is the guard.
- **The signals are `Enemy.died(reward: int, kind: StringName)` and
  `Enemy.leaked(life_loss: int)`.** This entry previously claimed `died` took
  reward only and told you to trust the code over the plan; the code has
  carried both arguments all along (`game/enemy.gd`, the `signal died` line and
  its `died.emit` in `_die`), so the entry itself was the wrong half. Connect
  with two parameters — a one-argument `Callable` fails to connect, which in a
  test aborts the method and trips the crash sentinel rather than failing
  cleanly. Trusting the code remains the right instinct; that is how this was
  caught.
- **Enemy kind keys name what the ART DRAWS.** They used to say slime and bee
  while the sprites drew a goblin and a bat. The key picks the sprite
  directory, the death sound and the join to wave composition, so renaming one
  means moving art, renaming audio and updating `AudioManager.SOUNDS`
  together. **`troll` is deliberately absent from `Enemies.KINDS`** - it is
  boss-only, and KINDS is what wave composition iterates.
- **Resistance is split by COUNTER, not sprinkled.** Armour is flat reduction
  so it folds to few large hits; shields absorb most of a hit so they fold to
  many cheap ones. Ogres and trolls carry armour, bats and shamans carry
  shields, and **the goblin carries neither on purpose** - it is the control
  every other kind is read against. Scaling never GRANTS what a kind lacks: a
  0 in the table stays 0 forever.
- **Damage has a TYPE, and the edges are soft.** Physical is strong against
  armour and reduced against shields; magic is the inverse. Under both sits
  `Damage.MIN_DAMAGE_FRACTION`, a floor expressed as a fraction of the incoming
  hit - a flat floor would make a 4-damage tower and an 80-damage tower equally
  good against a wall. **A shield is a reduction, not immunity**: a shield-met
  hit can be lethal, deliberately, or a 1-health shielded enemy would be
  unkillable.
- **Penetration scales with tower level**, not only with the two Long Range
  tiers that name it. Its rate and `ARMOR_PER_WAVE` are a PAIR and were tuned
  together - at 2 per tier, six tiers erased armour outright for every physical
  tower. Change one and re-measure the other.
- **A boss is an ordinary enemy with different numbers.** It uses the same
  movement, targeting, damage and leak rules; `Enemy.make_boss` overrides stats
  on top of `setup()`, rules state first, so the ordinary spawn path never has
  to know bosses exist. The boss is appended to the **schedule**, not the
  composition - anything counting spawns must add it separately.
- **The shaman aura is a shared rule.** `sim/aura.gd` reports which ids gain a
  charge and applies nothing; the board and the harness both call it, and the
  harness calls it before its fire block so a charge granted this tick can
  absorb this tick's shot.
- **The full wave composition runs down EVERY spawn path**, not divided between
  them — ported from the reference, which computes
  `totalEnemies * enemyPaths.length`. A two-entrance map therefore fields twice
  the wave at the same wave number, which is why The Fork opens with 250 gold
  and a budget of 20 against The Pass's 100 and 16. `GameBoard` keeps one queue
  and one cursor per path; the queues share one schedule array, which is safe
  because they are only ever read.
- **A kill's reward is scaled by the wave's `gold_modifier`**, which DECREASES
  where health and speed increase. Composition accumulates from wave 1, so a
  flat per-kill reward made income compound with enemy count: 48% of a run's
  gold used to land in the last five waves, and wave 20 paid 68.8× wave 1. The
  order in `EconomySim.kill_reward` is load-bearing — wave modifier, then the
  tower's gold multiplier, then the flat bonus, which is never scaled.
- **The prep timer lives in `_physics_process`, deliberately**, so
  `Engine.time_scale` scales it and fast-forwarding cannot buy real thinking
  time. It is armed only PAST the victory branch in `_on_wave_cleared`, or
  winning starts a countdown to a twenty-first wave; and `start_next_wave`
  must CLEAR it as well as pay for it, or the countdown keeps running
  underneath the live wave. Both orderings have their own test, and the second
  was found only by mutation testing.
- **`test/case.gd`'s `_values_equal` cannot distinguish `20` from `20.0`**, so no
  data-table test detects a *type* change. Known limitation.

---

## 8. How the work has been done, and why it kept finding bugs

Each task is implemented by a fresh subagent from a task brief, then independently
reviewed, then fixed until the review is clean. Progress is appended to
`.superpowers/sdd/2026-08-09-godot-core-slice/progress.md` — **that ledger is the
recovery map. Trust it and `git log` over recollection.**
`deferred-for-final-review.md` beside it lists the minors that were consciously
left alone.

**Almost every defect found in the rules layer came from mutation testing** —
deliberately breaking a value and checking the suite notices — and **almost none
from reading code**. Dispatch implementers with two standing instructions:

1. Port **every** meaningful test from the reference module, not just the brief's
   subset. When this instruction was added at Task 9, test counts went from ~11 to
   36 and real gaps started surfacing.
2. **Mutation-test your own work**, enumerate every line first, and report survivors
   honestly. Several reports were caught claiming coverage they had not earned.

Self-testing raises the floor but does **not** replace review — an implementer
grading its own homework reported a pass it had not earned, more than once.

**From Task 16 on, rendering cannot be mutation-tested.** A sprite at the wrong
scale, an atlas off by a row, an enemy facing backwards — none fail a test.
Verification is **screenshots and measurement**, via the Godot MCP. Task 15 proved
the point: 5 of the 8 rects inherited from the original game were wrong, and every
one was found by looking at the image, never by a test.

**And one lesson the whole-branch review added, which is worth more than either:**
the waves 19/20 soft-lock was *found* by a task review, *correctly diagnosed*, and
then dismissed because the test harness's tick cap contained it. It did. The game
had no tick cap. **Containment reasoning does not transfer across callers.** When a
review concludes "this is survivable", check whether it is survivable in the thing
the player runs, not only in the thing the tests run.

---

## 9. Open decisions for the project owner

1. **Endpoint markers are shared across biomes, not themed per biome.** The
   goal (a composed keep) and spawn (a composed cave mouth) render identically
   in forest, ice and desert. Spec §8.1 defers per-biome endpoints
   deliberately — a forest keep of stone, an ice fortress of crystal, a desert
   one of sandstone would read better and make each map feel authored, but
   triple the endpoint art and add two assets per future biome. **Decide
   whether that's worth it** when maps 2 and 3 are actually built.
2. **The balance is unplaytested, with three measured exceptions.** The
   original's own handoff notes say every number is a placeholder, and
   "Matches Phaser" will not mean "plays well." The exception is the **gold
   curve**: `Waves.GOLD_PER_WAVE` was swept against the most a player could
   possibly spend (16 towers at the budget, best mix, every tier the
   cross-path rule allows = 17,170 gold on map 1) rather than guessed. Slice 0
   had to touch it — the wave economy adds ~3,555 gold against no new sink,
   which would have turned a 1,185 deficit into a 2,370 surplus. See
   `docs/superpowers/specs/2026-08-24-slice-0-design.md` §4.6 for the full
   measurement and the sweep table.

   Slice 1 added two more: **`Waves.HEALTH_PER_WAVE`** and the
   **`ARMOR_PER_WAVE` / `PIERCE_PER_TIER` pair**. The decisive finding there is
   worth knowing before touching any of it - *health scaling alone cannot
   threaten a maxed board at any rate*, because the binding constraint is board
   COVERAGE rather than hit points. At the shipped values, eight maxed towers
   lose wave 20 and twelve hold it, against a budget of sixteen. Everything
   else still wants the harness.
3. **Volume and mute do not persist between runs.** The HUD's two audio
   controls drive `AudioManager` directly and nothing writes them to disk, so
   a player who mutes the game gets sound back next launch. Deliberately not
   built: there is no settings file in this project yet, and inventing one for
   two values is a bigger decision than it looks. **Decide** whether this
   project wants a settings resource, and if so what else belongs in it.
4. **Web export is 40.6 MB** — measured, not predicted; the design anticipated
   25–40 MB. 39.5 MB of that is `index.wasm`, the Godot engine binary. The
   game's own `index.pck` is 790 KB raw / 666 KB gzipped, against the Phaser
   build's 368 KB gzipped — so the game data itself is roughly 1.8× larger, but
   that difference is noise beside the engine. Trimming art or audio cannot
   meaningfully move the total; only a different engine would.
5. **RESOLVED — the HUD text now has a backing plate.** The white
   Gold/Lives/Wave text had no backing and was confirmed illegible on both
   ice and desert, with screenshots. It stayed open because only forest was
   reachable; the two new maps make both pale biomes reachable, and slice 0's
   own additions (the tower budget and the prep countdown) made it worse by
   putting more text up there. Fixed with a semi-transparent plate behind the
   whole `Top` bar (`ui/hud.tscn`, node `Plate`), chosen over a per-biome tint
   or a text shadow because it is the only one of the three that is
   biome-independent — a fourth biome cannot arrive and break it. Verified
   live on ice and desert; screenshots re-taken at
   `docs/screenshots/board-map{2,3}.png`.

6. **RESOLVED — towers now draw at 2.4x their footprint.** They were the
   least prominent thing on the board: a placed tower drew about 19 x 26px of
   art against 44px bright-orange campfires and 48px trees. They had not
   shrunk (the Kenney basic drew 20 x 22) — the props got louder. Fixed by
   `Tower.DISPLAY_SCALE`, set to 2.0 and then raised to 2.4 on the owner's
   call, which is **display only**: `Placement`
   still reads `Towers.DEFS[kind]["size"]` directly, so the corridor, the prop
   clearances and the tower-to-tower spacing are untouched, and
   `test_the_display_scale_does_not_reach_the_placement_radius` is what stops
   a future tidy-up merging the two. Compared in game at 1.6, 1.8 and 2.0 and
   checked at the crowded end, where four towers packed to
   `MIN_TOWER_SPACING` stay individually legible. Left here rather than
   deleted because the *reason* still matters: this art needs the player's
   pieces drawn larger than their footprint, and anything new that goes on
   the board should be judged against the props, not against the old pack.

---
## 10. Known gaps

- **Task 15 never had a formal review pass.** It was verified visually by the
  controller, but the implementer's own self-check proved unreliable there.
- The remaining deferred minors are in
  `.superpowers/sdd/2026-08-09-godot-core-slice/deferred-for-final-review.md`, each
  triaged by the final review. The ones left open are cosmetic or YAGNI: the dead
  `PlacementPreview` node, the unread `_range_visible` field, the uncalled
  `Enemy.get_sim_state()`, the map-dimension triplication, the always-enabled Sell
  button, the tap-selects-tower asymmetry, and the `instance_id` targeting
  tie-break. The map-dimension one got one copy *smaller*, not larger, when the
  build panel was re-anchored: its old fixed `-140` offset silently encoded
  "1244 − 1104", and it now derives the number from
  `Maps.pixel_size(board.get_map_name())` instead.
- `game/game_board.gd` is ~270 lines and owns state, spawn scheduling, tower
  ticking, hit resolution, input, placement and now upgrades. Not urgent; worth
  splitting if it grows again.
- The upgrade branch's deferred minors are in
  `.superpowers/sdd/2026-08-14-tower-upgrades/progress.md`, for a whole-branch
  review. Two are worth knowing without reading it: `GameBoard`'s
  no-selection guards (`sell_selected_tower`, `upgrade_selected_tower`) cannot be
  pinned by this harness — without them the method dereferences null, which
  aborts its own frame and looks to the caller exactly like the no-op the guard
  produces. `can_upgrade`'s unknown-branch guard is the same shape. Keep them
  and stop expecting a test to hold them. (The effect-values gap listed here
  before is closed: `EXPECTED_EFFECTS` in `test_upgrade_tables.gd` now states
  all thirty-two tiers.)
- **`assets/enemies/**` (30 PNGs: directional `D_Walk`/`D_Death`/`S_Walk`/
  `S_Death`/`U_Walk`/`U_Death` sheets for bee, ogre and slime) is orphaned.**
  Found while documenting the illustrated art swap: it predates *both* art
  swaps — the Kenney branch explicitly left it untouched, and the
  illustrated branch's own enemy work (Tasks 7 and 9) moved `game/enemy.gd`
  onto `assets/art/enemies/<kind>/variant_N.png` per-spawn variants without
  ever pointing at these sheets. Nothing references them by path or by
  `.import` UID — grepped both, zero hits. Out of scope to delete here: this
  task's constraints rule out touching any PNG, and this directory has
  nothing to do with Kenney. Whoever next touches enemy art should delete
  it.

---

## 11. Suggested next action

```bash
cd ~/Projects/project-t-godot
git checkout feat/illustrated-art-swap
godot --headless --import                            # once, after a fresh clone
godot --headless --quit --script test/run_tests.gd   # expect 7143 checks, exit 0
godot --path .                                       # and actually play a run
```

**§0 — the illustrated art swap — is done and not yet merged.** All ten
tasks are implemented and the suite is green. Merge
`feat/illustrated-art-swap` to `master` first; if you touch map or enemy
rendering again afterward, read §0's traps before you do — the mipmap gap in
particular has now recurred once already across two separate branches, and
will again if the next new art forgets it is a two-part fix (filter AND
`.import` generation).

**After that merge**, the next piece is the map 2 and map 3 layouts plus
map-to-map progression, which this branch (like the one before it)
deliberately excludes and which needs its own spec and plan.

**The other standing feature** is the five composable enemy properties —
armoured, phased, swift, shielded, splitter. Pierce and detection are already
wired and waiting for them, and the upgrade tiers that carry those effects are
inert until they land. It needs its own spec and plan.

**To close the last verification gap**, play the deployed build at
https://tmegill1.github.io/project-t-godot/ — place a tower, buy a tier, run a
wave, hear it fire. It is confirmed to boot and render in a browser; nobody has
yet put a click through it. That takes two minutes and needs a human, because it
cannot be automated on this setup.

Play a full run before changing any number. The balance has never been playtested
and every value came across from a prototype whose own notes call them
placeholders; `sim/harness.gd` can simulate whole waves headlessly — upgrade
tiers included — so tuning does not mean sitting through twenty of them.

---

## 12. Making maps

Maps are **plain text**, one character per tile, in `data/maps/*.txt`:
`S` spawn, `G` goal, `=` road, `#` blocked, `.` buildable. `data/map_format.gd`
parses, formats and validates them; `data/maps.gd` reads the file named by each
map's `"layout"` field. The old algorithmic builders (`demo_map.gd`, `map2.gd`,
`map3.gd`) are **deleted** — the shape of a map is now the file.

**To paint one:** open `tools/map_editor.tscn` in the Godot editor, select the
`Layer` node, and use Godot's own TileMap panel — rectangle fill, bucket, line,
undo, all free. Then select the root node and tick `load_map` (pull a committed
map in), `export_map` (write your painting out), or `check_map` (report problems
without writing) in the Inspector.

**The game only ever reads the `.txt`.** `tools/` is excluded from the export,
the editor is a `@tool` script rather than an addon (so the no-addons rule
holds), and none of it ships — verified by loading the live `.pck` and
confirming the scene, IO module, baker and palette are all absent. Delete the
editor tomorrow and every map still loads. Adding a map is a `.txt` plus one
`Maps.DEFS` entry.

Export **refuses** a map with problems, naming the cell: *"the spawn at column
0, row 0 cannot reach the goal"*. All three shipped maps round-trip
byte-identical through the real scene, which is what stops an edit rewriting a
whole file and burying the actual change in noise.

**`PathFinder.get_all_spawn_paths` cannot tell you whether a spawn can reach the
goal.** It returns a two-point *fallback* path for one that cannot, because
`Movement.advance` indexes into a path and derives arrival from its length — so
every path must have a start and an end whatever the map looks like. Counting
its results therefore always equals counting spawns, and a test doing exactly
that passed on a map with a wall across it. Use
`PathFinder.unreachable_spawns`.

---

## 13. Decoration: camps, and what a prop slot actually is

Fences and fires do not scatter. They appear only as **camps**: a run of 3–5
abutting wall sections with one or two fire pits behind them, sited 2–3 tiles
back from the road and one tile clear of the map border. Anything that used to
be a lone fence is now a tree or a rock.

The reason is that a palisade and a fire pit are *manufactured* objects. A
boulder alone in a field is a boulder; a fence alone in a field is a fence
around nothing.

**Camp walls skip the jitter every other prop gets** — alignment is the whole
effect, since the art only abuts at exact tile pitch. That also means they skip
the road clamp jitter carries (`_room_towards`), so they are safe *only* because
the siting rules hold them clear of the lane. Relaxing any siting rule makes
`test_no_prop_overhangs_the_road` fail, which is how that dependency was found.

**A prop slot name does not tell you what the art is.** `Biomes.PROP_SLOTS` is
the same four names in every biome, but `spike` is a 95x63 wooden palisade in
forest, a 37x79 totem on a post in ice, and a 42x35 skull pile in desert. Only
the palisade tiles into a wall — five totems in a row would be a worse version
of the problem camps fix. `Biomes.has_wall_art()` carries that fact and camps
are forest-only because of it; ice and desert scatter their spike as the
landmark it actually is. **Check the PNG dimensions before writing any layout
rule over a slot name.**

Camps cost build space, measured rather than assumed: legal tower positions on
a half-tile lattice went 46.3% → 42.1% on The Pass, 54.7% → 51.7% on The Fork,
50.1% → 45.5% on The Coils. Against a 16-tower limit and 542 legal spots on the
tightest map, nowhere near binding — but re-measure if camp counts or widths
grow. The variant that held the prop count steady was built and rejected: it
stripped The Pass to six scattered props.

`update.md` records what would finish the idea — wall art for the other two
biomes, a corner piece, and hand-authored settlements in the map text rather
than rolled camps.

---

## 14. The sidebar has to fit

The 140px column right of the map holds the build palette **or** the tower
inspector, never both. Stacked they needed 924px of a 672px viewport, and the
last row — **Sell** — rendered 38px below the bottom edge: built, wired, and
covered by a test that pressed it and asserted the board sold, while no player
could reach it. Every test asked "does this button work"; none asked "is it on
the screen."

Selecting a tower hands the column to the inspector; ESC or a tap on empty
ground hands it back. Worst case is now 465px of 672.

**The viewport height is the map's pixel height** (`GameBoard.required_content_size`),
so the shortest shipped map is the binding constraint — a new, shorter map can
put this back. `test_tower_panel.gd` pins it.

Two traps if you touch this: a `Container` returns `(0, 0)` from
`get_combined_minimum_size()` outside a live tree *and* whenever it is hidden,
so a fit test must sum the children itself; and the inspector needs its own
`bind()` (game.gd binds it separately from the panel) or every row is
text-less and reports the bare 56px tap minimum instead of the 69px three lines
of tier text actually take.

---

## 14. What a leak costs

`Leak.resolve` returns `ceil(life_loss × remaining_health ÷ max_health)`,
floored at one, with a boss's declared `boss_life_loss` bypassing the rule
entirely. It takes no `wave` argument and reads no constant — the cost is a
function of the enemy alone.

**What this replaced, because it is the kind of thing that gets "restored".**
The old rule was a flat per-kind cost through wave 5 and
`min(4, ceil(remaining_health))` after it. Both halves failed. The health term
was unbounded and enemy health compounds every wave, so by wave 20 one leak
ended the run — which is what the cap of 4 was added to stop. The cap then
flattened everything it was meant to bound: from wave 10 on every ordinary
enemy has at least 4 health, so goblin, bat, shaman and ogre all cost exactly
4, `life_loss` was dead data at every wave that mattered, and the run was
always exactly five leaks from over no matter what leaked.

Taking the **ratio** rather than the absolute health gets both properties at
once, because it is bounded above by a table value rather than by one that
grows with the wave. So the cap has nothing left to do.

**Do not add a second clamp.** Clamping the incoming health to `max_health` is
what bounds the whole rule — a `left` no greater than `full` makes the ratio no
greater than 1, which makes the result no greater than the kind's own price. An
explicit ceiling of `life_loss` on the result is unreachable dead code, and
worse than useless, because it masks the clamp that is doing the work. Both
survived mutation testing when both were present; removing one killed both
mutants. This is the standing lesson of §6 arriving in a new place.

**Retuning was measured and rejected.** See `update.md` §1 for the table: per
leak the cost falls about 37%, but the wave a run ends on is unchanged in seven
of eight boards, so `Economy.STARTING_LIVES` stays at 20.

---

## 15. Difficulty, and where enemies die

**Difficulty is a parameter, never a global.** `data/difficulty.gd` holds a pure
tier table; `Waves.get_composition`, `Waves.get_modifiers` and
`Waves.build_schedule` each take a tier defaulting to `Difficulty.NORMAL`, and
`Harness.run_wave` reads it from `config["difficulty"]`. Nothing reads a mutable
singleton, which is what keeps `sim/` pure and keeps the harness's
same-input-same-result guarantee — the property every balance claim here rests
on. An autoload was considered and rejected for exactly that reason.

**Normal is the exact identity transform.** Every measured number in this
project describes Normal, so the whole pre-existing suite doubles as the
regression net: if a Normal multiplier drifts, something else fails.

| Tier | count | interval | health | speed | gold | lives |
|---|---|---|---|---|---|---|
| Normal | 1.00 | 1.00 | 1.00 | 1.00 | 1.00 | 20 |
| Hard | 1.30 | 0.70 | 1.30 | 1.10 | 0.90 | 15 |
| Nightmare | 1.40 | 0.60 | 1.40 | 1.15 | 0.85 | 12 |

Smaller is harsher for `interval_multiplier` and `gold_multiplier`; larger is
harsher for the other three. `test_difficulty.gd` encodes both directions, so a
transposed row fails a test no single-tier check could see.

The levers attack **coverage**, which prior measurement established as the
binding constraint rather than hit points. `interval_multiplier` is the sharpest
of them: halving spawn spacing doubles the crowd one tower must cover without
touching a single enemy stat.

**How the choice travels.** `GameBoard.pending_difficulty` is a static, set by
the main menu and consumed in `_ready` — the same shape and lifetime as
`pending_map`, for the same reason. `GameBoard.active_difficulty()` validates it
through `Difficulty.is_valid`, so an unset or misspelled tier falls back to
Normal rather than crashing a run. It is chosen **per run and not persisted**:
there is no settings file in this project and Slice 3 owns saving.

### The harness knows where enemies died

`Harness.run_wave`'s result carries two fields beyond kills/leaks/lives/gold/
ticks, both fractions of the route from 0.0 to 1.0:

- **`deepest_progress`** — the furthest any enemy got. A leak forces it to 1.0.
- **`progress_at_death`** — the mean over enemies that died; 0.0 when nothing
  died, which is the honest answer rather than a division by zero.

Both derive from `path_index` and cumulative route length, which the harness
already tracks for movement, so there is no second implementation to drift.

**Why they exist.** The owner reported that enemies never reached the first
bend, and nothing in a suite of thirteen thousand assertions could express that:
the old result reported *how many* died, never *where*. With these, The Pass's
first bend — 768px into a 2,448px route, `FIRST_BEND_FRACTION := 0.31` — is a
number a test can check.

It paid for itself immediately. **At Normal, against the full twelve-tower maxed
board, `deepest_progress` never exceeds 0.18 on any of the twenty waves.** Wave
1 reaches 0.02. Nothing has ever reached the bend.

### The benchmark now covers the board the game hands out

`test_balance_tuning.gd` used to benchmark six towers — a board the player
passes *through* on the way to the one they finish with — and its `leaks > 0`
assertion stayed true however easy the game became for a full board. That is the
gap that let a shut-out board read as balanced. The full legal roster now sits
beside it, with the assertion written directionally so it survives retuning: *a
full maxed board must not shut out the hardest tier.*

**Two things to know before touching the tiers.** The full board is a wall and
fails as one — full-board lives lost across a run go 0 → 11 → 46 → 87 → 720 as
the row hardens, so ten points of multiplier is the difference between a scratch
and a wipe. And the benchmark board **loses** Nightmare: leaks from wave 17,
36 lives on wave 20 alone. That is shipped knowingly. The harness has no
projectile travel time, so it is kinder than the live board; these values are a
starting point to be played, not a finished tuning.
