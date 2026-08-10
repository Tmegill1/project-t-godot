class_name Waves

## Wave composition, difficulty scaling, and spawn scheduling.
##
## Composition ACCUMULATES: a wave's contents are the sum of the additions
## table from wave 1 up to it, so wave 3 contains waves 1 and 2 as well.
## That is how the game has always behaved.

const MAX_WAVES := 20
const LAST_AUTHORED_WAVE := 5

const _ADDITIONS := {
	1: [{"kind": &"slime", "count": 5}],
	2: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}],
	3: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}],
	4: [{"kind": &"ogre", "count": 2}],
	5: [{"kind": &"slime", "count": 3}, {"kind": &"bee", "count": 3}, {"kind": &"ogre", "count": 1}],
}

const _ENDLESS_BUNDLE := [
	{"kind": &"slime", "count": 2},
	{"kind": &"bee", "count": 5},
	{"kind": &"ogre", "count": 2},
]

const HEALTH_PER_WAVE := 0.1
const SPEED_PER_WAVE := 0.05

const INTERVAL_MS := 500.0
const BEE_START_DELAY_MS := 5000.0
const OGRE_DELAY_AFTER_LAST_SLIME_MS := 3000.0
const OGRE_MAX_START_DELAY_MS := 10000.0

## Enemy counts for a wave, accumulated from wave 1. Returns fresh
## dictionaries on every call so a caller cannot corrupt later waves.
static func get_composition(wave_number: int) -> Array[Dictionary]:
	var composition: Array[Dictionary] = []

	var authored_through: int = mini(wave_number, LAST_AUTHORED_WAVE)
	for wave in range(1, authored_through + 1):
		if _ADDITIONS.has(wave):
			for entry in _ADDITIONS[wave]:
				_add(composition, entry)

	var endless: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	for i in endless:
		for entry in _ENDLESS_BUNDLE:
			_add(composition, entry)

	return composition

static func _add(composition: Array[Dictionary], entry: Dictionary) -> void:
	for existing in composition:
		if existing["kind"] == entry["kind"]:
			existing["count"] += entry["count"]
			return
	composition.append({"kind": entry["kind"], "count": entry["count"]})

## Health and speed multipliers. Both are 1.0 through wave 5.
static func get_modifiers(wave_number: int) -> Dictionary:
	var past: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	return {
		"health_modifier": 1.0 + float(past) * HEALTH_PER_WAVE,
		"speed_modifier": 1.0 + float(past) * SPEED_PER_WAVE,
	}

## When the ogre column starts, given how many slimes precede it. Ogres trail
## the last slime by three seconds but never wait more than ten.
static func ogre_spawn_delay(slime_count: int) -> float:
	var last_slime_at := float(slime_count - 1) * INTERVAL_MS
	return minf(last_slime_at + OGRE_DELAY_AFTER_LAST_SLIME_MS, OGRE_MAX_START_DELAY_MS)

## Spawn instants for a wave, mirroring GameScene.startWave's offsets.
##
## Public (not a private helper on Harness) because Task 19's live game board
## needs the exact same schedule the headless harness uses — one
## implementation, two callers, so the board can never spawn on a schedule
## the harness didn't also simulate.
static func build_schedule(wave: int) -> Array:
	var schedule: Array = []
	var composition := get_composition(wave)

	var slime_count := 0
	for entry in composition:
		if entry["kind"] == &"slime":
			slime_count = entry["count"]

	for entry in composition:
		var kind: StringName = entry["kind"]
		var start := 0.0
		match kind:
			&"bee":
				start = BEE_START_DELAY_MS
			&"ogre":
				start = ogre_spawn_delay(slime_count)
			_:
				start = 0.0
		for i in entry["count"]:
			schedule.append({"kind": kind, "at_ms": start + float(i) * INTERVAL_MS})

	schedule.sort_custom(func(a, b): return a["at_ms"] < b["at_ms"])
	return schedule
