# Progress

Live status of the Godot port. Updated as tasks complete.

**Project location on this machine:** `~/Projects/project-t-godot`
**Branch:** `feat/core-slice`
**Engine:** Godot 4.7.1.stable

---

## What this is

A port of [Tmegill1/project-t](https://github.com/Tmegill1/project-t) — the Phaser
tower-defence game — to Godot 4.7 in GDScript.

This first pass covers the **core slice**, not the whole game: one map, four
towers, three enemies, twenty waves, win and lose. The upgrade branches, enemy
properties, bosses, powers, currencies and meta-progression are deliberately
deferred so there is something playable in the middle rather than at the end.

Full reasoning lives in:
- [`docs/superpowers/specs/2026-08-09-godot-port-design.md`](docs/superpowers/specs/2026-08-09-godot-port-design.md) — the design and why
- [`docs/superpowers/plans/2026-08-09-godot-core-slice.md`](docs/superpowers/plans/2026-08-09-godot-core-slice.md) — the 23-task implementation plan

---

## How to run it

Nothing is playable yet — the first playable build arrives at Task 21.

```bash
cd ~/Projects/project-t-godot

# Run the test suite (works now)
godot --headless --quit --script test/run_tests.gd

# Open in the editor
godot --path .
```

---

## Task status

| # | Task | Status |
|---|---|---|
| 1 | Project scaffold and test harness | ✅ |
| 2 | Seeded RNG | ✅ |
| 3 | Tiles and grid conversion | 🔧 |
| 4 | Map generation | ⬜ |
| 5 | Pathfinding | ⬜ |
| 6 | Enemy, tower, economy, map data tables | ⬜ |
| 7 | Wave composition and scaling | ⬜ |
| 8 | Movement | ⬜ |
| 9 | Damage resolution | ⬜ |
| 10 | Leak penalty | ⬜ |
| 11 | Targeting | ⬜ |
| 12 | Economy arithmetic | ⬜ |
| 13 | Purity guard | ⬜ |
| 14 | Headless wave harness | ⬜ ← **checkpoint: rules layer complete** |
| 15 | Asset import and atlas extraction | ⬜ |
| 16 | Map renderer | ⬜ |
| 17 | Enemy view | ⬜ |
| 18 | Tower and projectile views | ⬜ |
| 19 | Game board | ⬜ |
| 20 | HUD and tower panel | ⬜ |
| 21 | Scene flow and main scene | ⬜ ← **first playable** |
| 22 | Audio | ⬜ |
| 23 | Web export and README | ⬜ |

Legend: ⬜ not started · 🔧 in progress · ✅ done

---

## Log

### Task 1 — scaffold and test harness

**Commit `2aa4a8d`.** Created `project.godot` (Compatibility renderer, 1104×672,
`canvas_items`/`expand` stretch), a dependency-free headless test runner, and the
`TestCase` assertion base.

gdUnit4 was dropped in favour of a hand-rolled runner. Godot 4.7 is new enough
that betting the whole suite on addon compatibility is a risk worth avoiding, and
the runner is about 60 lines.

**Review found two Critical defects in that runner**, both verified by injecting
probe files rather than by reading:

- A test that hits a runtime error mid-run reports **green and exits 0**. Godot's
  script-error recovery lets the loop continue past the crash, so the test
  contributes zero checks and no failure line — it simply vanishes.
- A test file with a syntax error is **silently skipped entirely**, again exiting
  0. One typo in any later task's tests would delete that file's whole coverage
  with no signal.

Both are fixed (commit `899b0cf`), along with two lesser issues: discovery was
case-sensitive, and a suite that discovered *zero* tests also exited 0 —
indistinguishable from a green run.

Two corrections came out of this that were worth more than the fix itself:

- The guidance given to the implementer said `load()` returns `null` on a parse
  error. On Godot 4.7.1 it does not — it returns a `GDScript` whose
  `can_instantiate()` is `false`. The implementer checked rather than complied,
  and the reviewer independently confirmed it. Following the hint would have
  produced a null check that never fires.
- The implementer then reported that one gap — a test that passes assertions and
  *then* crashes — was permanently unfixable in GDScript. Review **refuted** that
  empirically: when GDScript aborts a function mid-run it returns the declared
  return type's default, so `func test_x() -> bool: ...; return true` reads as
  `false` when the test dies partway.

**Test-authoring contract, binding on every later task:** every `test_*` method is
declared `-> bool` and ends with `return true`. It is self-enforcing — a method
that forgets returns `null` instead of `true` and fails loudly.

---

## Decisions worth knowing

- **Combat uses distance maths, never physics.** Targeting and hit detection live
  in `sim/`, not in `Area2D` overlaps, so the rules stay deterministic and can be
  tested with no engine running. `Area2D` is used only for tapping a tower.
- **`sim/` and `data/` may not touch the engine.** No `Node`, no `get_tree()`, no
  `preload`. A test enforces this, and that test's detector is itself tested so it
  cannot pass vacuously.
- **The sim thinks in milliseconds.** Godot hands you seconds; callers convert.
  This keeps `fire_rate: 1000` and every ported test transferable unchanged.
- **The RNG is bit-exact with the JavaScript original.** mulberry32 depends on
  32-bit overflow semantics that GDScript's 64-bit ints do not share natively.
  The port was verified identical to 17 decimal places and the values are pinned
  in a test — if it ever drifts, every generated map silently changes.
- **Balance is ported, not fixed.** The Phaser original's own handoff notes say
  every number is an unplaytested placeholder. "Matches Phaser" does not mean
  "plays well".
