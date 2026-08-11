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

	var towers: Array = []
	for t in config.get("towers", []):
		var def: Dictionary = Towers.DEFS[t["kind"]]
		towers.append({
			"position": t["position"],
			"range": float(def["range"]),
			"fire_rate": float(def["fire_rate"]),
			"damage": float(def["damage"]),
			"pierce": int(def["pierce"]),
			"detection": bool(def["detection"]),
			"splash": float(def["base_splash_radius"]),
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
			})
			next_id += 1
			spawned += 1

		# Move.
		var survivors: Array = []
		for e in enemies:
			if not e["alive"]:
				continue
			var m := Movement.advance(e["position"], e["path_index"], path,
				e["speed"], tick_ms)
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
			var hit_list: Array = [target]
			if tower["splash"] > 0.0:
				for e in enemies:
					if e["id"] != target["id"] \
							and e["position"].distance_to(target["position"]) <= tower["splash"]:
						hit_list.append(e)
			for e in hit_list:
				var r := Damage.resolve({"damage": tower["damage"], "pierce": tower["pierce"]}, e)
				e["health"] = r["remaining_health"]
				if r["lethal"]:
					e["alive"] = false
					kills += 1
					gold_earned += int(Enemies.DEFS[e["kind"]]["reward"])

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
