class_name Movement

## Path following. Pure: returns new values rather than mutating.
##
## Two quirks from the original are preserved deliberately, both affecting
## arrival timing. They are called out at their sites.

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

	if distance < WAYPOINT_ARRIVAL_RADIUS:
		# QUIRK: arriving consumes the whole tick. The original never advances
		# the index and moves in the same frame, and changing that would shift
		# every enemy's arrival time.
		var next_index := path_index + 1
		return {
			"position": position, "path_index": next_index,
			"reached_goal": next_index >= path.size(),
			"advanced_waypoint": true, "direction": direction,
			"moving_left": moving_left,
		}

	# QUIRK: no clamping to the waypoint, so a fast enough enemy overshoots
	# and then steers back. At current speeds this is imperceptible.
	var move_distance := speed * delta_ms / 1000.0
	return {
		"position": Vector2(
			position.x + (dx / distance) * move_distance,
			position.y + (dy / distance) * move_distance),
		"path_index": path_index, "reached_goal": false,
		"advanced_waypoint": false, "direction": direction,
		"moving_left": moving_left,
	}
