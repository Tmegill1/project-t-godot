# Audio Controls and Enemy Run Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The player can mute the game and set its volume from the HUD, and enemies read as running rather than sliding.

**Architecture:** `AudioManager` already owns a `_muted` flag with a setter nothing calls, and no volume concept at all. It gains a linear volume applied to the master bus, and the HUD gains the two controls that drive both — matching the existing `SpeedButton` pattern rather than introducing a settings screen. Separately, `Enemy`'s motion stops being a fixed-frequency 2px bob and becomes a stride cycle driven by **distance travelled**, so it speeds up with the enemy, slows when the enemy is slowed, and stops when it stops.

**Tech Stack:** Godot 4.7.1.stable, GDScript, the project's own `TestCase`/`run_tests.gd` harness.

**Why there is no spec:** both items are bounded changes to flows that already exist — an autoload with an unwired setter, and a `_physics_process` that already synthesises motion. The design decisions each task makes are stated in the task.

## Global Constraints

- Godot 4.7.1.stable. Run the suite with `godot --headless --quit --script test/run_tests.gd` from the repo root.
- Every task ends on a green suite. Baseline at the start of this plan: **7157 checks across 37 files, 0 failing**.
- A green run in this project is deliberately noisy — it emits `push_error` from refusal paths under test. Judge pass/fail from the final summary line, not stderr.
- Every `test_*` method MUST be declared `-> bool` and end with `return true`. Every early `return` inside one must also `return true`. A test recording zero assertions fails the run.
- Prefer flat `test_*` bodies; where a helper is unavoidable, assert on its result.
- `data/` and `sim/` must contain no engine calls; `test/test_sim_purity.gd` enforces this recursively. Anything that needs `load()` or `AudioServer` belongs in `game/`, `ui/` or `audio/`.
- **The test harness never enters the scene tree.** `test/test_enemy.gd`'s header explains why at length. Anything that needs a live tree needs a guard, as `Enemy._die` already has.
- No asset file changes in this plan. Do not run the bake tool.
- `sim/` is out of scope for both tasks. Enemy movement arithmetic lives in `sim/movement.gd` and does not change; only how the view draws it does.

---

### Task 1: Mute and volume in the HUD

**Files:**
- Modify: `audio/audio_manager.gd`
- Modify: `ui/hud.tscn`
- Modify: `ui/hud.gd`
- Test: `test/test_audio_manager.gd`
- Test: `test/test_hud.gd`

**Interfaces:**
- Produces: `AudioManager.set_volume(linear: float)`, `AudioManager.get_volume() -> float`, `AudioManager.is_muted() -> bool`, `Hud.mute_button() -> Button`, `Hud.volume_slider() -> HSlider`.
- Consumes: `AudioManager.set_muted`, which exists today and has never had a production caller.

**`set_muted` already exists and is already tested** — `test/test_audio_manager.gd` covers it at both settings. What has never existed is anything that calls it. Do not reimplement the flag; wire it.

**Volume applies to the master bus, not to each player.** `AudioManager` pools twelve `AudioStreamPlayer`s and rotates through them, so setting a volume per player would leave already-playing sounds at the old level and would need re-applying on every `play()`. `AudioServer.set_bus_volume_db(0, linear_to_db(v))` moves everything at once, including sounds mid-playback.

**Volume is stored linear and converted at the edge.** `linear_to_db(0.0)` is `-inf`, which is correct for silence but cannot round-trip, so `get_volume` returns the stored linear value rather than reading the bus back.

**Mute and volume are independent.** Muting does not zero the volume and unmuting does not restore a remembered one — `_muted` short-circuits `play()` and the bus keeps whatever level the slider last set. A player who mutes, moves the slider, then unmutes gets the level they chose while muted.

**The controls go in the existing top bar**, beside `SpeedButton`, because that is where every other always-available control already lives and the sidebar is 140px wide and cannot take a slider.

- [ ] **Step 1: Write the failing tests**

Add to `test/test_audio_manager.gd`:

```gdscript
func test_volume_round_trips_as_the_linear_value_that_was_set() -> bool:
	# Stored linear rather than read back from the bus: linear_to_db(0.0) is
	# -inf, so silence cannot survive a round trip through decibels.
	var mgr := _manager()
	mgr.set_volume(0.5)
	assert_almost_eq(mgr.get_volume(), 0.5, 0.0001, "half volume round-trips")
	mgr.set_volume(0.0)
	assert_almost_eq(mgr.get_volume(), 0.0, 0.0001, "silence round-trips")
	mgr.set_volume(1.0)
	assert_almost_eq(mgr.get_volume(), 1.0, 0.0001, "full volume round-trips")
	mgr.free()
	return true

func test_volume_is_clamped_to_the_range_a_slider_can_produce() -> bool:
	var mgr := _manager()
	mgr.set_volume(-3.0)
	assert_almost_eq(mgr.get_volume(), 0.0, 0.0001, "below zero clamps to silence")
	mgr.set_volume(9.0)
	assert_almost_eq(mgr.get_volume(), 1.0, 0.0001, "above one clamps to full")
	mgr.free()
	return true

func test_volume_reaches_the_master_bus() -> bool:
	# The pool rotates through twelve players, so a per-player volume would
	# leave a sound already playing at the old level. The bus moves all of
	# them, mid-playback included.
	var mgr := _manager()
	var before := AudioServer.get_bus_volume_db(0)
	mgr.set_volume(0.25)
	var quiet := AudioServer.get_bus_volume_db(0)
	mgr.set_volume(1.0)
	var loud := AudioServer.get_bus_volume_db(0)
	assert_true(quiet < loud, "a lower linear volume is a lower bus level (%f vs %f)" % [quiet, loud])
	assert_almost_eq(loud, 0.0, 0.001, "full volume is unity gain on the bus")
	AudioServer.set_bus_volume_db(0, before)
	mgr.free()
	return true

func test_muting_does_not_disturb_the_volume() -> bool:
	# Two independent controls. A player who mutes, moves the slider, then
	# unmutes must get the level they chose while muted.
	var mgr := _manager()
	mgr.set_volume(0.4)
	mgr.set_muted(true)
	assert_almost_eq(mgr.get_volume(), 0.4, 0.0001, "muting leaves the volume alone")
	mgr.set_volume(0.8)
	mgr.set_muted(false)
	assert_almost_eq(mgr.get_volume(), 0.8, 0.0001, "the level chosen while muted survives unmuting")
	assert_false(mgr.is_muted(), "and the mute is off")
	mgr.free()
	return true
```

`_manager()` is a helper this file needs if it does not already have one: build a bare `AudioManager` the way the existing mute tests do, without entering the tree. Read the file's header before writing it — it documents at length why a live autoload cannot be used here.

Add to `test/test_hud.gd`:

```gdscript
func test_the_mute_button_reports_and_toggles_the_muted_state() -> bool:
	var h := _ready_hud()
	var mgr := _audio_manager_for(h)
	mgr.set_muted(false)
	h.refresh_audio_controls()
	assert_eq(h.mute_button().text, "Sound on", "the button names the state it is in")

	h.mute_button().emit_signal("pressed")
	assert_true(mgr.is_muted(), "pressing it mutes")
	assert_eq(h.mute_button().text, "Sound off", "and the label follows")

	h.mute_button().emit_signal("pressed")
	assert_false(mgr.is_muted(), "pressing it again unmutes")
	h.free()
	return true

func test_the_volume_slider_drives_the_audio_manager() -> bool:
	var h := _ready_hud()
	var mgr := _audio_manager_for(h)
	var s := h.volume_slider()
	assert_almost_eq(s.min_value, 0.0, 0.0001, "the slider bottoms out at silence")
	assert_almost_eq(s.max_value, 1.0, 0.0001, "and tops out at full")

	s.value = 0.3
	s.emit_signal("value_changed", 0.3)
	assert_almost_eq(mgr.get_volume(), 0.3, 0.0001, "moving the slider sets the volume")
	h.free()
	return true

func test_the_volume_slider_shows_the_volume_already_set() -> bool:
	# The HUD is built after the AudioManager exists, so it must read the
	# current level rather than assume a default and silently reset it.
	var h := _ready_hud()
	var mgr := _audio_manager_for(h)
	mgr.set_volume(0.6)
	h.refresh_audio_controls()
	assert_almost_eq(h.volume_slider().value, 0.6, 0.0001, "the slider starts where the volume is")
	h.free()
	return true
```

`_audio_manager_for(hud)` is a helper: the HUD reaches the manager the same way `GameBoard._play_sound` does — by looking it up on the tree root by name — so the test needs to put one there, or the HUD needs a seam. **Read `game/game_board.gd:414-441` before choosing**; it documents why the lookup is by absolute path and what breaks otherwise. Whichever you choose, say so in your report.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`

Expected: FAIL — `set_volume`, `get_volume`, `is_muted`, `mute_button` and `volume_slider` do not exist.

- [ ] **Step 3: Give AudioManager a volume**

In `audio/audio_manager.gd`:

```gdscript
## Volume as a linear 0..1, applied to the master bus.
##
## Stored linear rather than read back from the bus because linear_to_db(0.0)
## is -inf: silence is a level the bus can hold but not report in a form that
## converts back.
##
## The bus, not the players: the pool rotates through POOL_SIZE
## AudioStreamPlayers, so setting this per player would leave anything already
## playing at the old level and would need re-applying inside play(). The bus
## moves every voice at once, mid-playback included.
var _volume := 1.0

func set_volume(linear: float) -> void:
	_volume = clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(_volume))

func get_volume() -> float:
	return _volume

## Whether play() is currently short-circuited. Independent of the volume:
## muting does not zero the level and unmuting does not restore a remembered
## one, so a player who adjusts the slider while muted gets what they chose.
func is_muted() -> bool:
	return _muted
```

- [ ] **Step 4: Add the two controls to the HUD**

In `ui/hud.tscn`, add to `Top`, after `SpeedButton`:

```
[node name="MuteButton" type="Button" parent="Top"]
custom_minimum_size = Vector2(44, 44)
layout_mode = 2
text = "Sound on"

[node name="VolumeSlider" type="HSlider" parent="Top"]
custom_minimum_size = Vector2(90, 44)
layout_mode = 2
min_value = 0.0
max_value = 1.0
step = 0.05
value = 1.0
```

In `ui/hud.gd`, add the `@onready` pair, the two accessors, the signal connections in `_ready`, and:

```gdscript
## Pulls both controls back into line with the AudioManager's actual state.
##
## Called on bind rather than assumed at build time: the HUD scene ships with
## a full slider and an unmuted label, and the manager may already be at some
## other setting by the time the HUD exists.
func refresh_audio_controls() -> void:
	var mgr := _audio()
	if mgr == null:
		return
	_mute.text = "Sound off" if mgr.is_muted() else "Sound on"
	_volume_slider.set_value_no_signal(mgr.get_volume())
```

`set_value_no_signal` is the point: plain assignment emits `value_changed`, so refreshing the slider from the manager would write the value straight back and, on a rounding difference, could fight the thing it is reading.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 6: Check it by ear and by eye**

Run the game. Confirm the two controls sit in the top bar without pushing anything off the edge, that the button's label tracks its state, that the slider changes how loud a tower firing is, and that muting silences it with the slider left where it was.

- [ ] **Step 7: Commit**

```bash
git add audio/audio_manager.gd ui/hud.tscn ui/hud.gd test/test_audio_manager.gd test/test_hud.gd
git commit -m "Let the player mute the game and set its volume"
```

---

### Task 2: Enemies that read as running

**Files:**
- Modify: `game/enemy.gd`
- Modify: `data/enemies.gd`
- Test: `test/test_enemy.gd`
- Test: `test/test_data_tables.gd`

**Interfaces:**
- Consumes: `Movement.advance`'s returned position, which does not change.
- Produces: `Enemy.stride_phase() -> float`, so a test can read the cycle without inspecting the sprite's transform.

**What is wrong today.** `_physics_process` runs `_bob_clock += delta` and lifts the sprite by `absf(sin(_bob_clock * BOB_HZ * TAU)) * BOB_PIXELS`, with `BOB_HZ = 5.0` and `BOB_PIXELS = 2.0`. Three separate problems, and they compound:

1. **The cycle is timed, not travelled.** A 60px/s ogre bobs at exactly the rate a 150px/s bat does, so neither looks like it is moving under its own power. It is the single thing most responsible for the sliding read.
2. **It keeps cycling when the enemy does not move.** A slowed enemy bobs at full rate; one stopped at a waypoint keeps bobbing.
3. **2px is below the threshold where it registers** on sprites 28 to 58px tall.

**What replaces it.** The phase advances with distance travelled, and three things read off it:

- **Bob**, `-abs(sin(phase))` — two lifts per stride, one per foot.
- **Squash and stretch**, keyed to footfall. This is what actually sells a run on a sprite with no frames: at the bottom of the bob the creature compresses and widens, at the top it extends. Without it the sprite is a rigid cut-out being moved up and down.
- **Lean**, a small constant rotation into the direction of travel, which the spec asked for (§6, "a slight lean applied while moving") and Task 7 of the art swap dropped without ruling on it.

All three go to zero when the enemy is not moving, because all three are driven by the same phase and the phase stops advancing.

**`stride_px` is per kind and is not a speed.** It is how far the creature travels per complete stride, so it sets the cycle's *spatial* frequency while the enemy's own speed sets its temporal one. A bat's wings beat far faster than its body advances, so its stride is short; an ogre lumbers, so its stride is long. Starting values, to be judged by eye in Step 6: goblin 30, ogre 46, bat 14.

- [ ] **Step 1: Write the failing tests**

Replace `test_the_walk_bob_lifts_the_sprite` and any other test reading `_bob_clock` in `test/test_enemy.gd`, and add:

```gdscript
func test_the_stride_advances_with_distance_not_with_time() -> bool:
	# The whole point. A slow enemy and a fast one must not cycle at the same
	# rate, or neither looks like it is moving under its own power.
	var slow := _ready_enemy()
	slow.setup(&"ogre", _straight_path(), 1)
	var fast := _ready_enemy()
	fast.setup(&"bee", _straight_path(), 1)
	assert_true(Enemies.DEFS[&"bee"]["base_speed"] > Enemies.DEFS[&"ogre"]["base_speed"],
		"precondition: the bat is faster than the ogre")

	for i in 10:
		slow._physics_process(0.05)
		fast._physics_process(0.05)

	assert_true(fast.stride_phase() > slow.stride_phase(),
		"over the same elapsed time the faster enemy is further through its stride (%f vs %f)"
			% [fast.stride_phase(), slow.stride_phase()])
	slow.free()
	fast.free()
	return true

func test_a_stationary_enemy_does_not_cycle() -> bool:
	# A timed cycle keeps running when the enemy is held up. A travelled one
	# cannot.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	e._physics_process(0.05)
	var moving := e.stride_phase()
	assert_true(moving > 0.0, "precondition: it cycled while it was moving")

	e.sim["speed"] = 0.0
	for i in 10:
		e._physics_process(0.05)
	assert_almost_eq(e.stride_phase(), moving, 0.0001,
		"a stopped enemy holds its phase instead of running on the spot")
	e.free()
	return true

func test_a_slowed_enemy_cycles_more_slowly() -> bool:
	var normal := _ready_enemy()
	normal.setup(&"slime", _straight_path(), 1)
	var slowed := _ready_enemy()
	slowed.setup(&"slime", _straight_path(), 1)
	slowed.sim["slow"] = Slow.apply(Slow.none(), 0.5, 5000.0)

	for i in 8:
		normal._physics_process(0.05)
		slowed._physics_process(0.05)

	assert_true(slowed.stride_phase() < normal.stride_phase(),
		"a slowed enemy is less far through its stride (%f vs %f)"
			% [slowed.stride_phase(), normal.stride_phase()])
	normal.free()
	slowed.free()
	return true

func test_the_stride_squashes_and_stretches_the_sprite() -> bool:
	# A rigid sprite moved up and down still reads as a cut-out. The
	# compression at footfall is what makes it read as weight.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	var seen_squashed := false
	var seen_neutral := false
	var base := sprite.scale.y
	for i in 40:
		e._physics_process(0.02)
		if sprite.scale.y < base * 0.995:
			seen_squashed = true
		if absf(sprite.scale.y - base) < base * 0.005:
			seen_neutral = true
		assert_true(sprite.scale.y <= base + 0.0001,
			"the stride never stretches past the sprite's declared height")
	assert_true(seen_squashed, "the sprite compresses somewhere in the stride")
	assert_true(seen_neutral, "and returns to its declared height somewhere in it")
	e.free()
	return true

func test_the_stride_leans_the_sprite_into_its_travel() -> bool:
	# Spec section 6 asked for this and the art swap dropped it without ruling
	# on it.
	var e := _ready_enemy()
	e.setup(&"slime", _straight_path(), 1)
	var sprite: Sprite2D = e.get_node("Sprite")
	e.set_facing_from_travel(false)
	e._physics_process(0.05)
	var right_lean := sprite.rotation
	assert_true(absf(right_lean) > 0.0001, "a moving enemy leans")

	e.set_facing_from_travel(true)
	e._physics_process(0.05)
	assert_true(signf(sprite.rotation) != signf(right_lean),
		"and leans the other way when it turns around")
	e.free()
	return true

func test_every_kind_declares_a_stride() -> bool:
	for kind in Enemies.KINDS:
		assert_true(float(Enemies.DEFS[kind]["stride_px"]) > 0.0,
			"%s declares a stride length" % kind)
	return true
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: FAIL — `stride_phase` and `stride_px` do not exist.

- [ ] **Step 3: Give each kind a stride**

In `data/enemies.gd`, add `"stride_px"` to each kind — goblin 30.0, ogre 46.0, bat 14.0 — and document it:

```gdscript
## stride_px is how far a creature travels per complete stride, so it sets the
## SPATIAL frequency of the run cycle while the creature's own speed sets the
## temporal one. That is why it is not a rate: the bat's wings beat far faster
## than its body advances, so its stride is short, and the ogre lumbers, so its
## stride is long.
```

Add it to `test/test_data_tables.gd`'s cosmetic-field table alongside `variant_count` and `sprite_px`.

- [ ] **Step 4: Rewrite the motion**

In `game/enemy.gd`, replace `BOB_HZ` and `_bob_clock` with:

```gdscript
## How far the stride lifts, compresses and leans the sprite.
##
## All three are fractions of the sprite rather than pixel counts, because the
## kinds are drawn at 28 to 58px tall and a fixed 2px lift - what this replaced -
## is below the threshold where it registers on any of them.
const BOB_FRACTION := 0.10
const SQUASH_FRACTION := 0.10
const LEAN_RADIANS := 0.08

var _travelled := 0.0
var _flip := false
```

```gdscript
## How far through its stride the enemy is, in radians. Advanced by DISTANCE
## TRAVELLED, not by elapsed time.
##
## This is the difference between running and sliding. A timed cycle makes a
## 60px/s ogre bob at exactly the rate a 150px/s bat does, keeps cycling while
## an enemy is slowed, and keeps cycling while it is stopped. A travelled one
## cannot do any of those things - the same arithmetic that moves the enemy
## drives the cycle, so the cycle is correct for free.
func stride_phase() -> float:
	return _travelled / float(Enemies.DEFS[kind]["stride_px"]) * TAU

## Draws one frame of the stride: two lifts per cycle, one per foot, with the
## sprite compressing at each footfall and extending at the top of each lift.
##
## The squash is what sells it. A sprite that only moves up and down is a
## rigid cut-out being moved up and down; compressing it at the moment it
## takes weight is what a run looks like without any frames to draw it with.
func _apply_stride() -> void:
	var lift := absf(sin(stride_phase()))
	var height := float(Enemies.DEFS[kind]["sprite_px"])
	_sprite.position.y = -lift * height * BOB_FRACTION
	var squash := (1.0 - lift) * SQUASH_FRACTION
	_sprite.scale = Vector2(_base_scale * (1.0 + squash * 0.6),
		_base_scale * (1.0 - squash))
	_sprite.rotation = (LEAN_RADIANS if _flip else -LEAN_RADIANS) * lift
```

`_base_scale` is what `apply_sprite_height` already computes; store it in a field there rather than recomputing, so the squash multiplies a known value instead of compounding on the last frame's.

In `_physics_process`, accumulate the distance actually covered and drive the stride from it:

```gdscript
	var before := position
	var result := Movement.advance(...)
	position = result["position"]
	...
	_travelled += before.distance_to(position)
	_apply_stride()
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `godot --headless --quit --script test/run_tests.gd`
Expected: PASS.

- [ ] **Step 6: Watch a wave**

Run the game and watch one, at 1x and at the faster speed. This is a motion change and no assertion can tell you whether it reads as running — the tests pin that the cycle is travelled rather than timed, and that the parts move, but not that the result looks right.

Judge three things and report on each: whether each kind's cycle rate suits its speed, whether the squash reads as weight rather than as a wobble, and whether the lean reads as forward motion rather than as a tilted sprite. **If a value is wrong, change the value and say what you changed it from** — the starting numbers are a first guess and are labelled as one.

- [ ] **Step 7: Commit**

```bash
git add game/enemy.gd data/enemies.gd test/test_enemy.gd test/test_data_tables.gd
git commit -m "Drive the run cycle from distance travelled, and give it weight"
```

---

## Notes for the executor

**Task 1 is the safer of the two and should go first** — it adds controls beside existing ones and touches an autoload with an unwired setter. Task 2 rewrites motion that every enemy on screen runs every physics frame.

**Neither task may touch `sim/`.** Enemy movement arithmetic is already correct and already tested; this plan changes only how the view draws what the sim decides.

**The targeting-priority control the owner also asked for is NOT in this plan.** It is Tasks 1 to 3 of `docs/superpowers/plans/2026-08-20-turret-tracking-and-targeting.md`, which are still live and unexecuted. Tasks 4 to 7 of that plan are dead: they bake turret atlases with `tools/bake_kenney.gd`, which the illustrated art swap deleted.
