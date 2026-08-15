# project-t-godot

A GDScript port of [Tmegill1/project-t](https://github.com/Tmegill1/project-t)
— a Phaser 3 tower-defence game — to **Godot 4.7.1**.

This is the **core slice**: one map, four towers, three enemies, twenty waves,
win and lose. It is not the whole game. The Phaser original is ~18k lines
across four completed phases (upgrade branches, composable enemy properties,
bosses, three currencies, tactical powers, meta-progression, a versioned save)
plus a headless simulation harness backed by 615 tests. Porting all of that in
one pass had no playable milestone in the middle, so this pass stops at the
end of the Phaser project's own Phase 0, plus a fourth tower. Later phases, if
they happen, layer on the same way they did in Phaser, each behind its own
design spec.

The full reasoning — including the three architecture options considered and
why this one was chosen — lives in:

- [`docs/superpowers/specs/2026-08-09-godot-port-design.md`](docs/superpowers/specs/2026-08-09-godot-port-design.md) — the design and why
- [`docs/superpowers/plans/2026-08-09-godot-core-slice.md`](docs/superpowers/plans/2026-08-09-godot-core-slice.md) — the 23-task implementation plan

For narrative history of how the port was built task by task, see
[`PROGRESS.md`](PROGRESS.md) (task log and decision log) and
[`CONTINUE.md`](CONTINUE.md) (single-file resume/orientation doc, written for
an assistant picking the project back up). Both are current and agree with this
README: all 23 tasks are complete. `CONTINUE.md` additionally carries the engine
and harness facts that are expensive to rediscover — including the stretch/aspect
model behind the layout section below — so read it before changing anything, not
after.

---

## Setup: one thing you must do after cloning

```bash
git clone <this-repo>
cd project-t-godot
godot --headless --import
```

Run the import **once** before anything else. Godot resolves `class_name`
identifiers from a project-wide cache that only gets built by an import pass.
Skip this step and you will hit a parse error that gives no hint as to the
real cause:

```
Identifier "Grid" not declared in the current scope.
```

You do not need to re-run `--import` for ordinary edits — only after a fresh
clone, or if you introduce a brand-new `class_name`.

---

## How to run it

```bash
# Play it (opens the editor's running window at the main menu)
godot --path .
```

Main menu → place towers on The Pass → defend twenty waves → win at wave 20 or
lose at zero lives → retry or return to the menu.

## How to test

```bash
godot --headless --quit --script test/run_tests.gd
```

A hand-rolled runner, not an addon — Godot 4.7 was new enough at the time this
was built that betting the whole suite on third-party addon compatibility was
a risk worth avoiding. Exit code 0 means pass, 1 means fail. As of this
writing the suite is green at **4589 checks across 29 files**.

A passing run is noisy: it prints around 118 `SCRIPT ERROR` lines to stderr.
That is expected and documented at the top of `test/test_game_board.gd` and in
`CONTINUE.md` §3 — nearly all come from `@onready` resolution being
deliberately probed outside a live scene tree. Judge the run by the summary
line and the exit code, not by stderr volume. *New* noise is a defect, and has
been: the bug where pressing an upgrade row failed to refresh the panel was
found by reading these lines, not by a failing test.

## How to export (Web)

```bash
mkdir -p export/web
godot --headless --export-release "Web" export/web/index.html
```

The `Web` preset in `export_presets.cfg` sets `variant/thread_support=false`.
Godot's web export needs `SharedArrayBuffer`, which browsers only expose to a
cross-origin-isolated page — that requires the host to send `COOP`/`COEP`
response headers, which most static hosts (GitHub Pages, a plain S3 bucket,
etc.) do not send. Disabling threads avoids that hosting requirement entirely
at the cost of running single-threaded, which this game does not need.

The exclude filter on the preset (`reference/*, test/*, tools/*`) keeps the
checked-out Phaser reference repo, the test suite, and the dev-only atlas
tool out of the shipped build — none of them are needed at runtime, and
`reference/` in particular is a full second git checkout that has no business
in a browser bundle.

`export/` is gitignored; export output is never committed.

The build is about **40 MB**, of which `index.wasm` — the Godot engine itself —
is 39.5 MB. The game's own data (`index.pck`) is 790 KB raw, 666 KB gzipped;
the Phaser original shipped 368 KB gzipped in total. So the game data is
roughly 1.8× larger, and the engine is ~107× the entire Phaser build. Nothing
you do to the art or audio will move that total meaningfully — it is the price
of shipping an engine to the browser, and it was accepted during design.

> **The web build boots and renders** — first confirmed in Firefox on
> 2026-08-14, which until then had never been done. The wasm compiles, the
> `.pck` loads, the main menu draws, and past it the play field renders: map,
> HUD and build panel. **What is still unverified is that it *plays*.**
> Placing a tower and running a wave have been exercised headlessly and in the
> desktop build, but never through the browser. Do that next:

```bash
python3 -m http.server 8000 --directory export/web
# open http://localhost:8000 — menu, then place a tower and run wave 1
```

---

## How the layout responds to window size

`project.godot` declares a **1244×672** design viewport with
`window/stretch/mode="canvas_items"` and `window/stretch/aspect="expand"`.
Under `expand` the scale factor is `min(window.x / 1244, window.y / 672)` and
the viewport absorbs whatever the window has spare on the other axis. So a
window *wider* in aspect than 1244:672 grows the viewport's **width** while its
height stays exactly 672; a *narrower* one grows its **height** while width
stays exactly 1244. Viewport width therefore never drops below 1244.

The map is a fixed **1104×672** (23×14 tiles at 48px) anchored at the origin,
leaving exactly 140px for the build panel at the design ratio — the two tile
edge to edge with nothing between them. Every pixel `expand` adds beyond that
has to be claimed by something, or it shows through as bare engine background:

- **The build panel claims the surplus.** `TowerPanel` anchors its left edge to
  the map's right edge — `Maps.pixel_size(board.get_map_name()).x`, set in
  `bind()` rather than hardcoded, so a later map of different dimensions still
  lines up — and its other three sides to the viewport. It is 140px wide at the
  design ratio, wider on a wider screen, and never narrower. It spans the full
  viewport height so no bare strip is left beside the map's top rows; the 52px
  clearance for the HUD bar lives on its `Buttons` container instead.
- **The HUD bar is inset** 12px from both viewport edges (`Hud.EDGE_INSET`), so
  its first and last children do not sit flush against the screen border with
  the tilemap showing through behind them.

**Scaling the map up to fill the space instead does not work.** It already
fills the viewport height exactly, and on a wide window `expand` adds width
only — so there is zero vertical headroom. Any uniform upscale crops the bottom
rows, and a width-only stretch distorts the tiles.

---

## Why `sim/` and `data/` cannot touch the engine

`sim/` (rules — movement, damage, targeting, leaks, economy, pathfinding, RNG)
and `data/` (balance tables — towers, enemies, waves, maps, economy constants)
are **pure GDScript with zero engine references**: no `Node`, no
`get_tree()`, no `preload`, no `@onready`, no scene types, no `Time.` /
`Engine.` / `OS.`. `test/test_sim_purity.gd` scans both directories for those
symbols and fails the suite on a hit; its own detector is unit-tested against
known-positive and known-negative samples so it cannot pass vacuously.

This exists so the rules stay **deterministic and headlessly testable** —
`sim/harness.gd` can simulate a full wave (pathing, targeting, damage,
splash, leaks) with no window open and no frame rendered, in the same process
that runs the rest of the test suite. That property is worth protecting
because it is what turns a balance claim ("wave 12 is beatable with two Fast
towers") into something a test asserts rather than something a person plays
out by hand. Everything above that line — `game/`, `ui/`, `audio/` — is
ordinary Godot: nodes, scenes, signals, `@onready`, the render tree.

One consequence that follows directly: **combat is never physics**.
Targeting and hit detection are distance arithmetic in `sim/targeting.gd` and
`sim/damage.gd`, not `Area2D` overlap callbacks. Godot's physics is
frame-coupled and non-deterministic across runs; routing combat through it
would put rules in the engine and make the headless harness impossible.
`Area2D` is used for exactly one thing in this codebase: picking a tower with
a tap.

---

## What the core slice contains

One map (`demoMap`, "The Pass," 23×14 at 48px tiles, seeded generation), BFS
pathing spawn→goal, four towers (Basic, Fast, Mortar, Long Range) with cost
escalation and per-kind limits, three enemies (Slime, Ogre, Bee), twenty
waves with accumulate-from-wave-1 composition and per-wave scaling, an
economy (100 starting gold, 20 lives, kill rewards, 50% sell refund), flat
projectiles and Mortar splash, a capped leak penalty, tap-to-place input with
affordability/occupancy checks and range preview, the win/lose flow, and
pooled audio for the events the slice can fire.

## Tower upgrades

Every tower carries two branches of four tiers each, ported from the
reference's table verbatim: Basic (Barrage / Marksman), Fast (Suppression /
Bounty Hunter), Mortar (Saturation / Demolition) and Long Range (Bombardment /
Siege). Tiers cost from 30–60 gold up to 260–500, and a tower's sell refund is
half of everything sunk into it, placement included.

**The cross-path rule is the point.** A branch may pass tier 2 only while the
other sits at tier 2 or below, so a tower is a commitment rather than a
checklist — the second branch reads `locked` in the inspector once the first
commits. A tower's sprite advances through the four frames its table already
carried, driven by *total* investment across both branches (`ceil(total / 2)`,
capped): the look changes at 1, 3 and 5 tiers, not at every purchase.

Two mechanics were built for the tiers that need them. **Slowing** (`sim/slow.gd`)
is Fast's branch identity: strongest factor wins, the longer timer wins, and
expiry restores full speed. **Gold per kill** (`EconomySim.kill_reward`) pays a
kill through the gold effects of the tower that actually made it, splash kills
included. **Pierce and detection are wired but dormant** — `Damage.resolve` and
`Targeting` already implement them, and they start biting the day armoured and
phased enemies land, with no further work.

Stats are resolved in one place, `UpgradesSim.resolve_tower_stats`, which both
the live game and `sim/harness.gd` call. A build tested headlessly is therefore
the build the player gets:

```gdscript
Harness.run_wave({"wave": 20, "path": path, "towers": [
    {"kind": &"fast", "position": pos, "tiers": {&"sustained": 4, &"burst": 0}},
]})
```

## What is deliberately deferred — not a bug, not forgotten

Dropped permanently from this slice, matching the design spec's "Out" list
(§3):

- The five composable enemy properties (`Waves.propertiesFor` is not ported)
- Boss archetypes and lieutenants
- Tactical powers and command upgrades
- Insignia, seals, and the meta shop/passives
- Save and meta-progression
- Currencies beyond gold
- Maps 2 and 3 (The Fork, The Coils) — the map registry is built to hold three
  from the start; adding the other two later is data entry against a working
  renderer, not new architecture
- Call-wave-early, wave-clear bonus, and interest
- Auth and leaderboards — dropped rather than deferred. The Cloudflare Worker
  in the Phaser project exists mainly to serve a leaderboard that does not
  exist yet, and a login wall in front of a browser tower defence is friction
  with nothing behind it.

The spec also lists what is intentionally *not* reproduced even though it
exists in the Phaser build: a leak event that hops across two scenes' event
emitters, wave-completion detected in two redundant places, an enemy counter
that counts spawns rather than survivors, a debug hotkey, and money/lives
living as private UI-scene fields. None of those are bugs to fix in the
port — they are Phaser-specific accidents of that codebase's structure that
this one's single node tree with signals does not have in the first place.

---

## A gotcha specific to developing this with the Godot MCP

Running the game through the Godot MCP's `run_project` tool injects an
`[autoload] McpInteractionServer` entry into `project.godot`, and leaves an
empty `[autoload]` section behind when the game stops — local debug tooling
that has no business being committed. Before every commit made after running
the game through the MCP:

```bash
git diff project.godot
```

`AudioManager` (`res://audio/audio_manager.gd`) should be the only entry
under `[autoload]`. Strip anything else before committing. The MCP's own
`mcp_interaction_server.gd` file is already gitignored, but the
`project.godot` edit is not caught by any ignore rule and has to be checked
by hand.

---

## Balance is ported, not fixed

Every number in `data/` is carried over from the Phaser original as-is. That
project's own handoff notes are explicit that none of it was ever
playtested — every value is a placeholder. "Matches Phaser" is a statement
about porting fidelity, not about whether the game plays well. `sim/harness.gd`
exists to make tuning that later a matter of editing a table and re-running a
headless simulation, not re-deriving the rules from scratch.
