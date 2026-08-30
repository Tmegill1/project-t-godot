extends TestCase

func _ready_effect() -> Sprite2D:
	var scene: PackedScene = load("res://game/mortar_explosion.tscn")
	if scene == null:
		return null
	var effect: Sprite2D = scene.instantiate()
	effect.notification(Node.NOTIFICATION_READY)
	return effect

func test_setup_scales_the_six_frame_explosion_to_the_splash_diameter() -> bool:
	var effect := _ready_effect()
	assert_true(effect != null, "the mortar explosion scene can be instantiated")
	if effect == null:
		return true

	effect.setup(64.0)

	assert_eq(effect.hframes, 6, "the explosion texture is divided into six animation frames")
	assert_eq(effect.scale, Vector2.ONE, "a 64px radius maps the 128px sprite sheet frame to its 128px diameter")
	effect.free()
	return true

## The mortar's splash grows 55 -> 70 -> 95 -> 130 across its tiers, so the
## blast has to grow with it rather than drawing one fixed size.
func test_a_wider_blast_draws_a_bigger_explosion() -> bool:
	var small := _ready_effect()
	var large := _ready_effect()
	assert_true(small != null and large != null, "both explosions instantiate")
	if small == null or large == null:
		return true

	small.setup(55.0)
	large.setup(130.0)

	assert_true(large.scale.x > small.scale.x,
		"a maxed mortar's blast draws wider than a base one")
	small.free()
	large.free()
	return true

func test_animation_advances_then_frees_itself_after_the_last_frame() -> bool:
	var effect := _ready_effect()
	assert_true(effect != null, "the mortar explosion scene can be instantiated")
	if effect == null:
		return true

	effect.setup(48.0)
	effect._physics_process(effect.FRAME_DURATION)
	assert_eq(effect.frame, 1, "one frame duration advances the explosion to frame one")

	effect._physics_process(effect.FRAME_DURATION * 5.0)
	assert_true(effect.is_queued_for_deletion(), "the effect frees itself after all six frames have played")
	effect.free()
	return true
