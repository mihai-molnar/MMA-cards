class_name CardTemplate
extends RefCounted

## Where every element of a composed card face sits, and how it is styled.
##
## Zones are stored NORMALIZED as 0-1 fractions of the card rect, never in
## pixels. CardView.CARD_SIZE has already changed once (the bigger-readable-
## layout pass), and normalized zones survive that without a re-measure.
## Multiply by CardView.CARD_SIZE via to_pixels() / centred_pixels().
##
## Card-face geometry is layout, and CLAUDE.md keeps layout constants with
## their owner -- this file is that owner, the way card geometry lives in
## card_view.gd and fan geometry in hand_view.gd. Durations and curves belong
## in juice.gd; balance numbers belong in BattleConfig. Neither belongs here.
##
## Every number below was measured off the 1024x1536 template PNGs and then
## checked against a render (tools/capture_cards.gd). Re-measure, do not
## guess, if the templates are ever repainted.

const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"

## Identical on both frames: the ribbon, the art window and the parchment
## panel are drawn in the same place on each.
const TITLE_ZONE: Rect2 = Rect2(0.146, 0.127, 0.713, 0.094)
## COVERS the frame's transparent art opening with bleed on every side,
## rather than tracing it. Measured opening (both frames): x .152-.849,
## y .252-.584 -- but its edges are not clean rectangles. The ribbon's drop
## shadow above and the badge's flanks below are SEMI-transparent, so an
## illustration cut to the opening leaves those pixels showing the dark
## background as a gap between art and frame (shipped once: a dark band
## under the ribbon and dark pockets beside the badge). Overshoot is free --
## the frame draws over the illustration and its paint covers the excess --
## so the zone extends past the opening to just inside the opaque border
## columns. test_card_template.gd asserts the zone contains the measured
## opening.
const WINDOW_ZONE: Rect2 = Rect2(0.14, 0.20, 0.72, 0.50)
## A WRAPPING BOX, not a text extent: the label centres each wrapped line
## inside it, so what must fit the artwork is each rendered LINE, not this
## box (test_card_template.gd models the wrap and asserts exactly that).
##
##   centre .498  the parchment's own measured centre (runs x .163-.834 at
##                the full-width rows) -- rules text is centre-aligned, so it
##                only LOOKS centred if the zone centre sits here. The
##                previous zone ended at .670 to keep the BOX off the corner
##                ornament, which pushed its centre to .423 and every line
##                visibly left of the parchment's middle.
##   top    .688  the defense shield hangs lower than the attack burst (.672),
##                so the shared zone has to clear the later of the two
##   bottom .820  the vertical band the wrapped block is centred in; the
##                lines themselves stay well above the ornament rows
##   width  .600  chosen away from wrap borderlines: in Kreon at RULES_SIZE,
##                Straight's first line ("Deal 9 damage. Combo: +7", 106px)
##                fits 120px with margin, and adding "right" (129px) clearly
##                does not, so the greedy wrap model in the tests and the
##                label's own TextServer wrap agree instead of racing at a
##                boundary. Re-check these margins if the font or size moves.
const RULES_ZONE: Rect2 = Rect2(0.198, 0.688, 0.600, 0.132)

## The value and cost badges are the ONLY zones that differ between the two
## frames, and both are centred on a drawn icon rather than fitted to a panel
## -- hence a centre plus a box rather than a rect. On the attack frame the
## number sits in the free red plate to the right of the burst; on the defense
## frame it sits dead centre in the shield.
## The y values sit ~.007 BELOW the icons' measured pixel centres (plate
## rows .59-.64 -> .615; shield blue bbox centre y .607; disc centres .815
## on both frames): digits have no descender, so a Label centring its full
## line box (ascent + descent) parks the glyph visibly high in the icon.
## The nudge is the optical correction, judged against a zoomed render.
const VALUE_CENTRE: Dictionary = {
	ATTACK: Vector2(0.591, 0.617),
	DEFENSE: Vector2(0.487, 0.612),
}
const VALUE_BOX: Dictionary = {
	ATTACK: Vector2(0.100, 0.070),
	DEFENSE: Vector2(0.150, 0.090),
}
const COST_CENTRE: Dictionary = {
	ATTACK: Vector2(0.788, 0.822),
	DEFENSE: Vector2(0.763, 0.821),
}
const COST_BOX: Vector2 = Vector2(0.120, 0.070)

## Kreon (OFL, assets/fonts/) -- the slab serif Slay the Spire itself uses
## for card text. Two weights from the one variable file: bold for the
## outlined display text (title, value, cost -- light-on-saturated, needs
## the mass), regular for the rules ink on parchment (dark-on-light, needs
## the readability). Every card font routes through these two constants;
## CardView._make_label picks by its `outlined` flag. Swapping faces is a
## re-point of these two .tres files, not a hunt through card_view.gd.
const FONT: Font = preload("res://assets/fonts/kreon_text.tres")
const DISPLAY_FONT: Font = preload("res://assets/fonts/kreon_display.tres")
## 20 with Kreon where the fallback face wore 17: Kreon's caps are narrower
## (STRAIGHT at 20 is 94px against the title zone's 142px), so the size buys
## presence without crowding the ribbon.
const TITLE_SIZE: int = 20
const VALUE_SIZE: int = 22
const COST_SIZE: int = 18
## 10 with Kreon where the fallback face needed 8. Kreon is both narrower
## and tighter-leaded (height 13.75 at 10 vs the fallback's 12 at 8), so the
## bigger size still wraps Straight to 2 lines (~31px against the zone's
## ~40px) with the first line "Deal 9 damage. Combo: +7" -- see the
## RULES_ZONE width note above for the wrap-borderline margins. The card is
## drawn through the project's 2.222x canvas magnification, so 10 here
## renders near 22px on screen -- small in the constant, not on the card.
const RULES_SIZE: int = 10

const TITLE_COLOR: Color = Color(0.98, 0.94, 0.80)
const VALUE_COLOR: Color = Color(1.00, 1.00, 1.00)
const COST_COLOR: Color = Color(1.00, 1.00, 1.00)
## Dark ink on the parchment panel. The only card text that needs no outline:
## it is dark-on-light, where the other three are light-on-saturated.
const RULES_COLOR: Color = Color(0.20, 0.14, 0.08)

const OUTLINE_SIZE: int = 4
const OUTLINE_COLOR: Color = Color(0.05, 0.03, 0.02, 0.9)

## Which frame a card wears. Tag-driven, so it needs no per-card registration:
## anything tagged defense gets the shield, everything else gets the burst.
static func variant_for(card: CardData) -> StringName:
	return DEFENSE if card.has_tag(&"defense") else ATTACK

## Converts a normalized zone to a pixel rect against a card of `size`.
static func to_pixels(zone: Rect2, size: Vector2) -> Rect2:
	return Rect2(zone.position * size, zone.size * size)

## Converts a normalized centre + box to a pixel rect against a card of `size`.
## Takes a CENTRE, not an origin -- a badge is centred on a drawn icon.
static func centred_pixels(centre: Vector2, box: Vector2, size: Vector2) -> Rect2:
	var pixel_box: Vector2 = box * size
	return Rect2(centre * size - pixel_box / 2.0, pixel_box)
