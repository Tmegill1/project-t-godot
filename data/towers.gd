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

const DEFS := {
	&"basic": {
		"label": "Basic", "damage_type": &"physical", "cost": 20, "cost_escalation": 10, "range": 100.0,
		"fire_rate": 1000.0, "damage": 4, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0x66, 0xff),
		"size": 0.8, "sprite_frame": 8, "upgrade_frames": [8, 9, 11, 17],
		"base_limit": 8, "limit_bonus_map2": 2,
	},
	&"fast": {
		"label": "Magic", "damage_type": &"magic", "cost": 50, "cost_escalation": 15, "range": 80.0,
		"fire_rate": 500.0, "damage": 2, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0x00, 0xff, 0x00),
		"size": 0.75, "sprite_frame": 5, "upgrade_frames": [5, 6, 12, 13],
		"base_limit": 8, "limit_bonus_map2": 2,
	},
	&"mortar": {
		"label": "Mortar", "damage_type": &"physical", "cost": 70, "cost_escalation": 35, "range": 120.0,
		"fire_rate": 2000.0, "damage": 5, "pierce": 0, "detection": false,
		"base_splash_radius": 55.0, "projectile_speed": 350.0,
		"projectile_arcs": true, "color": Color8(0xb0, 0x7a, 0x3a),
		"size": 0.85, "sprite_frame": 1, "upgrade_frames": [1, 0, 7, 16],
		"base_limit": 5, "limit_bonus_map2": 2,
	},
	&"long": {
		"label": "Long Range", "damage_type": &"physical", "cost": 100, "cost_escalation": 50, "range": 150.0,
		"fire_rate": 1500.0, "damage": 15, "pierce": 0, "detection": false,
		"base_splash_radius": 0.0, "projectile_speed": 500.0,
		"projectile_arcs": false, "color": Color8(0xff, 0x66, 0x00),
		"size": 0.85, "sprite_frame": 2, "upgrade_frames": [2, 10, 18, 19],
		"base_limit": 5, "limit_bonus_map2": 2,
	},
}

const KINDS: Array[StringName] = [&"basic", &"fast", &"mortar", &"long"]

static func get_def(kind: StringName) -> Dictionary:
	return DEFS[kind]
