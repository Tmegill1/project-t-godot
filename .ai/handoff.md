# Claude Handoff

Generated: 2026-08-29 (America/Chicago)

## Repository state

- Repository: `/home/tylermegill/Projects/project-t-godot`
- Branch: `master`
- Local and remote HEAD: `2a1ac6a`
- Live site: `https://tmegill1.github.io/project-t-godot/`
- The Pages deployment for `2a1ac6a` completed successfully.
- `.ai/` is intentionally untracked. Do not commit it unless the owner asks.
- `test/test_balance_tuning.gd.uid` is an untracked Godot-generated UID left by an import pass. Do not add it incidentally.

## Work completed

### Tower limits and balance

Commit: `121bc7f Cap each tower kind at three`

- Every tower kind is capped at 3 on every map: Basic, Magic (`fast` internally), Mortar, and Long Range.
- Every map has a 12-tower total budget, matching the reachable total of three per kind.
- Added `test/test_balance_tuning.gd` as a permanent late-game benchmark.
- Six fully committed mixed towers were measured on The Pass:
  - waves 1-15: zero leaks
  - wave 18: 19 leaks and 21 lives lost
  - wave 20: 31 leaks and 44 lives lost
- Enemy health/count/spawn tuning was deliberately left unchanged because wave 18 already met the owner's requested leak threshold. The opening remains approachable while the late game requires more coverage and upgrades.

### Themed projectiles and firing sounds

Commit: `2a1ac6a Give each tower a themed projectile`

- Replaced the generic 6x6 white `ColorRect` projectile with a `Sprite2D`.
- Added four transparent 32x32 pixel-art sprites under `assets/art/projectiles/`:
  - `basic.png`: blue-steel cannon bolt
  - `fast.png`: cyan crystal / arcane shot
  - `mortar.png`: dark iron shell with ember fuse
  - `long.png`: orange-gold piercing round
- `GameBoard` passes `tower.kind` into `Projectile.launch()`.
- `Projectile` loads the matching texture, points the sprite along its flight direction, and preserves the mortar's screen-upward arc.
- Replaced all four `assets/audio/fire-*.ogg` clips with distinct original synthesized effects: mechanical snap, crystalline zap, artillery thump, and piercing crack.
- Added projectile mapping and runtime texture-selection coverage in `test/test_projectile.gd`.

## Verification

- Full suite after the projectile/audio work: 13,436 checks across 42 files, with zero failing assertions, load errors, or aborted tests.
- A release Web export completed successfully.
- The deployed `index.pck` was downloaded and inspected; it contains all four projectile assets and the new projectile scene/code.

## Browser cache diagnosis

The owner initially still saw white squares in the live game. The main-menu build label showed `121bc7f`, proving the browser was running the previous cached pack rather than the deployed `2a1ac6a` build.

If this is reported again:

1. Check the lower-left build label first.
2. The correct projectile build is `2a1ac6a`.
3. If it shows `121bc7f`, close all game tabs and reopen the site in a private/incognito window, or clear site data/cache for `tmegill1.github.io`.
4. Do not retune or rewrite projectile code based on a stale build.

## Asset coordination rule — owner instruction

**If any new visual, audio, animation, sprite, texture, icon, or other game asset appears necessary, stop and talk with Codex first. Do not generate, source, replace, or commission new assets independently. Ask the owner to return to Codex so the asset can be discussed and created there before continuing.**

Existing assets may be wired, debugged, and tested normally. The pause applies when the work would require a new asset or a replacement asset not already approved above.

## Guidance for continuing

- Read `update.md` and `CONTINUE.md` before selecting the next task.
- Preserve the two commits above; both are pushed to `origin/master` and deployed.
- Diagnose live reports against the build stamp before changing code.
- Keep live rules and `sim/harness.gd` behavior aligned; balance claims should remain reproducible tests.
- Run `godot --headless --script test/run_tests.gd` before claiming completion.
