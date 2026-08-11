extends SceneTree

# Frame -> source rect in map-sprites.png (1024x1536), from BootScene.create().
const FRAMES := [
	{"name": "grass",  "rect": Rect2i(60, 150, 64, 64)},
	{"name": "path",   "rect": Rect2i(60, 64, 64, 64)},
	# Widened from the reference's (40, 250, 100, 150): decoding the source PNG's
	# alpha channel showed the tree canopy is a single connected blob spanning
	# x=[20,159] y=[253,407] — the reference rect clipped ~20px of leaf canopy off
	# both the left and right sides. This box was re-measured, not eyeballed.
	{"name": "tree",   "rect": Rect2i(15, 248, 150, 165)},
	{"name": "stone",  "rect": Rect2i(670, 230, 128, 128)},
	{"name": "castle", "rect": Rect2i(750, 600, 256, 350)},
	# Re-measured from the reference's (700, 880, 300, 300): the reference rect's
	# top ~35px was the castle sprite's ground bleeding in, its left ~15px was a
	# neighbouring sprite, its right edge cut off ~13px of the cave's own rock
	# wall, and its bottom ~45px was the next rock-pile sprite bleeding in.
	# Flood-filling the alpha channel from a seed inside the cave mouth found the
	# true connected blob at x=[720,1013] y=[930,1135]; this box adds a few
	# pixels of margin on each side, landing in the confirmed-transparent gutters.
	{"name": "cave",   "rect": Rect2i(716, 924, 300, 216)},
	{"name": "spike",  "rect": Rect2i(760, 530, 100, 100)},
	{"name": "fire",   "rect": Rect2i(650, 500, 100, 100)},
]

func _initialize() -> void:
	var source := Image.load_from_file("res://assets/map_sprites_source.png")
	if source == null:
		printerr("could not load res://assets/map_sprites_source.png")
		quit(1)
		return

	for frame in FRAMES:
		var rect: Rect2i = frame["rect"]
		var out := Image.create(rect.size.x, rect.size.y, false, source.get_format())
		out.blit_rect(source, rect, Vector2i.ZERO)
		var path := "res://assets/map/%s.png" % frame["name"]
		DirAccess.make_dir_recursive_absolute("res://assets/map")
		var err := out.save_png(path)
		if err != OK:
			printerr("failed writing %s: %d" % [path, err])
			quit(1)
			return
		print("wrote %s (%dx%d)" % [path, rect.size.x, rect.size.y])

	quit(0)
