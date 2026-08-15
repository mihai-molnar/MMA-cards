extends SceneTree

## Generates the defense card frame from the master template by recolouring
## its red accents steel-blue. Accents ONLY: the dark cage metal, gold trims
## and silver bevels are untouched, so attack and defense cards still read
## as one product -- the hue split is what lets a player sort the hand
## without reading anything (the same job frame colour does in Slay the
## Spire).
##
## A generated recolour rather than a second authored template on purpose:
## a separately produced PNG would not be pixel-aligned with the master, and
## the shared CardTemplate zones depend on the geometry being IDENTICAL --
## which a recolour guarantees by construction and
## test_card_template.gd's PNG-measuring guards then enforce. The day
## defense wants its own design language (not just its own hue), replace
## the generated file with an authored one at the same path; if that
## authored frame moves geometry, those same guards fail loudly and
## per-variant zones become a real requirement.
##
## Deterministic: same master in, byte-identical PNG out. Re-run after any
## master repaint:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless \
##     --path . --script res://tools/generate_defense_frame.gd

const SOURCE: String = "res://assets/frames/card_master_template.png"
const OUTPUT: String = "res://assets/frames/card_master_template_defense.png"

## A pixel is "red accent" by dominance: how far red rises above the larger
## of the other two channels. The accents measure ~(.77, .11, .11) -- deeply
## dominant -- while the warm greys of the metal stay within a few percent.
## The band between the thresholds feathers the remap so anti-aliased trim
## edges blend instead of haloing.
const REDNESS_FULL: float = 0.12
const REDNESS_NONE: float = 0.02

func _initialize() -> void:
	var image := Image.new()
	var err: int = image.load(ProjectSettings.globalize_path(SOURCE))
	if err != OK:
		push_error("failed to load %s: %d" % [SOURCE, err])
		quit(1)
		return

	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var p: Color = image.get_pixelv(Vector2i(x, y))
			var redness: float = p.r - maxf(p.g, p.b)
			if redness <= REDNESS_NONE:
				continue
			var weight: float = clampf(
				(redness - REDNESS_NONE) / (REDNESS_FULL - REDNESS_NONE), 0.0, 1.0)
			# Steel-blue remap that preserves the pixel's brightness pattern:
			# red's energy moves to blue, and a fraction of it lifts green so
			# the result lands on steel (~hue 210) rather than royal blue.
			# (.77, .11, .11) -> (.11, .34, .77).
			var remapped := Color(p.b, lerpf(p.g, p.r, 0.35), p.r, p.a)
			image.set_pixelv(Vector2i(x, y), p.lerp(remapped, weight))

	image.save_png(ProjectSettings.globalize_path(OUTPUT))
	print("wrote %s" % OUTPUT)
	quit(0)
