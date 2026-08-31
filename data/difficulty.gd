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
	## RE-SWEPT 2026-08-31 against A PLAYER WHO HAS TO BUILD, which is the thing
	## every earlier sweep got wrong.
	##
	## Both previous sweeps measured a COMPLETED, fully-maxed twelve-tower board.
	## Measured against a player who starts with two towers and buys as they can
	## afford, the shipped rows were not hard - they were unplayable: Hard and
	## Nightmare both killed that player on WAVE 3, of twenty, on the easiest
	## map. Neither ramping the tier in, nor more lives, nor more gold, nor a
	## larger opening purse moved it past wave 14:
	##
	##   lever tried                       spending player on Hard
	##   as shipped (2.35 health)          dies wave 3
	##   20 lives instead of 15            dies wave 3
	##   400 starting gold                 dies wave 8
	##   +25% income                       dies wave 9
	##   tier ramped in over 10 waves      dies wave 8
	##   tier ramped over 30 (never full)  dies wave 14
	##
	## The cause is not the tier. A fully-maxed board is roughly TEN TIMES a
	## full-but-unupgraded one, and the tier is a single curve across a run in
	## which the player's board spans that range. No flat multiplier is gentle
	## at wave 3 and meaningful at wave 20, and no ramp bridges it either.
	##
	## OWNER'S DECISION (2026-08-31): put the difficulty in the BUILD-OUT, which
	## is where measurement says the run is actually decided - a maxed board
	## took zero damage at every setting tried, on every tier. These rows are
	## therefore swept against the spending player, and they make a ladder:
	##
	##   Normal     survives with 13 of 20 lives
	##   Hard       survives with  7 of 15
	##   Nightmare  dies on wave 13 of 20
	##
	## The simulated player is a FLOOR, not a ceiling - it buys the cheapest
	## legal thing, never sells, never re-places, and never calls a wave early.
	## A good player should finish Nightmare; this one should not.
	##
	## What this costs, stated because it was a real trade: a fully maxed board
	## now wins every tier without losing a life. The assertions that used to
	## forbid that are gone from test_balance_tuning.gd, with the reasoning in
	## their place. Difficulty lives in the build-out now, not in the endgame.
	&"hard": {
		## A spending player finishes with 7 of 15 lives, against 13 of 20 on
		## Normal - pressed the whole way without the run ever being lost.
		"label": "Hard",
		"count_multiplier": 1.00,
		"interval_multiplier": 1.00,
		"health_multiplier": 1.30,
		"speed_multiplier": 1.10,
		"gold_multiplier": 0.90,
		"starting_lives": 15,
	},
	&"nightmare": {
		## A spending player dies on wave 13 of 20. That player is a floor - it
		## buys the cheapest legal thing and never calls a wave early - so the
		## tier is meant to be finishable by someone playing well, and by nobody
		## playing carelessly.
		"label": "Nightmare",
		"count_multiplier": 1.00,
		"interval_multiplier": 1.00,
		"health_multiplier": 1.35,
		"speed_multiplier": 1.10,
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
