extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_variant_follows_the_defense_tag(t)
	_test_frame_name_follows_the_variant(t)
	_test_zones_are_normalized(t)
	_test_window_zone_covers_the_frame_opening(t)
	_test_rules_zone_is_centred_on_the_panel(t)
	_test_rules_lines_fit_the_painted_panel(t)
	_test_type_text_follows_the_variant(t)
	_test_rules_bbcode_colors_numbers(t)
	_test_rules_bbcode_colors_status_keywords(t)
	_test_rules_bbcode_word_boundary_ignores_block_inside_unblocked(t)
	_test_keywords_are_found_by_word_boundary(t)
	_test_burn_is_a_rule_keyword(t)
	_test_reward_card_number_colours(t)
	_test_rules_lines_fit_with_buffed_previews(t)
	_test_pixel_conversion(t)

## The frame is drawn OVER the illustration, and its art opening is not a
## clean rectangle: the octagonal window's cut corners and the trim shadows
## are semi-transparent, so any opening pixel outside WINDOW_ZONE shows the
## background as a dark gap instead of art. The zone must therefore COVER the
## opening (with bleed), not merely trace it: this measures the bounding box
## of every transparent pixel inside the card body and asserts the zone
## contains it -- on BOTH frames, because the defense frame is generated
## from the master by recolour alone and the zones are shared: this is the
## check that turns "the recolour moved no geometry" into an enforced fact.
## Overshoot is free -- the frame's opaque paint covers whatever the
## illustration puts behind it.
func _test_window_zone_covers_the_frame_opening(t: TestRunner) -> void:
	# The card body, excluding the frame's transparent outside-the-rounded-
	# corners margin.
	const BODY_X0: float = 0.08
	const BODY_X1: float = 0.92
	const BODY_Y0: float = 0.10
	const BODY_Y1: float = 0.65
	for frame: StringName in [CardTemplate.FRAME, CardTemplate.DEFENSE_FRAME]:
		var image: Image = _frame_image(frame)
		var width: int = image.get_width()
		var height: int = image.get_height()
		var min_x: int = width
		var max_x: int = -1
		var min_y: int = height
		var max_y: int = -1
		for y: int in range(int(BODY_Y0 * height), int(BODY_Y1 * height)):
			for x: int in range(int(BODY_X0 * width), int(BODY_X1 * width)):
				if image.get_pixel(x, y).a < 0.10:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
		t.check(max_x >= 0, "the %s frame has a transparent art opening" % frame)
		if max_x < 0:
			continue
		var zone: Rect2 = CardTemplate.WINDOW_ZONE
		t.check(zone.position.x <= float(min_x) / width and zone.end.x >= float(max_x) / width,
			"the window zone covers the %s opening horizontally (opening %.3f..%.3f)" % [
				frame, float(min_x) / width, float(max_x) / width])
		t.check(zone.position.y <= float(min_y) / height and zone.end.y >= float(max_y) / height,
			"the window zone covers the %s opening vertically (opening %.3f..%.3f)" % [
				frame, float(min_y) / height, float(max_y) / height])

## Rules text is centre-aligned, so it only LOOKS centred if the zone's own
## horizontal centre sits on the panel's visual centre. Measured from the
## painted pixels at the zone's top row, not hand-set, so a repainted
## template moves this too. Both frames, same reason as the window test.
func _test_rules_zone_is_centred_on_the_panel(t: TestRunner) -> void:
	for frame: StringName in [CardTemplate.FRAME, CardTemplate.DEFENSE_FRAME]:
		var image: Image = _frame_image(frame)
		var y: int = int((CardTemplate.RULES_ZONE.position.y + 0.01) * image.get_height())
		var run: Array = _widest_panel_run(image, y)
		t.check(run[1] > run[0], "the %s rules panel has a full-width run at the zone top" % frame)
		if run[1] <= run[0]:
			continue
		var panel_centre: float = (run[0] + run[1]) / 2.0
		var zone_centre: float = CardTemplate.RULES_ZONE.get_center().x
		t.check(absf(zone_centre - panel_centre) < 0.02,
			"the %s rules zone is centred on the panel (zone %.3f, panel %.3f)" % [
				frame, zone_centre, panel_centre])

## The defense frame is the master recoloured, not the master reused: the
## two variants must resolve to two DIFFERENT frame names, and each name to
## its own texture, or defense cards silently wear attack red again.
func _test_frame_name_follows_the_variant(t: TestRunner) -> void:
	t.check_eq(CardTemplate.frame_name(CardTemplate.ATTACK), CardTemplate.FRAME,
		"the attack variant wears the master frame")
	t.check_eq(CardTemplate.frame_name(CardTemplate.DEFENSE), CardTemplate.DEFENSE_FRAME,
		"the defense variant wears the blue-accented frame")
	t.check(CardTemplate.FRAME != CardTemplate.DEFENSE_FRAME,
		"the two frame names are actually different")

func _test_variant_follows_the_defense_tag(t: TestRunner) -> void:
	# Tag-driven, so a new card needs no registration here. The variant no
	# longer picks a frame -- every card wears the master template -- but it
	# still picks the type-plate word and the fallback number colour.
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"block")), CardTemplate.DEFENSE,
		"a card tagged defense is the defense variant")
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"jab")), CardTemplate.ATTACK,
		"a card without the defense tag is the attack variant")

	var untagged := CardData.new()
	t.check_eq(CardTemplate.variant_for(untagged), CardTemplate.ATTACK,
		"a card with no tags at all falls to the attack variant rather than erroring")

## The type plate prints the variant as display text: the word the player
## reads under the artwork, same place Slay the Spire prints "Attack".
func _test_type_text_follows_the_variant(t: TestRunner) -> void:
	t.check_eq(CardTemplate.type_text(CardTemplate.ATTACK), "ATTACK",
		"the attack variant prints ATTACK on the type plate")
	t.check_eq(CardTemplate.type_text(CardTemplate.DEFENSE), "DEFENSE",
		"the defense variant prints DEFENSE on the type plate")

## The numbers moved off the badge and INTO the rules text, coloured so they
## still pop: damage red, guard blue. The colour is decided per number from
## the sentence it sits in, falling back to the card's variant for sentences
## that name neither (Straight's "Combo: +7 right after Jab.").
func _test_rules_bbcode_colors_numbers(t: TestRunner) -> void:
	var damage_hex: String = CardTemplate.RULES_DAMAGE_COLOR.to_html(false)
	var guard_hex: String = CardTemplate.RULES_GUARD_COLOR.to_html(false)

	t.check_eq(CardTemplate.rules_bbcode(CardLibrary.load_card(&"jab")),
		"Deal [color=#%s]6[/color] damage." % damage_hex,
		"jab's damage number is wrapped in the damage colour")
	t.check_eq(CardTemplate.rules_bbcode(CardLibrary.load_card(&"block")),
		"Gain [color=#%s]5[/color] guard." % guard_hex,
		"block's guard number is wrapped in the guard colour")
	var keyword_hex: String = CardTemplate.RULES_KEYWORD_COLOR.to_html(false)
	t.check_eq(CardTemplate.rules_bbcode(CardLibrary.load_card(&"straight")),
		"Deal [color=#%s]9[/color] damage. [color=#%s]Combo[/color] right after Jab." % [
			damage_hex, keyword_hex],
		"straight's Combo is a yellow keyword, its damage number red")

	# A card mixing both keywords colours each number by its own sentence.
	var mixed := CardData.new()
	mixed.rules_text = "Deal 3 damage. Gain 4 guard."
	t.check_eq(CardTemplate.rules_bbcode(mixed),
		"Deal [color=#%s]3[/color] damage. Gain [color=#%s]4[/color] guard." % [
			damage_hex, guard_hex],
		"a mixed card colours damage red and guard blue in the same text")

	# A number in a sentence naming neither damage nor guard falls back to
	# the variant, so a defense card's bare number reads blue -- and the
	# Combo word itself is a keyword, coloured yellow independently.
	var vague := CardData.new()
	vague.tags = [&"defense"] as Array[StringName]
	vague.rules_text = "Combo: +2 right after Jab."
	t.check_eq(CardTemplate.rules_bbcode(vague),
		"[color=#%s]Combo[/color]: [color=#%s]+2[/color] right after Jab." % [
			keyword_hex, guard_hex],
		"a damage/guard-less sentence's number falls back to the variant colour")

	# The plain text is the bbcode with the colour tags stripped -- what the
	# wrap model below measures, and what the label actually renders.
	t.check_eq(CardTemplate.rules_plain(CardLibrary.load_card(&"straight")),
		"Deal 9 damage. Combo right after Jab.",
		"rules_plain returns the uncoloured text")

## Status names are KEYWORDS: rendered yellow (the tooltip explains them on
## hover), while a number in a status sentence stays plain -- the 1 in
## "for 1 turn" is a duration, and painting it damage-red (or guard-blue)
## would lie.
func _test_rules_bbcode_colors_status_keywords(t: TestRunner) -> void:
	var damage_hex: String = CardTemplate.RULES_DAMAGE_COLOR.to_html(false)
	var keyword_hex: String = CardTemplate.RULES_KEYWORD_COLOR.to_html(false)
	t.check_eq(CardTemplate.rules_bbcode(CardLibrary.load_card(&"low_kick")),
		"Deal [color=#%s]2[/color] damage. If unblocked, causes [color=#%s]Leg Injury[/color] for 1 turn." % [
			damage_hex, keyword_hex],
		"low kick colours its damage red, its keyword yellow, and its duration not at all")

## "unblocked" contains "block" as a substring -- a plain String.contains()
## sentence classifier would misread the duration's sentence as a guard
## sentence and paint "1" blue. The classifier must be word-bounded, exactly
## like the keyword matcher just below.
func _test_rules_bbcode_word_boundary_ignores_block_inside_unblocked(t: TestRunner) -> void:
	var card := CardData.new()
	card.rules_text = "If unblocked, deals 1 extra."
	t.check(not CardTemplate.rules_bbcode(card).contains("[color=#%s]1[/color]" % [
		CardTemplate.RULES_GUARD_COLOR.to_html(false)]),
		"'unblocked' must not be read as naming guard/block")

## What the tooltip needs from a card: which registered statuses its text
## names. Word-bounded, so STR never fires inside STRAIGHT.
func _test_keywords_are_found_by_word_boundary(t: TestRunner) -> void:
	t.check_eq(CardTemplate.keywords_in(CardLibrary.load_card(&"low_kick")),
		[&"leg_injury"] as Array[StringName], "low kick mentions leg injury")
	t.check_eq(CardTemplate.keywords_in(CardLibrary.load_card(&"jab")),
		[] as Array[StringName], "jab mentions no keyword")
	# Combo is a keyword WITHOUT a status behind it -- the keyword table is
	# not status-only.
	t.check_eq(CardTemplate.keywords_in(CardLibrary.load_card(&"straight")),
		[&"combo"] as Array[StringName], "straight mentions the combo keyword")

	var custom := CardData.new()
	custom.rules_text = "A STRAIGHT strike."
	t.check_eq(CardTemplate.keywords_in(custom), [] as Array[StringName],
		"STR inside STRAIGHT is not a keyword match")
	custom.rules_text = "Gain 2 STR."
	t.check_eq(CardTemplate.keywords_in(custom), [&"strength"] as Array[StringName],
		"a word-bounded STR is")

## Zones are fractions of the card rect, not pixels, so CARD_SIZE can change
## without a re-measure. A value outside 0..1 means someone pasted a raw
## template pixel coordinate in by mistake.
func _test_zones_are_normalized(t: TestRunner) -> void:
	for named_zone: Array in [
		["title", CardTemplate.TITLE_ZONE],
		["window", CardTemplate.WINDOW_ZONE],
		["type", CardTemplate.TYPE_ZONE],
		["rules", CardTemplate.RULES_ZONE],
	]:
		var label: String = named_zone[0]
		var zone: Rect2 = named_zone[1]
		t.check(zone.position.x >= 0.0 and zone.position.y >= 0.0,
			"the %s zone starts inside the card" % label)
		t.check(zone.end.x <= 1.0 and zone.end.y <= 1.0,
			"the %s zone ends inside the card" % label)
		t.check(zone.size.x > 0.0 and zone.size.y > 0.0,
			"the %s zone has a positive size" % label)

	var cost: Rect2 = CardTemplate.centred_pixels(
		CardTemplate.COST_CENTRE, CardTemplate.COST_BOX, Vector2.ONE)
	t.check(cost.position.x >= 0.0 and cost.end.x <= 1.0,
		"the cost badge sits inside the card horizontally")
	t.check(cost.position.y >= 0.0 and cost.end.y <= 1.0,
		"the cost badge sits inside the card vertically")

## RULES_ZONE is a WRAPPING BOX, not a text extent: the label centres each
## wrapped line inside it, so a wide zone with short centred lines is fine.
## What must sit on the painted panel is each RENDERED LINE -- these helpers
## model exactly what the label draws (greedy word wrap at the zone's pixel
## width, lines centred both ways) so the guard below can assert on it. Wrap
## and metrics use the same font the rules label wears -- CardTemplate.FONT,
## falling back to the theme default while that is null -- or the model
## measures a different face than the one on screen.

const CARD_SIZE: Vector2 = Vector2(200.0, 300.0)
## RichTextLabel's default theme separates lines by 0px on top of font height
## (Label's default is 3). Must match the live label, or the block height in
## the model drifts from the rendered one.
const LINE_SPACING: float = 0.0

func _frame_image(frame: StringName) -> Image:
	return (load("res://assets/frames/%s.png" % frame) as Texture2D).get_image()

func _rules_font() -> Font:
	return CardTemplate.FONT if CardTemplate.FONT != null else ThemeDB.fallback_font

func _wrapped_lines(text: String, width_px: float) -> Array[String]:
	var font: Font = _rules_font()
	var lines: Array[String] = []
	var current: String = ""
	for word: String in text.split(" ", false):
		var candidate: String = word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1,
				CardTemplate.RULES_SIZE).x <= width_px or current.is_empty():
			current = candidate
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return lines

## Normalized rect of each rendered line: the wrapped block is centred
## vertically in the zone, each line centred horizontally on the zone's
## centre, exactly as the label draws it.
func _line_rects(lines: Array[String]) -> Array[Rect2]:
	var font: Font = _rules_font()
	var line_height: float = font.get_height(CardTemplate.RULES_SIZE)
	var pitch: float = line_height + LINE_SPACING
	var block_px: float = lines.size() * line_height + (lines.size() - 1) * LINE_SPACING
	var zone_px: Rect2 = CardTemplate.to_pixels(CardTemplate.RULES_ZONE, CARD_SIZE)
	var top_px: float = zone_px.get_center().y - block_px / 2.0
	var rects: Array[Rect2] = []
	for index: int in range(lines.size()):
		var width_px: float = font.get_string_size(lines[index],
			HORIZONTAL_ALIGNMENT_LEFT, -1, CardTemplate.RULES_SIZE).x
		var rect_px := Rect2(
			zone_px.get_center().x - width_px / 2.0, top_px + index * pitch,
			width_px, line_height)
		rects.append(Rect2(rect_px.position / CARD_SIZE, rect_px.size / CARD_SIZE))
	return rects

## Reads the ACTUAL PAINTED ARTWORK rather than another hand-set constant:
## every rendered line of every library card must sit on the painted rules
## panel. If the template is ever repainted such that the panel moves, this
## fails, which is the point: CLAUDE.md's "re-measure, do not guess"
## instruction for card_template.gd becomes an enforced check instead of a
## request. The wrap model measures the PLAIN text -- the colour tags add no
## visible characters, so the label wraps the same string.
func _test_rules_lines_fit_the_painted_panel(t: TestRunner) -> void:
	# The painted edge is anti-aliased near the trim, so a rim can dip a few
	# pixels below the panel predicate right at a line's boundary without
	# anything being unreadable -- this forgives raster noise, not a line
	# genuinely off the panel.
	const EDGE_TOLERANCE: float = 0.03

	for card_id: StringName in [&"jab", &"straight", &"block", &"low_kick", &"one_two", &"strength_up", &"prepared"]:
		var card: CardData = CardLibrary.load_card(card_id)
		# Each card is checked against the frame it actually wears.
		var image: Image = _frame_image(
			CardTemplate.frame_name(CardTemplate.variant_for(card)))
		var height: int = image.get_height()
		var zone_width_px: float = CardTemplate.RULES_ZONE.size.x * CARD_SIZE.x
		var rects: Array[Rect2] = _line_rects(
			_wrapped_lines(CardTemplate.rules_plain(card), zone_width_px))
		for rect: Rect2 in rects:
			# Top, middle and bottom row of the line's own band.
			for frac_y: float in [rect.position.y + 0.004, rect.get_center().y, rect.end.y - 0.004]:
				var y: int = mini(int(frac_y * float(height)), height - 1)
				var run: Array = _widest_panel_run(image, y)
				t.check(run[1] > run[0],
					"%s: row %.3f has a wide painted-panel run" % [card_id, frac_y])
				if run[1] <= run[0]:
					continue
				t.check(run[0] <= rect.position.x + EDGE_TOLERANCE,
					"%s: the panel covers the line's left edge at row %.3f (run %.3f, line %.3f)" % [
						card_id, frac_y, run[0], rect.position.x])
				t.check(run[1] >= rect.end.x - EDGE_TOLERANCE,
					"%s: the panel covers the line's right edge at row %.3f (run %.3f, line %.3f)" % [
						card_id, frac_y, run[1], rect.end.x])

## Widest painted rules-panel run on a pixel row, as [x0, x1] fractions.
## Pixel predicate derived by measuring the master template: the panel is
## opaque near-neutral dark grey (v .03-.38 with a vignette toward the
## bottom), where the red inner trim is strongly red-dominant and the metal
## trims are bright. A run narrower than 5% of the width is a stray patch of
## border texture coincidentally matching, not a writable area.
func _widest_panel_run(image: Image, y: int) -> Array:
	const ALPHA_MIN: float = 0.90
	const VALUE_MAX: float = 0.42
	const RED_DOMINANCE_MAX: float = 0.10
	const MIN_RUN_FRACTION: float = 0.05

	var width: int = image.get_width()
	var best_start: int = -1
	var best_length: int = 0
	var run_start: int = -1
	for x in range(width):
		var pixel: Color = image.get_pixel(x, y)
		var value: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
		var is_panel: bool = pixel.a > ALPHA_MIN and value < VALUE_MAX \
			and (pixel.r - pixel.b) < RED_DOMINANCE_MAX \
			and (pixel.r - pixel.g) < RED_DOMINANCE_MAX
		if is_panel:
			if run_start == -1:
				run_start = x
		elif run_start != -1:
			var run_length: int = x - run_start
			if run_length >= int(width * MIN_RUN_FRACTION) and run_length > best_length:
				best_start = run_start
				best_length = run_length
			run_start = -1
	if run_start != -1:
		var run_length: int = width - run_start
		if run_length >= int(width * MIN_RUN_FRACTION) and run_length > best_length:
			best_start = run_start
			best_length = run_length
	if best_start == -1:
		return [0.0, 0.0]
	return [float(best_start) / float(width), float(best_start + best_length) / float(width)]

## Burn is the second rule-keyword after Combo: no status behind it, its
## tooltip body lives beside the rule in Deck.burn_description().
func _test_burn_is_a_rule_keyword(t: TestRunner) -> void:
	t.check_eq(CardTemplate.keyword_title(CardTemplate.BURN_KEYWORD), "Burn", "the keyword's word")
	t.check_eq(CardTemplate.keyword_description(CardTemplate.BURN_KEYWORD), Deck.burn_description(),
		"the tooltip body comes from the rule's own description")

	var strength_up: CardData = CardLibrary.load_card(&"strength_up")
	var keywords: Array[StringName] = CardTemplate.keywords_in(strength_up)
	t.check(keywords.has(CardTemplate.BURN_KEYWORD), "strength up's text names Burn")
	t.check(keywords.has(&"strength"), "strength up's text names STR")
	var bbcode: String = CardTemplate.rules_bbcode(strength_up)
	t.check(bbcode.contains("[color=#%s]Burn[/color]" % CardTemplate.RULES_KEYWORD_COLOR.to_html(false)),
		"Burn renders keyword-yellow")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	t.check(CardTemplate.keywords_in(prepared).has(&"prepared"),
		"prepared's text names its own status keyword")

## One-Two: both 5s are damage-red (the second sentence names "guard" only
## as a condition; "damage" wins, checked first). Prepared: both 4s are
## guard-blue.
func _test_reward_card_number_colours(t: TestRunner) -> void:
	var damage_html: String = CardTemplate.RULES_DAMAGE_COLOR.to_html(false)
	var guard_html: String = CardTemplate.RULES_GUARD_COLOR.to_html(false)

	var one_two: CardData = CardLibrary.load_card(&"one_two")
	var one_two_bbcode: String = CardTemplate.rules_bbcode(one_two)
	t.check_eq(one_two_bbcode.count("[color=#%s]%d[/color]" % [damage_html, BattleConfig.ONE_TWO_DAMAGE]), 2,
		"both of one-two's 5s are damage-red")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	var prepared_bbcode: String = CardTemplate.rules_bbcode(prepared)
	t.check_eq(prepared_bbcode.count("[color=#%s]%d[/color]" % [guard_html, BattleConfig.PREPARED_GUARD]), 2,
		"both of prepared's 4s are guard-blue")

## The preview-aware wrap case CLAUDE.md reserved: the player can now BUFF
## (Strength Up), so a previewed damage number can be WIDER than its base
## ("9" -> "13"). The plain-text wrap tests measure rules_plain() and no
## longer model a buffed face -- this one wraps the PREVIEWED text (bbcode
## with the colour tags stripped; the tags add no visible characters) at the
## maximum reachable player strength: STRENGTH_UP_STACKS, one Strength Up
## per fight today. Raising the reachable stacks must widen this test too.
func _test_rules_lines_fit_with_buffed_previews(t: TestRunner) -> void:
	const EDGE_TOLERANCE: float = 0.03
	var strong := Fighter.new("Strong", 50)
	strong.statuses.apply(&"strength", BattleConfig.STRENGTH_UP_STACKS, BattleConfig.STATUS_PERMANENT)
	var target := Fighter.new("Target", 50)
	var tag_pattern: RegEx = RegEx.create_from_string("\\[/?color[^\\]]*\\]")

	for card_id: StringName in [&"jab", &"straight", &"low_kick", &"one_two"]:
		var card: CardData = CardLibrary.load_card(card_id)
		var previewed_plain: String = tag_pattern.sub(
			CardTemplate.rules_bbcode(card, strong, target), "", true)
		var image: Image = _frame_image(
			CardTemplate.frame_name(CardTemplate.variant_for(card)))
		var height: int = image.get_height()
		var zone_width_px: float = CardTemplate.RULES_ZONE.size.x * CARD_SIZE.x
		var rects: Array[Rect2] = _line_rects(_wrapped_lines(previewed_plain, zone_width_px))
		for rect: Rect2 in rects:
			for frac_y: float in [rect.position.y + 0.004, rect.get_center().y, rect.end.y - 0.004]:
				var y: int = mini(int(frac_y * float(height)), height - 1)
				var run: Array = _widest_panel_run(image, y)
				t.check(run[1] > run[0],
					"%s buffed: row %.3f has a wide painted-panel run" % [card_id, frac_y])
				if run[1] <= run[0]:
					continue
				t.check(run[0] <= rect.position.x + EDGE_TOLERANCE,
					"%s buffed: panel covers the line's left edge at row %.3f" % [card_id, frac_y])
				t.check(run[1] >= rect.end.x - EDGE_TOLERANCE,
					"%s buffed: panel covers the line's right edge at row %.3f" % [card_id, frac_y])

func _test_pixel_conversion(t: TestRunner) -> void:
	var size := Vector2(200.0, 300.0)

	var title: Rect2 = CardTemplate.to_pixels(CardTemplate.TITLE_ZONE, size)
	t.check(is_equal_approx(title.position.x, CardTemplate.TITLE_ZONE.position.x * 200.0),
		"to_pixels scales the zone origin by the card size")
	t.check(is_equal_approx(title.size.y, CardTemplate.TITLE_ZONE.size.y * 300.0),
		"to_pixels scales the zone extent by the card size")

	# centred_pixels takes a CENTRE, not an origin: a badge is centred on a
	# drawn icon rather than fitted to a panel, so getting this backwards
	# would offset every number by half a box.
	var badge: Rect2 = CardTemplate.centred_pixels(Vector2(0.5, 0.5), Vector2(0.1, 0.1), size)
	t.check(is_equal_approx(badge.get_center().x, 100.0),
		"centred_pixels centres the box on the given point horizontally")
	t.check(is_equal_approx(badge.get_center().y, 150.0),
		"centred_pixels centres the box on the given point vertically")
	t.check(is_equal_approx(badge.size.x, 20.0), "centred_pixels scales the box width")
