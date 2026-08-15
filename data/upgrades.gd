class_name Upgrades

## Tower upgrade tiers. Two branches per tower, four tiers each, and a
## cross-path rule (in sim/upgrades.gd) that lets only one branch pass tier 2.
##
##   sustained  rate of fire, splash, slowing  -> clears waves
##   burst      damage per hit, pierce         -> kills elites
##
## Ported from the Phaser build's data/upgrades.ts. Every number is a
## placeholder that has never been playtested, exactly as the rest of data/ is.
##
## Scarce counters sit at tier 3+ deliberately: the cross-path rule hands every
## tower two free tiers of its off-branch, so a counter any cheaper would be
## given to every build for nothing.

const BRANCHES: Array[StringName] = [&"sustained", &"burst"]

const DEFS := {
	&"basic": {
		&"sustained": {
			"label": "Barrage",
			"summary": "Faster fire, then splash damage. Clears crowds and splitters.",
			"tiers": [
				{"label": "Quick Loader", "description": "Fires 20% faster.",
					"cost": 30, "effects": {&"fire_rate_multiplier": 0.8}},
				{"label": "Drum Feed", "description": "Fires 20% faster again.",
					"cost": 60, "effects": {&"fire_rate_multiplier": 0.8}},
				{"label": "Fragmentation", "description": "Shots splash for 45px.",
					"cost": 130, "effects": {&"splash_radius": 45.0, &"fire_rate_multiplier": 0.9}},
				{"label": "Saturation", "description": "Splash grows to 75px and damage rises by half.",
					"cost": 260, "effects": {&"splash_radius": 75.0, &"damage_multiplier": 1.5}},
			],
		},
		&"burst": {
			"label": "Marksman",
			"summary": "Heavier hits, then detection. The only way to see phased enemies.",
			"tiers": [
				{"label": "Heavy Rounds", "description": "Damage up by 40%.",
					"cost": 30, "effects": {&"damage_multiplier": 1.4}},
				{"label": "Rifled Barrel", "description": "Damage up by 40% again.",
					"cost": 65, "effects": {&"damage_multiplier": 1.4}},
				# Dormant marker: detection has working machinery but no target
				# until phased enemies land. Damage stays live so the purchase
				# is not wasted while it is dormant.
				{"label": "Spotter",
					"description": "Reveals and targets phased enemies (no effect yet). Damage up by half.",
					"cost": 145, "effects": {&"detection": true, &"damage_multiplier": 1.5}},
				{"label": "Executioner", "description": "Damage doubles and range extends by a quarter.",
					"cost": 290, "effects": {&"damage_multiplier": 2.0, &"range_multiplier": 1.25}},
			],
		},
	},
	&"fast": {
		&"sustained": {
			"label": "Suppression",
			"summary": "Blistering cadence, then slowing. Answers shields and swiftness.",
			"tiers": [
				{"label": "Hair Trigger", "description": "Fires 25% faster.",
					"cost": 40, "effects": {&"fire_rate_multiplier": 0.75}},
				{"label": "Overclocked", "description": "Fires 25% faster again.",
					"cost": 80, "effects": {&"fire_rate_multiplier": 0.75}},
				{"label": "Cryo Rounds", "description": "Hits slow enemies to 70% speed for 1.5s.",
					"cost": 165, "effects": {&"slow_factor": 0.7, &"slow_duration_ms": 1500}},
				{"label": "Deep Freeze", "description": "Slows to 45% speed for 2.5s and fires 20% faster.",
					"cost": 330, "effects": {&"slow_factor": 0.45, &"slow_duration_ms": 2500, &"fire_rate_multiplier": 0.8}},
			],
		},
		# The income branch. A fast tower farms a great many small kills, so
		# gold per kill is the multiplier that suits it - and it gives the
		# player a reason to build economy rather than only defence.
		&"burst": {
			"label": "Bounty Hunter",
			"summary": "Turns volume of kills into gold. The economy branch.",
			"tiers": [
				{"label": "Machined Rounds", "description": "Damage up by half.",
					"cost": 40, "effects": {&"damage_multiplier": 1.5}},
				{"label": "Scavenger", "description": "Kills pay 1 extra gold.",
					"cost": 85, "effects": {&"bonus_gold_per_kill": 1}},
				{"label": "Bounty Board", "description": "Kills pay 60% more gold, and damage rises by 40%.",
					"cost": 175, "effects": {&"gold_multiplier": 1.6, &"damage_multiplier": 1.4}},
				{"label": "War Profiteer", "description": "Kills pay double gold, plus 2 extra each.",
					"cost": 350, "effects": {&"gold_multiplier": 2.0, &"bonus_gold_per_kill": 2}},
			],
		},
	},
	# The area specialist. Both branches widen or deepen area damage rather
	# than reaching for pierce, detection or slowing - those belong to the
	# other three, and a tower that could take them would answer everything.
	&"mortar": {
		&"sustained": {
			"label": "Saturation",
			"summary": "Wider blasts, fired faster. Buries splitters and packed waves.",
			"tiers": [
				{"label": "Wide Bore", "description": "Blast radius grows to 70px.",
					"cost": 50, "effects": {&"splash_radius": 70.0}},
				{"label": "Quick Crew", "description": "Fires 25% faster.",
					"cost": 100, "effects": {&"fire_rate_multiplier": 0.75}},
				{"label": "Cluster Shell", "description": "Blast radius grows to 95px and fires 15% faster.",
					"cost": 200, "effects": {&"splash_radius": 95.0, &"fire_rate_multiplier": 0.85}},
				{"label": "Firestorm", "description": "Blast radius grows to 130px and damage rises by half.",
					"cost": 400, "effects": {&"splash_radius": 130.0, &"damage_multiplier": 1.5}},
			],
		},
		&"burst": {
			"label": "Demolition",
			"summary": "Heavier shells at the same reach. Trades coverage for punch.",
			"tiers": [
				{"label": "Packed Charge", "description": "Damage up by 60%.",
					"cost": 50, "effects": {&"damage_multiplier": 1.6}},
				{"label": "Heavy Shell", "description": "Damage up by 60% again.",
					"cost": 105, "effects": {&"damage_multiplier": 1.6}},
				{"label": "Siege Charge", "description": "Damage doubles and range extends by a fifth.",
					"cost": 210, "effects": {&"damage_multiplier": 2.0, &"range_multiplier": 1.2}},
				{"label": "Bunker Buster", "description": "Damage doubles again.",
					"cost": 420, "effects": {&"damage_multiplier": 2.0}},
			],
		},
	},
	# Anti-armour specialist. The heaviest pierce in the game.
	&"long": {
		&"sustained": {
			"label": "Bombardment",
			"summary": "Reach and cadence, then splash. Covers ground nothing else can.",
			"tiers": [
				{"label": "Long Barrel", "description": "Range up by 20%.",
					"cost": 60, "effects": {&"range_multiplier": 1.2}},
				{"label": "Rapid Loader", "description": "Fires 30% faster.",
					"cost": 120, "effects": {&"fire_rate_multiplier": 0.7}},
				{"label": "Shellburst", "description": "Shots splash for 55px.",
					"cost": 240, "effects": {&"splash_radius": 55.0}},
				{"label": "Carpet Fire", "description": "Splash grows to 90px and range extends by a third.",
					"cost": 450, "effects": {&"splash_radius": 90.0, &"range_multiplier": 1.33}},
			],
		},
		&"burst": {
			"label": "Siege",
			"summary": "The armour answer. Enormous hits that ignore plating entirely.",
			"tiers": [
				{"label": "Dense Slug", "description": "Damage up by 40%.",
					"cost": 60, "effects": {&"damage_multiplier": 1.4}},
				{"label": "Shaped Charge", "description": "Damage up by 40% again.",
					"cost": 130, "effects": {&"damage_multiplier": 1.4}},
				# DIVERGENCE from the reference, deliberate and temporary.
				# Upstream gives this tier pierce and nothing else, which is
				# inert until armoured enemies exist - 260 gold for no effect,
				# and a mandatory step to Siege Cannon behind it. The damage
				# multiplier and the "(no effect yet)" note are interim: delete
				# both, and test_tungsten_core_carries_an_interim_live_effect,
				# when enemy properties land.
				{"label": "Tungsten Core",
					"description": "Ignores 5 armour (no effect yet). Damage up by 30%.",
					"cost": 260, "effects": {&"pierce_bonus": 5, &"damage_multiplier": 1.3}},
				# Dormant marker: pierce has working machinery but no target
				# until armoured enemies land.
				{"label": "Siege Cannon",
					"description": "Damage doubles and ignores 10 more armour (no effect yet).",
					"cost": 500, "effects": {&"damage_multiplier": 2.0, &"pierce_bonus": 10}},
			],
		},
	},
}

static func get_branch(kind: StringName, branch: StringName) -> Dictionary:
	return DEFS[kind][branch]
