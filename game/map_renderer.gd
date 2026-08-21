class_name MapRenderer
extends Node2D

## Draws a tile grid. Decoration scatter is seeded so a map renders
## identically every run.

## Shared across every biome: the goal and spawn markers are player landmarks,
## not scenery, and are the same object whatever the map is made of.
const _CASTLE := preload("res://assets/art/castle.png")
const _CAVE := preload("res://assets/art/cave.png")

const _MAX_FIRE_TILES := 7

## z-index ordering. Ground draws below decoration, endpoints and blocked-tile
## overlays. Ground sits at -1 rather than 0 for no reason beyond history: a
## grid overlay used to occupy 0 between them, and the values were left alone
## when it was removed rather than renumbering every layer.
const _Z_GROUND := -1
const _Z_OVERLAY := 1

var _tiles: Array = []
var _rows := 0
var _cols := 0
var _decorations := {}  # Vector2i -> Sprite2D
var _biome: StringName = Biomes.FIRST

## Sprites that count as solid props, recorded as they are created.
##
## This replaces the old _PROP_TEXTURES const array of preloads, which could
## not express a per-biome prop set. Recording at creation is also strictly
## more robust than comparing textures after the fact - two biomes could
## legitimately share a texture without both being props.
var _prop_sprites := {}

func render(tiles: Array, rng: Rng = null, biome: StringName = Biomes.FIRST) -> void:
	if rng == null:
		rng = Rng.new(Seeds.DEFAULT_DECORATION_SEED)
	_biome = biome
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
	_prop_sprites.clear()

	_draw_ground()
	_draw_endpoints()
	_scatter_decoration(rng)
	_draw_blocked(rng)

## Every prop as a world-space blocking circle, for sim/placement.gd.
##
## Endpoints are excluded on purpose: they are drawn 3 tiles wide, so a
## footprint from one would carry a ~72px radius and sterilise the ground
## around the spawn and goal - where a player most wants a last line of
## defence. The path corridor already keeps towers off the endpoints.
##
## Radius is half the sprite's LONGEST displayed axis, so it over-covers
## rather than under-covers: blocking slightly too much reads as level design,
## while a tower clipping into a rock reads as a bug. This only measures
## correctly because _place scales uniformly (see its doc comment); under the
## stretch-to-square behaviour it replaced, displayed size was a distortion.
func prop_footprints() -> Array:
	var out: Array = []
	for child in get_children():
		if not (child is Sprite2D):
			continue
		var sprite: Sprite2D = child
		if not _prop_sprites.has(sprite):
			continue
		var tex: Texture2D = sprite.texture
		var display := Vector2(tex.get_width(), tex.get_height()) * sprite.scale
		out.append({
			"pos": sprite.position + display / 2.0,
			"radius": maxf(display.x, display.y) / 2.0,
		})
	return out

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
	# Every tile here is minified, several of them hard (the largest Kenney
	# source in this renderer is 128px, drawn into a 48px tile). The
	# project-wide default filter is plain LINEAR, which samples the
	# base level only and aliases badly at those ratios; this reads the mipmap
	# chain that the .import files generate instead. LINEAR rather than NEAREST
	# because this art is painted, not pixel art - the enemy sheets are the
	# opposite case and take NEAREST (game/enemy.tscn).
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = z
	add_child(s)
	return s

## Places a prop and records it as one, so prop_footprints can find it.
func _place_prop(slot: StringName, col: int, row: int) -> Sprite2D:
	# load() here, not in Biomes: data/ stays engine-free (test_sim_purity.gd).
	var texture: Texture2D = load(Biomes.prop_path(_biome, slot))
	var sprite := _place(texture, col, row, Tiles.TILE_SIZE, _Z_OVERLAY)
	_prop_sprites[sprite] = true
	return sprite

## Ground is one sprite per tile, on the tile grid.
##
## This replaces a corner-mask lattice that sampled terrain at tile centres
## over a (cols+1) x (rows+1) grid offset half a tile. That existed because the
## previous art blended between terrains; this art does not - its cells are
## discrete cards and its road pieces are shapes. An edge mask over orthogonal
## neighbours is the simpler thing that this art actually wants.
##
## Ground variety is drawn from its own Rng rather than the decoration one.
## Which of the six ground cards a tile gets is cosmetic and should not move
## when the decoration seed changes; drawing from the passed rng here would
## also shift the whole decoration stream, since _draw_ground runs first.
func _draw_ground() -> void:
	var variants := Rng.new(Seeds.DEFAULT_GROUND_SEED)
	for r in _rows:
		for c in _cols:
			# load() rather than a texture from Biomes: data/ is held
			# engine-free by test_sim_purity.gd, so the render layer is where
			# a path becomes a resource. Godot's ResourceLoader caches by
			# path, so the repeated calls are dictionary hits.
			if _is_road(c, r):
				_place_tile(load(Biomes.road_path(_biome, edge_mask(c, r))), c, r)
			else:
				_place_tile(load(Biomes.ground_path(
					_biome, variants.int_range(0, Biomes.GROUND_VARIANTS - 1))), c, r)

## The four orthogonal neighbours of a cell that are road, as a bitmask.
## Bit order is fixed: N=1, E=2, S=4, W=8. Out of bounds is not road.
## Public so tests can assert the mask without inspecting sprites.
func edge_mask(c: int, r: int) -> int:
	var mask := 0
	if _is_road(c, r - 1):
		mask |= 1
	if _is_road(c + 1, r):
		mask |= 2
	if _is_road(c, r + 1):
		mask |= 4
	if _is_road(c - 1, r):
		mask |= 8
	return mask

## Draws a ground or road tile STRETCHED to fill its cell exactly.
##
## Deliberately not _place. A tile is a cell of a grid and has to cover its
## cell; _place fits a source inside the box preserving aspect and centres it
## in the slack, which is right for a prop and opens seams here - the road
## pieces are 66x63, so aspect-fitting leaves 2.2px of transparency under
## every one of them. The distortion this trades for is 4.7% on the roads and
## under 2% on the ground.
##
## prop_footprints reads displayed size to derive a blocking radius and its
## doc comment says that only measures correctly because _place scales
## uniformly. That stays true: props still go through _place, and nothing
## drawn here is ever recorded as a prop.
func _place_tile(texture: Texture2D, col: int, row: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.position = Vector2(col * Tiles.TILE_SIZE, row * Tiles.TILE_SIZE)
	s.scale = Vector2(
		float(Tiles.TILE_SIZE) / float(texture.get_width()),
		float(Tiles.TILE_SIZE) / float(texture.get_height()))
	# Same reasoning as _place: this art is painted, not pixel art, and every
	# tile is minified from 66px into 48px.
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.z_index = _Z_GROUND
	add_child(s)
	return s

## Out of bounds reads as ground, which is what the edge mask needs at the
## map's border without a special case.
func _is_road(c: int, r: int) -> bool:
	if r < 0 or r >= _rows or c < 0 or c >= _cols:
		return false
	return _tiles[r][c] in Tiles.WALKABLE

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
		_decorations[t] = _place_prop(&"spike", t.x, t.y)

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
		_decorations[t] = _place_prop(&"fire", t.x, t.y)

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
		_place_prop(&"stone" if stones.has(t) else &"tree", t.x, t.y)

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
