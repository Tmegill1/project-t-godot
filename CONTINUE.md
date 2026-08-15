# CONTINUE HERE

**Point an assistant at this file and say "continue this project."** It contains
everything needed to resume with no prior conversation.

Last updated: 2026-08-14 · Branch `master` · **core slice complete and merged;
tower upgrades specced and planned, not started**

> **Starting the next piece of work?** Go straight to
> [`docs/superpowers/plans/2026-08-14-tower-upgrades.md`](docs/superpowers/plans/2026-08-14-tower-upgrades.md).
> It is a complete eleven-task implementation plan with the code for every
> task, and its design rationale is in
> [`docs/superpowers/specs/2026-08-14-tower-upgrades-design.md`](docs/superpowers/specs/2026-08-14-tower-upgrades-design.md).
> Read §5 and §6 of this file first — the engine facts and the standing rules
> apply to that plan too. See §4 for the one open decision inside it.

> This file is the *orientation* document: state, how to run things, and the
> hard-won facts that are expensive to rediscover. The per-task status table and
> the decision log live in [`PROGRESS.md`](PROGRESS.md) and are **not** duplicated
> here — read that too, and trust it over this file for task-by-task status.

---

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

**All 23 tasks complete. The game is playable end to end** — main menu → game →
win or lose → retry or menu, with sound.

| Layer | State |
|---|---|
| `sim/` — 9 modules | ✅ complete, reviewed |
| `data/` — 8 modules | ✅ complete, reviewed |
| `assets/` — 61 files | ✅ imported, sliced, verified visually |
| `game/` — board, enemy, tower, projectile, map renderer | ✅ complete |
| `ui/` — menu, HUD, build panel, game-over, victory | ✅ complete |
| `audio/` — pooled playback, 17 core-slice events | ✅ complete |
| Web export | ✅ preset + build; **boots and renders in a browser; not yet played in one** |
| Deploy | ✅ live at **https://tmegill1.github.io/project-t-godot/** — every push to `master` republishes |
| Tests | ✅ 4054 checks across 25 files, exit 0 |
| Tower upgrades | 📋 specced and planned, **not started** — see §4 |

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

A passing suite prints **54 `SCRIPT ERROR` lines** to stderr. All are expected:

- **3** from `test/test_harness_selfcheck.gd`, which crashes deliberately on
  purpose to prove the runner's crash sentinel works.
- **51** from `Tower.setup` / `Tower.set_range_visible` / `Enemy.setup` aborting on
  unresolved `@onready` in nodes the *board* instantiated (see §5 — the board's own
  `add_child()` does not deliver `NOTIFICATION_READY` in a frameless test either).
  Documented at the top of `test/test_game_board.gd`.

Judge the run by the **summary line and the exit code**, never by stderr volume.
`FAIL` lines and the counters in the summary are the signal. *New* noise is a
defect; this noise is not.

---

## 4. What is left

The 23-task plan is finished. What remains is not implementation:

**1. Play the web build in a browser.** It has been *opened* in one now — it
boots, the menu draws and the play field renders — but no click has ever been
put through it. Placing a tower, starting a wave and hearing it fire are all
still unverified in the browser specifically.

```bash
godot --headless --export-release "Web" export/web/index.html
python3 -m http.server 8000 --directory export/web   # then open http://localhost:8000
```

Expect the menu, then a run: place a tower, start wave 1, hear it fire. Audio needs
a user gesture in browsers — the menu's Play button supplies it, so no explicit
unlock call exists or is needed.

Worth knowing if you are driving this from an agent: the boot sequence is legible
in the server's own access log. `index.html` → `index.js` → `index.wasm` →
`index.pck` is just the download, but the two `index.audio*.worklet.js` requests
that follow are made by the engine *at runtime*, after the wasm has instantiated
and the pack has been read — so seeing them is decent evidence the engine started,
short of seeing a pixel.

**2. Build tower upgrades — this is the next real piece of work.** The design
and the plan are both written, reviewed and merged; nothing has been
implemented.

- Spec: [`docs/superpowers/specs/2026-08-14-tower-upgrades-design.md`](docs/superpowers/specs/2026-08-14-tower-upgrades-design.md)
- Plan: [`docs/superpowers/plans/2026-08-14-tower-upgrades.md`](docs/superpowers/plans/2026-08-14-tower-upgrades.md)

Two branches per tower, four tiers each, and a cross-path rule that lets only
one branch pass tier 2. It also builds the two mechanics those tiers need and
the core slice never had — slowing and gold-per-kill. Pierce and detection are
wired but dormant: their machinery already exists in `Damage.resolve` and
`Targeting`, and only lacks armoured and phased enemies to bite on.

**Progress: 1 of 11 tasks complete.** Task 1 (the 32-tier data table) landed in
`40942a9`; suite green at 4224 checks. Resume at **Task 2** — tier legality,
cost and investment in `sim/upgrades.gd`. The live ledger, with every ruling
and deferred minor, is at
`.superpowers/sdd/2026-08-14-tower-upgrades/progress.md` (git-ignored) — trust
it and `git log` over any summary, including this line.

Each task leads with a failing test and ends with a mutation-test step;
dispatch a fresh subagent per task, as §8 explains.

**One open decision inside that plan.** Long Range's `Tungsten Core` tier is
pierce-only in the reference, so it would be 260 gold for no effect until
armoured enemies exist — and it is the mandatory step to the tier behind it.
The plan gives it an interim `damage_multiplier` of 1.3 and a "(no effect yet)"
note, pinned by its own test so the divergence is deliberate. Reverse it if you
would rather it stayed faithful and inert; nothing else depends on it.

**3. The branch is merged.** The whole-branch review and its fix wave were
completed and verified, and `feat/core-slice` is in `master`. Nothing to do.

**4. Decide the open art question in §9** — the squashed stone tiles.

**5. Playtest and tune.** Nothing here has been balanced. See §9.

Note for whoever touches `project.godot`: the `[autoload]` entry for `AudioManager`
is *legitimate*. §5's strip-before-commit warning is about the Godot MCP's
`McpInteractionServer` entry only — do not let the habit delete the real one.

---

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
- **A screenshot is the only way to catch a layout regression here.** The test
  harness never puts nodes in a live tree, so containers never lay out and every
  child's computed rect stays at its unlaid-out default. Layout tests therefore
  assert *anchors and offsets*, not positions (`test_hud.gd`,
  `test_tower_panel.gd`). One trap that follows: a property set as an **instance
  override** in a composing scene is invisible to a test that instantiates the
  sub-scene alone — `TowerPanel`'s vertical placement lived in `game.tscn`, so the
  standalone test read the panel's own value and passed regardless. Assert on the
  composed scene when the value being pinned lives on the instance.
- **Running the game through the Godot MCP rewrites `project.godot`.** It injects an
  `[autoload] McpInteractionServer` entry, and leaves an empty `[autoload]` section
  behind on stop. That is local debug tooling — committing it breaks the project for
  anyone without the MCP. **`git diff project.godot` and strip it before every
  commit made after running the game.**

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

1. **The map tiles now look better than the original.** 5 of 8 rects were corrected
   for clipping and bleed. The spec says the original's visual quirks are preserved
   deliberately, so this is a real divergence. Every deviation is documented in a
   header block in `tools/slice_atlas.gd` with reference/used/reason — any rect is
   one edit from exact parity. **Decide whether you want parity or the better art.**
2. **`map_renderer` scales decoration per-axis**, which squeezes the stone tile
   ~2.2×. Left alone pending decision 1; it is the same call.
3. **The balance is unplaytested.** The original's own handoff notes say every
   number is a placeholder. "Matches Phaser" will not mean "plays well." Tune with
   the harness, which is exactly what it is for.
4. **Web export is 40.6 MB** — measured, not predicted; the design anticipated
   25–40 MB. 39.5 MB of that is `index.wasm`, the Godot engine binary. The
   game's own `index.pck` is 790 KB raw / 666 KB gzipped, against the Phaser
   build's 368 KB gzipped — so the game data itself is roughly 1.8× larger, but
   that difference is noise beside the engine. Trimming art or audio cannot
   meaningfully move the total; only a different engine would.

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
- `game/game_board.gd` is ~250 lines and owns state, spawn scheduling, tower
  ticking, hit resolution, input and placement. Not urgent; worth splitting if it
  grows again.

---

## 11. Suggested next action

```bash
cd ~/Projects/project-t-godot
git checkout master
godot --headless --import                            # once, after a fresh clone
godot --headless --quit --script test/run_tests.gd   # expect 4054 checks, exit 0
godot --path .                                       # and actually play a run
```

Then pick one of two things.

**To build the next feature**, open
[`docs/superpowers/plans/2026-08-14-tower-upgrades.md`](docs/superpowers/plans/2026-08-14-tower-upgrades.md)
and start at Task 1. That plan is self-contained: every task carries its own
tests and code, and §4 above names the one decision left open inside it.

**To close the last verification gap**, play the deployed build at
https://tmegill1.github.io/project-t-godot/ — place a tower, run a wave, hear
it fire. It is confirmed to boot and render in a browser; nobody has yet put a
click through it. That takes two minutes and needs a human, because it cannot
be automated on this setup.

Play a full run before changing any number. The balance has never been playtested
and every value came across from a prototype whose own notes call them
placeholders; `sim/harness.gd` can simulate whole waves headlessly, so tuning does
not mean sitting through twenty of them.
