extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_variant_follows_the_defense_tag(t)
	_test_zones_are_normalized(t)
	_test_rules_zone_clears_both_cost_badges(t)
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
## (attack) and .763 (defense) with a radius of about .065, so its left edge
## is .723 and .700. Rules text running under it would be unreadable, and
## nothing else in the project would catch that -- the layout draws fine, it
## just cannot be read.
func _test_rules_zone_clears_both_cost_badges(t: TestRunner) -> void:
	const COST_RADIUS: float = 0.066
	for variant: StringName in [CardTemplate.ATTACK, CardTemplate.DEFENSE]:
		var circle_left: float = CardTemplate.COST_CENTRE[variant].x - COST_RADIUS
		t.check(CardTemplate.RULES_ZONE.end.x < circle_left,
			"the rules zone ends before the %s cost badge begins" % variant)

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
