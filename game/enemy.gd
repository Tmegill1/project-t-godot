class_name Enemy
extends Node2D

## Enemy view: owns a sprite and health bar, asks sim/movement.gd
## where to move each tick, and reports its own death/leak upward by signal.
## Decides nothing about the game itself - the sim modules do.

signal died(reward: int, kind: StringName)
signal leaked(life_loss: int)

## How long a kill takes to leave the screen.
##
## Replaces awaiting the death animation, which tied despawn timing to whatever
## length the artist drew. The sheet has no death frames, so this file owns the
## duration - short enough not to hold a corpse on screen, long enough that a
## kill registers as feedback.
const DEATH_TWEEN_MS := 250.0


@onready var _sprite: Sprite2D = $Sprite
@onready var _health_bar: ColorRect = $HealthBar

var kind: StringName
var sim := {}
var _path: PackedVector2Array
var _wave := 1
var _travelled := 0.0
var _flip := false
var _base_scale := 1.0

func setup(enemy_kind: StringName, path: PackedVector2Array, wave: int, rng: Rng = null) -> void:
	kind = enemy_kind
	_path = path
	_wave = wave
	var modifiers := Waves.get_modifiers(wave)
	var health := float(Enemies.scaled_health(kind, modifiers["health_modifier"]))

	sim = {
		"id": get_instance_id(),
		"health": health,
		"max_health": health,
		"speed": Enemies.scaled_speed(kind, modifiers["speed_modifier"]),
		"alive": true,
		"dying": false,
		"path_index": Movement.starting_path_index(path[0], path),
		"slow": Slow.none(),
	}

	position = path[0]
	# The first frame of the walk cycle. _physics_process advances it from
	# there; an enemy that never moves stays on this one, which is correct.
	#
	# `rng` is unused now and kept on purpose: GameBoard threads a per-wave one
	# in, and the enemy-variety feature this art gave up is the obvious next
	# caller for it. Removing it would mean re-plumbing the board to bring it
	# back.
	_sprite.texture = load("res://assets/art/enemies/%s/walk_0.png" % kind)
	apply_sprite_height()
	_update_health_bar()

## Scales the current frame to the kind's declared displayed height.
##
## Derived per frame rather than fixed, because the frames are not a uniform
## size - a walking creature's bounding box changes with its stride, and its
## death frames are far wider than tall. Without this the sprite would jump in
## size every time the frame changed. Uniform on both axes: these are
## creatures, and a stretched one reads as a bug.
func apply_sprite_height() -> void:
	var factor := float(Enemies.DEFS[kind]["sprite_px"]) \
		/ float(_sprite.texture.get_height())
	_base_scale = factor
	_sprite.scale = Vector2.ONE * factor

## Which frame of the walk cycle the enemy is showing.
##
## Indexed by DISTANCE TRAVELLED, not by elapsed time. This is the difference
## between running and sliding, and real frames need it exactly as much as the
## synthesised stride they replaced did: a timed cycle moves a 60px/s ogre's
## legs at the same rate as a 150px/s bat's, keeps cycling while an enemy is
## slowed, and keeps cycling while it is stopped. A travelled one cannot do any
## of those - the same arithmetic that moves the enemy drives the cycle, so the
## cycle is correct for free. stride_px is the distance one full cycle covers.
func walk_frame() -> int:
	var frames := Enemies.walk_frames(kind)
	var cycles := _travelled / float(Enemies.DEFS[kind]["stride_px"])
	return int(floor(cycles * float(frames))) % frames

## Draws the frame the cycle names, and rescales to it.
##
## The rescale is not optional: the frames are not a uniform size, so drawing
## one at the previous frame's scale makes the creature pulse as it walks.
func _apply_walk_frame() -> void:
	var wanted := "res://assets/art/enemies/%s/walk_%d.png" % [kind, walk_frame()]
	if _sprite.texture != null and _sprite.texture.resource_path == wanted:
		return
	_sprite.texture = load(wanted)
	apply_sprite_height()

func _physics_process(delta: float) -> void:
	# sim starts as {}; a physics tick landing between the node entering the
	# tree and setup() being called would otherwise hit a missing-key error
	# on sim["alive"] below, which aborts this whole function silently.
	if sim.is_empty():
		return
	if not sim["alive"] or sim["dying"]:
		return

	# The slow runs down before the step it governs, matching sim/harness.gd's
	# loop order so a wave times the same headlessly as it plays.
	tick_slow(delta * 1000.0)

	var before := position
	var result := Movement.advance(position, sim["path_index"], _path,
		current_speed(), delta * 1000.0)
	position = result["position"]
	sim["path_index"] = result["path_index"]

	# A tick that advanced a waypoint covered no distance, so its reported
	# direction comes from a sub-pixel delta and would make the sprite jitter.
	if not result["advanced_waypoint"]:
		set_facing_from_travel(bool(result["moving_left"]))

	# Distance actually covered this tick, not elapsed time - see
	# walk_frame()'s doc comment for why that distinction is the whole point.
	_travelled += before.distance_to(position)
	_apply_walk_frame()

	if result["reached_goal"]:
		sim["alive"] = false
		leaked.emit(Leak.resolve(
			{"life_loss": Enemies.DEFS[kind]["life_loss"], "health": sim["health"]}, _wave))
		queue_free()

## Speed after any active slow. Movement reads this, never sim["speed"].
func current_speed() -> float:
	return Slow.effective_speed(float(sim["speed"]), sim["slow"])

func tick_slow(delta_ms: float) -> void:
	sim["slow"] = Slow.tick(sim["slow"], delta_ms)

func take_damage(source: Dictionary) -> Dictionary:
	# Unconditional: Slow.apply ignores a factor of 1.0 or above, which is
	# what a source with no slow effect carries, so a tower that cannot slow
	# leaves a running slow untouched rather than refreshing or clearing it.
	# The slow lands even when the hit does no damage - being hit is what
	# chills the target, not being hurt by it.
	sim["slow"] = Slow.apply(sim["slow"], float(source.get(&"slow_factor", 1.0)),
		float(source.get(&"slow_duration_ms", 0.0)))
	var result := Damage.resolve(source, sim)
	sim["health"] = result["remaining_health"]
	_update_health_bar()
	if result["lethal"]:
		_die(source)
	return result

func to_candidate() -> Dictionary:
	return {
		"id": sim["id"], "position": position, "health": sim["health"],
		"path_index": sim["path_index"], "alive": sim["alive"],
		"dying": sim["dying"], "node": self,
	}

func get_sim_state() -> Dictionary:
	return sim

## `source` is the killing shot's payload: the reward is paid through the
## firing tower's gold effects, so a kill pays according to which tower made
## it - splash kills included, since they carry the same dictionary.
func _die(source: Dictionary) -> void:
	sim["dying"] = true
	sim["alive"] = false
	# Emitted before the presentation, unchanged across three rewrites of what
	# a death looks like: economy timing must not move because the art did.
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
	_health_bar.visible = false
	# Every enemy the test harness builds is outside the scene tree (see the
	# header of test/test_enemy.gd), and both create_timer and the frames
	# below need one. Not a new limitation: the tween this replaced could not
	# run off-tree either, nor could the animation before that, so nothing past
	# this point has ever run in a test. Returning says so instead of parking a
	# coroutine forever.
	if not is_inside_tree():
		return
	# The artist drew the fall, so it is played rather than faked. Each frame
	# gets an equal share of DEATH_TWEEN_MS, which is what the fade-and-shrink
	# tween before it took.
	var frames := Enemies.death_frames(kind)
	var step := DEATH_TWEEN_MS / 1000.0 / float(frames)
	for i in frames:
		_sprite.texture = load("res://assets/art/enemies/%s/death_%d.png" % [kind, i])
		apply_sprite_height()
		await get_tree().create_timer(step).timeout
	queue_free()

## Faces the way the enemy is travelling. Up and down both draw the side pose -
## the sheet gives one facing, so there is nothing else to draw.
func set_facing_from_travel(moving_left: bool) -> void:
	var flip := moving_left
	if Enemies.DEFS[kind]["flip_horizontally"]:
		flip = not flip
	if flip == _flip:
		return
	_flip = flip
	_sprite.flip_h = flip

func _update_health_bar() -> void:
	var fraction: float = clampf(sim["health"] / sim["max_health"], 0.0, 1.0)
	_health_bar.size.x = 32.0 * fraction
	_health_bar.color = Color.GREEN.lerp(Color.RED, 1.0 - fraction)
