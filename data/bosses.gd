class_name Bosses

## Which waves carry a boss, and what it is.
##
## A TABLE rather than special cases in Waves, so waves 30 and 40 in endless
## play - and any new sprite the owner drops in later - are data entry rather
## than code.
##
## A boss is an ORDINARY ENEMY WITH DIFFERENT NUMBERS. It moves with
## sim/movement.gd, is targeted by sim/targeting.gd, takes damage through
## sim/damage.gd and leaks through sim/leak.gd exactly as everything else
## does. Every field below is one the ordinary spawn pipeline already reads;
## anything that would need a special case in those modules does not belong
## here.
##
## Both bosses are trolls because the troll is the largest creature the
## illustrated sheet carries and it was otherwise unused. `display_scale`
## separates them visually and is a RENDER field - no rule reads it, the same
## separation Tower.DISPLAY_SCALE already keeps from Placement.tower_radius.
##
## The numbers are unplaytested placeholders, like the rest of data/. The
## measurement pass owns them.

const WAVES: Array[int] = [10, 20]

const DEFS := {
	10: {
		"kind": &"troll", "label": "Troll Chieftain",
		"health": 220, "speed": 45.0, "armor": 6, "shield": 0,
		"reward": 150, "display_scale": 1.6,
	},
	# The run's final fight. Health well past twice the first boss's, armour
	# heavy enough that only pierce or the largest per-hit damage in the game
	# gets through cleanly, and drawn half again as large so it reads as worse
	# from the moment it appears.
	20: {
		"kind": &"troll", "label": "Troll Warlord",
		"health": 900, "speed": 40.0, "armor": 14, "shield": 0,
		"reward": 500, "display_scale": 2.2,
	},
}

## The boss for a wave, or an empty dictionary when there is none.
##
## Returns a deep copy: the caller overrides spawn stats from it, and a
## caller editing the table would change every later run in the session.
static func on_wave(wave: int) -> Dictionary:
	if not DEFS.has(wave):
		return {}
	return (DEFS[wave] as Dictionary).duplicate(true)

static func has_boss(wave: int) -> bool:
	return DEFS.has(wave)
