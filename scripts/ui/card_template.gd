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

## One frame DESIGN, two colourways: attacks wear the dark octagon-cage
## master template with its red accents; defense cards wear the same
## template with the accents recoloured steel-blue -- generated from the
## master by tools/generate_defense_frame.gd, never authored separately, so
## the geometry is identical by construction and every zone below is shared.
## The hue split is what lets a player tell defense from attack at fan
## distance without reading anything; the type plate and number colours
## reinforce it.
const FRAME: StringName = &"card_master_template"
const DEFENSE_FRAME: StringName = &"card_master_template_defense"

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
## it. Status KEYWORDS ("Leg Injury") render yellow, Slay-the-Spire style --
## the signal that hovering the card will explain the word.
const RULES_DAMAGE_COLOR: Color = Color(1.00, 0.40, 0.33)
const RULES_GUARD_COLOR: Color = Color(0.45, 0.72, 1.00)
const RULES_KEYWORD_COLOR: Color = Color(1.00, 0.84, 0.35)
## A damage number previewed BELOW its base value (the source is weakened,
## e.g. Leg Injury) -- bruised orange, distinct from RULES_DAMAGE_COLOR red
## at a glance so a halved hit reads as different from a plain one, not just
## a smaller version of it.
const RULES_WEAKENED_COLOR: Color = Color(0.95, 0.62, 0.30)

const OUTLINE_SIZE: int = 4
const OUTLINE_COLOR: Color = Color(0.05, 0.03, 0.02, 0.9)

## Which variant a card is. Tag-driven, so it needs no per-card registration:
## anything tagged defense is defense, everything else attack.
static func variant_for(card: CardData) -> StringName:
	return DEFENSE if card.has_tag(&"defense") else ATTACK

## The word the type plate prints -- the variant, upper-cased for display.
static func type_text(variant: StringName) -> String:
	return String(variant).to_upper()

## Which frame a variant wears: the red-accented master for attack, its
## blue-accented recolour for defense.
static func frame_name(variant: StringName) -> StringName:
	return DEFENSE_FRAME if variant == DEFENSE else FRAME

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

## The rules text with its numbers and keywords wrapped in colour tags:
## damage numbers red, guard numbers blue, status names yellow. Each number
## is coloured by the SENTENCE it sits in -- a mixed card colours each
## number independently. A sentence naming a status keeps its numbers PLAIN
## (the 1 in "for 1 turn" is a duration, not damage), and a sentence naming
## nothing at all ("Combo: +7 right after Jab.") falls back to the card's
## variant, so the number still reads as what the card is. Markup adds no
## visible characters, so the label wraps exactly the string the wrap model
## measures.
##
## `source`/`target` are OPTIONAL and default to null: every existing caller
## renders EXACTLY as before. Pass both to preview what the card would
## actually hit for right now -- if the card has exactly one DamageEffect and
## a damage-coloured number span equals that effect's base amount, the span
## is replaced with Combat.preview_damage(amount, source, target), coloured
## RULES_DAMAGE_COLOR when the preview equals or exceeds the base (a future
## buff still reads as a plain hit) and RULES_WEAKENED_COLOR when it is
## lower. Cards with zero or multiple DamageEffects, spans that don't match
## the amount, or EITHER fighter left null (simplest safe fallback -- no
## half-preview from one side's modifiers alone) render untouched, exactly as
## today. Guard, duration and keyword spans are never previewed.
static func rules_bbcode(card: CardData, source: Fighter = null, target: Fighter = null) -> String:
	var plain: String = rules_plain(card)
	var fallback: Color = RULES_GUARD_COLOR if variant_for(card) == DEFENSE \
		else RULES_DAMAGE_COLOR
	var preview_effect: DamageEffect = null
	if source != null and target != null:
		preview_effect = _sole_damage_effect(card)

	# Every span to wrap, as [start, end, text, colour]. Numbers and keywords
	# never overlap -- no registered status name contains a digit.
	var spans: Array = []
	var number_pattern: RegEx = RegEx.create_from_string("[+\\-]?\\d+")
	for found: RegExMatch in number_pattern.search_all(plain):
		var color: Variant = _number_color(plain, found.get_start(), fallback)
		if color == null:
			continue
		var span_text: String = plain.substr(found.get_start(), found.get_end() - found.get_start())
		if preview_effect != null and color == RULES_DAMAGE_COLOR \
				and span_text.to_int() == preview_effect.amount:
			var preview: int = Combat.preview_damage(preview_effect.amount, source, target)
			span_text = str(preview)
			color = RULES_DAMAGE_COLOR if preview >= preview_effect.amount else RULES_WEAKENED_COLOR
		spans.append([found.get_start(), found.get_end(), span_text, color])
	for id: StringName in _keyword_ids():
		for found: RegExMatch in _keyword_pattern(id).search_all(plain):
			var text: String = plain.substr(found.get_start(), found.get_end() - found.get_start())
			spans.append([found.get_start(), found.get_end(), text, RULES_KEYWORD_COLOR])

	spans.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var result: String = ""
	var cursor: int = 0
	for span: Array in spans:
		result += plain.substr(cursor, span[0] - cursor)
		result += "[color=#%s]%s[/color]" % [(span[3] as Color).to_html(false), span[2]]
		cursor = span[1]
	result += plain.substr(cursor)
	return result

## The card's single DamageEffect, or null if it has zero or more than one --
## the live preview only ever replaces a number that unambiguously belongs to
## exactly one effect.
static func _sole_damage_effect(card: CardData) -> DamageEffect:
	var found: DamageEffect = null
	var count: int = 0
	for effect: CardEffect in card.effects:
		if effect is DamageEffect:
			count += 1
			found = effect as DamageEffect
	return found if count == 1 else null

## Which keywords this card's text names -- what the hover tooltip explains
## and rules_bbcode colours yellow. Every registered status is a keyword;
## COMBO_KEYWORD is the one game-rule keyword without a status behind it.
## Word-bounded, so STR never fires inside STRAIGHT.
static func keywords_in(card: CardData) -> Array[StringName]:
	var found: Array[StringName] = []
	var plain: String = rules_plain(card)
	for id: StringName in _keyword_ids():
		if _keyword_pattern(id).search(plain) != null:
			found.append(id)
	return found

## The combo mechanic's keyword id. Not a status: its title and description
## resolve through keyword_title()/keyword_description() below.
const COMBO_KEYWORD: StringName = &"combo"

## The burn mechanic's keyword id. Like Combo, a game-rule keyword with no
## status behind it: its title and description resolve through
## keyword_title()/keyword_description(), the body from Deck (core), beside
## the rule it describes.
const BURN_KEYWORD: StringName = &"burn"

static func _keyword_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in StatusRegistry.DEFINITIONS:
		ids.append(id)
	ids.append(COMBO_KEYWORD)
	ids.append(BURN_KEYWORD)
	return ids

## The word printed on cards and as the tooltip's heading.
static func keyword_title(id: StringName) -> String:
	if id == COMBO_KEYWORD:
		return "Combo"
	if id == BURN_KEYWORD:
		return "Burn"
	return StatusRegistry.display_name(id)

## The tooltip's body: statuses describe themselves via the registry; the
## rule keywords via the rule they name.
static func keyword_description(id: StringName) -> String:
	if id == COMBO_KEYWORD:
		return ComboRule.keyword_description()
	if id == BURN_KEYWORD:
		return Deck.burn_description()
	return StatusRegistry.description(id)

## Case-insensitive, word-bounded matcher for a keyword's display word. The
## words are plain ("Leg Injury", "STR", "Combo"); if one ever gains a regex
## metacharacter it must be escaped here.
static func _keyword_pattern(id: StringName) -> RegEx:
	return RegEx.create_from_string("(?i)\\b%s\\b" % keyword_title(id))

## The colour for a number at `at` -- or null for no colour at all: scan its
## own sentence (between the surrounding full stops) for the damage/guard
## keywords, then for status names.
static func _number_color(text: String, at: int, fallback: Color) -> Variant:
	var start: int = text.rfind(".", at) + 1
	var end: int = text.find(".", at)
	if end == -1:
		end = text.length()
	var sentence: String = text.substr(start, end - start)
	if _sentence_names_word(sentence, "damage"):
		return RULES_DAMAGE_COLOR
	if _sentence_names_word(sentence, "guard") or _sentence_names_word(sentence, "block"):
		return RULES_GUARD_COLOR
	for id: StringName in StatusRegistry.DEFINITIONS:
		if _keyword_pattern(id).search(sentence) != null:
			return null
	return fallback

## Word-bounded, case-insensitive substring test -- NOT String.contains(),
## which would match "block" inside "unblocked" and misclassify a duration
## number (Low Kick's "If unblocked, causes...") as a guard number.
static func _sentence_names_word(sentence: String, word: String) -> bool:
	return RegEx.create_from_string("(?i)\\b%s\\b" % word).search(sentence) != null

## Converts a normalized zone to a pixel rect against a card of `size`.
static func to_pixels(zone: Rect2, size: Vector2) -> Rect2:
	return Rect2(zone.position * size, zone.size * size)

## Converts a normalized centre + box to a pixel rect against a card of `size`.
## Takes a CENTRE, not an origin -- a badge is centred on a drawn icon.
static func centred_pixels(centre: Vector2, box: Vector2, size: Vector2) -> Rect2:
	var pixel_box: Vector2 = box * size
	return Rect2(centre * size - pixel_box / 2.0, pixel_box)
