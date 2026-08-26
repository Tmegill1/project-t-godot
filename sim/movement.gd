class_name Movement

## Path following. Pure: returns new values rather than mutating.
##
## One quirk from the original is preserved deliberately (arrival consumes the
## whole tick) and one was deliberately REMOVED because it soft-locked this
## port (the un-clamped overshoot). Both are called out at their sites.

const WAYPOINT_ARRIVAL_RADIUS := 2.0
const _SPAWN_SNAP_RADIUS := 1.0

## Which waypoint an enemy spawning at `position` should head for first.
## An enemy spawned exactly on path[0] would otherwise sit at zero distance
## from its own target and stall.
static func starting_path_index(position: Vector2, path: PackedVector2Array) -> int:
	if path.size() <= 1:
		return 0
	var first := path[0]
	var on_first := absf(first.x - position.x) < _SPAWN_SNAP_RADIUS \
		and absf(first.y - position.y) < _SPAWN_SNAP_RADIUS
	return 1 if on_first else 0

## Advances one tick along the path. `delta_ms` is milliseconds.
static func advance(position: Vector2, path_index: int, path: PackedVector2Array,
		speed: float, delta_ms: float) -> Dictionary:

	if path_index >= path.size():
		return {
			"position": position, "path_index": path_index, "reached_goal": true,
			"advanced_waypoint": false, "direction": &"down", "moving_left": false,
		}

	var target := path[path_index]
	var dx := target.x - position.x
	var dy := target.y - position.y
	var distance := sqrt(dx * dx + dy * dy)

	# Ties fall to "side": the original test is abs(dy) > abs(dx).
	var direction: StringName = &"side"
	if absf(dy) > absf(dx):
		direction = &"down" if dy > 0.0 else &"up"
	var moving_left := dx < 0.0

	var move_distance := speed * delta_ms / 1000.0

	# An enemy arrives when it is already inside the radius, OR when this
	# tick's step would reach or pass the waypoint.
	#
	# REMOVED QUIRK — read this before "restoring fidelity".
	#
	# The original (movement.ts, ported verbatim by Task 8) tested only
	# `distance < WAYPOINT_ARRIVAL_RADIUS` and never clamped or crossing-tested
	# the step, so a fast enough enemy overshot the waypoint and steered back.
	# That is safe in the reference and NOT safe here, and the difference is
	# the caller's timing model, not the rule:
	#
	#   - Phaser hands BaseEnemy.update a *measured* frame delta, so the step
	#     length jitters every frame.
	#   - Godot's _physics_process delta is fixed at 1/60s, so each enemy's
	#     step is a constant for its whole life.
	#
	# With a constant step, whenever the approach remainder r and the overshoot
	# (step - r) are BOTH >= WAYPOINT_ARRIVAL_RADIUS, the enemy oscillates
	# around the waypoint forever and never arrives. That needs step > 2 *
	# WAYPOINT_ARRIVAL_RADIUS = 4.0 px/tick, which this game reaches: bees at
	# wave 19 move 150 * 1.70 = 4.25 px/tick and at wave 20 4.375 px/tick.
	# Measured against the real 52-point path, waves 19 and 20 undefended never
	# terminated (wave 19 alternated 2.00/2.25, wave 20 2.375/2.00 — exact
	# cycles, not float near-misses). In the live game that is unbounded: a
	# stuck enemy never leaks, never frees, so GameBoard's "no enemies left"
	# wave-clear test never fires, the Start button never re-enables and
	# victory is unreachable. Preserving the quirk faithfully is what makes the
	# game unwinnable, so faithfulness yields here.
	#
	# Do NOT instead retune WAYPOINT_ARRIVAL_RADIUS or the speed table: wave 18
	# also exceeds 4.0 px/tick and happens not to trap, so any threshold picked
	# to dodge today's cycle is a coincidence that the next balance change
	# reopens. `distance <= move_distance` is a mechanism fix — it makes the
	# distance to the current waypoint fall by a fixed positive amount every
	# non-arriving tick, so arrival is guaranteed in finitely many ticks at any
	# speed and any tick size.
	#
	# Cost, measured across all 20 waves undefended at the default tick: waves
	# 1-16 are tick-for-tick IDENTICAL, wave 17 shifts by 2 ticks and wave 18 by
	# 3, out of ~3000 (0.1%). Leaks and lives lost are unchanged on every wave
	# that previously completed, and every exact balance pin in test_harness.gd
	# held. The largest shift anywhere in the suite is 2 ticks out of 712, at
	# the non-default tick_ms=40. Full table in final-fix-report.md.
	#
	# Enemies whose step is under the 2px radius are bit-identical, since
	# `distance <= move_distance` cannot fire before `distance < 2.0` does. That
	# is every ogre at every wave (max 1.75 px/tick) and every goblin below wave
	# 9 — which is why the shift is as small as it is.
	#
	# Note that explicit crossing detection would be the same predicate: motion
	# is always straight at the current waypoint, so "this step crosses it" is
	# exactly "move_distance >= distance".
	if distance < WAYPOINT_ARRIVAL_RADIUS or distance <= move_distance:
		# QUIRK, preserved: arriving consumes the whole tick. The original
		# never advances the index and moves in the same frame, and changing
		# that would shift every enemy's arrival time.
		var next_index := path_index + 1
		return {
			"position": position, "path_index": next_index,
			"reached_goal": next_index >= path.size(),
			"advanced_waypoint": true, "direction": direction,
			"moving_left": moving_left,
		}

	# Still short of the waypoint by more than one step: move a full step. This
	# is unreachable when move_distance >= distance (see the arrival test
	# above), so the step can no longer carry the enemy past its target.
	return {
		"position": Vector2(
			position.x + (dx / distance) * move_distance,
			position.y + (dy / distance) * move_distance),
		"path_index": path_index, "reached_goal": false,
		"advanced_waypoint": false, "direction": direction,
		"moving_left": moving_left,
	}
