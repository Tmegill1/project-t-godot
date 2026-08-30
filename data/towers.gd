class_name Towers

## The `fast` key is a JOIN, not a name. It ties this table to Upgrades.DEFS,
## to the `fire-fast` audio event, to the sprite lookup and to every test that
## names a kind. The tower the player sees is called "Magic", which lives in
## the `label` field - the only one of the two a player ever reads. Renaming
## the key would be a rename across five files for no visible gain.
##
## DELIBERATE DIVERGENCE from the Phaser reference, the fourth this port
## carries: Fast and Mortar have swapped sprite_frame and upgrade_frames,
## because they were wearing each other's art. Measured by cropping
## assets/towers.png - frames 1/0/7/16 draw a CANNON and 5/6/12/13 draw
## CRYSTALS, and upstream had the cannon on the rapid-fire tower and the
## crystals on the artillery piece. No stat, cost, range or rate moved with
## them; test_data_tables.gd pins that separately.

## COSTS AND ESCALATION were re-measured on 2026-08-30, and they are pacing
## numbers rather than power numbers - no stat moved with them.
##
## The finding that produced them: a player who simply buys the cheapest legal
## thing whenever they can afford it used to fill the entire twelve-tower budget
## by WAVE 7 of 20, max every tier by 18, lose one life all run, and finish with
## 5,488 gold that had nothing left to buy. Two-thirds of a run had no placement
## decision left in it and money had stopped meaning anything.
##
## Placing the whole board cost 1,050 gold against a run's ~16,200 of income, so
## the purse was never the constraint - the price of a board was. Escalation
## carries most of the increase rather than base cost, so the FIRST of each kind
## stays reachable and the opening can still build; it is the second and third
## that now have to be earned.
##
## Measured against that same greedy player, on The Pass:
##
##   basic/fast/mortar/long        board full   maxed   lives   gold left
##   20+10  50+15  70+35  100+50        wave 7      18      19       5,488
##   20+40  50+60  70+120 100+180      wave 10      18      18       4,757
##   25+60  60+90  85+170 120+250      wave 11      19      16       3,978
##   35+100 80+150 115+270 165+400     wave 13      20      10       2,532
##   40+150 90+220 130+350 180+500     DEAD on wave 15
##
## test_affordability.gd holds the bound this has to keep meeting.
const DEFS := {
	&"basic": {
		"label": "Basic", "damage_type": &"physical", "cost": 35, "cost_escalation": 100, "range": 100.0,
		"fire_rate": 1000.0, "damage": 4, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0x66, 0xff),
		"size": 0.8, "sprite_frame": 8, "upgrade_frames": [8, 9, 11, 17],
		"base_limit": 3, "limit_bonus_map2": 0,
	},
	&"fast": {
		"label": "Magic", "damage_type": &"magic", "cost": 80, "cost_escalation": 150, "range": 80.0,
		"fire_rate": 500.0, "damage": 2, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0xff, 0x00),
		"size": 0.75, "sprite_frame": 5, "upgrade_frames": [5, 6, 12, 13],
		"base_limit": 3, "limit_bonus_map2": 0,
	},
	&"mortar": {
		"label": "Mortar", "damage_type": &"physical", "cost": 115, "cost_escalation": 270, "range": 120.0,
		"fire_rate": 2000.0, "damage": 5, "pierce": 0, "detection": false,
		"base_splash_radius": 55.0, "projectile_speed": 350.0,
		"projectile_arcs": true, "color": Color8(0xb0, 0x7a, 0x3a),
		"size": 0.85, "sprite_frame": 1, "upgrade_frames": [1, 0, 7, 16],
		"base_limit": 3, "limit_bonus_map2": 0,
	},
	&"long": {
		"label": "Long Range", "damage_type": &"physical", "cost": 165, "cost_escalation": 400, "range": 150.0,
		"fire_rate": 1500.0, "damage": 15, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0xff, 0x66, 0x00),
		"size": 0.85, "sprite_frame": 2, "upgrade_frames": [2, 10, 18, 19],
		"base_limit": 3, "limit_bonus_map2": 0,
	},
}

const KINDS: Array[StringName] = [&"basic", &"fast", &"mortar", &"long"]

static func get_def(kind: StringName) -> Dictionary:
	return DEFS[kind]
