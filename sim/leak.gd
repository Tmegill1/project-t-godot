class_name Leak

## What it costs the player when an enemy reaches the exit.
##
## The cost is the enemy's OWN price, scaled by how much of it arrived alive:
##
##     ceil(life_loss * remaining_health / max_health)
##
## floored at one and ceilinged at the kind's own `life_loss`. So which kind
## leaked is what decides the damage - a goblin is a scratch and an ogre is
## five of a twenty-life budget - and an enemy that limps in nearly dead costs
## less than one that walks through untouched.
##
## WHAT THIS REPLACED, AND WHY IT IS NOT COMING BACK. The rule used to be a
## flat per-kind cost through wave 5 and `min(4, ceil(remaining_health))`
## after it. Both halves failed:
##
## - The health-based half was unbounded, and enemy health compounds every
##   wave, so by wave 20 a single leak ended the run. That is what the cap of
##   4 was added to stop.
## - The cap then flattened everything it was meant to bound. From wave 10 on
##   every ordinary enemy has at least 4 health, so the cap ALWAYS bound: a
##   goblin, a bat, a shaman and an ogre all cost exactly 4, `life_loss` was
##   dead data at every wave that mattered, and the run was always exactly
##   five leaks from over no matter what leaked.
##
## Taking the ratio rather than the absolute health is what gets both
## properties at once. It cannot compound, because it is bounded above by a
## number from the table rather than by a number that grows with the wave -
## so the cap has nothing left to do and is gone, along with the wave
## parameter, which nothing reads any more.

## What a leak costs, in lives.
##
## `enemy` carries `life_loss`, `health` (what is LEFT, at the goal) and
## `max_health` (what it spawned with, wave scaling already applied).
##
## `boss_life_loss` is a per-enemy override that bypasses the ordinary rule
## entirely. It exists because a boss must read as worse than anything the
## roster can do, and it is a DECLARED number from data/bosses.gd rather than
## one derived from the boss's own health - which is the whole lesson above.
## A 900-health Warlord scaled against its own maximum would cost exactly what
## a goblin costs, since both arrive whole.
static func resolve(enemy: Dictionary) -> int:
	if enemy.get("exempt_from_life_loss", false):
		return 0

	# Checked before the ordinary rule, and deliberately not clamped by it.
	var boss_cost := int(enemy.get("boss_life_loss", 0))
	if boss_cost > 0:
		return boss_cost

	var flat := int(enemy["life_loss"])
	var full := float(enemy["max_health"])

	# Nothing in the game spawns a zero-health enemy, but this module takes a
	# plain dictionary and is the last thing between a malformed spawn and a
	# division by zero mid-wave. With no ratio to take, the kind's own price
	# stands.
	if full <= 0.0:
		return maxi(1, flat)

	# Clamped, so an enemy cannot arrive carrying more health than it spawned
	# with. This is also what bounds the whole rule: a `left` no greater than
	# `full` makes the ratio no greater than 1, which makes the result no
	# greater than the kind's own price. An explicit ceiling of `flat` on the
	# line below would be unreachable dead code - and worse than useless,
	# because it would mask this clamp. Mutation testing is what found that:
	# with both present, neither could be shown to matter.
	var left := clampf(float(enemy["health"]), 0.0, full)

	# Rounds UP, so chip damage never discounts a leak below what the
	# arithmetic says. The floor of one is reachable only at exactly zero
	# remaining health, since any positive remainder already rounds up to one.
	return maxi(1, int(ceil(float(flat) * left / full)))
