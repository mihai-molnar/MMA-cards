extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_variant_follows_the_defense_tag(t)
	_test_zones_are_normalized(t)
	_test_rules_zone_clears_both_cost_badges(t)
	_test_rules_zone_fits_the_painted_parchment(t)
	_test_pixel_conversion(t)

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

## Measured from the template pixels: the cost circle is centred at x .788
## (attack) and .763 (defense) with a radius of about .066, so its left edge
## is .722 and .697.
##
## This is the WEAKER of two constraints. A render pass found the real
## binding limit is the frame's own bottom-right corner ornament (the cost
## badge's outline ring and drop shadow), which cuts in tighter than this
## plain circle by .027 to .052 -- see
## `_test_rules_zone_fits_the_painted_parchment` below, which reads the
## actual frame PNGs and is the test that would catch a "widen the box" edit
## running text over painted art that this one would wave through. This
## circle check stays too: it is cheap, needs no image load, and holds
## regardless of what the frame artwork looks like, so it is worth keeping
## as a coarse independent guard even though it is not the tight one.
func _test_rules_zone_clears_both_cost_badges(t: TestRunner) -> void:
	const COST_RADIUS: float = 0.066
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var circle_left: float = CardTemplate.COST_CENTRE[variant].x - COST_RADIUS
		t.check(CardTemplate.RULES_ZONE.end.x < circle_left,
			"the rules zone ends before the %s cost badge begins" % variant)

## Reads the ACTUAL PAINTED ARTWORK rather than another hand-set constant --
## a widened RULES_ZONE that still passes the cost-circle test above would
## fail here, because this samples the real frame PNGs pixel by pixel. If a
## template is ever repainted such that the parchment moves, this fails,
## which is the point: CLAUDE.md's "re-measure, do not guess" instruction
## for `card_template.gd` becomes an enforced check instead of a request.
func _test_rules_zone_fits_the_painted_parchment(t: TestRunner) -> void:
	# Classifies a pixel as parchment. Derived by measuring these exact PNGs:
	# opaque, warm, and neither as red as the frame border nor as blue/grey
	# as the cost badge disc.
	const ALPHA_MIN: float = 0.78
	const RED_MIN: float = 0.373
	const RED_MINUS_BLUE_MAX: float = 0.470
	const RED_MINUS_GREEN_MAX: float = 0.216
	const GREEN_MIN: float = 0.333
	const BLUE_MIN: float = 0.216

	# A run shorter than this is a stray pixel of the frame's own red or
	# gold trim coincidentally matching the predicate, not a real writable
	# area -- ignore it rather than let it win "widest run" by default when
	# the real parchment run is filtered out for some other reason.
	const MIN_RUN_FRACTION: float = 0.05

	# Rows are sampled half-open over [position.y, end.y): Rect2.end is the
	# conventional exclusive bound, and the literal last pixel row is where
	# card_template.gd's own comment says the ornament "cuts in" -- right at
	# that row the badge ring's anti-aliased edge fragments the parchment
	# into two separate runs, and naively picking the widest one grabs the
	# wrong side of the gap. Sampling the box's open interior avoids that
	# artifact instead of papering over it with a bigger tolerance.
	const SAMPLE_ROWS: int = 8

	# The painted edge is anti-aliased and, near the cost badge, shadowed --
	# not a hard vector line -- so a highlight rim or shadow can dip a
	# handful of pixels below the predicate right at the zone's own boundary
	# without anything actually being unreadable there. The worst case
	# measured on the committed RULES_ZONE is about 0.0157 (defense frame,
	# row 7 of 8, right edge). 0.03 covers that with a little headroom while
	# staying far below the 0.145 the discrimination check below moves the
	# boundary by -- this tolerance forgives raster noise, not a genuinely
	# widened zone.
	const EDGE_TOLERANCE: float = 0.03

	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var image: Image = (load("res://assets/frames/%s.png" % variant) as Texture2D).get_image()
		var width: int = image.get_width()
		var height: int = image.get_height()

		for row_index in range(SAMPLE_ROWS):
			var frac_y: float = CardTemplate.RULES_ZONE.position.y \
				+ CardTemplate.RULES_ZONE.size.y * float(row_index) / float(SAMPLE_ROWS)
			var y: int = mini(int(frac_y * float(height)), height - 1)

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

			t.check(best_start != -1,
				"row %d of the %s rules zone has a wide painted-parchment run" % [row_index, variant])
			if best_start == -1:
				continue

			var run_x0: float = float(best_start) / float(width)
			var run_x1: float = float(best_start + best_length) / float(width)
			t.check(run_x0 <= CardTemplate.RULES_ZONE.position.x + EDGE_TOLERANCE,
				"row %d of the %s rules zone: painted parchment covers the zone's left edge" % [row_index, variant])
			t.check(run_x1 >= CardTemplate.RULES_ZONE.end.x - EDGE_TOLERANCE,
				"row %d of the %s rules zone: painted parchment covers the zone's right edge" % [row_index, variant])

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
