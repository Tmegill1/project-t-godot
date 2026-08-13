class_name GameBoard
extends Node2D

## The hub that wires sim to views: owns gold, lives, the wave number, the
## occupied-tile map and per-kind tower counts; runs spawns from the
## schedule; ticks towers; resolves projectile hits including splash; and
## handles taps for placement. The sim modules decide, the board wires - it
## contains no targeting, damage, leak-cost, pricing or scheduling rules of
## its own; every one of those questions is delegated to sim/ or data/.

signal gold_changed(gold: int)
signal lives_changed(lives: int)
signal wave_changed(wave: int, max_waves: int)
signal wave_state_changed(active: bool)
signal game_over()
signal victory()
signal tower_placed(kind: StringName)
signal placement_rejected(reason: String)

const ENEMY_SCENE := preload("res://game/enemy.tscn")
const TOWER_SCENE := preload("res://game/tower.tscn")
const PROJECTILE_SCENE := preload("res://game/projectile.tscn")

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
var _occupied := {}          # Vector2i -> Tower
var _counts := {}            # StringName -> int
var _spawn_queue: Array = []  # {kind, at_ms}
var _wave_clock := 0.0
var _spawned := 0

@onready var _map_renderer: MapRenderer = $MapRenderer
@onready var _towers_root: Node2D = $Towers
@onready var _enemies_root: Node2D = $Enemies
@onready var _projectiles_root: Node2D = $Projectiles

func _ready() -> void:
	var def := Maps.get_def(_map_name)
	Grid.set_active(def["cols"], def["rows"], def["tile_size"])
	_tiles = Maps.build_tiles(_map_name)
	_map_renderer.render(_tiles)
	_paths = PathFinder.get_all_spawn_paths(_tiles)

	_gold = int(def["starting_gold"])
	_lives = Economy.STARTING_LIVES
	for kind in Towers.KINDS:
		_counts[kind] = 0

	gold_changed.emit(_gold)
	lives_changed.emit(_lives)
	wave_changed.emit(_wave, Waves.MAX_WAVES)

func get_gold() -> int: return _gold
func get_lives() -> int: return _lives
func get_wave() -> int: return _wave
func is_wave_active() -> bool: return _wave_active

func get_tower_count(kind: StringName) -> int:
	return _counts.get(kind, 0)

func select_tower_kind(kind: StringName) -> void:
	_selected_kind = kind
	_deselect_tower()

func start_next_wave() -> void:
	if _wave_active or _run_finished:
		return
	_wave += 1
	if _wave > Waves.MAX_WAVES:
		return
	_wave_active = true
	_wave_clock = 0.0
	_spawned = 0
	_spawn_queue = Waves.build_schedule(_wave)
	wave_changed.emit(_wave, Waves.MAX_WAVES)
	wave_state_changed.emit(true)

func _physics_process(delta: float) -> void:
	if _run_finished:
		return
	var delta_ms := delta * 1000.0

	if _wave_active:
		_wave_clock += delta_ms
		while _spawned < _spawn_queue.size() \
				and _spawn_queue[_spawned]["at_ms"] <= _wave_clock:
			_spawn(_spawn_queue[_spawned]["kind"])
			_spawned += 1

	var candidates: Array = []
	for enemy in _enemies_root.get_children():
		if enemy is Enemy and enemy.sim["alive"] and not enemy.sim["dying"]:
			candidates.append(enemy.to_candidate())

	for tower in _towers_root.get_children():
		if tower is Tower:
			tower.tick(delta_ms, candidates)

	if _wave_active and _spawned >= _spawn_queue.size() \
			and _enemies_root.get_child_count() == 0:
		_on_wave_cleared()

func _spawn(kind: StringName) -> void:
	if _paths.is_empty():
		return
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	_enemies_root.add_child(enemy)
	enemy.setup(kind, _paths[0], _wave)
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)

func _on_enemy_died(reward: int) -> void:
	_gold += reward
	gold_changed.emit(_gold)

func _on_enemy_leaked(life_loss: int) -> void:
	_lives = maxi(0, _lives - life_loss)
	lives_changed.emit(_lives)
	if _lives <= 0 and not _run_finished:
		_run_finished = true
		_wave_active = false
		game_over.emit()

func _on_wave_cleared() -> void:
	_wave_active = false
	wave_state_changed.emit(false)
	if _wave >= Waves.MAX_WAVES and not _run_finished:
		_run_finished = true
		victory.emit()

# --- Input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _run_finished:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_tap(get_global_mouse_position())
		get_viewport().set_input_as_handled()

func _handle_tap(world: Vector2) -> void:
	var t := Grid.world_to_tile(world.x, world.y)
	if not t["in_bounds"]:
		return
	var key := Vector2i(t["col"], t["row"])

	if _occupied.has(key):
		_select_tower(_occupied[key])
		return

	if _selected_kind == &"":
		_deselect_tower()
		return

	_try_place(t["col"], t["row"])

func _try_place(col: int, row: int) -> void:
	if _tiles[row][col] != Tiles.BUILDABLE:
		placement_rejected.emit("You can only build on open ground.")
		return

	var total := _towers_root.get_child_count()
	if total >= int(Maps.get_def(_map_name)["tower_budget"]):
		placement_rejected.emit("Tower budget reached.")
		return

	if _counts[_selected_kind] >= EconomySim.tower_limit(_selected_kind, _map_name):
		placement_rejected.emit("You cannot build any more of that tower.")
		return

	var price := EconomySim.tower_price(_selected_kind, _counts[_selected_kind])
	if not EconomySim.can_afford(_gold, price):
		placement_rejected.emit("Not enough gold — that costs %d." % price)
		return

	var tower: Tower = TOWER_SCENE.instantiate()
	_towers_root.add_child(tower)
	tower.setup(_selected_kind, col, row, price)
	tower.wants_to_fire.connect(_on_tower_fired.bind(tower))

	_occupied[Vector2i(col, row)] = tower
	_counts[_selected_kind] += 1
	_gold -= price
	_map_renderer.clear_decoration_at(col, row)

	gold_changed.emit(_gold)
	var placed_kind := _selected_kind

	# Placing consumes the selection. Without this the kind stays armed and
	# the next tap on open ground builds another one, which is the opposite
	# of what a tap on empty ground means once you have finished building.
	_selected_kind = &""

	tower_placed.emit(placed_kind)

func _on_tower_fired(target_node: Node2D, source: Dictionary,
		splash: float, tower: Tower) -> void:
	if not is_instance_valid(target_node):
		return
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

func _select_tower(tower: Tower) -> void:
	_deselect_tower()
	_selected_tower = tower
	tower.set_range_visible(true)

func _deselect_tower() -> void:
	if _selected_tower != null and is_instance_valid(_selected_tower):
		_selected_tower.set_range_visible(false)
	_selected_tower = null

func sell_selected_tower() -> void:
	if _selected_tower == null or not is_instance_valid(_selected_tower):
		return
	var tower := _selected_tower
	_deselect_tower()
	_gold += EconomySim.sell_refund(tower.price_paid)
	_counts[tower.kind] -= 1
	_occupied.erase(Vector2i(tower.grid_col, tower.grid_row))
	tower.queue_free()
	gold_changed.emit(_gold)
