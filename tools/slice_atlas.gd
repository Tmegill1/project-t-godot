extends SceneTree

# Frame -> source rect in map-sprites.png (1024x1536), from BootScene.create().
#
# ============================================================================
# DEVIATIONS FROM THE REFERENCE RECTS — READ BEFORE CHANGING THIS FILE
# ============================================================================
# Five of the eight rects below were corrected from BootScene.ts's literal
# values after measuring true alpha-channel content bounding boxes in the
# source sheet (flood fill from a seed inside each sprite, cross-checked with
# row/column opacity scans and visual crops with the old/new boundary drawn
# on top — not eyeballed, and not "does it still look like a tree" checked).
# Three (grass, path, spike) were measured the same way and found already
# correct; they are listed unchanged for completeness.
#
# This is a real, visible divergence from the Phaser original, not a neutral
# cleanup. The project spec is explicit that the original's visual quirks —
# including sprite-sheet slicing artifacts — are preserved deliberately:
# "that squashing is the game's actual look." These five corrections make
# tiles cleaner than the source game ever rendered them. That's a defensible
# call (nobody wants a stray boulder glued to the bottom of their castle) but
# it is a decision, not a default, and it is one edit away from being
# reverted: swap any corrected rect below back to the "reference" value in
# its comment to restore exact source-for-source parity with the original.
#
#   name    | reference (BootScene.ts) | used here          | reason
#   --------|--------------------------|---------------------|------------------------------
#   grass   | (60,150,64,64)           | unchanged           | seamless texture swatch, no seam crossed
#   path    | (60,64,64,64)            | unchanged           | seamless texture swatch, no seam crossed
#   tree    | (40,250,100,150)         | (15,248,150,165)    | reference clipped ~20px of canopy off both sides
#   stone   | (670,230,128,128)        | (670,236,128,122)   | reference's top 6px bled in a texture swatch above
#   castle  | (750,600,256,350)        | (750,622,256,302)   | reference bled in a prop row above and a boulder below
#   cave    | (700,880,300,300)        | (716,924,300,216)   | reference bled in on 3 sides, clipped the rock wall on the 4th
#   spike   | (760,530,100,100)        | unchanged           | isolated bush, clean margins already
#   fire    | (650,500,100,100)        | (650,511,100,89)    | reference's top 11px bled in a neighbouring prop's base
# ============================================================================
const FRAMES := [
	{"name": "grass",  "rect": Rect2i(60, 150, 64, 64)},
	{"name": "path",   "rect": Rect2i(60, 64, 64, 64)},
	# Widened from the reference's (40, 250, 100, 150): decoding the source PNG's
	# alpha channel showed the tree canopy is a single connected blob spanning
	# x=[20,159] y=[253,407] — the reference rect clipped ~20px of leaf canopy off
	# both the left and right sides. This box was re-measured, not eyeballed.
	{"name": "tree",   "rect": Rect2i(15, 248, 150, 165)},
	# Trimmed from the reference's (670, 230, 128, 128): a row scan restricted to
	# this rect's own x-range found rows y=225-231 fully opaque edge-to-edge
	# (~123px wide) — the bottom of a dirt/stone-block texture swatch sitting
	# directly above stone in the sheet, not stone content — followed by a clean
	# 8-row transparent gap (y=232-239) before the rock cluster's own top begins
	# at y=240. New top lands mid-gap at y=236. Visually confirmed with a 4x
	# zoomed crop of the boundary: the reference line cuts directly through the
	# texture's cracked pattern.
	{"name": "stone",  "rect": Rect2i(670, 236, 128, 122)},
	# Trimmed on both top and bottom from the reference's (750, 600, 256, 350);
	# left (750) and right (1006) were re-measured and found already correct.
	# TOP: a row scan restricted to x=[750,1006) found the reference's top 22
	# rows (y=600-621) were the tapering-off base of a prop row (fire/spike/an
	# unnamed rock formation) sitting directly above castle, not castle content
	# — narrowing from ~115px wide down to single pixels, then a clean
	# fully-transparent row at y=622, with the tips of castle's own flags first
	# appearing at y=623. New top = 622 (the clean row itself; there is no room
	# for extra margin here, the neighbour is packed tight against castle).
	# BOTTOM: the reference's bottom 45px (y=905-949) is castle's own ground
	# tapering off, followed by a clean 8-row transparent gap (y=920-927), then
	# a separate rock-pile/boulder prop resumes at y=928 and is clearly visible
	# bleeding into the bottom of the original crop. New bottom = 924 (mid-gap).
	# LEFT: a live flood fill (4-connected, alpha>0) grew to x=724, suggesting
	# bleed from a black rock+log prop further left, but a 3x zoomed visual crop
	# showed that prop fully isolated with a wide (~25px) whitespace gap before
	# castle's own tower wall, which begins right at x=750 — the flood fill had
	# followed a single-pixel-wide antialiasing bridge, not real bleed. Reference
	# left (750) is correct; kept unchanged. RIGHT (1006): confirmed clean the
	# same way — castle's rightmost tower ends with visible margin before x=1006.
	{"name": "castle", "rect": Rect2i(750, 622, 256, 302)},
	# Re-measured from the reference's (700, 880, 300, 300): the reference rect's
	# top ~35px was the castle sprite's ground bleeding in, its left ~15px was a
	# neighbouring sprite, its right edge cut off ~13px of the cave's own rock
	# wall, and its bottom ~45px was the next rock-pile sprite bleeding in.
	# Flood-filling the alpha channel from a seed inside the cave mouth found the
	# true connected blob at x=[720,1013] y=[930,1135]; this box adds a few
	# pixels of margin on each side, landing in the confirmed-transparent gutters.
	{"name": "cave",   "rect": Rect2i(716, 924, 300, 216)},
	{"name": "spike",  "rect": Rect2i(760, 530, 100, 100)},
	# Trimmed from the reference's (650, 500, 100, 100): a row scan restricted to
	# this rect's own x-range found no fully clean transparent row between the
	# reference's top and fire's own flame — the base of a grass/rock prop
	# sitting above-right of fire tapers off (count dropping 81 -> 2) right where
	# fire's own embers begin ramping up (count climbing 2 -> 37 through y=524).
	# y=511 is the local-minimum seam (only 2 stray antialiased pixels, both
	# outside the flame's own footprint) between the two; used as the new top.
	# Visually confirmed with a 4x zoomed crop: the reference line cuts through
	# a neighbouring rock/grass base, while the flame and its floating embers
	# sit safely below the new line with a clear margin.
	{"name": "fire",   "rect": Rect2i(650, 511, 100, 89)},
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
