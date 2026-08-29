class_name Leak

## What it costs the player when an enemy reaches the exit.

## Past this wave, a leak costs the enemy's remaining health instead of its
## flat life value.
const LIFE_LOSS_SCALING_WAVE := 5

## Most lives a single leak can cost. The health-based rule was unbounded and
## enemy health compounds every wave, so by wave 20 one leak ended the run.
## Capped, twenty lives is a budget of five mistakes.
const MAX_LIFE_LOSS_PER_LEAK := 4

## What a leak costs, in lives.
##
## `boss_life_loss` is a per-enemy override that BYPASSES the cap. It exists
## because the cap flattened the endgame: from wave 10 on, every enemy has at
## least 4 health, so a bat, an ogre and a 900-health troll all cost exactly 4
## and a boss reaching the goal was indistinguishable from the weakest thing
## in the game.
##
## The override is a DECLARED number from data/bosses.gd, never derived from
## the enemy's health - which is the whole reason the cap exists. A
## health-based cost compounds without limit, and by wave 20 one leak ended
## the run; a boss must not reintroduce that by the back door.
static func resolve(enemy: Dictionary, wave: int) -> int:
	if enemy.get("exempt_from_life_loss", false):
		return 0

	# Checked before the cap, and deliberately not clamped by it.
	var boss_cost := int(enemy.get("boss_life_loss", 0))
	if boss_cost > 0:
		return boss_cost

	if wave > LIFE_LOSS_SCALING_WAVE:
		return mini(MAX_LIFE_LOSS_PER_LEAK, maxi(1, int(ceil(float(enemy["health"])))))

	return mini(MAX_LIFE_LOSS_PER_LEAK, int(enemy["life_loss"]))
