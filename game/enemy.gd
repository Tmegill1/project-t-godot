class_name Enemy
extends Node2D

## Enemy view: owns a sprite and health bar, asks sim/movement.gd
## where to move each tick, and reports its own death/leak upward by signal.
## Decides nothing about the game itself - the sim modules do.

signal died(reward: int, kind: StringName)
signal leaked(life_loss: int)

## How long a kill takes to leave the screen.
##
## 400ms across four drawn frames is 100ms each, which is a normal rate for
## sprite animation. It was 250 when a death was a fade-and-shrink tween, where
## the number set how fast one continuous motion ran; spread over four discrete
## frames that is 62ms each and the fall reads as a blur rather than as a fall.
const DEATH_MS := 400.0


@onready var _sprite: Sprite2D = $Sprite
@onready var _health_bar: ColorRect = $HealthBar

var kind: StringName
var sim := {}
var _path: PackedVector2Array
var _wave := 1
var _travelled := 0.0
var _flip := false
## Whether this spawn is a boss, and what it pays. A boss draws from
## data/bosses.gd rather than from its kind's table.
var is_boss := false
var boss_reward := 0
## What this boss costs on leak, bypassing Leak's ordinary cap. Zero for
## everything that is not a boss.
var boss_life_loss := 0
## How much larger a boss draws than its kind. 1.0 for everything else.
var _boss_display_scale := 1.0

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
		# Read by sim/damage.gd, which has implemented both since the core
		# slice and never had an enemy carrying either.
		"armor": int(Enemies.resistance_for(enemy_kind, wave)["armor"]),
		"shield": int(Enemies.resistance_for(enemy_kind, wave)["shield"]),
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
	# walk_0 is the creature standing, so it is what sprite_px is a height OF.
	# Every other frame - mid-stride, mid-fall, flat - is drawn at this same
	# scale rather than renormalised to its own height.
	# The kind's own scale, WITHOUT any boss multiplier. make_boss runs after
	# setup(), so folding _boss_display_scale in here silently used 1.0 - the
	# boss was never drawn larger, and apply_sprite_height's (standing - drawn)
	# arithmetic then pushed it off the road because only one half of the sum
	# knew about the scale. The multiplier is applied at draw time instead,
	# where both halves see it.
	_frame_scale = float(Enemies.DEFS[kind]["sprite_px"]) \
		/ float(_sprite.texture.get_height())
	apply_sprite_height()
	refresh_resistance_visual()
	_update_health_bar()

## Draws the current frame at the kind's ONE scale, resting on the ground line
## the creature stands on.
##
## The scale comes from the creature's STANDING height, taken once, and never
## from the frame in hand. An earlier version divided sprite_px by each
## frame's own height, which is only sensible while the creature is upright: a
## death sequence ends lying down, so its last frames are short, and dividing
## by a short height scales them UP. Measured on the committed art, the
## goblin's final death frame drew 2.1x the standing creature and the ogre's
## went from 57px wide to 147 - the corpse ballooned as it fell. Frame heights
## vary across the walk cycle too, so the same arithmetic made the creature
## pulse a few percent with every step.
##
## The vertical offset keeps the frame's BOTTOM on one line. The sprite is
## centred, so without it a creature that lies down settles where its torso
## used to be and appears to float; with it, the feet stay where the feet
## were and the body goes down.
func apply_sprite_height() -> void:
	var standing := float(Enemies.DEFS[kind]["sprite_px"]) * _boss_display_scale
	# Both terms below carry the boss multiplier, or the two disagree and the
	# creature is displaced by the difference.
	var drawn_scale := _frame_scale * _boss_display_scale
	var drawn := float(_sprite.texture.get_height()) * drawn_scale
	_sprite.scale = Vector2.ONE * drawn_scale
	_sprite.position.y = (standing - drawn) / 2.0

## The one scale every frame of this kind is drawn at, from its standing
## height. Set in setup() off walk_0, which is the creature on its feet.
var _frame_scale := 1.0

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
		leaked.emit(Leak.resolve({
			"life_loss": Enemies.DEFS[kind]["life_loss"],
			"health": sim["health"],
			"boss_life_loss": boss_life_loss,
		}, _wave))
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
	# Written back, or a shield absorbs every hit forever - which is the
	# difference between a charge and invulnerability.
	sim["shield"] = int(result["remaining_shield"])
	refresh_resistance_visual()
	_update_health_bar()
	if result["lethal"]:
		_die(source)
	return result

## Re-applies anything drawn from the enemy's resistance. A no-op until Task 8
## gives resistance a visual; the call site exists now because the aura is what
## changes a shield mid-flight, and that is the moment the look has to follow.
func refresh_resistance_visual() -> void:
	_sprite.modulate = resistance_tint()

## How this enemy's sprite is tinted for the resistance it carries.
##
## Armour drains warmth toward cold steel; a shield casts pale blue. Both are
## clamped so a deep endless wave stays a readable sprite rather than a
## silhouette.
##
## DISPLAY ONLY. sim/damage.gd reads sim["armor"] and sim["shield"]; nothing
## reads this. It exists because a player needs to know a thing is tough
## BEFORE it reaches the towers, and because the owner is replacing it with
## real art later.
##
## modulate rather than a shader, deliberately: modulate can only multiply, so
## it cannot truly desaturate - but it is a render change with no new files
## and no .import churn, and this is placeholder signalling. A shader is the
## upgrade path when the art arrives.
func resistance_tint() -> Color:
	var armor := float(sim.get("armor", 0))
	var shield := float(sim.get("shield", 0))
	if armor <= 0.0 and shield <= 0.0:
		return Color.WHITE
	# Each point of armour cools the whole sprite toward steel, to a floor that
	# stays legible.
	var warmth := clampf(1.0 - armor * 0.035, 0.5, 1.0)
	# A shield drains the WARM channels and leaves blue alone, so the creature
	# reads cold rather than merely dark. Lifting blue instead does nothing on
	# an unarmoured target, where blue is already at 1.0 - which is exactly how
	# the first version of this failed its own test.
	var chill := clampf(1.0 - shield * 0.12, 0.55, 1.0)
	return Color(warmth * chill, warmth * 0.98 * chill, warmth)

## The height this enemy actually draws at, boss scale included. Exposed so a
## test can compare a boss against its kind without reaching into the sprite.
func drawn_height() -> float:
	return float(Enemies.DEFS[kind]["sprite_px"]) * _boss_display_scale

## Overrides this enemy's stats with a boss definition, after setup().
##
## Applied on top rather than threaded through setup(), so nothing about the
## ordinary spawn path has to know bosses exist. Everything downstream -
## movement, targeting, damage, leak - reads the same sim dictionary it always
## did, which is what keeps a boss from needing a special case anywhere in
## sim/.
func make_boss(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	is_boss = true
	boss_reward = int(definition["reward"])
	boss_life_loss = int(definition["life_loss"])
	sim["health"] = float(definition["health"])
	sim["max_health"] = float(definition["health"])
	sim["speed"] = float(definition["speed"])
	sim["armor"] = int(definition["armor"])
	sim["shield"] = int(definition["shield"])
	# Display only. sprite_px and every placement rule are untouched; this is
	# the same separation Tower.DISPLAY_SCALE keeps from the placement radius.
	_boss_display_scale = float(definition["display_scale"])
	apply_sprite_height()
	refresh_resistance_visual()
	_update_health_bar()

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
	# A boss pays its own bounty, not its kind's.
	var base_reward := boss_reward if is_boss else int(Enemies.DEFS[kind]["reward"])
	died.emit(EconomySim.kill_reward(
		base_reward, source,
		float(Waves.get_modifiers(_wave)["gold_modifier"])), kind)
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
	# gets an equal share of DEATH_MS.
	var frames := Enemies.death_frames(kind)
	var step := DEATH_MS / 1000.0 / float(frames)
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
