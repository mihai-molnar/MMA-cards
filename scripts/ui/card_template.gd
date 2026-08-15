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
## Every number below was measured off the 1036x1554 master template PNG and
## then checked against a render (tools/capture_cards.gd). Re-measure, do not
## guess, if the template is ever repainted.

## The ONE frame every card wears: the dark octagon-cage master template.
## Attack and defense no longer differ by frame -- they differ by the word on
## the type plate and the colour of the numbers in the rules text.
const FRAME: StringName = &"card_master_template"

## Variants survive the single-frame world because two things still read off
## the tags: the type plate's word and the keyword-less number colour.
const ATTACK: StringName = &"attack"
const DEFENSE: StringName = &"defense"

## The banner across the top of the frame, between its two metal trims. The
## banner is an ARCH, not a bar: its painted midline is highest mid-span
## (y .088) and sags to ~.099 / ~.106 at the zone's ends, so the zone is
## centred on the APEX and ArcTitleLabel bends the glyph run down
## TITLE_ARC_BOW toward the ends. The bow is the measured sag at the zone
## edge (~4.8px at the current card size) as a fraction of the zone's pixel
## width, so it scales with the card the way the zones do.
const TITLE_ZONE: Rect2 = Rect2(0.22, 0.051, 0.62, 0.075)
const TITLE_ARC_BOW: float = 0.039
## COVERS the frame's transparent art opening with bleed on every side,
## rather than tracing it. Measured opening: x .126-.873, y .168-.576 -- but
## the opening is an octagon with anti-aliased cut corners, so an
## illustration cut to the bbox still shows the background through the
## semi-transparent edge pixels as dark gaps between art and frame (that
## shipped once on the old frames). Overshoot is free -- the frame draws
## over the illustration and its paint covers the excess -- so the zone
## extends past the opening on every side. test_card_template.gd asserts
## the zone contains the measured opening.
const WINDOW_ZONE: Rect2 = Rect2(0.10, 0.14, 0.80, 0.47)
## The small riveted plate hanging under the art window -- the type plate,
## where Slay the Spire prints "Attack". The plate's painted interior runs
## y .570-.620 (centre .595); the zone centres the text on .600 -- the same
## ~.005 no-descender optical nudge the cost octagon carries, because
## caps-only text centred by its full line box parks visibly high in the
## plate (shipped that way once, flagged from an in-game screenshot).
const TYPE_ZONE: Rect2 = Rect2(0.354, 0.575, 0.30, 0.050)
## A WRAPPING BOX, not a text extent: the label centres each wrapped line
## inside it, so what must fit the artwork is each rendered LINE, not this
## box (test_card_template.gd models the wrap and asserts exactly that).
## The rules panel's painted interior runs x .082-.913, so the zone centre
## sits on .498 -- rules text is centre-aligned, and it only LOOKS centred
## if the zone centre sits on the panel's. The vertical band keeps the
## wrapped block off the panel's darkest bottom vignette.
const RULES_ZONE: Rect2 = Rect2(0.158, 0.648, 0.680, 0.220)

## The cost octagon, top-left. Centred on a drawn icon rather than fitted to
## a panel -- hence a centre plus a box rather than a rect. The y sits ~.007
## BELOW the octagon's measured pixel centre: digits have no descender, so a
## Label centring its full line box (ascent + descent) parks the glyph
## visibly high in the icon. The nudge is the optical correction, judged
## against a zoomed render.
const COST_CENTRE: Vector2 = Vector2(0.135, 0.103)
const COST_BOX: Vector2 = Vector2(0.130, 0.075)

## Kreon (OFL, assets/fonts/) -- the slab serif Slay the Spire itself uses
## for card text. Two weights from the one variable file: bold for the
## outlined display text (title, type, cost -- light-on-dark, needs the
## mass), regular for the rules text on the panel. Every card font routes
## through these two constants; CardView._make_label picks by its `outlined`
## flag. Swapping faces is a re-point of these two .tres files, not a hunt
## through card_view.gd.
const FONT: Font = preload("res://assets/fonts/kreon_text.tres")
const DISPLAY_FONT: Font = preload("res://assets/fonts/kreon_display.tres")
const TITLE_SIZE: int = 20
const TYPE_SIZE: int = 8
const COST_SIZE: int = 18
## The card is drawn through the project's 2.222x canvas magnification, so
## 11 here renders near 24px on screen -- small in the constant, not on the
## card. Chosen by rendering rather than arithmetic: 10 read lost in the
## master template's tall panel, 11 fills it the way the reference does.
const RULES_SIZE: int = 11

const TITLE_COLOR: Color = Color(0.98, 0.94, 0.80)
const TYPE_COLOR: Color = Color(0.85, 0.78, 0.62)
const COST_COLOR: Color = Color(1.00, 1.00, 1.00)
## Light ink on the dark rules panel -- every text on this frame is
## light-on-dark now that the parchment is gone.
const RULES_COLOR: Color = Color(0.88, 0.87, 0.84)
## The numbers inside the rules text, coloured so they pop the way the old
## value badge did: damage in the frame's red accent pushed bright enough to
## read on the dark panel, guard in a cool blue that cannot be mistaken for
## it.
const RULES_DAMAGE_COLOR: Color = Color(1.00, 0.40, 0.33)
const RULES_GUARD_COLOR: Color = Color(0.45, 0.72, 1.00)

const OUTLINE_SIZE: int = 4
const OUTLINE_COLOR: Color = Color(0.05, 0.03, 0.02, 0.9)

## Which variant a card is. Tag-driven, so it needs no per-card registration:
## anything tagged defense is defense, everything else attack.
static func variant_for(card: CardData) -> StringName:
	return DEFENSE if card.has_tag(&"defense") else ATTACK

## The word the type plate prints -- the variant, upper-cased for display.
static func type_text(variant: StringName) -> String:
	return String(variant).to_upper()

## The card's rules text without any markup: the .tres author's text if set,
## else the effects describing themselves. This is what the player reads,
## what the wrap tests measure, and what rules_bbcode() decorates.
static func rules_plain(card: CardData) -> String:
	if not card.rules_text.is_empty():
		return card.rules_text
	var parts: Array[String] = []
	for effect: CardEffect in card.effects:
		var description: String = effect.describe()
		if not description.is_empty():
			parts.append(description)
	return " ".join(parts)

## The rules text with every number wrapped in a colour tag: damage red,
## guard blue. Each number is coloured by the SENTENCE it sits in -- a mixed
## card colours each number independently -- and a sentence naming neither
## keyword ("Combo: +7 right after Jab.") falls back to the card's variant,
## so the number still reads as what the card is. The numbers themselves are
## the plain text's; markup adds no visible characters, so the label wraps
## exactly the string the wrap model measures.
static func rules_bbcode(card: CardData) -> String:
	var plain: String = rules_plain(card)
	var fallback: Color = RULES_GUARD_COLOR if variant_for(card) == DEFENSE \
		else RULES_DAMAGE_COLOR
	var number_pattern: RegEx = RegEx.create_from_string("[+\\-]?\\d+")
	var result: String = ""
	var cursor: int = 0
	for found: RegExMatch in number_pattern.search_all(plain):
		var color: Color = _number_color(plain, found.get_start(), fallback)
		result += plain.substr(cursor, found.get_start() - cursor)
		result += "[color=#%s]%s[/color]" % [color.to_html(false), found.get_string()]
		cursor = found.get_end()
	result += plain.substr(cursor)
	return result

## The colour for a number at `at`: scan its own sentence (between the
## surrounding full stops) for the damage/guard keywords.
static func _number_color(text: String, at: int, fallback: Color) -> Color:
	var start: int = text.rfind(".", at) + 1
	var end: int = text.find(".", at)
	if end == -1:
		end = text.length()
	var sentence: String = text.substr(start, end - start).to_lower()
	if sentence.contains("damage"):
		return RULES_DAMAGE_COLOR
	if sentence.contains("guard") or sentence.contains("block"):
		return RULES_GUARD_COLOR
	return fallback

## Converts a normalized zone to a pixel rect against a card of `size`.
static func to_pixels(zone: Rect2, size: Vector2) -> Rect2:
	return Rect2(zone.position * size, zone.size * size)

## Converts a normalized centre + box to a pixel rect against a card of `size`.
## Takes a CENTRE, not an origin -- a badge is centred on a drawn icon.
static func centred_pixels(centre: Vector2, box: Vector2, size: Vector2) -> Rect2:
	var pixel_box: Vector2 = box * size
	return Rect2(centre * size - pixel_box / 2.0, pixel_box)
