class_name Leak

## What it costs the player when an enemy reaches the exit.

## Past this wave, a leak costs the enemy's remaining health instead of its
## flat life value.
const LIFE_LOSS_SCALING_WAVE := 5

## Most lives a single leak can cost. The health-based rule was unbounded and
## enemy health compounds every wave, so by wave 20 one leak ended the run.
## Capped, twenty lives is a budget of five mistakes.
const MAX_LIFE_LOSS_PER_LEAK := 4

static func resolve(enemy: Dictionary, wave: int) -> int:
	if enemy.get("exempt_from_life_loss", false):
		return 0

	if wave > LIFE_LOSS_SCALING_WAVE:
		return mini(MAX_LIFE_LOSS_PER_LEAK, maxi(1, int(ceil(float(enemy["health"])))))

	return mini(MAX_LIFE_LOSS_PER_LEAK, int(enemy["life_loss"]))
