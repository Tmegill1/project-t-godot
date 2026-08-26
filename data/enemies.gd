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
const DEFS := {
	&"goblin": {
		"label": "Goblin", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "walk_frames": 8, "death_frames": 4, "sprite_px": 34.0,
		"stride_px": 30.0, "flip_horizontally": false,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 60.0, "base_health": 8, "reward": 20,
		"life_loss": 5, "walk_frames": 8, "death_frames": 4, "sprite_px": 58.0,
		"stride_px": 46.0, "flip_horizontally": false,
	},
	&"bat": {
		"label": "Bat", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "walk_frames": 7, "death_frames": 4, "sprite_px": 28.0,
		"stride_px": 32.0, "flip_horizontally": false,
	},
}

const KINDS: Array[StringName] = [&"goblin", &"ogre", &"bat"]

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
