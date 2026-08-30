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

## Which lever attacks what. RE-MEASURED 2026-08-30, and the first reading was
## wrong in a way worth recording rather than quietly overwriting.
##
## The original table called interval_multiplier "the sharpest lever available"
## and health "proven weak alone", reasoning from an earlier finding that board
## COVERAGE binds rather than hit points. Against a full twelve-tower board that
## is backwards. Count and interval both raise enemy DENSITY, and the sustained
## upgrade branch grants splash - 45px, then 75px - whose value scales with
## density. So the two levers picked to attack coverage are exactly the ones a
## splash build answers best, and eleven of the sixteen legal maxed boards shut
## the old Nightmare row out completely.
##
##   health_multiplier    hit points, and the lever that actually bites. Splash
##                        kills a cluster in one hit however many are in it;
##                        what it cannot do is kill something twice.
##   speed_multiplier     time under fire, and a THRESHOLD rather than a dial.
##                        Below 1.40 the strongest legal board leaks nothing at
##                        all, at any health up to 4.0. At 1.40 it starts to
##                        bleed. Less time in range is the same as less range,
##                        and no upgrade branch answers it.
##   count_multiplier     enemies per wave. Held at 1.0 deliberately: raising it
##                        WIDENS the gap between a splash build and one without,
##                        punishing the weaker build and feeding the stronger.
##   interval_multiplier  spawn spacing, so concurrency. Held at 1.0 for the
##                        same reason. Both are left in the table because they
##                        are the right levers for a mid-run board and the wrong
##                        ones for a completed board, and a later tier may want
##                        them back.
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
	## RE-SWEPT 2026-08-30, after area damage went back to the Mortar. The rows
	## before this one were measured against boards carrying splash on three
	## towers; that board does not exist any more, and against the roster that
	## replaced it those rows cost the best board over two hundred lives.
	##
	## Measured against every legal fully-upgraded board rather than a named
	## one. The cross-path rule allows two maxed splits per tower and a board
	## picks one per kind, so "the best board" is a thing you find, not a thing
	## you name - it used to be all-sustained and is now whichever mix the sweep
	## reports.
	##
	## Best board's lives lost on wave 20, and how many of the sixteen boards
	## shut the wave out entirely:
	##
	##   health/speed        best board   boards with ZERO leaks
	##   1.30 1.10                    0                       15
	##   1.60 1.20                    0                       13
	##   2.00 1.25                    0                        5
	##   2.25 1.30                    0                        2
	##   2.35 1.30 (Hard)             5                        0
	##   2.50 1.30 (Nightmare)       10                        0
	##   2.75 1.35                   14                        0
	##
	## The threshold where the last board stops shutting the wave out sits
	## between 2.25 and 2.35, and both tiers are set just past it. Count and
	## interval stay at 1.0 for the reason above: the Mortar still splashes, and
	## density is what splash is for.
	&"hard": {
		## The best legal board loses 5 of its 15 lives, on wave 20, and
		## finishes with 10: real lives late without ending the run.
		"label": "Hard",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 2.35,
		"speed_multiplier": 1.30,
		"gold_multiplier": 0.90,
		"starting_lives": 15,
	},
	&"nightmare": {
		## Every one of the sixteen legal boards leaks on wave 20, and the best
		## of them loses 10 of its 12 lives across a run - it survives with two.
		## Beatable, and only by the best build there is.
		"label": "Nightmare",
		"count_multiplier": 1.0,
		"interval_multiplier": 1.0,
		"health_multiplier": 2.50,
		"speed_multiplier": 1.30,
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
