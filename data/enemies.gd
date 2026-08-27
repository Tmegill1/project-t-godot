class_name Enemies

## The kind keys name WHAT THE ART DRAWS.
##
## They used to say slime and bee while the sprites drew a goblin with a knife
## and a bat - verified by rendering them - so every reader had to carry a
## translation table in their head, and the wave tables read as a bestiary that
## did not exist. The names are the art's now.
##
## The keys are load-bearing beyond this file: they pick the sprite directory
## (assets/art/enemies/<kind>/), the death sound (death-<kind>), and the join
## to every wave composition. Renaming one means moving the art, renaming the
## audio, and updating AudioManager.SOUNDS together - see the commit that did
## it for the full set.

## walk_frames and death_frames replaced variant_count when the enemy art
## became drawn animation rather than a set of per-spawn variants. The first
## sheet's rows were fifteen different goblins, not one goblin walking -
## measured twice - so variety was all it could offer; this one is the other
## way round, and the owner chose animation over variety knowingly.
##
## sprite_px is a displayed HEIGHT, not a scale factor. It replaced
## sprite_scale, which only made sense against Kenney's uniform 48x48
## animation frames: the illustrated variants are not a uniform size (goblins
## 54-69 x 50-54, ogres 71-80 x 67-76, bats 94-105 x 41-47), so a fixed factor
## drew the same kind at a different size from one spawn to the next. The
## values preserve the sizes the Kenney art drew at - 33.6, 57.6 and 33.6px -
## except the bat, which is naturally wide and is given a little less height
## so it does not out-mass the tanky kind.
##
## flip_horizontally is false for all three because all three faces on this
## sheet point right. It stays in the table because it is a property of the
## ART, and the next sheet may not agree with this one.
##
## stride_px is how far a creature travels per complete stride, so it sets the
## SPATIAL frequency of the run cycle while the creature's own speed sets the
## temporal one. That is why it is not a rate: the bat's wings beat far faster
## than its body advances, so its stride is short, and the ogre lumbers, so its
## stride is long.
##
## The bat's stride_px was retuned from an initial guess of 14.0 to 32.0 (see
## Enemy.stride_phase's doc comment and the run motion task's report): at
## 14.0 and the bat's own 150px/s, _physics_process's fixed 1/60s tick covers
## more than a third of the sine's half-period every frame, so the bob/squash/
## lean sampled a fast-moving wave far below the rate needed to read as
## motion - watching it live showed the whole sprite buzzing rather than
## flying, not a faster version of the same cycle the other kinds show. 32.0
## keeps the bat's cycle visibly quicker than the goblin's (about 9.4 footfalls
## a second against 6.7) while sampling it densely enough per frame to read as
## a cycle rather than noise.
## Health descends ogre > shaman > goblin > bat and speed is its exact
## inverse, so every creature trades one for the other and no kind is strictly
## better than another. test_data_tables.gd pins the ORDERING as well as the
## values - and the ordering after wave scaling too, since the modifiers are
## applied per kind and a scaled roster could in principle cross over.
const DEFS := {
	&"goblin": {
		"label": "Goblin", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "walk_frames": 8, "death_frames": 4, "sprite_px": 34.0,
		"stride_px": 30.0, "flip_horizontally": false,
		"armor": 0, "shield": 0,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 55.0, "base_health": 10, "reward": 20,
		"life_loss": 5, "walk_frames": 8, "death_frames": 4, "sprite_px": 58.0,
		"stride_px": 46.0, "flip_horizontally": false,
		"armor": 2, "shield": 0,
	},
	# The support caster. Its health and speed sit between the goblin's and the
	# ogre's, matching its place in the roster; sprite_px is 44 because its
	# source art is 112px tall against the goblin's 89, so drawing it at the
	# goblin's 34 would make the taller creature render smaller.
	&"shaman": {
		"label": "Goblin Shaman", "base_speed": 80.0, "base_health": 7, "reward": 15,
		"life_loss": 3, "walk_frames": 8, "death_frames": 4, "sprite_px": 44.0,
		"stride_px": 36.0, "flip_horizontally": false,
		"armor": 0, "shield": 1,
	},
	# BOSS ONLY - deliberately absent from KINDS, which is what wave
	# composition iterates. Its per-spawn numbers come from data/bosses.gd;
	# what lives here is the art and the animation the renderer needs.
	&"troll": {
		"label": "Troll", "base_speed": 45.0, "base_health": 220, "reward": 150,
		"life_loss": 5, "walk_frames": 8, "death_frames": 4, "sprite_px": 62.0,
		"stride_px": 50.0, "flip_horizontally": false,
		"armor": 6, "shield": 0,
	},
	&"bat": {
		"label": "Bat", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "walk_frames": 7, "death_frames": 4, "sprite_px": 28.0,
		"stride_px": 32.0, "flip_horizontally": false,
		"armor": 0, "shield": 1,
	},
}

## Not ordered by anything meaningful - callers iterate it to cover every
## kind, never to rank them. The roster's ordering by health lives in
## test_data_tables.gd, which asserts it directly.
const KINDS: Array[StringName] = [&"goblin", &"ogre", &"bat", &"shaman"]

## Health for a spawn, applying the wave modifier. Floors, never below one.
static func scaled_health(kind: StringName, health_modifier: float) -> int:
	return maxi(1, int(floor(float(DEFS[kind]["base_health"]) * health_modifier)))

## Speed for a spawn, applying the wave modifier. Unrounded, never below one.
static func scaled_speed(kind: StringName, speed_modifier: float) -> float:
	return maxf(1.0, float(DEFS[kind]["base_speed"]) * speed_modifier)

## How many frames each animation holds. Baked by tools/bake_sheet.gd and
## pinned by test_enemy.gd against the files on disk, so a re-bake that
## produces a different number cannot silently leave this table pointing at a
## frame that is not there.
##
## The bat's walk is SEVEN where the others are eight: its eighth frame came
## off the sheet as an orphaned wing with no body, and the bake drops broken
## art on area rather than on index.
static func walk_frames(kind: StringName) -> int:
	return int(DEFS[kind]["walk_frames"])

static func death_frames(kind: StringName) -> int:
	return int(DEFS[kind]["death_frames"])


# --- Resistance -----------------------------------------------------------

## The wave from which resistance starts SCALING.
##
## Not wave 1: armour on the first goblin a new player meets teaches nothing
## except that their tower is broken. The early game is where the base rules
## are learned, so resistance grows once they are. A kind's base value from
## DEFS still applies from wave 1 - this gates the growth, not the property.
const RESISTANCE_ONSET_WAVE := 8

## Armour added per wave past the onset, on kinds that carry armour at all.
## Measured. Was 0.6, alongside PIERCE_PER_TIER of 2 - and that pairing had
## erased armour entirely: a maxed Basic dealt exactly as much to a wave-20
## ogre as to an unarmoured goblin, because six tiers of levelling bought more
## pierce than the ogre had armour.
##
## At 1.0 against PIERCE_PER_TIER of 1, each tower gets a distinct relationship
## to armour at wave 20: Basic 67% through, Mortar 84%, Magic 15% (the floor -
## magic is the shield answer, not the armour one), and Long Range 100%,
## because its own pierce tiers are what make it the armour specialist.
const ARMOR_PER_WAVE := 1.0

## How many waves apart each additional shield charge lands. Shields STEP
## rather than scale, because half a charge absorbs nothing - the whole point
## of a charge is that it eats one hit regardless of size.
const WAVES_PER_SHIELD_CHARGE := 6

## Armour and shields for a spawn of this kind at this wave.
##
## Scaling never GRANTS what a kind lacks: a 0 in the table stays 0 forever.
## That is what keeps the goblin a control, and what keeps armour and shields
## answering different towers instead of blurring into general toughness.
static func resistance_for(kind: StringName, wave: int) -> Dictionary:
	var def: Dictionary = DEFS[kind]
	var base_armor := int(def.get("armor", 0))
	var base_shield := int(def.get("shield", 0))
	var past: int = maxi(0, wave - RESISTANCE_ONSET_WAVE)
	return {
		"armor": 0 if base_armor <= 0 else base_armor + int(floor(float(past) * ARMOR_PER_WAVE)),
		"shield": 0 if base_shield <= 0 else base_shield + int(past / WAVES_PER_SHIELD_CHARGE),
	}
