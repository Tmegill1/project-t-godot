class_name Harness

## Runs a wave headlessly on a fixed timestep, with no engine involvement.
##
## It reuses the game's own sim modules, so there is no second rules
## implementation to drift. Every balance claim in this project is a test
## rather than an assertion because of this file.
##
## Simplifications versus the TS reference (`harness.ts`), deliberate for
## this core slice:
## - No projectile travel time: a tower's hit resolves the instant it fires,
##   rather than a projectile flying at a finite speed toward its target.
## - One lane, no seed, no lieutenants/bosses/insignia/powers/upgrades/splits
##   — none of that exists in this slice yet. Determinism therefore falls
##   out for free: nothing here draws from an RNG.

const DEFAULT_TICK_MS := 1000.0 / 60.0
const DEFAULT_MAX_TICKS := 60000

static func run_wave(config: Dictionary) -> Dictionary:
	var wave: int = config["wave"]
	var path: PackedVector2Array = config["path"]
	var tick_ms: float = config.get("tick_ms", DEFAULT_TICK_MS)
	var max_ticks: int = config.get("max_ticks", DEFAULT_MAX_TICKS)

	# Stats come from the upgrade rules, not the table, so a build tested here
	# is the build the player gets. A tower given no tiers resolves to exactly
	# its table values, which is what every balance pin above depends on.
	var towers: Array = []
	for t in config.get("towers", []):
		var tiers: Dictionary = t.get("tiers", UpgradesSim.empty_tiers())
		var stats := UpgradesSim.resolve_tower_stats(t["kind"], tiers)
		towers.append({
			"position": t["position"],
			"range": float(stats["range"]),
			"fire_rate": float(stats["fire_rate"]),
			"damage": float(stats["damage"]),
			"pierce": int(stats["pierce"]),
			"detection": bool(stats["detection"]),
			"splash": float(stats["splash_radius"]),
			"slow_factor": float(stats["slow_factor"]),
			"slow_duration_ms": float(stats["slow_duration_ms"]),
			"gold_multiplier": float(stats["gold_multiplier"]),
			"bonus_gold_per_kill": int(stats["bonus_gold_per_kill"]),
			# Physical or magic - decides how armour and shields bite this tower.
			"damage_type": Towers.DEFS[t["kind"]]["damage_type"],
			"priority": Targeting.DEFAULT_PRIORITY,
			"cooldown": 0.0,
		})

	var schedule := Waves.build_schedule(wave)
	var modifiers := Waves.get_modifiers(wave)

	var enemies: Array = []
	var next_id := 0
	var elapsed := 0.0
	var ticks := 0
	var kills := 0
	var leaks := 0
	var lives_lost := 0
	var gold_earned := 0
	var spawned := 0

	while ticks < max_ticks:
		ticks += 1
		elapsed += tick_ms

		# Spawns due this tick.
		while spawned < schedule.size() and schedule[spawned]["at_ms"] <= elapsed:
			var s: Dictionary = schedule[spawned]
			var kind: StringName = s["kind"]
			var health := float(Enemies.scaled_health(kind, modifiers["health_modifier"]))
			enemies.append({
				"id": next_id,
				"kind": kind,
				"position": path[0],
				"path_index": Movement.starting_path_index(path[0], path),
				"health": health,
				"max_health": health,
				"speed": Enemies.scaled_speed(kind, modifiers["speed_modifier"]),
				"alive": true,
				"dying": false,
				"slow": Slow.none(),
				# Read by sim/damage.gd. The live board sets the same two keys in
				# Enemy.setup; if only one side carried them, every balance number
				# this harness produces would be a fiction.
				"armor": int(Enemies.resistance_for(kind, wave)["armor"]),
				"shield": int(Enemies.resistance_for(kind, wave)["shield"]),
			})
			next_id += 1
			spawned += 1

		# Move.
		var survivors: Array = []
		for e in enemies:
			if not e["alive"]:
				continue
			# The slow runs down before the step it governs, matching
			# game/enemy.gd's _physics_process so a wave times the same here
			# as it does on screen.
			e["slow"] = Slow.tick(e["slow"], tick_ms)
			var m := Movement.advance(e["position"], e["path_index"], path,
				Slow.effective_speed(float(e["speed"]), e["slow"]), tick_ms)
			e["position"] = m["position"]
			e["path_index"] = m["path_index"]
			if m["reached_goal"]:
				leaks += 1
				lives_lost += Leak.resolve(
					{"life_loss": Enemies.DEFS[e["kind"]]["life_loss"], "health": e["health"]},
					wave)
				e["alive"] = false
			else:
				survivors.append(e)
		enemies = survivors

		# Fire.
		for tower in towers:
			tower["cooldown"] -= tick_ms
			if tower["cooldown"] > 0.0:
				continue
			var target = Targeting.select(tower, enemies)
			if target == null:
				continue
			tower["cooldown"] = tower["fire_rate"]
			# The same shape game/tower.gd emits with wants_to_fire, so the
			# rules downstream cannot tell the harness from the live game.
			var source := {
				"damage": tower["damage"],
				"pierce": tower["pierce"],
				"damage_type": tower["damage_type"],
				"gold_multiplier": tower["gold_multiplier"],
				"bonus_gold_per_kill": tower["bonus_gold_per_kill"],
				"slow_factor": tower["slow_factor"],
				"slow_duration_ms": tower["slow_duration_ms"],
			}
			var hit_list: Array = [target]
			if tower["splash"] > 0.0:
				for e in enemies:
					# The blast's own target is already in hit_list; the
					# geometry is Damage.in_splash, shared with the live board.
					if e["id"] != target["id"] \
							and Damage.in_splash(target["position"], e["position"], tower["splash"]):
						hit_list.append(e)
			for e in hit_list:
				# Every enemy the blast caught takes the whole payload, slow
				# included - Projectile.applyTo does the same for its splash
				# victims, and game/game_board.gd hands the same source to
				# every enemy in range.
				e["slow"] = Slow.apply(e["slow"], float(source["slow_factor"]),
					float(source["slow_duration_ms"]))
				var r := Damage.resolve(source, e)
				e["health"] = r["remaining_health"]
				# Written back, or a shield absorbs every hit forever.
				e["shield"] = int(r["remaining_shield"])
				if r["lethal"]:
					e["alive"] = false
					kills += 1
					gold_earned += EconomySim.kill_reward(
						int(Enemies.DEFS[e["kind"]]["reward"]), source,
						float(modifiers["gold_modifier"]))

		enemies = enemies.filter(func(e): return e["alive"])

		if spawned >= schedule.size() and enemies.is_empty():
			return _result(kills, leaks, lives_lost, gold_earned, ticks, false)

	return _result(kills, leaks, lives_lost, gold_earned, ticks, true)

static func _result(kills: int, leaks: int, lives_lost: int, gold: int,
		ticks: int, timed_out: bool) -> Dictionary:
	return {
		"kills": kills, "leaks": leaks, "lives_lost": lives_lost,
		"gold_earned": gold, "ticks": ticks, "timed_out": timed_out,
	}
