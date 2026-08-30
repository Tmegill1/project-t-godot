class_name Difficulty

## Difficulty tiers. Pure data, like the rest of data/.
##
## Difficulty is a PARAMETER in this project, never a global. Waves and the
## harness take a tier argument; nothing reads a mutable singleton. That is
## what keeps sim/ pure and keeps Harness.run_wave's guarantee - same input,
## same result - which is the property every balance claim here rests on.
##
## Normal is the exact identity transform. Every measured number in this
## project describes Normal, so the existing suite doubles as the regression
## net for this file: if a Normal multiplier drifts, something else fails.

const NORMAL := &"normal"
const HARD := &"hard"
const NIGHTMARE := &"nightmare"

## Easiest first. Task 2's monotonicity test walks this in order.
const ORDER: Array[StringName] = [NORMAL, HARD, NIGHTMARE]

## The multiplier keys, as distinct from starting_lives (an int) and label
## (a string). Tests iterate this rather than restating the list.
const KEYS: Array[StringName] = [
	&"count_multiplier",
	&"interval_multiplier",
	&"health_multiplier",
	&"speed_multiplier",
	&"gold_multiplier",
]

## Which lever attacks what, and why these and not others:
##
##   interval_multiplier  spawn spacing, so CONCURRENCY. The sharpest lever
##                        available. Measurement established that board
##                        COVERAGE binds, not hit points; halving the interval
##                        doubles the crowd one tower must cover without
##                        touching a single enemy stat.
##   count_multiplier     enemies per wave. Same constraint, blunter, and it
##                        compounds with the accumulating composition.
##   health_multiplier    hit points. Proven WEAK ALONE - wave-20 health x11.5
##                        leaked zero against a maxed board - but real in
##                        combination, because it lengthens the window during
##                        which concurrency matters.
##   speed_multiplier     time under fire. The other side of coverage: less
##                        time in range is the same as less range.
##   gold_multiplier      the board a player can afford. Indirect, strong.
##   starting_lives       forgiveness. The only lever a player feels at once.
##
## SMALLER is harsher for interval_multiplier and gold_multiplier. Larger is
## harsher for the other three. The monotonicity test encodes both directions.
const DEFS := {
	&"normal": {
		"label": "Normal",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 1.0,
		"speed_multiplier": 1.0,
		"gold_multiplier": 1.0,
		"starting_lives": Economy.STARTING_LIVES,
	},
	## Measured 2026-08-30 with probe_tiers.gd, against the full legal roster -
	## three of each kind, twelve towers, every tier the cross-path rule allows -
	## on The Pass, all twenty waves. Task 1 established that board is
	## affordable (16,199 gold of income against an 11,415 cost), so it is the
	## board these are set against rather than something smaller.
	##
	## What the sweep found, and it is the reason these two rows sit so close
	## together: the full board is a WALL, and it fails as one. Every lever
	## combination either holds a wave completely or collapses on it - there is
	## almost no middle. Full-board lives lost across a run, by row:
	##
	##   count/interval/health/speed/gold   lives lost   first leak
	##   1.00 1.00 1.00 1.00 1.00 (Normal)           0   never
	##   1.15 0.85 1.15 1.05 0.95                    1   wave 20
	##   1.30 0.70 1.30 1.10 0.90 (Hard)            11   wave 20
	##   1.40 0.60 1.40 1.15 0.85 (Nightmare)       46   wave 17
	##   1.50 0.55 1.50 1.15 0.82                   87   wave 16
	##   2.00 0.40 2.00 1.30 0.70                  720   wave 13
	##
	## Ten points of multiplier between Hard and Nightmare is the difference
	## between losing eleven lives and losing forty-six. That cliff is the
	## coverage finding restated: a board either covers the crowd or it does
	## not, and hit points only decide which side of the line a wave lands on.
	&"hard": {
		"label": "Hard",
		## Hard's brief is "real lives late, without ending the run". The full
		## board loses 11 of its 15 lives, all on wave 20, and finishes with 4.
		## The teeth are aimed at the board a player actually has: the six-tower
		## mid-run board loses 110 lives across a Normal run and 639 across this
		## one.
		"count_multiplier": 1.30,
		"interval_multiplier": 0.70,
		"health_multiplier": 1.30,
		"speed_multiplier": 1.10,
		"gold_multiplier": 0.90,
		"starting_lives": 15,
	},
	&"nightmare": {
		## Nightmare's brief is that a full maxed board must NOT shut it out.
		## It does not: leaks start at wave 17 and wave 20 alone costs 36 lives.
		## Cumulative loss through wave 19 is exactly 10, so a twelve-life board
		## reaches the final wave and dies on it.
		##
		## Stated plainly rather than hidden: the benchmark board LOSES this
		## tier. Whether a human finds a better one is a playtest question, not
		## a measured one - the harness resolves hits instantly, with no
		## projectile travel time, so it is kinder to the player than the live
		## board is. These are a starting point to be played, per the spec's own
		## risk section, not a finished tuning.
		"label": "Nightmare",
		"count_multiplier": 1.40,
		"interval_multiplier": 0.60,
		"health_multiplier": 1.40,
		"speed_multiplier": 1.15,
		"gold_multiplier": 0.85,
		"starting_lives": 12,
	},
}

static func get_def(tier: StringName) -> Dictionary:
	return DEFS[tier]

static func multiplier(tier: StringName, key: StringName) -> float:
	return float(DEFS[tier][key])

static func starting_lives(tier: StringName) -> int:
	return int(DEFS[tier]["starting_lives"])

static func label(tier: StringName) -> String:
	return String(DEFS[tier]["label"])

## Whether a tier name is one this table knows. Callers that read a tier from
## outside the table - a saved run, a menu, a harness config - use this rather
## than indexing DEFS and crashing on a typo.
static func is_valid(tier: StringName) -> bool:
	return DEFS.has(tier)
