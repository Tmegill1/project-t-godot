class_name Placement

## Pure placement rules: may a tower stand at a given world point?
##
## No nodes, no scene tree, no static state. Every input is an argument -
## unlike Grid, which keeps the active map in static vars. That is deliberate:
## it lets a test build an arbitrary board without touching engine singletons,
## and it means these rules can never disagree with themselves between callers.

const REASON_OK := &"ok"
const REASON_OUT_OF_BOUNDS := &"out_of_bounds"
const REASON_ON_PATH := &"on_path"
const REASON_BLOCKED_BY_PROP := &"blocked_by_prop"
const REASON_TOO_CLOSE := &"too_close"

## How close two towers may sit, centre to centre. Deliberately NOT derived
## from the tower radius: "how big a tower looks" is an art decision and "how
## close two may sit" is a balance lever, and coupling them would make one
## untunable without disturbing the other. Starts just under the old 48px tile
## pitch so day-one density roughly matches the grid this replaces.
const MIN_TOWER_SPACING := 44.0

## Half the width of the corridor kept clear along the enemy route. Half a
## tile (24) plus a small margin, so a tower may not encroach on the road
## enemies visibly walk down.
const PATH_HALF_WIDTH := 26.0

## Shortest distance from `point` to the segment ab.
##
## Clamping t to [0, 1] is what makes this a *segment* rather than an infinite
## line: without it, a point far beyond an endpoint reports the distance to the
## line's projection, which for a path polyline means a tower could be built
## past the end of the road and still be judged "on" it.
static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq == 0.0:
		# Degenerate segment: a and b are the same point, so there is no
		# direction to project onto. Guarded explicitly because the division
		# below would produce NAN, and NAN compares false against every
		# threshold - the rules would silently stop rejecting anything.
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

## Shortest distance from `point` to any segment of any path polyline.
## Returns INF when there are no paths, so an absent route imposes no
## constraint rather than blocking everything.
static func distance_to_paths(point: Vector2, paths: Array) -> float:
	var best := INF
	for path in paths:
		var pts: PackedVector2Array = path
		if pts.size() == 0:
			continue
		if pts.size() == 1:
			best = minf(best, point.distance_to(pts[0]))
			continue
		for i in range(pts.size() - 1):
			best = minf(best, distance_to_segment(point, pts[i], pts[i + 1]))
	return best

## A tower's collision radius, from the `size` multiplier it already declares
## in data/towers.gd. Derived rather than tabulated so that re-sizing a tower
## for art reasons cannot leave its collision disagreeing with its sprite.
static func tower_radius(kind: StringName) -> float:
	return Tiles.TILE_SIZE * float(Towers.DEFS[kind]["size"]) / 2.0

## May a tower of `radius` stand centred on `pos`?
##
## Returns a reason as well as a verdict so the board can keep showing the
## player a specific message instead of one generic refusal. Checks run
## cheapest-and-most-explanatory first, and the order is load-bearing: it is
## what makes the reported reason stable when several rules fail at once.
##
## `props` is [{ "pos": Vector2, "radius": float }], `towers` is [Vector2],
## `paths` is [PackedVector2Array].
static func can_place(
		pos: Vector2,
		radius: float,
		props: Array,
		towers: Array,
		paths: Array,
		bounds: Rect2,
		min_spacing: float = MIN_TOWER_SPACING) -> Dictionary:
	if pos.x - radius < bounds.position.x \
			or pos.y - radius < bounds.position.y \
			or pos.x + radius > bounds.end.x \
			or pos.y + radius > bounds.end.y:
		return {"ok": false, "reason": REASON_OUT_OF_BOUNDS}

	if distance_to_paths(pos, paths) < radius + PATH_HALF_WIDTH:
		return {"ok": false, "reason": REASON_ON_PATH}

	for prop in props:
		var p: Dictionary = prop
		if pos.distance_to(p["pos"]) < radius + float(p["radius"]):
			return {"ok": false, "reason": REASON_BLOCKED_BY_PROP}

	for other in towers:
		var t: Vector2 = other
		if pos.distance_to(t) < min_spacing:
			return {"ok": false, "reason": REASON_TOO_CLOSE}

	return {"ok": true, "reason": REASON_OK}
