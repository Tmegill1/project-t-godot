@tool
extends Node2D

## Paint a map with Godot's own tile editor, then export it to the text format
## the game reads.
##
## HOW TO USE IT
##   1. Open tools/map_editor.tscn in the Godot editor.
##   2. Select the Layer node. Godot's TileMap panel appears at the bottom -
##      paint with it. The palette is ground, road, rocks, cave, castle, which
##      are spawn/goal/road/buildable/blocked.
##   3. Select this root node. In the Inspector, set `map` and tick `load_map`
##      to pull the committed layout in, or tick `export_map` to write your
##      painting back out.
##   4. `check_map` reports problems without writing anything.
##
## A @tool script, NOT an addon: it runs in the editor because of the
## annotation on line one, and needs nothing enabled in Project Settings. The
## project's no-addons rule stands.
##
## Nothing here ships. tools/ is excluded from the export, and the GAME only
## ever reads the .txt - so this scene can be deleted tomorrow and every map
## still loads. That is the point of exporting to a format rather than making
## the scene the map.
##
## The conversion itself lives in tools/map_editor_io.gd, which is tested
## headlessly. This file is a shell: it moves bytes between that module, the
## Layer, and disk, and reports what happened.

@export_enum("demoMap", "map2", "map3") var map: String = "demoMap"

## Tick to load `map`'s committed layout into the Layer, replacing whatever is
## painted. Untoggles itself - a checkbox is the simplest button the Inspector
## offers without an addon.
@export var load_map := false:
	set(value):
		if value:
			_load_map()
		load_map = false

## Tick to write the Layer back to `map`'s layout file. REFUSES to write a map
## with problems, so a broken map cannot reach the game through this door.
@export var export_map := false:
	set(value):
		if value:
			_export_map()
		export_map = false

## Tick to report problems without writing anything.
@export var check_map := false:
	set(value):
		if value:
			_check_map()
		check_map = false

@onready var _layer: TileMapLayer = $Layer

func _ready() -> void:
	# The TileSet is built in code rather than saved beside the scene, so a
	# re-bake of the palette cannot leave a stale resource mapping columns to
	# the wrong kinds. See MapEditorIO.build_tileset.
	if _layer != null and _layer.tile_set == null:
		_layer.tile_set = MapEditorIO.build_tileset()

func _load_map() -> void:
	var path: String = Maps.DEFS[StringName(map)]["layout"]
	if not FileAccess.file_exists(path):
		push_error("map editor: no layout at %s" % path)
		return
	if _layer.tile_set == null:
		_layer.tile_set = MapEditorIO.build_tileset()
	MapEditorIO.paint_layer(_layer, MapFormat.parse(FileAccess.get_file_as_string(path)))
	print("map editor: loaded %s" % path)

func _check_map() -> Array:
	var tiles := MapEditorIO.tiles_from_layer(_layer)
	var problems := MapEditorIO.problems_with(tiles)
	if problems.is_empty():
		print("map editor: %s looks good - %d x %d" % [
			map, tiles[0].size() if tiles.size() > 0 else 0, tiles.size()])
	else:
		for p in problems:
			push_warning("map editor: %s" % p)
	return problems

func _export_map() -> void:
	# Checked before writing, deliberately. The alternative is a map that
	# fails at run time, and the whole reason this scene calls the real
	# PathFinder is to catch an unwalkable goal at the moment it is drawn
	# rather than the moment it is played.
	if not _check_map().is_empty():
		push_error("map editor: refusing to export %s - fix the problems above" % map)
		return
	var path: String = Maps.DEFS[StringName(map)]["layout"]
	var text := MapFormat.format(MapEditorIO.tiles_from_layer(_layer))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("map editor: could not write %s" % path)
		return
	file.store_string(text + "\n")
	file.close()
	print("map editor: exported %s" % path)
