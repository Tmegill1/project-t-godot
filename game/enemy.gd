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

## How far the walk bob lifts the sprite, and how fast it cycles.
##
## The sheet's rows are variants rather than animation frames, so motion is
## synthesised: without this an enemy slides along the path like a paper
## cutout.
const BOB_PIXELS := 2.0
const BOB_HZ := 5.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _health_bar: ColorRect = $HealthBar

var kind: StringName
var sim := {}
var _path: PackedVector2Array
var _wave := 1
var _bob_clock := 0.0
var _flip := false

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
	# One of this kind's variants, chosen per spawn. A wave of eight shows
	# eight subtly different creatures rather than eight identical ones. The
	# default keeps the three-argument call sites working and keeps a spawn
	# reproducible either way.
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_SPAWN_SEED)
	_sprite.texture = load("res://assets/art/enemies/%s/variant_%d.png"
		% [kind, rng.int_range(0, Enemies.variant_count(kind) - 1)])
	apply_sprite_height()
	_update_health_bar()

## Scales the current variant to the kind's declared displayed height.
##
## Derived per sprite rather than fixed, because the variants are not a
## uniform size - see data/enemies.gd's note on sprite_px. Uniform on both
## axes: these are creatures, and a stretched one reads as a bug.
func apply_sprite_height() -> void:
	var factor := float(Enemies.DEFS[kind]["sprite_px"]) \
		/ float(_sprite.texture.get_height())
	_sprite.scale = Vector2.ONE * factor

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

	var result := Movement.advance(position, sim["path_index"], _path,
		current_speed(), delta * 1000.0)
	position = result["position"]
	sim["path_index"] = result["path_index"]

	# A tick that advanced a waypoint covered no distance, so its reported
	# direction comes from a sub-pixel delta and would make the sprite jitter.
	if not result["advanced_waypoint"]:
		set_facing_from_travel(bool(result["moving_left"]))

	_bob_clock += delta
	_sprite.position.y = -absf(sin(_bob_clock * BOB_HZ * TAU)) * BOB_PIXELS

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
	# Emitted before the presentation, unchanged: economy timing must not move
	# because the death animation became a tween.
	died.emit(EconomySim.kill_reward(int(Enemies.DEFS[kind]["reward"]), source), kind)
	_health_bar.visible = false
	# Every enemy the test harness builds is outside the scene tree (see the
	# header of test/test_enemy.gd) and create_tween() requires one. This is
	# not a new limitation: today's `await _sprite.animation_finished` never
	# resolves off-tree either, so nothing past this point has ever run in a
	# test. Returning says so instead of parking a coroutine forever.
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 0.6, DEATH_TWEEN_MS / 1000.0)
	tween.tween_property(self, "modulate:a", 0.0, DEATH_TWEEN_MS / 1000.0)
	await tween.finished
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
