class_name Waves

## Wave composition, difficulty scaling, and spawn scheduling.
##
## Composition ACCUMULATES: a wave's contents are the sum of the additions
## table from wave 1 up to it, so wave 3 contains waves 1 and 2 as well.
## That is how the game has always behaved.

const MAX_WAVES := 20
const LAST_AUTHORED_WAVE := 5

const _ADDITIONS := {
	1: [{"kind": &"goblin", "count": 5}],
	2: [{"kind": &"goblin", "count": 3}, {"kind": &"bat", "count": 3}],
	3: [{"kind": &"goblin", "count": 3}, {"kind": &"bat", "count": 3}],
	4: [{"kind": &"ogre", "count": 2}],
	5: [{"kind": &"goblin", "count": 3}, {"kind": &"bat", "count": 3}, {"kind": &"ogre", "count": 1}],
}

## Shamans ride in here rather than in an authored wave, which is what puts
## them from wave 6 onward without moving LAST_AUTHORED_WAVE: `endless` is
## max(0, wave - LAST_AUTHORED_WAVE), so this bundle first contributes at
## wave 6 already. Moving the boundary instead would have shifted the health,
## speed and gold modifier onset and every composition total pinned against
## them, for no gain.
##
## One per bundle, against two goblins and five bats, because a shaman is an
## escort rather than a wave - it is dangerous for what it grants the things
## around it, not for its own numbers.
const _ENDLESS_BUNDLE := [
	{"kind": &"goblin", "count": 2},
	{"kind": &"bat", "count": 5},
	{"kind": &"ogre", "count": 2},
	{"kind": &"shaman", "count": 1},
]

const HEALTH_PER_WAVE := 0.1
const SPEED_PER_WAVE := 0.05

## How much of a kill's reward each wave past LAST_AUTHORED_WAVE removes.
##
## Gold decays where health and speed grow, because the two problems have
## opposite shapes. Composition ACCUMULATES from wave 1, so a late wave fields
## far more enemies than an early one - 161 at wave 20 against 5 at wave 1 -
## and a flat per-kill reward turns that into compounding income. Measured
## before this constant existed: 48% of a run's kill income landed in the last
## five waves and wave 20 paid 68.8x wave 1, which put the money where the
## player had already finished building and their upgrade paths were locked by
## the cross-path rule.
##
## 0.025 was chosen by sweeping decay against the most a player could possibly
## spend (16 towers at the map budget, best mix, every tier the cross-path rule
## allows = 17,170 gold). It brings a full run to 15,780 against that ceiling -
## the same tightness the game shipped with before the wave economy was added -
## while cutting the back-loading ratio to 23.9x. See
## docs/superpowers/specs/2026-08-24-slice-0-design.md section 4.6.
const GOLD_PER_WAVE := 0.025

## Floor under the gold modifier.
##
## A safety rail for endless play, NOT part of the twenty-wave tuning: at wave
## 20 the modifier is 0.625 and this never binds. It exists so a run past
## roughly wave 29 cannot drive a kill reward to zero or negative.
const MIN_GOLD_MODIFIER := 0.40

const INTERVAL_MS := 500.0
const BAT_START_DELAY_MS := 5000.0
const OGRE_DELAY_AFTER_LAST_GOBLIN_MS := 3000.0
const OGRE_MAX_START_DELAY_MS := 10000.0

## How long after the last ordinary spawn the boss walks in.
##
## After, not among: a boss arriving beside the first goblin is a boss nobody
## sees coming, and it would be fought with a board the player has not been
## paid for yet.
const BOSS_DELAY_MS := 4000.0

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

## Health, speed and gold multipliers. All three are 1.0 through wave 5.
##
## Health and speed scale UP with the wave; gold scales DOWN. See
## GOLD_PER_WAVE for why the third one runs the other way.
static func get_modifiers(wave_number: int) -> Dictionary:
	var past: int = maxi(0, wave_number - LAST_AUTHORED_WAVE)
	return {
		"health_modifier": 1.0 + float(past) * HEALTH_PER_WAVE,
		"speed_modifier": 1.0 + float(past) * SPEED_PER_WAVE,
		"gold_modifier": maxf(MIN_GOLD_MODIFIER, 1.0 - float(past) * GOLD_PER_WAVE),
	}

## When the ogre column starts, given how many goblins precede it. Ogres trail
## the last goblin by three seconds but never wait more than ten.
static func ogre_spawn_delay(goblin_count: int) -> float:
	var last_goblin_at := float(goblin_count - 1) * INTERVAL_MS
	return minf(last_goblin_at + OGRE_DELAY_AFTER_LAST_GOBLIN_MS, OGRE_MAX_START_DELAY_MS)

## Spawn instants for a wave, mirroring GameScene.startWave's offsets.
##
## Public (not a private helper on Harness) because Task 19's live game board
## needs the exact same schedule the headless harness uses — one
## implementation, two callers, so the board can never spawn on a schedule
## the harness didn't also simulate.
static func build_schedule(wave: int) -> Array:
	var schedule: Array = []
	var composition := get_composition(wave)

	var goblin_count := 0
	for entry in composition:
		if entry["kind"] == &"goblin":
			goblin_count = entry["count"]

	# Tie-break carries push order (see below) so two entries at the same
	# at_ms sort deterministically instead of depending on whatever ordering
	# Array.sort_custom happens to produce for equal keys — it is not
	# documented as a stable sort on this engine. Ties are not hypothetical:
	# from wave 6 on, goblin/bat/ogre columns land on identical at_ms values
	# (e.g. wave 12 has genuine three-way ties at 10000, 10500, 11000...).
	var push_index := 0
	for entry in composition:
		var kind: StringName = entry["kind"]
		var start := 0.0
		match kind:
			&"bat":
				start = BAT_START_DELAY_MS
			&"ogre":
				start = ogre_spawn_delay(goblin_count)
			_:
				start = 0.0
		for i in entry["count"]:
			schedule.append({
				"kind": kind, "at_ms": start + float(i) * INTERVAL_MS,
				"_push_index": push_index,
			})
			push_index += 1

	# Mirrors the reference (harness.ts): sort by time, then by push order,
	# "so the schedule does not depend on the sort implementation."
	schedule.sort_custom(func(a, b):
		if a["at_ms"] != b["at_ms"]:
			return a["at_ms"] < b["at_ms"]
		return a["_push_index"] < b["_push_index"])

	for entry in schedule:
		entry.erase("_push_index")

	# The boss is appended after the sort, so it lands last however the
	# ordinary columns happen to order themselves.
	if Bosses.has_boss(wave):
		var last_at := 0.0
		for entry in schedule:
			last_at = maxf(last_at, float(entry["at_ms"]))
		schedule.append({
			"kind": Bosses.on_wave(wave)["kind"],
			"at_ms": last_at + BOSS_DELAY_MS,
			"boss": true,
		})

	return schedule
