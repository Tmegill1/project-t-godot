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
an assistant picking the project back up). Both are current as of the final
commit and agree with this README: all 23 tasks are complete. `CONTINUE.md`
additionally carries the engine and harness facts that are expensive to
rediscover — read it before changing anything, not after.

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
writing the suite is green at **4039 checks across 25 files**.

A passing run is noisy: it prints roughly fifty `SCRIPT ERROR` lines to
stderr. That is expected and documented at the top of
`test/test_game_board.gd` and in `CONTINUE.md` §3 — most come from `@onready`
resolution being deliberately probed outside a live scene tree. Judge the run
by the summary line and the exit code, not by stderr volume.

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
is 39.5 MB. The game's own data (`index.pck`) is 785 KB raw, 658 KB gzipped;
the Phaser original shipped 368 KB gzipped in total. So the game data is
roughly 1.8× larger, and the engine is ~107× the entire Phaser build. Nothing
you do to the art or audio will move that total meaningfully — it is the price
of shipping an engine to the browser, and it was accepted during design.

> **The web build has never been opened in a browser.** Every check done on it
> so far was mechanical: the expected artefacts exist, the magic bytes are
> right, a local server returns 200 for each, and threads are confirmably off
> in the shipped `index.html`. Whether it *boots and plays* is unverified —
> the port was built by tooling with no browser available. Do this first:

```bash
cd export/web && python3 -m http.server 8000
# open http://localhost:8000 — expect the menu, then place a tower and run wave 1
```

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

## What is deliberately deferred — not a bug, not forgotten

Dropped permanently from this slice, matching the design spec's "Out" list
(§3):

- Upgrade branches and the escalation frames beyond `upgradeFrames[0]`
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
