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

## Cumulative distance to each waypoint, and the route's total length.
##
## Precomputed once per run rather than per tick: the route never changes
## during a wave, and this is read for every living enemy on every tick.
static func _route_metrics(path: PackedVector2Array) -> Dictionary:
	var cumulative := PackedFloat32Array()
	cumulative.resize(path.size())
	if path.size() > 0:
		cumulative[0] = 0.0
	for i in range(1, path.size()):
		cumulative[i] = cumulative[i - 1] + path[i - 1].distance_to(path[i])
	var total := 0.0 if path.size() == 0 else float(cumulative[path.size() - 1])
	return {"cumulative": cumulative, "total": total}

## How far along the route a position is, as a fraction of the whole.
##
## path_index is the waypoint being walked TOWARD, so everything up to
## path_index - 1 is already behind the enemy; the remainder is the straight
## line from that waypoint to where it now stands.
static func _progress_of(position: Vector2, path_index: int,
		path: PackedVector2Array, route: Dictionary) -> float:
	var total: float = route["total"]
	if total <= 0.0 or path.size() == 0:
		return 0.0
	var cumulative: PackedFloat32Array = route["cumulative"]
	var behind := clampi(path_index - 1, 0, path.size() - 1)
	var travelled := float(cumulative[behind]) + path[behind].distance_to(position)
	return clampf(travelled / total, 0.0, 1.0)

static func run_wave(config: Dictionary) -> Dictionary:
	var wave: int = config["wave"]
	# One lane or many. `path` is the older spelling and means exactly one lane;
	# every balance number this project has measured came through it, so it
	# stays a first-class spelling rather than a deprecated one.
	var paths: Array = config["paths"] if config.has("paths") else [config["path"]]
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

	# Difficulty travels as a parameter, never a global, so this stays a pure
	# function of its config - which is what makes every balance claim in this
	# project reproducible.
	var tier: StringName = config.get("difficulty", Difficulty.NORMAL)
	var schedule := Waves.build_schedule(wave, tier)
	var modifiers := Waves.get_modifiers(wave, tier)

	var enemies: Array = []
	var next_id := 0
	var elapsed := 0.0
	var ticks := 0
	var kills := 0
	var leaks := 0
	var lives_lost := 0
	var gold_earned := 0
	# The wave DIVIDED between the entrances, one queue and one cursor each,
	# mirroring GameBoard's _spawn_queues and _spawned_per_path. A second
	# entrance means two approaches, not twice the enemies - Waves.split_schedule
	# carries that rule for both callers, so a wave cannot mean one thing on
	# screen and another here.
	var lane_schedules := Waves.split_schedule(schedule, paths.size())
	var spawned: Array[int] = []
	for i in lane_schedules.size():
		spawned.append(0)
	# Precomputed once per lane: a lane's route never changes during a wave and
	# this is read for every living enemy on every tick.
	var routes: Array = []
	for lane_path in paths:
		routes.append(_route_metrics(lane_path))
	var deepest_progress := 0.0
	var death_progress_total := 0.0
	var deaths := 0

	while ticks < max_ticks:
		ticks += 1
		elapsed += tick_ms

		# Spawns due this tick, lane by lane, each from its own share of the
		# wave. An N-lane map fields the SAME enemies as a one-lane map, split
		# N ways - see Waves.split_schedule for why that replaced doubling.
		for lane in lane_schedules.size():
			var lane_path: PackedVector2Array = paths[lane]
			var queue: Array = lane_schedules[lane]
			while spawned[lane] < queue.size() \
					and queue[spawned[lane]]["at_ms"] <= elapsed:
				var s: Dictionary = queue[spawned[lane]]
				var kind: StringName = s["kind"]
				# A boss is an ordinary enemy with different numbers - same
				# dictionary, same rules downstream, only the stats overridden.
				# Enemy.make_boss does exactly this on the live board.
				var boss: Dictionary = Bosses.on_wave(wave) if s.get("boss", false) else {}
				var is_boss := not boss.is_empty()
				var health := float(boss["health"]) if is_boss \
					else float(Enemies.scaled_health(kind, modifiers["health_modifier"]))
				enemies.append({
					"id": next_id,
					"kind": kind,
					# The lane this enemy walks. Carried on the enemy rather
					# than looked up, because a lane belongs to the thing
					# walking it - which is why targeting, damage, splash, slow
					# and the aura all needed no change at all: not one of them
					# ever looks at a path.
					"lane": lane,
					"position": lane_path[0],
					"path_index": Movement.starting_path_index(lane_path[0], lane_path),
					"health": health,
					"max_health": health,
					"speed": float(boss["speed"]) if is_boss \
						else Enemies.scaled_speed(kind, modifiers["speed_modifier"]),
					"alive": true,
					"dying": false,
					"slow": Slow.none(),
					# Read by sim/damage.gd. The live board sets the same two keys in
					# Enemy.setup; if only one side carried them, every balance number
					# this harness produces would be a fiction.
					"armor": int(boss["armor"]) if is_boss \
						else int(Enemies.resistance_for(kind, wave)["armor"]),
					"shield": int(boss["shield"]) if is_boss \
						else int(Enemies.resistance_for(kind, wave)["shield"]),
					"boss": is_boss,
					"reward_override": int(boss["reward"]) if is_boss else 0,
					"boss_life_loss": int(boss["life_loss"]) if is_boss else 0,
				})
				next_id += 1
				spawned[lane] += 1

		# Move.
		var survivors: Array = []
		for e in enemies:
			if not e["alive"]:
				continue
			# The slow runs down before the step it governs, matching
			# game/enemy.gd's _physics_process so a wave times the same here
			# as it does on screen.
			e["slow"] = Slow.tick(e["slow"], tick_ms)
			var walking: PackedVector2Array = paths[e["lane"]]
			var m := Movement.advance(e["position"], e["path_index"], walking,
				Slow.effective_speed(float(e["speed"]), e["slow"]), tick_ms)
			e["position"] = m["position"]
			e["path_index"] = m["path_index"]
			# A fraction of ITS OWN lane, maxed across lanes - so a single-lane
			# wave reports exactly what it always did.
			deepest_progress = maxf(deepest_progress, _progress_of(
				e["position"], e["path_index"], walking, routes[e["lane"]]))
			if m["reached_goal"]:
				# A leak has by definition walked the whole route.
				deepest_progress = 1.0
				leaks += 1
				lives_lost += Leak.resolve({
					"life_loss": Enemies.DEFS[e["kind"]]["life_loss"],
					"health": e["health"],
					"max_health": e["max_health"],
					# A boss carries its own cost here too, or the harness
					# under-reports exactly the leak that matters most.
					"boss_life_loss": int(e.get("boss_life_loss", 0)),
				})
				e["alive"] = false
			else:
				survivors.append(e)
		enemies = survivors

		# The shaman aura, BEFORE the fire block - a charge granted this tick is
		# available to absorb this tick's shot, identically in the live board.
		var shamans: Array = []
		for e in enemies:
			if e["kind"] == &"shaman" and e["alive"] and not e["dying"]:
				shamans.append(e)
		for granted_id in Aura.grant(shamans, enemies, elapsed):
			for e in enemies:
				if e["id"] == granted_id:
					e["shield"] = mini(int(e.get("shield", 0)) + 1, Aura.MAX_GRANTED_CHARGES)
					break

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
					death_progress_total += _progress_of(e["position"],
						e["path_index"], paths[e["lane"]], routes[e["lane"]])
					deaths += 1
					# A boss pays its own bounty, not its kind's.
					var base_reward: int = int(e["reward_override"]) if e.get("boss", false) \
						else int(Enemies.DEFS[e["kind"]]["reward"])
					gold_earned += EconomySim.kill_reward(
						base_reward, source, float(modifiers["gold_modifier"]))

		enemies = enemies.filter(func(e): return e["alive"])

		if _all_spawns_issued(spawned, lane_schedules) and enemies.is_empty():
			return _result(kills, leaks, lives_lost, gold_earned, ticks, false,
				deepest_progress, death_progress_total, deaths)

	return _result(kills, leaks, lives_lost, gold_earned, ticks, true,
		deepest_progress, death_progress_total, deaths)

## Whether every lane has issued its whole schedule.
##
## Checking one cursor is not enough: a wave is not over while any entrance
## still has enemies to send. GameBoard._all_spawns_issued exists for exactly
## this reason and says exactly this.
static func _all_spawns_issued(spawned: Array[int], lane_schedules: Array) -> bool:
	for lane in spawned.size():
		if spawned[lane] < (lane_schedules[lane] as Array).size():
			return false
	return true

static func _result(kills: int, leaks: int, lives_lost: int, gold: int,
		ticks: int, timed_out: bool, deepest_progress: float,
		death_progress_total: float, deaths: int) -> Dictionary:
	return {
		"kills": kills,
		"leaks": leaks,
		"lives_lost": lives_lost,
		"gold_earned": gold,
		"ticks": ticks,
		"timed_out": timed_out,
		# How far the furthest enemy got, as a fraction of the route. This is
		# what makes "they never reach the first bend" an assertion instead of
		# an observation - the gap that let a shut-out board read as balanced.
		"deepest_progress": deepest_progress,
		# Mean progress at the moment of death, over enemies that died. Zero
		# when nothing died, which is the honest answer rather than a
		# division by zero.
		"progress_at_death": 0.0 if deaths == 0 else death_progress_total / float(deaths),
	}
