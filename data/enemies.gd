class_name Enemies

const DEFS := {
	&"slime": {
		"label": "Slime", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "texture_key": "slime", "sprite_scale": 0.7,
		"flip_horizontally": false,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 60.0, "base_health": 8, "reward": 20,
		"life_loss": 5, "texture_key": "ogre", "sprite_scale": 1.2,
		"flip_horizontally": true,
	},
	&"bee": {
		"label": "Bee", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "texture_key": "bee", "sprite_scale": 0.7,
		"flip_horizontally": false,
	},
}

const KINDS: Array[StringName] = [&"slime", &"ogre", &"bee"]

## Health for a spawn, applying the wave modifier. Floors, never below one.
static func scaled_health(kind: StringName, health_modifier: float) -> int:
	return maxi(1, int(floor(float(DEFS[kind]["base_health"]) * health_modifier)))

## Speed for a spawn, applying the wave modifier. Unrounded, never below one.
static func scaled_speed(kind: StringName, speed_modifier: float) -> float:
	return maxf(1.0, float(DEFS[kind]["base_speed"]) * speed_modifier)
