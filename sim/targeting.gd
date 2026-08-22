class_name Targeting

## Target selection. Which enemy a tower shoots is a tactical lever: "first"
## pushes damage toward the exit where leaks happen, "last" protects the back
## of a queue, "strongest" focuses elites, "closest" maximises uptime.

## `weakest` sits directly after `strongest` rather than at the end. The two
## health scorers read as a pair there, and it keeps `closest` last, which is
## what lets next_priority()'s existing wrap test keep passing unchanged.
const PRIORITIES: Array[StringName] = [&"first", &"last", &"strongest", &"weakest", &"closest"]

## The default a freshly placed tower uses, matching pre-upgrade behaviour
## where every tower shot whatever was nearest.
const DEFAULT_PRIORITY := &"closest"

const LABELS := {
	&"first": "First", &"last": "Last",
	&"strongest": "Highest Health", &"weakest": "Lowest Health",
	&"closest": "Closest",
}

static func next_priority(current: StringName) -> StringName:
	var index := PRIORITIES.find(current)
	return PRIORITIES[(index + 1) % PRIORITIES.size()]

## Whether a tower is allowed to shoot a given enemy at all.
static func is_targetable(tower: Dictionary, candidate: Dictionary) -> bool:
	if not candidate.get("alive", true) or candidate.get("dying", false):
		return false
	# Phasing is a hard gate, not a penalty: without detection the enemy
	# simply is not there as far as this tower is concerned.
	if candidate.get("phased", false) and not tower.get("detection", false):
		return false
	var d: float = tower["position"].distance_to(candidate["position"])
	return d <= float(tower["range"])

## Picks a target, or null when nothing is eligible. Ties break on lowest id,
## so the result never depends on iteration order.
static func select(tower: Dictionary, candidates: Array):
	var best = null
	var best_score := 0.0

	for candidate in candidates:
		if not is_targetable(tower, candidate):
			continue
		var score := _score_for(tower, candidate)
		# Strict equality, not is_equal_approx: an approximate-tolerance
		# tie-break would let a genuinely-closer candidate lose to a
		# genuinely-farther one whenever their scores land within the
		# tolerance window without being equal, which is reachable in
		# practice (movement.gd accumulates position via continuous float
		# arithmetic every tick) and would make selection order-dependent -
		# the exact bug this tie-break exists to prevent. Matches
		# targeting.ts's `score === bestScore` exactly.
		if best == null or score > best_score \
				or (score == best_score and int(candidate["id"]) < int(best["id"])):
			best = candidate
			best_score = score

	return best

static func _score_for(tower: Dictionary, candidate: Dictionary) -> float:
	match tower["priority"]:
		&"first":
			return float(candidate["path_index"])
		&"last":
			return -float(candidate["path_index"])
		&"strongest":
			return float(candidate["health"])
		&"weakest":
			return -float(candidate["health"])
		_:
			return -tower["position"].distance_to(candidate["position"])
