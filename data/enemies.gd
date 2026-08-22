class_name Enemies

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
## keeps the bat's cycle visibly quicker than the slime's (about 9.4 footfalls
## a second against 6.7) while sampling it densely enough per frame to read as
## a cycle rather than noise.
const DEFS := {
	&"slime": {
		"label": "Slime", "base_speed": 100.0, "base_health": 5, "reward": 5,
		"life_loss": 1, "variant_count": 15, "sprite_px": 34.0,
		"stride_px": 30.0, "flip_horizontally": false,
	},
	&"ogre": {
		"label": "Ogre", "base_speed": 60.0, "base_health": 8, "reward": 20,
		"life_loss": 5, "variant_count": 13, "sprite_px": 58.0,
		"stride_px": 46.0, "flip_horizontally": false,
	},
	&"bee": {
		"label": "Bee", "base_speed": 150.0, "base_health": 3, "reward": 10,
		"life_loss": 2, "variant_count": 3, "sprite_px": 28.0,
		"stride_px": 32.0, "flip_horizontally": false,
	},
}

const KINDS: Array[StringName] = [&"slime", &"ogre", &"bee"]

## Health for a spawn, applying the wave modifier. Floors, never below one.
static func scaled_health(kind: StringName, health_modifier: float) -> int:
	return maxi(1, int(floor(float(DEFS[kind]["base_health"]) * health_modifier)))

## Speed for a spawn, applying the wave modifier. Unrounded, never below one.
static func scaled_speed(kind: StringName, speed_modifier: float) -> float:
	return maxf(1.0, float(DEFS[kind]["base_speed"]) * speed_modifier)

## How many per-spawn variants this kind's art directory holds. Baked by
## tools/bake_sheet.gd; pinned by test_enemy.gd against the files on disk, so a
## re-bake that produces a different number cannot silently leave this table
## pointing at a variant that is not there.
static func variant_count(kind: StringName) -> int:
	return int(DEFS[kind]["variant_count"])
