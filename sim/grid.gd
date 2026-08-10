class_name Grid

## Tile <-> world-pixel conversion for whichever map is loaded.
##
## Active dimensions are static state rather than a parameter: there is only
## ever one map loaded, and threading it through every caller buys nothing.
## Call set_active() before anything reads a tile coordinate.

static var _cols := 23
static var _rows := 14
static var _tile_size := Tiles.TILE_SIZE

static func set_active(cols: int, rows: int, tile_size: int = Tiles.TILE_SIZE) -> void:
	_cols = cols
	_rows = rows
	_tile_size = tile_size

static func get_active() -> Dictionary:
	return {"cols": _cols, "rows": _rows, "tile_size": _tile_size}

static func tile_to_world_center(col: int, row: int) -> Vector2:
	var half := float(_tile_size) / 2.0
	return Vector2(float(col * _tile_size) + half, float(row * _tile_size) + half)

static func world_to_tile(x: float, y: float) -> Dictionary:
	var col := int(floor(x / float(_tile_size)))
	var row := int(floor(y / float(_tile_size)))
	return {
		"col": col,
		"row": row,
		"in_bounds": col >= 0 and col < _cols and row >= 0 and row < _rows,
	}
