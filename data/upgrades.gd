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
##
## AREA DAMAGE BELONGS TO THE MORTAR, and to nothing else. Basic and Long Range
## both used to buy splash on their deep sustained tiers; measured 2026-08-30,
## eleven of the sixteen legal fully-upgraded boards then shut the hardest
## difficulty out with zero leaks, because a splash hit carries its WHOLE
## payload - the Magic tower's slow included - to everything it catches. One
## Magic tower plus any splasher slowed the entire wave, and Long Range was the
## worst of them: 90px of blast at 239px of reach, wider effective area than the
## tower whose whole identity is area. test_upgrades.gd's
## test_only_the_mortar_ever_resolves_splash pins this on RESOLVED stats, so a
## tier that finds some other route to splash fails too.
##
## DAMAGE AND FIRE RATE ARE FLAT, never multipliers. Compounding is what made
## the deep tiers explode - two tiers of x1.4 is +96%, not +80%, and it got
## worse the deeper a branch went. A flat amount costs what it says wherever it
## sits, and reads as something a player can act on: "hits for 12 more" rather
## than "damage doubles", which doubles what?

const BRANCHES: Array[StringName] = [&"sustained", &"burst"]

const DEFS := {
	&"basic": {
		&"sustained": {
			"label": "Barrage",
			"summary": "Faster fire and longer reach. Clears crowds by volume, not by blast.",
			"tiers": [
				{"label": "Quick Loader", "description": "Fires 0.2s faster.",
					"cost": 30, "effects": {&"fire_rate_bonus_ms": 200.0}},
				{"label": "Drum Feed", "description": "Fires 0.16s faster.",
					"cost": 60, "effects": {&"fire_rate_bonus_ms": 160.0}},
				{"label": "Open Bolt", "description": "Fires 0.14s faster and reaches 15% further.",
					"cost": 130, "effects": {&"fire_rate_bonus_ms": 140.0, &"range_multiplier": 1.15}},
				{"label": "Sustained Fire", "description": "Fires 0.15s faster and hits for 2 more.",
					"cost": 260, "effects": {&"fire_rate_bonus_ms": 150.0, &"damage_bonus": 2.0}},
			],
		},
		&"burst": {
			"label": "Marksman",
			"summary": "Heavier hits, then detection. The only way to see phased enemies.",
			"tiers": [
				{"label": "Heavy Rounds", "description": "Hits for 2 more.",
					"cost": 30, "effects": {&"damage_bonus": 2.0}},
				{"label": "Rifled Barrel", "description": "Hits for 2 more again.",
					"cost": 65, "effects": {&"damage_bonus": 2.0}},
				# Dormant marker: detection has working machinery but no target
				# until phased enemies land. Damage stays live so the purchase
				# is not wasted while it is dormant.
				{"label": "Spotter",
					"description": "Reveals and targets phased enemies (no effect yet). Hits for 4 more.",
					"cost": 145, "effects": {&"detection": true, &"damage_bonus": 4.0}},
				{"label": "Executioner", "description": "Hits for 12 more and reaches a quarter further.",
					"cost": 290, "effects": {&"damage_bonus": 12.0, &"range_multiplier": 1.25}},
			],
		},
	},
	&"fast": {
		&"sustained": {
			"label": "Suppression",
			"summary": "Blistering cadence, then slowing. Answers shields and swiftness.",
			"tiers": [
				{"label": "Hair Trigger", "description": "Fires 0.125s faster.",
					"cost": 40, "effects": {&"fire_rate_bonus_ms": 125.0}},
				{"label": "Overclocked", "description": "Fires 0.094s faster.",
					"cost": 80, "effects": {&"fire_rate_bonus_ms": 94.0}},
				{"label": "Cryo Rounds", "description": "Hits slow enemies to 70% speed for 1.5s.",
					"cost": 165, "effects": {&"slow_factor": 0.7, &"slow_duration_ms": 1500}},
				{"label": "Deep Freeze", "description": "Slows to 45% speed for 2.5s and fires 0.056s faster.",
					"cost": 330, "effects": {&"slow_factor": 0.45, &"slow_duration_ms": 2500, &"fire_rate_bonus_ms": 56.0}},
			],
		},
		# The income branch. A fast tower farms a great many small kills, so
		# gold per kill is the multiplier that suits it - and it gives the
		# player a reason to build economy rather than only defence.
		&"burst": {
			"label": "Bounty Hunter",
			"summary": "Turns volume of kills into gold. The economy branch.",
			"tiers": [
				{"label": "Machined Rounds", "description": "Hits for 1 more.",
					"cost": 40, "effects": {&"damage_bonus": 1.0}},
				{"label": "Scavenger", "description": "Kills pay 1 extra gold.",
					"cost": 85, "effects": {&"bonus_gold_per_kill": 1}},
				{"label": "Bounty Board", "description": "Kills pay 60% more gold, and hits land 1 harder.",
					"cost": 175, "effects": {&"gold_multiplier": 1.6, &"damage_bonus": 1.0}},
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
				{"label": "Quick Crew", "description": "Fires 0.5s faster.",
					"cost": 100, "effects": {&"fire_rate_bonus_ms": 500.0}},
				{"label": "Cluster Shell", "description": "Blast radius grows to 95px and fires 0.225s faster.",
					"cost": 200, "effects": {&"splash_radius": 95.0, &"fire_rate_bonus_ms": 225.0}},
				{"label": "Firestorm", "description": "Blast radius grows to 130px and hits for 3 more.",
					"cost": 400, "effects": {&"splash_radius": 130.0, &"damage_bonus": 3.0}},
			],
		},
		&"burst": {
			"label": "Demolition",
			"summary": "Heavier shells at the same reach. Trades coverage for punch.",
			"tiers": [
				{"label": "Packed Charge", "description": "Hits for 3 more.",
					"cost": 50, "effects": {&"damage_bonus": 3.0}},
				{"label": "Heavy Shell", "description": "Hits for 5 more.",
					"cost": 105, "effects": {&"damage_bonus": 5.0}},
				{"label": "Siege Charge", "description": "Hits for 13 more and reaches a fifth further.",
					"cost": 210, "effects": {&"damage_bonus": 13.0, &"range_multiplier": 1.2}},
				{"label": "Bunker Buster", "description": "Hits for 25 more.",
					"cost": 420, "effects": {&"damage_bonus": 25.0}},
			],
		},
	},
	# Anti-armour specialist. The heaviest pierce in the game.
	&"long": {
		&"sustained": {
			"label": "Bombardment",
			"summary": "Reach and cadence. Covers ground nothing else can.",
			"tiers": [
				{"label": "Long Barrel", "description": "Range up by 20%.",
					"cost": 60, "effects": {&"range_multiplier": 1.2}},
				{"label": "Rapid Loader", "description": "Fires 0.45s faster.",
					"cost": 120, "effects": {&"fire_rate_bonus_ms": 450.0}},
				{"label": "Autoloader", "description": "Fires 0.25s faster.",
					"cost": 240, "effects": {&"fire_rate_bonus_ms": 250.0}},
				{"label": "Overwatch", "description": "Fires 0.2s faster and range extends by a third.",
					"cost": 450, "effects": {&"fire_rate_bonus_ms": 200.0, &"range_multiplier": 1.33}},
			],
		},
		&"burst": {
			"label": "Siege",
			"summary": "The armour answer. Enormous hits that ignore plating entirely.",
			"tiers": [
				{"label": "Dense Slug", "description": "Hits for 6 more.",
					"cost": 60, "effects": {&"damage_bonus": 6.0}},
				{"label": "Shaped Charge", "description": "Hits for 8 more.",
					"cost": 130, "effects": {&"damage_bonus": 8.0}},
				# DIVERGENCE from the reference, deliberate and temporary.
				# Upstream gives this tier pierce and nothing else, which is
				# inert until armoured enemies exist - 260 gold for no effect,
				# and a mandatory step to Siege Cannon behind it. The damage
				# multiplier and the "(no effect yet)" note are interim: delete
				# both, and test_tungsten_core_carries_an_interim_live_effect,
				# when enemy properties land.
				{"label": "Tungsten Core",
					"description": "Ignores 5 armour (no effect yet). Hits for 9 more.",
					"cost": 260, "effects": {&"pierce_bonus": 5, &"damage_bonus": 9.0}},
				# Dormant marker: pierce has working machinery but no target
				# until armoured enemies land.
				{"label": "Siege Cannon",
					"description": "Hits for 38 more and ignores 10 more armour (no effect yet).",
					"cost": 500, "effects": {&"damage_bonus": 38.0, &"pierce_bonus": 10}},
			],
		},
	},
}

## The order effects are rendered in, so two tiers carrying the same effects
## read the same way whatever order their dictionaries happen to iterate in.
const _SUMMARY_ORDER: Array[StringName] = [
	&"damage_bonus", &"fire_rate_bonus_ms", &"range_multiplier", &"splash_radius",
	&"slow_factor", &"pierce_bonus", &"gold_multiplier", &"bonus_gold_per_kill",
	&"detection",
]

## A tier's effects as a short line for the panel: "+2 damage · fires 0.15s
## faster".
##
## GENERATED rather than written beside the tier, so the number a player reads
## is the number the simulation applies. A hand-written description drifts the
## first time a value is tuned, and the tier's own `description` field - which
## stays, as the tooltip - is where flavour and dormant-effect notes live.
##
## An unknown key renders as "?" rather than vanishing, which is what
## test_every_tier_renders_a_summary detects: adding an effect without teaching
## this function about it fails the suite instead of blanking a row.
static func effect_summary(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in _SUMMARY_ORDER:
		if effects.has(key):
			parts.append(_render_effect(key, effects))
	for key in effects:
		# slow_duration_ms is rendered by slow_factor rather than on its own,
		# so it is known without being listed.
		if not _SUMMARY_ORDER.has(key) and key != &"slow_duration_ms":
			parts.append("?")
	return " · ".join(parts)

static func _render_effect(key: StringName, effects: Dictionary) -> String:
	match key:
		&"damage_bonus":
			return "+%d damage" % int(effects[key])
		&"fire_rate_bonus_ms":
			return "fires %ss faster" % _trim(float(effects[key]) / 1000.0)
		&"range_multiplier":
			return "+%d%% range" % int(round((float(effects[key]) - 1.0) * 100.0))
		&"splash_radius":
			return "%dpx blast" % int(effects[key])
		&"slow_factor":
			return "slows to %d%% for %ss" % [
				int(round(float(effects[key]) * 100.0)),
				_trim(float(effects.get(&"slow_duration_ms", 0)) / 1000.0)]
		&"pierce_bonus":
			return "ignores %d armour" % int(effects[key])
		&"gold_multiplier":
			return "+%d%% gold" % int(round((float(effects[key]) - 1.0) * 100.0))
		&"bonus_gold_per_kill":
			return "+%d gold a kill" % int(effects[key])
		&"detection":
			return "reveals phased"
	return "?"

## Seconds without trailing zeroes: 0.40 -> "0.4", 1.00 -> "1".
static func _trim(seconds: float) -> String:
	var text := "%.3f" % seconds
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	return text.trim_suffix(".")

static func get_branch(kind: StringName, branch: StringName) -> Dictionary:
	return DEFS[kind][branch]
