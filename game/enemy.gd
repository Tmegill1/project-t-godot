class_name Enemy
extends Node2D

## Enemy view: owns an animated sprite and health bar, asks sim/movement.gd
## where to move each tick, and reports its own death/leak upward by signal.
## Decides nothing about the game itself - the sim modules do.

signal died(reward: int, kind: StringName)
signal leaked(life_loss: int)

const FRAME_SIZE := 48
const FRAMES_PER_SHEET := 6
const WALK_FPS := 8.0
const DEATH_FPS := 10.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _health_bar: ColorRect = $HealthBar

var kind: StringName
var sim := {}
var _path: PackedVector2Array
var _wave := 1
var _facing: StringName = &"side"
var _flip := false

func setup(enemy_kind: StringName, path: PackedVector2Array, wave: int) -> void:
	kind = enemy_kind
	_path = path
	_wave = wave
	var def: Dictionary = Enemies.DEFS[kind]
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
	}

	position = path[0]
	_sprite.sprite_frames = _build_frames(def["texture_key"])
	_sprite.scale = Vector2.ONE * float(def["sprite_scale"])
	_play_walk()
	_update_health_bar()

func _physics_process(delta: float) -> void:
	# sim starts as {}; a physics tick landing between the node entering the
	# tree and setup() being called would otherwise hit a missing-key error
	# on sim["alive"] below, which aborts this whole function silently.
	if sim.is_empty():
		return
	if not sim["alive"] or sim["dying"]:
		return

	var result := Movement.advance(position, sim["path_index"], _path,
		sim["speed"], delta * 1000.0)
	position = result["position"]
	sim["path_index"] = result["path_index"]

	# A tick that advanced a waypoint covered no distance, so its reported
	# direction comes from a sub-pixel delta and would make the sprite jitter.
	if not result["advanced_waypoint"]:
		_set_facing(result["direction"], result["moving_left"])

	if result["reached_goal"]:
		sim["alive"] = false
		leaked.emit(Leak.resolve(
			{"life_loss": Enemies.DEFS[kind]["life_loss"], "health": sim["health"]}, _wave))
		queue_free()

func take_damage(source: Dictionary) -> Dictionary:
	var result := Damage.resolve(source, sim)
	sim["health"] = result["remaining_health"]
	_update_health_bar()
	if result["lethal"]:
		_die()
	return result

func to_candidate() -> Dictionary:
	return {
		"id": sim["id"], "position": position, "health": sim["health"],
		"path_index": sim["path_index"], "alive": sim["alive"],
		"dying": sim["dying"], "node": self,
	}

func get_sim_state() -> Dictionary:
	return sim

func _die() -> void:
	sim["dying"] = true
	sim["alive"] = false
	died.emit(int(Enemies.DEFS[kind]["reward"]), kind)
	_health_bar.visible = false
	_sprite.play("death_%s" % _facing)
	await _sprite.animation_finished
	queue_free()

func _set_facing(direction: StringName, moving_left: bool) -> void:
	var flip := moving_left if direction == &"side" else false
	if Enemies.DEFS[kind]["flip_horizontally"]:
		flip = not flip
	if direction == _facing and flip == _flip:
		return
	_facing = direction
	_flip = flip
	_sprite.flip_h = flip
	_play_walk()

func _play_walk() -> void:
	_sprite.play("walk_%s" % _facing)

func _update_health_bar() -> void:
	var fraction: float = clampf(sim["health"] / sim["max_health"], 0.0, 1.0)
	_health_bar.size.x = 32.0 * fraction
	_health_bar.color = Color.GREEN.lerp(Color.RED, 1.0 - fraction)

func _build_frames(texture_key: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for action in ["Walk", "Death"]:
		for dir_pair in [["U", "up"], ["S", "side"], ["D", "down"]]:
			var anim := "%s_%s" % [action.to_lower(), dir_pair[1]]
			frames.add_animation(anim)
			frames.set_animation_speed(anim, WALK_FPS if action == "Walk" else DEATH_FPS)
			frames.set_animation_loop(anim, action == "Walk")
			var path := "res://assets/enemies/%s/%s_%s.png" % [texture_key, dir_pair[0], action]
			var sheet: Texture2D = load(path)
			if sheet == null:
				push_error("missing sheet %s" % path)
				continue
			for i in FRAMES_PER_SHEET:
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
				frames.add_frame(anim, atlas)
	return frames
