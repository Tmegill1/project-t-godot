class_name Slow

## An enemy's slow state: a speed factor and how long it has left to run.
##
## Strongest-factor-wins matches sim/upgrades.gd's stat resolution, so a weak
## slow landing on a deeply slowed enemy cannot speed it back up. The timer is
## refreshed independently, so standing in a weak tower's fire keeps an enemy
## slowed rather than letting a strong slow lapse early.
##
## The reference stores an absolute deadline (BaseEnemy.applySlow's
## `slowedUntilMs`) read against a simulation clock. This counts a remainder
## down instead: sim/ is forbidden a clock of its own, and the callers already
## have the per-tick delta. One consequence is deliberate - expiry here clears
## the factor, where upstream leaves a lapsed slow's factor in place forever and
## min()s the next slow against it.
##
## Pure: returns new dictionaries rather than mutating.

static func none() -> Dictionary:
	return {&"factor": 1.0, &"remaining_ms": 0.0}

static func apply(state: Dictionary, factor: float, duration_ms: float) -> Dictionary:
	# A factor of 1.0 or above is not a slow. Taking it would start a timer
	# that expires having done nothing, and would read as "slowed" to any UI.
	# It must leave a slow already running alone rather than replacing it, so
	# a tower with no slow effect cannot cure one.
	if factor >= 1.0:
		return state.duplicate()
	return {
		&"factor": minf(float(state.get(&"factor", 1.0)), factor),
		&"remaining_ms": maxf(float(state.get(&"remaining_ms", 0.0)), duration_ms),
	}

static func tick(state: Dictionary, delta_ms: float) -> Dictionary:
	var remaining := float(state.get(&"remaining_ms", 0.0)) - delta_ms
	if remaining <= 0.0:
		return none()
	return {&"factor": float(state.get(&"factor", 1.0)), &"remaining_ms": remaining}

## Speed after any slow still running. The timer gates the factor, matching
## the reference's effectiveSpeed - apply and tick keep the two consistent, so
## this only differs for a hand-built state, but it keeps the function whole
## rather than resting on an invariant maintained elsewhere.
static func effective_speed(base_speed: float, state: Dictionary) -> float:
	if float(state.get(&"remaining_ms", 0.0)) <= 0.0:
		return base_speed
	return base_speed * float(state.get(&"factor", 1.0))
