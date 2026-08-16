class_name MapRenderer
extends Node2D

## Draws a tile grid. Decoration scatter is seeded so a map renders
## identically every run.

const _GRASS := preload("res://assets/map/grass.png")
const _PATH := preload("res://assets/map/path.png")
const _TREE := preload("res://assets/map/tree.png")
const _STONE := preload("res://assets/map/stone.png")
const _CASTLE := preload("res://assets/map/castle.png")
const _CAVE := preload("res://assets/map/cave.png")
const _SPIKE := preload("res://assets/map/spike.png")
const _FIRE := preload("res://assets/map/fire.png")

const _MAX_FIRE_TILES := 7

## z-index ordering. Godot z_index is an int, so the grid overlay cannot sit
## at a value strictly between two adjacent integers: ground is shifted down
## to -1 so the grid (0) lands strictly between the ground layer and the
## decoration/endpoint/blocked-tile overlays (1), instead of tying with the
## ground at 0.
const _Z_GROUND := -1
const _Z_GRID := 0
const _Z_OVERLAY := 1

const _GRID_LINE_COLOR := Color8(0x2a, 0x2a, 0x2a)

var _tiles: Array = []
var _rows := 0
var _cols := 0
var _decorations := {}  # Vector2i -> Sprite2D

func render(tiles: Array, rng: Rng = null) -> void:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DECORATION_SEED)
	_tiles = tiles
	_rows = tiles.size()
	_cols = tiles[0].size() if _rows > 0 else 0

	# Freed synchronously, not queue_free()'d: queue_free() only unparents a
	# node once a frame actually processes, which never happens within a
	# single headless test method (no await allowed) - a queue_free() here
	# would leave the previous render's sprites in get_children() alongside
	# the new ones, doubling counts on every re-render observed synchronously.
	# The sprites being cleared are owned exclusively by this node (nothing
	# else holds a reference once _decorations.clear() runs), so an immediate
	# free() is safe.
	for child in get_children():
		child.free()
	_decorations.clear()

	_draw_ground()
	_draw_endpoints()
	_scatter_decoration(rng)
	_draw_blocked(rng)
	_draw_grid_overlay()

## Removes a decoration sprite when a tower is built on its tile.
func clear_decoration_at(col: int, row: int) -> bool:
	var key := Vector2i(col, row)
	if not _decorations.has(key):
		return false
	_decorations[key].free()
	_decorations.erase(key)
	return true

## Fits a texture inside a size_px square box preserving the source aspect
## ratio, then centres it in that box.
##
## DELIBERATE DIVERGENCE FROM THE REFERENCE. Phaser's MapRenderer.ts uses
## setDisplaySize(size, size), which stretches each source to a square
## whatever its true proportions are; most of this art is not square, so the
## reference visibly distorts it (stone.png is 216x97 - squashed over 2:1 -
## and cave.png 300x216). Matching that stretch was faithful but wrong-looking,
## so the port scales uniformly instead. Anything comparing rendered geometry
## against the Phaser build will differ here, by design.
##
## Centring has to be applied to the position because these sprites are
## top-left anchored (centered = false, matching Phaser's setOrigin(0, 0)):
## once a sprite no longer fills its box, the leftover slack is split evenly
## rather than all landing on the right/bottom edge. A square source has zero
## slack and so still lands exactly on its tile origin, which is what keeps
## the ground layer flush and seam-free.
func _place(texture: Texture2D, col: int, row: int, size_px: float,
		z: int, offset := Vector2.ZERO) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	var src := Vector2(texture.get_width(), texture.get_height())
	var factor := size_px / maxf(src.x, src.y)
	var slack := (Vector2(size_px, size_px) - src * factor) / 2.0
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE) + offset + slack
	s.scale = Vector2.ONE * factor
	# Every tile here is minified, several of them hard (stone.png 216px into
	# 48px). The project-wide default filter is plain LINEAR, which samples the
	# base level only and aliases badly at those ratios; this reads the mipmap
	# chain that the .import files generate instead. LINEAR rather than NEAREST
	# because this art is painted, not pixel art - the enemy sheets are the
	# opposite case and take NEAREST (game/enemy.tscn).
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = z
	add_child(s)
	return s

func _draw_ground() -> void:
	for r in _rows:
		for c in _cols:
			var kind = _tiles[r][c]
			if kind == Tiles.PATH or kind == Tiles.SPAWN or kind == Tiles.GOAL:
				_place(_PATH, c, r, Tiles.TILE_SIZE, _Z_GROUND)
			else:
				_place(_GRASS, c, r, Tiles.TILE_SIZE, _Z_GROUND)

func _draw_endpoints() -> void:
	# Drawn 3 tiles wide, offset up and left, matching the Phaser build.
	var offset := Vector2(-Tiles.TILE_SIZE, -Tiles.TILE_SIZE - 20)
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.SPAWN:
				_place(_CAVE, c, r, Tiles.TILE_SIZE * 3, _Z_OVERLAY, offset)
			elif _tiles[r][c] == Tiles.GOAL:
				_place(_CASTLE, c, r, Tiles.TILE_SIZE * 3, _Z_OVERLAY, offset)

func _scatter_decoration(rng: Rng) -> void:
	var buildable: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BUILDABLE:
				buildable.append(Vector2i(c, r))

	var spike_count: int = mini(buildable.size(), maxi(5, int(floor(buildable.size() * 0.1))))
	var shuffled := rng.shuffle(buildable)
	for i in spike_count:
		var t: Vector2i = shuffled[i]
		_decorations[t] = _place(_SPIKE, t.x, t.y, Tiles.TILE_SIZE, _Z_OVERLAY)

	var path_adjacent: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.BUILDABLE:
				continue
			if _decorations.has(Vector2i(c, r)):
				continue
			if _is_adjacent_to_walkable(r, c):
				path_adjacent.append(Vector2i(c, r))

	var fire_count: int = mini(path_adjacent.size(), _MAX_FIRE_TILES)
	var shuffled_adjacent := rng.shuffle(path_adjacent)
	for i in fire_count:
		var t: Vector2i = shuffled_adjacent[i]
		_decorations[t] = _place(_FIRE, t.x, t.y, Tiles.TILE_SIZE, _Z_OVERLAY)

func _draw_blocked(rng: Rng) -> void:
	var excluded := {}
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] != Tiles.SPAWN and _tiles[r][c] != Tiles.GOAL:
				continue
			for dr in range(-1, 2):
				for dc in range(-1, 2):
					excluded[Vector2i(c + dc, r + dr)] = true

	var blocked: Array = []
	for r in _rows:
		for c in _cols:
			if _tiles[r][c] == Tiles.BLOCKED and not excluded.has(Vector2i(c, r)):
				blocked.append(Vector2i(c, r))

	var stone_count: int = mini(blocked.size(), rng.int_range(3, 5))
	var shuffled := rng.shuffle(blocked)
	var stones := {}
	for i in stone_count:
		stones[shuffled[i]] = true

	for t in blocked:
		_place(_STONE if stones.has(t) else _TREE, t.x, t.y, Tiles.TILE_SIZE, _Z_OVERLAY)

func _is_adjacent_to_walkable(row: int, col: int) -> bool:
	# The loop variable below is untyped Variant (an array literal's element
	# type is not inferred), so `:=` cannot infer a type for nr/nc from a
	# Variant-typed member access and hard-fails to parse ("Cannot infer the
	# type of ... variable") on Godot 4.7.1. Explicit `int` typing sidesteps
	# the broken inference; this is not a behavioural change from the brief.
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var nr: int = row + d.y
		var nc: int = col + d.x
		if nr < 0 or nr >= _rows or nc < 0 or nc >= _cols:
			continue
		if _tiles[nr][nc] in Tiles.WALKABLE:
			return true
	return false

## 1px grid overlay for tower-placement legibility (reference: MapRenderer.ts
## drawGrid()). Rebuilt by render() along with everything else, and sized
## from the tiles actually passed to render() - never from a map's static
## constants, so a differently-sized map still gets a correctly-bounded grid.
func _draw_grid_overlay() -> void:
	var grid := _GridOverlay.new()
	grid.cols = _cols
	grid.rows = _rows
	grid.z_index = _Z_GRID
	add_child(grid)
	grid.queue_redraw()

## The grid's line geometry is exposed as a plain data method (grid_lines)
## rather than only being computable inside _draw(), because CanvasItem only
## permits draw_* calls during an actual engine-driven redraw pass - which a
## synchronous, frameless headless test can never trigger. _draw() itself
## just replays whatever grid_lines() computes.
class _GridOverlay extends Node2D:
	var cols := 0
	var rows := 0

	## Vertical lines (x = c * TILE_SIZE for c in 0..cols inclusive, full
	## height) followed by horizontal lines (y = r * TILE_SIZE for r in
	## 0..rows inclusive, full width). cols + 1 and rows + 1 lines respectively,
	## including the outer edges.
	func grid_lines() -> Array:
		var lines: Array = []
		var ts := Tiles.TILE_SIZE
		for c in range(cols + 1):
			var x := c * ts
			lines.append([Vector2(x, 0), Vector2(x, rows * ts)])
		for r in range(rows + 1):
			var y := r * ts
			lines.append([Vector2(0, y), Vector2(cols * ts, y)])
		return lines

	func _draw() -> void:
		for line in grid_lines():
			draw_line(line[0], line[1], _GRID_LINE_COLOR, 1.0)
