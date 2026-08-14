extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_variant_follows_the_defense_tag(t)
	_test_zones_are_normalized(t)
	_test_window_zone_covers_the_frame_opening(t)
	_test_rules_zone_is_centred_on_the_parchment(t)
	_test_rules_lines_clear_both_cost_badges(t)
	_test_rules_lines_fit_the_painted_parchment(t)
	_test_pixel_conversion(t)

## The frame is drawn OVER the illustration, and its art opening is not a
## clean rectangle: the ribbon's drop shadow above and the badge's flanks
## below are semi-transparent, so any opening pixel outside WINDOW_ZONE shows
## the background as a dark gap instead of art. The zone must therefore
## COVER the opening (with bleed), not merely trace it: this measures the
## bounding box of every transparent pixel inside the card body on both
## frames and asserts the zone contains it. Overshoot is free -- the frame's
## opaque paint covers whatever the illustration puts behind it.
func _test_window_zone_covers_the_frame_opening(t: TestRunner) -> void:
	# The card body, excluding the frame's outer transparent glow border and
	# the decorative pockets above the title ribbon (those sit outside the
	# art window on purpose).
	const BODY_X0: float = 0.10
	const BODY_X1: float = 0.90
	const BODY_Y0: float = 0.15
	const BODY_Y1: float = 0.72
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var image: Image = (load("res://assets/frames/%s.png" % variant) as Texture2D).get_image()
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
		t.check(max_x >= 0, "the %s frame has a transparent art opening" % variant)
		if max_x < 0:
			continue
		var zone: Rect2 = CardTemplate.WINDOW_ZONE
		t.check(zone.position.x <= float(min_x) / width and zone.end.x >= float(max_x) / width,
			"the window zone covers the %s opening horizontally (opening %.3f..%.3f)" % [
				variant, float(min_x) / width, float(max_x) / width])
		t.check(zone.position.y <= float(min_y) / height and zone.end.y >= float(max_y) / height,
			"the window zone covers the %s opening vertically (opening %.3f..%.3f)" % [
				variant, float(min_y) / height, float(max_y) / height])

## Rules text is centre-aligned, so it only LOOKS centred if the zone's own
## horizontal centre sits on the parchment's visual centre. Measured from the
## painted pixels at the zone's top row (where the parchment runs full
## width), not hand-set, so a repainted template moves this too.
func _test_rules_zone_is_centred_on_the_parchment(t: TestRunner) -> void:
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var image: Image = (load("res://assets/frames/%s.png" % variant) as Texture2D).get_image()
		var y: int = int((CardTemplate.RULES_ZONE.position.y + 0.01) * image.get_height())
		var run: Array = _widest_parchment_run(image, y)
		t.check(run[1] > run[0], "the %s parchment has a full-width run at the zone top" % variant)
		var parchment_centre: float = (run[0] + run[1]) / 2.0
		var zone_centre: float = CardTemplate.RULES_ZONE.get_center().x
		t.check(absf(zone_centre - parchment_centre) < 0.02,
			"the %s rules zone is centred on the parchment (zone %.3f, parchment %.3f)" % [
				variant, zone_centre, parchment_centre])

func _test_variant_follows_the_defense_tag(t: TestRunner) -> void:
	# Tag-driven, so a new card needs no registration here.
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"block")), CardTemplate.DEFENSE,
		"a card tagged defense wears the defense frame")
	t.check_eq(CardTemplate.variant_for(CardLibrary.load_card(&"jab")), CardTemplate.ATTACK,
		"a card without the defense tag wears the attack frame")

	var untagged := CardData.new()
	t.check_eq(CardTemplate.variant_for(untagged), CardTemplate.ATTACK,
		"a card with no tags at all falls to the attack frame rather than erroring")

## Zones are fractions of the card rect, not pixels, so CARD_SIZE can change
## without a re-measure. A value outside 0..1 means someone pasted a raw
## template pixel coordinate in by mistake.
func _test_zones_are_normalized(t: TestRunner) -> void:
	for named_zone: Array in [
		["title", CardTemplate.TITLE_ZONE],
		["window", CardTemplate.WINDOW_ZONE],
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

	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var value: Rect2 = CardTemplate.centred_pixels(
			CardTemplate.VALUE_CENTRE[variant], CardTemplate.VALUE_BOX[variant], Vector2.ONE)
		t.check(value.position.x >= 0.0 and value.end.x <= 1.0,
			"the %s value badge sits inside the card horizontally" % variant)
		t.check(value.position.y >= 0.0 and value.end.y <= 1.0,
			"the %s value badge sits inside the card vertically" % variant)

## RULES_ZONE is a WRAPPING BOX, not a text extent: the label centres each
## wrapped line inside it, so a wide zone with short centred lines is fine
## even where the cost disc cuts into the parchment. What must stay clear of
## the disc is therefore each RENDERED LINE, not the zone box -- these
## helpers model exactly what the label draws (greedy word wrap at the
## zone's pixel width, lines centred both ways) so the guards below can
## assert on it. Wrap and metrics use ThemeDB.fallback_font, the same font
## the label falls back to while CardTemplate.FONT is null.

const CARD_SIZE: Vector2 = Vector2(200.0, 300.0)
## Godot's default Label theme separates lines by 3px on top of font height.
const LINE_SPACING: float = 3.0
const COST_RADIUS: float = 0.066

func _rules_text(card: CardData) -> String:
	if not card.rules_text.is_empty():
		return card.rules_text
	var parts: Array[String] = []
	for effect: CardEffect in card.effects:
		var description: String = effect.describe()
		if not description.is_empty():
			parts.append(description)
	return " ".join(parts)

func _wrapped_lines(text: String, width_px: float) -> Array[String]:
	var font: Font = ThemeDB.fallback_font
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
	var font: Font = ThemeDB.fallback_font
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

func _library_faces() -> Array[Array]:
	var faces: Array[Array] = []
	for card_id: StringName in [&"jab", &"straight", &"block"]:
		var card: CardData = CardLibrary.load_card(card_id)
		var variant: StringName = CardTemplate.variant_for(card)
		var zone_width_px: float = CardTemplate.RULES_ZONE.size.x * CARD_SIZE.x
		faces.append([card_id, variant, _line_rects(_wrapped_lines(_rules_text(card), zone_width_px))])
	return faces

## Cheap, frame-art-independent guard: any rendered line low enough to sit
## beside the cost disc must end before the disc begins. Holds regardless of
## what the frame artwork looks like; the painted-parchment test below is
## the tight one.
func _test_rules_lines_clear_both_cost_badges(t: TestRunner) -> void:
	for face: Array in _library_faces():
		var card_id: StringName = face[0]
		var variant: StringName = face[1]
		var circle_left: float = CardTemplate.COST_CENTRE[variant].x - COST_RADIUS
		var circle_top: float = CardTemplate.COST_CENTRE[variant].y - COST_RADIUS
		for rect: Rect2 in face[2]:
			if rect.end.y <= circle_top:
				continue
			t.check(rect.end.x < circle_left,
				"%s: a rules line beside the cost disc ends before it (line end %.3f, disc left %.3f)" % [
					card_id, rect.end.x, circle_left])

## Reads the ACTUAL PAINTED ARTWORK rather than another hand-set constant:
## every rendered line of every library card must sit on painted parchment
## on the frame it wears -- including the corner ornament and disc shadow,
## which cut in tighter than the plain circle above. If a template is ever
## repainted such that the parchment moves, this fails, which is the point:
## CLAUDE.md's "re-measure, do not guess" instruction for card_template.gd
## becomes an enforced check instead of a request.
func _test_rules_lines_fit_the_painted_parchment(t: TestRunner) -> void:
	# The painted edge is anti-aliased and shadowed near the disc, so a rim
	# can dip a few pixels below the parchment predicate right at a line's
	# boundary without anything being unreadable -- this forgives raster
	# noise, not a line genuinely off the parchment.
	const EDGE_TOLERANCE: float = 0.03
	var images: Dictionary = {}
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		images[variant] = (load("res://assets/frames/%s.png" % variant) as Texture2D).get_image()

	for face: Array in _library_faces():
		var card_id: StringName = face[0]
		var image: Image = images[face[1]]
		var height: int = image.get_height()
		for rect: Rect2 in face[2]:
			# Top, middle and bottom row of the line's own band.
			for frac_y: float in [rect.position.y + 0.004, rect.get_center().y, rect.end.y - 0.004]:
				var y: int = mini(int(frac_y * float(height)), height - 1)
				var run: Array = _widest_parchment_run(image, y)
				t.check(run[1] > run[0],
					"%s: row %.3f has a wide painted-parchment run" % [card_id, frac_y])
				if run[1] <= run[0]:
					continue
				t.check(run[0] <= rect.position.x + EDGE_TOLERANCE,
					"%s: parchment covers the line's left edge at row %.3f (run %.3f, line %.3f)" % [
						card_id, frac_y, run[0], rect.position.x])
				t.check(run[1] >= rect.end.x - EDGE_TOLERANCE,
					"%s: parchment covers the line's right edge at row %.3f (run %.3f, line %.3f)" % [
						card_id, frac_y, run[1], rect.end.x])

## Widest painted-parchment run on a pixel row, as [x0, x1] fractions.
## Pixel predicate derived by measuring these exact PNGs: opaque, warm, and
## neither as red as the frame border nor as blue/grey as the cost disc. A
## run narrower than 5% of the width is a stray pixel of trim coincidentally
## matching, not a writable area.
func _widest_parchment_run(image: Image, y: int) -> Array:
	const ALPHA_MIN: float = 0.78
	const RED_MIN: float = 0.373
	const RED_MINUS_BLUE_MAX: float = 0.470
	const RED_MINUS_GREEN_MAX: float = 0.216
	const GREEN_MIN: float = 0.333
	const BLUE_MIN: float = 0.216
	const MIN_RUN_FRACTION: float = 0.05

	var width: int = image.get_width()
	var best_start: int = -1
	var best_length: int = 0
	var run_start: int = -1
	for x in range(width):
		var pixel: Color = image.get_pixel(x, y)
		var is_parchment: bool = pixel.a > ALPHA_MIN and pixel.r > RED_MIN \
			and (pixel.r - pixel.b) < RED_MINUS_BLUE_MAX \
			and (pixel.r - pixel.g) < RED_MINUS_GREEN_MAX \
			and pixel.g > GREEN_MIN and pixel.b > BLUE_MIN
		if is_parchment:
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
