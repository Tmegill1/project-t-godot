class_name MapEditorIO

## Converts between a painted TileMapLayer and the text map format.
##
## This is the bridge in the pipeline the project chose: author with Godot's
## own tile painter, export to text, and the GAME only ever reads text. The
## editor is therefore optional - a map can still be typed by hand, and
## nothing at runtime knows this file exists.
##
## Lives in tools/, which is excluded from the export, so none of this ships.
##
## Deliberately separate from the editor SCENE. A scene cannot be exercised
## headlessly in this project's test harness, and the conversion is where the
## bugs would be - so the conversion is a plain function over a TileMapLayer
## and the scene is a thin shell around it.

## Palette column -> tile kind. The order is a contract with
## tools/bake_editor_tileset.gd, which bakes the strip in this order.
const PALETTE: Array[StringName] = [
	Tiles.BUILDABLE,
	Tiles.PATH,
	Tiles.BLOCKED,
	Tiles.SPAWN,
	Tiles.GOAL,
]

## The atlas source id the editor scene's TileSet uses. One source, one row.
const SOURCE_ID := 0

## The palette texture the editor paints from.
const PALETTE_TEXTURE := "res://assets/editor/map_palette.png"

## Builds the TileSet the editor scene paints with.
##
## Constructed in code rather than saved as a .tres so the palette cannot
## drift from tools/bake_editor_tileset.gd: a re-bake that changed the tile
## order would otherwise leave a stale resource mapping columns to the wrong
## kinds, and nothing would notice until a map exported wrong. The tests build
## it through this same function, so they exercise what the scene uses.
static func build_tileset() -> TileSet:
	var texture: Texture2D = load(PALETTE_TEXTURE)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(Tiles.TILE_SIZE, Tiles.TILE_SIZE)
	for i in PALETTE.size():
		source.create_tile(Vector2i(i, 0))
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(Tiles.TILE_SIZE, Tiles.TILE_SIZE)
	tileset.add_source(source, SOURCE_ID)
	return tileset

## Which palette column paints a kind. Inverse of PALETTE, derived rather than
## written twice.
static func column_for(kind: StringName) -> int:
	return PALETTE.find(kind)

## Reads a painted layer into the tile array the game speaks.
##
## Bounds come from the painted cells themselves, so the map is exactly what
## was drawn - there is no canvas size to keep in sync, and moving the whole
## map does not change it. An unpainted cell inside the bounds becomes
## BUILDABLE, which is the sane default: it is the kind you would have had to
## paint everywhere otherwise.
static func tiles_from_layer(layer: TileMapLayer) -> Array:
	var used: Array[Vector2i] = layer.get_used_cells()
	if used.is_empty():
		return []

	var min_c: int = used[0].x
	var max_c: int = used[0].x
	var min_r: int = used[0].y
	var max_r: int = used[0].y
	for cell in used:
		min_c = mini(min_c, cell.x)
		max_c = maxi(max_c, cell.x)
		min_r = mini(min_r, cell.y)
		max_r = maxi(max_r, cell.y)

	var tiles: Array = []
	for r in range(min_r, max_r + 1):
		var row: Array = []
		for c in range(min_c, max_c + 1):
			row.append(_kind_at(layer, Vector2i(c, r)))
		tiles.append(row)
	return tiles

## The kind painted in one cell, or BUILDABLE when nothing is.
static func _kind_at(layer: TileMapLayer, cell: Vector2i) -> StringName:
	if layer.get_cell_source_id(cell) < 0:
		return Tiles.BUILDABLE
	var column: int = layer.get_cell_atlas_coords(cell).x
	if column < 0 or column >= PALETTE.size():
		return Tiles.BUILDABLE
	return PALETTE[column]

## Paints a tile array onto a layer, replacing whatever was there.
##
## The inverse of tiles_from_layer for any array it could have produced, which
## is what makes the round trip safe: open a committed map, edit it, write it
## back, and the parts you did not touch are byte-identical.
static func paint_layer(layer: TileMapLayer, tiles: Array) -> void:
	layer.clear()
	for r in tiles.size():
		var row: Array = tiles[r]
		for c in row.size():
			var column := column_for(row[c])
			if column < 0:
				continue  # an unknown kind paints nothing rather than guessing
			layer.set_cell(Vector2i(c, r), SOURCE_ID, Vector2i(column, 0))

## Everything wrong with a painted map, as human-readable strings.
##
## Structural problems come from MapFormat, which the game itself uses, so the
## editor cannot accept a map the loader would reject. On top of that it runs
## the REAL pathfinder: a goal you cannot walk to is the one defect no
## structural check can see, and today you discover it by playing the map.
static func problems_with(tiles: Array) -> Array:
	var problems := MapFormat.validate(tiles)
	if not problems.is_empty():
		return problems  # pathfinding a malformed grid is not meaningful

	# unreachable_spawns, NOT get_all_spawn_paths. The latter returns a
	# two-point fallback path for a spawn it cannot route, so counting its
	# results always equals counting spawns and would accept a map with a wall
	# across it.
	for spawn in PathFinder.unreachable_spawns(tiles):
		problems.append("the spawn at column %d, row %d cannot reach the goal"
			% [spawn.x, spawn.y])
	return problems
