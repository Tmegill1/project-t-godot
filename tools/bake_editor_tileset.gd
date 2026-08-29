extends SceneTree

# Bakes the map editor's tile palette from art the game already ships.
#
#   godot --headless --script tools/bake_editor_tileset.gd
#   godot --headless --import
#   git checkout -- project.godot
#
# WHY REAL GAME ART rather than five flat colours: the editor is where a map
# is judged, and judging it means seeing roughly what the player will. Flat
# colours would make you author a diagram and discover the map only on the
# first run.
#
# The palette is deliberately ONE biome (forest). The editor paints tile
# KINDS, not appearances - which biome a map draws in is a field in
# Maps.DEFS, and painting an ice map in green would imply otherwise.
#
# Endpoints are composited over ground because cave.png and castle.png are
# transparent props, and a transparent tile in the palette reads as an eraser.

const TILE := 48
const OUT := "res://assets/editor/map_palette.png"

## Column order in the baked strip. The exporter maps a column back to a tile
## kind by this index, so the order is a contract - see MapEditorIO.PALETTE.
const ORDER := ["buildable", "path", "blocked", "spawn", "goal"]

func _init() -> void:
	var strip := Image.create(TILE * ORDER.size(), TILE, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0, 0, 0, 0))

	var ground := _load("res://assets/art/forest/ground_0.png")
	for i in ORDER.size():
		var cell := _cell_for(ORDER[i], ground)
		strip.blit_rect(cell, Rect2i(0, 0, TILE, TILE), Vector2i(i * TILE, 0))

	var err := strip.save_png(OUT)
	print("baked %s (%d tiles): %s" % [OUT, ORDER.size(), "ok" if err == OK else str(err)])
	quit()

## One palette cell, always opaque and always TILE square.
func _cell_for(kind: String, ground: Image) -> Image:
	var cell := _fit(ground, TILE)
	match kind:
		"buildable":
			pass  # bare ground is what a buildable cell is
		"path":
			cell = _fit(_load("res://assets/art/forest/road_10.png"), TILE)
		"blocked":
			_overlay(cell, _load("res://assets/art/forest/stone.png"), 0.92)
		"spawn":
			_overlay(cell, _load("res://assets/art/cave.png"), 0.95)
		"goal":
			_overlay(cell, _load("res://assets/art/castle.png"), 0.95)
	return cell

func _load(path: String) -> Image:
	var tex: Texture2D = load(path)
	return tex.get_image()

## Scales an image to fill a square box, preserving aspect by taking the
## larger factor and cropping the overflow - a palette cell must be full
## bleed, or the grid shows through and every tile reads as an icon.
func _fit(src: Image, size: int) -> Image:
	var copy := src.duplicate()
	var factor: float = float(size) / minf(float(src.get_width()), float(src.get_height()))
	copy.resize(int(ceil(src.get_width() * factor)), int(ceil(src.get_height() * factor)),
		Image.INTERPOLATE_LANCZOS)
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	out.blit_rect(copy, Rect2i(
		(copy.get_width() - size) / 2, (copy.get_height() - size) / 2, size, size),
		Vector2i.ZERO)
	return out

## Draws a prop over a ground cell at a fraction of the cell, centred.
func _overlay(cell: Image, prop: Image, fill: float) -> void:
	var box := int(TILE * fill)
	var copy := prop.duplicate()
	var factor: float = float(box) / maxf(float(prop.get_width()), float(prop.get_height()))
	copy.resize(maxi(1, int(prop.get_width() * factor)),
		maxi(1, int(prop.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
	cell.blend_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()),
		Vector2i((TILE - copy.get_width()) / 2, (TILE - copy.get_height()) / 2))
