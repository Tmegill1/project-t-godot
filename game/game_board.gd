class_name GameBoard
extends Node2D

## The hub that wires sim to views: owns gold, lives, the wave number, and
## per-kind tower counts; runs spawns from the schedule; ticks towers;
## resolves projectile hits including splash; and handles taps for
## placement. The sim modules decide, the board wires - it contains no
## targeting, damage, leak-cost, pricing or scheduling rules of its own;
## every one of those questions is delegated to sim/ or data/.

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int, max_waves: int)
signal wave_state_changed(active: bool)
signal game_over()
signal victory()
signal tower_placed(kind: StringName)
signal tower_upgraded(branch: StringName)
signal tower_selected(tower: Tower)
signal tower_deselected()
signal placement_rejected(reason: String)
signal wave_reward(base: int, speed: int, interest: int)
signal prep_changed(remaining_ms: float, bonus: int)
signal tower_sold(kind: StringName)

const ENEMY_SCENE := preload("res://game/enemy.tscn")
const TOWER_SCENE := preload("res://game/tower.tscn")
const PROJECTILE_SCENE := preload("res://game/projectile.tscn")

## Width the build panel needs beside the map.
##
## 140 is what the design viewport reserved: 1244 total minus map 1's 1104.
## TowerPanel anchors its left edge to the map's right edge and absorbs any
## surplus beyond this, so it is a MINIMUM rather than a fixed width.
const PANEL_WIDTH := 140

## The map the NEXT board to enter the tree should load, or empty for the
## first map.
##
## Static because it has to outlive a scene change: the victory screen sets it
## and then reloads, and there is no save file or run-state singleton in this
## project to carry it. _ready CONSUMES it - reads it, then clears it - so a
## run that ends on The Coils does not silently start the next one there.
## MainMenu.begin_new_run() clears it too, so "Play" always means map one.
##
## This is the same shape as Grid's static state and carries the same hazard:
## anything that reads it must not depend on test execution order. The tests
## that touch it set and clear it explicitly.
static var pending_map: StringName = &""

var _map_name: StringName = Maps.FIRST
var _tiles: Array = []
var _paths: Array[PackedVector2Array] = []
var _gold := 0
var _lives := 0
var _wave := 0
var _wave_active := false
var _run_finished := false
var _selected_kind: StringName = &""
var _selected_tower: Tower = null
var _counts := {}            # StringName -> int
## One queue and one cursor PER PATH. The full wave composition runs down every
## path rather than being divided between them, matching upstream (GameScene.ts
## computes totalEnemies * enemyPaths.length). A map with two entrances
## therefore fields twice the wave, which is a difficulty lever carried in the
## map's own starting gold and budget rather than anywhere in here.
var _spawn_queues: Array = []      # Array of Array of {kind, at_ms}
var _spawned_per_path: Array = []  # Array of int
var _wave_clock := 0.0
## The most recent wave clear's payout, itemised, for the HUD and for tests.
var _last_wave_reward := {"base": 0, "speed": 0, "interest": 0}
## Milliseconds left before the next wave starts on its own. Zero means no
## countdown is running - the game is either mid-wave, finished, or waiting
## for the player's very first Start press.
var _prep_remaining_ms := 0.0
## Which variant each spawn draws. Reset per wave so replaying a wave shows
## the same creatures, and separate from every other random system so enemy
## variety does not move when they do.
var _spawn_rng := Rng.new(Seeds.DEFAULT_SPAWN_SEED)

@onready var _map_renderer: MapRenderer = $MapRenderer
@onready var _towers_root: Node2D = $Towers
@onready var _enemies_root: Node2D = $Enemies
@onready var _projectiles_root: Node2D = $Projectiles
@onready var _ghost: Sprite2D = $PlacementPreview
@onready var _ghost_range: RangeIndicator = $PreviewRange

func _ready() -> void:
	# Consume the pending map, so the next board does not inherit this one's.
	if pending_map != &"":
		_map_name = pending_map
		pending_map = &""

	var def := Maps.get_def(_map_name)
	Grid.set_active(def["cols"], def["rows"], def["tile_size"])
	_tiles = Maps.build_tiles(_map_name)
	_map_renderer.render(_tiles, null, def["biome"])
	_paths = PathFinder.get_all_spawn_paths(_tiles)

	_gold = int(def["starting_gold"])
	_lives = Economy.STARTING_LIVES
	for kind in Towers.KINDS:
		_counts[kind] = 0

	gold_changed.emit(_gold)
	lives_changed.emit(_lives)
	wave_changed.emit(_wave, Waves.MAX_WAVES)

	# Applied here rather than in project.godot because it is per map. Guarded
	# because the test harness has no window: nodes there are never inside a
	# live tree, so get_window() is not available to them.
	if is_inside_tree():
		var window := get_window()
		if window != null:
			window.content_scale_size = required_content_size(_map_name)

## The base resolution a map needs: the map itself plus room for the panel.
##
## The window's content_scale_size is set to this rather than a Camera2D being
## added, and that choice is load-bearing. Both maps past the first are larger
## than the 1244x672 design box in both axes, so something has to give - but a
## camera, or a scale on this node, would put a transform between
## get_global_mouse_position() and every rule that consumes it. Placement,
## targeting, splash geometry and TowerPanel.offset_left all assume world
## space IS map pixel space, and this project's own history says geometry bugs
## are found by screenshots rather than by the suite. Changing the base
## resolution reaches the same result with no transform at all: the stretch
## system does the downscaling, and a map pixel stays a world unit.
static func required_content_size(map_name: StringName) -> Vector2i:
	var map_px := Maps.pixel_size(map_name)
	return Vector2i(map_px.x + PANEL_WIDTH, map_px.y)

func get_gold() -> int: return _gold
func get_lives() -> int: return _lives
func get_wave() -> int: return _wave
func is_wave_active() -> bool: return _wave_active

## Which map is loaded. The board picks it (_map_name) and everything sized
## against the map - currently TowerPanel, which butts its left edge up
## against the map's right edge - has to ask rather than assume Maps.FIRST,
## so a second map with different dimensions still lays out correctly.
func get_map_name() -> StringName: return _map_name

func get_tower_count(kind: StringName) -> int:
	return _counts.get(kind, 0)

## The itemised payout from the most recent wave clear, for the HUD and tests.
## Duplicated so a caller cannot edit the board's own record.
func get_last_wave_reward() -> Dictionary:
	return _last_wave_reward.duplicate()

## Test seam. The board owns gold and there is no other way to arrange a
## specific bank before a clear; the alternative is playing a whole wave.
func set_gold_for_test(amount: int) -> void:
	_gold = amount
	gold_changed.emit(_gold)

## Test seam. _on_wave_cleared is otherwise only reachable by running a wave
## to completion, which a frameless test cannot do.
func force_wave_cleared_for_test() -> void:
	_on_wave_cleared()

func get_prep_remaining_ms() -> float:
	return _prep_remaining_ms

func is_prepping() -> bool:
	return _prep_remaining_ms > 0.0

## Test seam: reaching the final wave otherwise means playing nineteen.
func set_wave_for_test(wave: int) -> void:
	_wave = wave

## Test seam: reaching a kind's limit otherwise means placing eight towers.
func set_tower_count_for_test(kind: StringName, count: int) -> void:
	_counts[kind] = count

## Test seam: the board otherwise always loads Maps.FIRST.
##
## Must be called BEFORE notification(NOTIFICATION_READY), because _ready is
## what reads _map_name to build the tiles and the paths.
func set_map_for_test(map_name: StringName) -> void:
	_map_name = map_name

## Total spawns issued this wave, across every path.
func get_spawned_count() -> int:
	var total := 0
	for n in _spawned_per_path:
		total += int(n)
	return total

## Test seam: losing otherwise means leaking twenty lives.
func force_game_over_for_test() -> void:
	_run_finished = true
	_wave_active = false
	_prep_remaining_ms = 0.0
	game_over.emit()

func select_tower_kind(kind: StringName) -> void:
	_selected_kind = kind
	# Rules state before anything visual - same reasoning as Tower.setup
	# (game/tower.gd). A GDScript runtime error aborts only the enclosing
	# function frame, so under a harness where @onready fields (_ghost,
	# _ghost_range) are unresolved, everything after the first @onready
	# access below would be silently skipped. _deselect_tower() is this
	# function's actual contract, so it must run before either onready
	# access can abort the frame.
	_deselect_tower()
	# The ghost otherwise keeps showing the previous kind's sprite/colour at
	# the last mouse position until the next InputEventMouseMotion arrives -
	# hiding it here means a kind change never briefly shows a stale preview.
	# _ghost_range is PlacementPreview's sibling, not its child, so hiding
	# _ghost alone would no longer carry the ring's visibility down with it.
	_ghost.visible = false
	_ghost_range.visible = false

func start_next_wave() -> void:
	if _wave_active or _run_finished:
		return

	# Whether the player pressed the button or the clock ran out, one path
	# starts a wave. call_early_bonus returns 0 for an expired clock, so the
	# timeout case needs no special handling here.
	if _prep_remaining_ms > 0.0:
		var early_bonus := EconomySim.call_early_bonus(_prep_remaining_ms)
		if early_bonus > 0:
			_gold += early_bonus
			gold_changed.emit(_gold)
	_prep_remaining_ms = 0.0
	prep_changed.emit(0.0, 0)

	_wave += 1
	if _wave > Waves.MAX_WAVES:
		return
	_wave_active = true
	_wave_clock = 0.0
	_spawn_rng = Rng.new(Seeds.DEFAULT_SPAWN_SEED)
	var schedule := Waves.build_schedule(_wave)
	_spawn_queues = []
	_spawned_per_path = []
	for i in maxi(1, _paths.size()):
		# One shared schedule, one cursor each. Sharing is safe because the
		# queue is only ever READ - progress lives entirely in
		# _spawned_per_path - and build_schedule already returns fresh
		# dictionaries per call. An earlier version deep-copied per path with
		# a comment claiming a shared array would make one path skip the
		# other's spawns; mutation testing showed that copy changed no
		# observable behaviour, because the claim was simply false.
		_spawn_queues.append(schedule)
		_spawned_per_path.append(0)
	wave_changed.emit(_wave, Waves.MAX_WAVES)
	wave_state_changed.emit(true)
	_play_sound(&"wave-start")

func _physics_process(delta: float) -> void:
	if _run_finished:
		return
	var delta_ms := delta * 1000.0

	# Deliberately inside _physics_process rather than on a Timer node, so
	# Engine.time_scale scales it: fast-forwarding must not buy the player
	# more real thinking time. It also stops on its own when the run ends,
	# because the _run_finished guard above already returned.
	if _prep_remaining_ms > 0.0:
		_prep_remaining_ms = maxf(0.0, _prep_remaining_ms - delta_ms)
		prep_changed.emit(_prep_remaining_ms,
			EconomySim.call_early_bonus(_prep_remaining_ms))
		if _prep_remaining_ms <= 0.0:
			start_next_wave()

	if _wave_active:
		_wave_clock += delta_ms
		for path_index in _spawn_queues.size():
			var queue: Array = _spawn_queues[path_index]
			var issued: int = _spawned_per_path[path_index]
			while issued < queue.size() and queue[issued]["at_ms"] <= _wave_clock:
				_spawn(queue[issued]["kind"], path_index,
					queue[issued].get("boss", false))
				issued += 1
			_spawned_per_path[path_index] = issued

	var candidates: Array = []
	for enemy in _enemies_root.get_children():
		if enemy is Enemy and enemy.sim["alive"] and not enemy.sim["dying"]:
			candidates.append(enemy.to_candidate())

	_apply_shaman_aura()

	for tower in _towers_root.get_children():
		if tower is Tower:
			tower.tick(delta_ms, candidates)

	if _wave_active and _all_spawns_issued() \
			and _enemies_root.get_child_count() == 0:
		_on_wave_cleared()

## Whether every path has issued its whole schedule. Checking one queue is not
## enough: the wave is not over while any entrance still has enemies to send.
func _all_spawns_issued() -> bool:
	for i in _spawn_queues.size():
		if int(_spawned_per_path[i]) < (_spawn_queues[i] as Array).size():
			return false
	return true

## Tops up shield charges around any shaman on the board.
##
## The rule is sim/aura.gd and the harness runs the identical call, so a wave
## simulated headlessly and the same wave played out resolve the same way. The
## board's job here is only to gather the two lists and apply the answer.
func _apply_shaman_aura() -> void:
	var shamans: Array = []
	var living: Array = []
	for child in _enemies_root.get_children():
		if not child is Enemy:
			continue
		if not child.sim["alive"] or child.sim["dying"]:
			continue
		living.append({
			"id": child.sim["id"], "position": child.position,
			"kind": child.kind, "shield": int(child.sim.get("shield", 0)),
			"alive": true, "dying": false,
		})
		if child.kind == &"shaman":
			shamans.append(living[living.size() - 1])

	var granted := Aura.grant(shamans, living, _wave_clock)
	if granted.is_empty():
		return
	for child in _enemies_root.get_children():
		if child is Enemy and granted.has(child.sim["id"]):
			child.sim["shield"] = mini(
				int(child.sim.get("shield", 0)) + 1, Aura.MAX_GRANTED_CHARGES)
			child.refresh_resistance_visual()

func _spawn(kind: StringName, path_index: int, is_boss: bool = false) -> void:
	if _paths.is_empty():
		return
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	_enemies_root.add_child(enemy)
	enemy.setup(kind, _paths[mini(path_index, _paths.size() - 1)], _wave, _spawn_rng)
	# A boss is an ordinary enemy with different numbers - the same node, the
	# same rules downstream, only its stats overridden. The harness does
	# exactly this too.
	if is_boss:
		enemy.make_boss(Bosses.on_wave(_wave))
		_play_sound(&"boss")
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)

func _on_enemy_died(reward: int, kind: StringName) -> void:
	_gold += reward
	gold_changed.emit(_gold)
	_play_sound(&"death-%s" % kind)

func _on_enemy_leaked(life_loss: int) -> void:
	_lives = maxi(0, _lives - life_loss)
	lives_changed.emit(_lives)
	_play_sound(&"leak")
	if _lives <= 0 and not _run_finished:
		_run_finished = true
		_wave_active = false
		game_over.emit()
		_play_sound(&"defeat")

func _on_wave_cleared() -> void:
	_wave_active = false
	wave_state_changed.emit(false)

	# Interest is taken on the bank as it stands BEFORE the clear bonus is
	# added, or the player earns interest on money paid in the same instant.
	var earned_interest := EconomySim.interest_on(_gold)
	var bonus := EconomySim.wave_clear_bonus(_wave, _wave_clock)
	_last_wave_reward = {
		"base": int(bonus["base"]),
		"speed": int(bonus["speed"]),
		"interest": earned_interest,
	}
	_gold += int(bonus["base"]) + int(bonus["speed"]) + earned_interest
	gold_changed.emit(_gold)
	wave_reward.emit(int(bonus["base"]), int(bonus["speed"]), earned_interest)

	_play_sound(&"wave-clear")
	if _wave >= Waves.MAX_WAVES and not _run_finished:
		_run_finished = true
		victory.emit()
		_play_sound(&"victory")
		return

	# Armed only PAST the victory check above, and the ordering is
	# load-bearing: winning must not start a countdown to a twenty-first wave
	# that cannot exist. test_clearing_the_final_wave_does_not_start_a_prep_timer
	# is what holds it.
	_prep_remaining_ms = float(Economy.CALL_EARLY["prep_duration_ms"])
	prep_changed.emit(_prep_remaining_ms,
		EconomySim.call_early_bonus(_prep_remaining_ms))

# --- Input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _run_finished:
		return
	if event is InputEventMouseMotion:
		_update_ghost(get_global_mouse_position())
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(get_global_mouse_position())
		get_viewport().set_input_as_handled()

## Ghost preview: green where the tower would land, red where it would not,
## with the range ring shown only when the spot is legal so its absence is a
## second, redundant signal. Pure view - it asks Placement the same question
## _try_place will ask and stores nothing of its own, so the preview cannot
## drift from the rule it previews.
func _update_ghost(world: Vector2) -> void:
	if _selected_kind == &"":
		_ghost.visible = false
		_ghost_range.visible = false
		return

	var def: Dictionary = Towers.DEFS[_selected_kind]
	var radius := Placement.tower_radius(_selected_kind)
	var verdict := Placement.can_place(
		world,
		radius,
		_map_renderer.prop_footprints(),
		_tower_positions(),
		_paths,
		Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(_map_name))))

	_ghost.visible = true
	_ghost.position = world
	_ghost_range.position = world

	var atlas := AtlasTexture.new()
	atlas.atlas = Tower.TOWER_SHEET
	atlas.region = Tower.frame_region(int(def["sprite_frame"]))
	_ghost.texture = atlas
	_ghost.centered = true
	# Tower.DISPLAY_SCALE too, or the preview would not be the size of the
	# thing it is previewing.
	_ghost.scale = Vector2.ONE * (Tiles.TILE_SIZE * float(def["size"])
		* Tower.DISPLAY_SCALE / Tower.FRAME_SIZE)
	_ghost.modulate = Color(0.4, 1.0, 0.4, 0.5) if verdict["ok"] else Color(1.0, 0.3, 0.3, 0.5)

	# PreviewRange is a sibling of PlacementPreview, not its child - like
	# Tower, where RangeIndicator sits beside _sprite rather than under it -
	# so it never inherits the ghost sprite's scale and always draws `radius`
	# at true size regardless of how the sprite is scaled.
	_ghost_range.visible = verdict["ok"]
	_ghost_range.radius = float(def["range"])
	_ghost_range.tint = def["color"]
	_ghost_range.queue_redraw()

func _handle_tap(world: Vector2) -> void:
	var hit := _tower_at(world)
	if hit != null:
		_select_tower(hit)
		return

	if _selected_kind == &"":
		_deselect_tower()
		return

	_try_place(world)

## The nearest tower whose own radius contains `world`, or null.
##
## Nearest rather than first-match: at the shipped MIN_TOWER_SPACING two hit
## circles cannot overlap, but they can as soon as that value is tuned down,
## and a first-match scan would then make selection depend on child order -
## a bug that would surface during balance tuning, far from its cause.
func _tower_at(world: Vector2) -> Tower:
	var best: Tower = null
	var best_distance := INF
	for child in _towers_root.get_children():
		var tower: Tower = child
		var distance := world.distance_to(tower.position)
		if distance <= Placement.tower_radius(tower.kind) and distance < best_distance:
			best = tower
			best_distance = distance
	return best

## Every tower's position, for Placement.can_place's spacing check.
func _tower_positions() -> Array:
	var out: Array = []
	for child in _towers_root.get_children():
		out.append(child.position)
	return out

func _try_place(world: Vector2) -> void:
	var verdict := Placement.can_place(
		world,
		Placement.tower_radius(_selected_kind),
		_map_renderer.prop_footprints(),
		_tower_positions(),
		_paths,
		Rect2(Vector2.ZERO, Vector2(Maps.pixel_size(_map_name))))
	if not verdict["ok"]:
		placement_rejected.emit(_rejection_message(verdict["reason"]))
		_play_sound(&"denied")
		return

	var total := _towers_root.get_child_count()
	if total >= int(Maps.get_def(_map_name)["tower_budget"]):
		placement_rejected.emit("Tower budget reached.")
		_play_sound(&"denied")
		return

	if _counts[_selected_kind] >= EconomySim.tower_limit(_selected_kind, _map_name):
		placement_rejected.emit("You cannot build any more of that tower.")
		_play_sound(&"denied")
		return

	var price := EconomySim.tower_price(_selected_kind, _counts[_selected_kind])
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		_play_sound(&"denied")
		return

	var tower: Tower = TOWER_SCENE.instantiate()
	_towers_root.add_child(tower)
	tower.setup(_selected_kind, world, price)
	tower.wants_to_fire.connect(_on_tower_fired.bind(tower))

	_counts[_selected_kind] += 1
	_gold -= price

	gold_changed.emit(_gold)
	var placed_kind := _selected_kind

	# Placing consumes the selection. Without this the kind stays armed and
	# the next tap on open ground builds another one, which is the opposite
	# of what a tap on empty ground means once you have finished building.
	_selected_kind = &""
	_ghost.visible = false
	_ghost_range.visible = false

	tower_placed.emit(placed_kind)
	_play_sound(&"place")

## Player-facing text for a Placement refusal. A match rather than a const
## dictionary: a const whose keys reference another class's constants is
## evaluated at parse time and is fragile across script load order.
func _rejection_message(reason: StringName) -> String:
	match reason:
		Placement.REASON_OUT_OF_BOUNDS:
			return "That is off the edge of the map."
		Placement.REASON_ON_PATH:
			return "You cannot build on the road."
		Placement.REASON_BLOCKED_BY_PROP:
			return "Something is already in the way there."
		Placement.REASON_TOO_CLOSE:
			return "That is too close to another tower."
	return "You cannot build there."

func _on_tower_fired(target_node: Node2D, source: Dictionary,
		splash: float, tower: Tower) -> void:
	if not is_instance_valid(target_node):
		return
	_play_sound(&"fire-%s" % tower.kind)
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	_projectiles_root.add_child(projectile)
	projectile.global_position = tower.global_position
	projectile.hit.connect(_on_projectile_hit)
	projectile.launch(target_node, source,
		float(tower.get_def()["projectile_speed"]),
		bool(tower.get_def()["projectile_arcs"]), splash)

func _on_projectile_hit(target_node: Node2D, source: Dictionary, splash: float) -> void:
	if not is_instance_valid(target_node):
		return
	target_node.take_damage(source)
	if splash <= 0.0:
		return
	for enemy in _enemies_root.get_children():
		# The primary target took its hit above, so it is excluded here; the
		# geometry itself is Damage.in_splash, the single copy of the splash
		# rule that sim/harness.gd's balance tests also run.
		if enemy == target_node or not enemy is Enemy:
			continue
		if Damage.in_splash(target_node.global_position, enemy.global_position, splash):
			enemy.take_damage(source)

## Selection is announced as well as drawn: the range ring is the board's own
## feedback, and the inspector is a separate view that has to follow it.
func _select_tower(tower: Tower) -> void:
	_deselect_tower()
	_selected_tower = tower
	tower.set_range_visible(true)
	tower_selected.emit(tower)

func _deselect_tower() -> void:
	if _selected_tower != null and is_instance_valid(_selected_tower):
		_selected_tower.set_range_visible(false)
	_selected_tower = null
	tower_deselected.emit()

## Buys the next tier on a branch of the selected tower.
##
## Gating lives here rather than only in the UI: the cross-path rule is a game
## rule, and a board method that trusted its caller would be one bug away from
## a tower with both branches maxed.
func upgrade_selected_tower(branch: StringName) -> void:
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	var tower := _selected_tower
	if not UpgradesSim.can_upgrade(tower.tiers, branch):
		placement_rejected.emit("That branch is locked - the other path is already committed.")
		_play_sound(&"denied")
		return
	var price := UpgradesSim.upgrade_cost(tower.kind, branch, int(tower.tiers[branch]))
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		_play_sound(&"denied")
		return

	_gold -= price
	gold_changed.emit(_gold)
	tower.apply_upgrade(branch)
	tower_upgraded.emit(branch)
	_play_sound(&"place")

## Advances the selected tower one step through Targeting.PRIORITIES.
##
## The inspector calls this rather than reaching into the tower, matching how
## upgrades and selling already work: the board owns what happens to a
## selected tower, and the panel only asks.
func cycle_selected_tower_priority() -> void:
	# is_instance_valid as well as the null check, matching the other two
	# methods that act on the selected tower. Nothing reaches this with a freed tower today - sell_selected_tower
	# deselects before it frees - but the three guards being different shapes
	# is how the fourth one gets written wrong.
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	_selected_tower.set_priority(Targeting.next_priority(_selected_tower.get_priority()))

func sell_selected_tower() -> void:
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	var tower := _selected_tower
	# Read the kind BEFORE queue_free, and hold it in a local: the panel's
	# handler runs during the emit below and must not reach into a tower that
	# is already on its way out.
	var sold_kind: StringName = tower.kind
	_deselect_tower()
	_gold += EconomySim.sell_refund(tower.price_paid)
	_counts[sold_kind] -= 1
	tower.queue_free()
	gold_changed.emit(_gold)
	tower_sold.emit(sold_kind)
	_play_sound(&"sell")

# --- Audio ---------------------------------------------------------------

## Looks up the AudioManager autoload by absolute path rather than
## referencing its global identifier directly.
##
## The autoload node IS instantiated under `godot --headless --script` (how
## the test suite runs) - probed directly: Engine.get_main_loop().root has
## exactly one child and it is AudioManager - and a bare `AudioManager`
## reference compiles and runs fine in a script loaded via load() the way
## this file is (confirmed with a probe shaped exactly like this file's
## _ready_board() pattern). What actually never happens under this harness
## is NOTIFICATION_READY reaching that node: is_inside_tree() on it is
## false, so its own _ready() never runs, _streams/_players stay empty, and
## play()'s own `has()` guard turns every call into a silent no-op whether
## it is reached directly or through this helper - see test_audio_manager.gd
## for the same finding from the manager's side.
##
## Routing through Engine.get_main_loop().root earns its keep for a second,
## real reason: calling get_node() on `self` when this node was never added
## to a live tree (true for every board the test harness builds) throws
## "Can't use get_node() with absolute paths from outside the active scene
## tree" - calling it on the tree's own root avoids that. In production,
## where the board IS in a live tree and AudioManager HAS completed
## _ready(), this same path finds the real, ready singleton.
func _play_sound(sound: StringName) -> void:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return
	var mgr = loop.root.get_node_or_null("AudioManager")
	if mgr:
		mgr.play(sound)
