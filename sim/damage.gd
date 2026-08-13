class_name Damage

## Every point of damage in the game routes through resolve().
##
## Armour reduces every hit by a flat amount, so it punishes many small hits
## and is beaten by few large ones. Shields absorb a whole hit regardless of
## size, so they punish large hits and are beaten by rapid cheap fire. If
## either could be answered by the same build as the other, enemy properties
## would be decoration.

## Whether a splash blast centred on `center` reaches something at `position`.
##
## This lives in sim/ because both callers need it and there must only be one
## of it: sim/harness.gd resolves splash for every balance test in the suite,
## and game/game_board.gd resolves it for the game the player actually runs.
## This project's load-bearing claim is that those are the same rules — with
## two copies, the first upgrade that touches splash gets written twice and
## only the harness's copy is covered by tests.
##
## The boundary is inclusive: something at exactly the splash radius IS hit.
## test_harness.gd's test_splash_radius_boundary_at_wave_ten depends on that
## exact edge (wave 10 puts a bystander at exactly 55.0 from the target).
##
## Excluding the blast's own primary target is deliberately left to the caller:
## the harness identifies it by sim id and the board by node identity, and that
## is a question of identity, not of geometry.
static func in_splash(center: Vector2, position: Vector2, radius: float) -> bool:
	return center.distance_to(position) <= radius

static func resolve(source: Dictionary, target: Dictionary) -> Dictionary:
	var shield: int = maxi(0, int(target.get("shield", 0)))
	var health: float = float(target["health"])
	var alive: bool = target.get("alive", true)

	# A corpse absorbs nothing. Enemies linger while their death animation
	# plays; without this a second projectile already in flight would report
	# a kill again and pay the reward twice.
	if not alive or health <= 0.0:
		return {
			"damage_dealt": 0.0, "remaining_health": maxf(0.0, health),
			"remaining_shield": shield, "shield_absorbed": false,
			"armor_absorbed": 0.0, "lethal": false,
		}

	# Negative damage must not heal. Nothing produces it today, but a bad data
	# value should be inert rather than a source of invincible enemies.
	var incoming: float = maxf(0.0, float(source["damage"]))

	# A zero-damage source must not strip a shield charge for free — otherwise
	# a tower that cannot hurt an armoured target could still peel its shield,
	# and armour would stop being a counter.
	if shield > 0 and incoming > 0.0:
		return {
			"damage_dealt": 0.0, "remaining_health": health,
			"remaining_shield": shield - 1, "shield_absorbed": true,
			"armor_absorbed": 0.0, "lethal": false,
		}

	var armor: float = maxf(0.0, float(target.get("armor", 0)))
	var pierce: float = maxf(0.0, float(source.get("pierce", 0)))
	var effective_armor := maxf(0.0, armor - pierce)
	var after_armor := maxf(0.0, incoming - effective_armor)

	var damage_dealt := minf(after_armor, health)
	var remaining_health := health - damage_dealt

	return {
		"damage_dealt": damage_dealt, "remaining_health": remaining_health,
		"remaining_shield": shield, "shield_absorbed": false,
		"armor_absorbed": incoming - after_armor,
		"lethal": remaining_health <= 0.0 and damage_dealt > 0.0,
	}
