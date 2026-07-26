extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)
	_test_frame_and_illustration_resolve(t)
	_test_badge_value_derives_from_effects(t)
	_test_missing_illustration_keeps_a_complete_frame(t)
	_test_zones_are_laid_out_from_the_template(t)
	_test_combo_armed_idempotent(t)
	_test_badge_falls_back_to_the_other_total_when_mistagged(t)

## A CardData with no matching res://assets/illustrations/<id>.png -- exactly
## what a freshly authored card looks like on day one, .tres written and art
## not painted yet.
func _no_illustration_card() -> CardData:
	var card := CardData.new()
	card.id = &"no_such_card_id"
	card.display_name = "TEST CARD"
	card.cost = 1
	return card

func _test_card_view_text(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)
	t.check(view != null, "CardView.create returns a view")
	t.check_eq(view.card.id, &"jab", "the view remembers its card")
	var text: String = view.debug_text()
	t.check(text.contains("JAB"), "the card shows its name")
	t.check(text.contains("1 AP"), "the card shows its cost")
	t.check(text.contains("6"), "the card shows its damage")
	t.check(text.contains("Deal 6 damage."), "the card shows its rules text")
	view.free()

func _test_affordability(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"straight")
	var view: CardView = CardView.create(card)
	view.set_affordable(true)
	t.check(not view.disabled, "an affordable card accepts clicks")
	t.check_eq(view.modulate.a, 1.0, "an affordable card renders at full opacity")

	view.set_affordable(false)
	t.check(view.disabled, "an unaffordable card refuses clicks")
	t.check(view.modulate.a < 1.0, "an unaffordable card is dimmed")
	view.free()

func _test_hand_view_rebuild(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	battle.deck.hand = [
		CardLibrary.load_card(&"jab"),
		CardLibrary.load_card(&"straight"),
	] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)
	t.check_eq(hand.get_child_count(), 2, "the hand view shows one node per card")

	# 3 AP: both are affordable.
	hand.refresh_states(battle)
	var first: CardView = hand.get_child(0) as CardView
	var second: CardView = hand.get_child(1) as CardView
	t.check(not first.disabled, "the jab is affordable with 3 AP")
	t.check(not second.disabled, "the straight is affordable with 3 AP")

	# 1 AP: the 2-cost straight is not.
	battle.ap = 1
	hand.refresh_states(battle)
	t.check(not first.disabled, "the 1 AP jab stays affordable")
	t.check(second.disabled, "the 2 AP straight is disabled at 1 AP")

	hand.free()

## Both layers come from CardArt, and they come from different lookups: the
## illustration by card id, the frame by tag-chosen variant. A card that got
## its frame by id would break the moment a card shipped without one.
func _test_frame_and_illustration_resolve(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._frame.texture, CardArt.frame_for(CardTemplate.ATTACK),
		"an attack card wears the attack frame")
	t.check_eq(jab._illustration.texture, CardArt.illustration_for(&"jab"),
		"the illustration is the one CardArt resolves for this card's id")
	jab.free()

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._frame.texture, CardArt.frame_for(CardTemplate.DEFENSE),
		"a defense-tagged card wears the defense frame")
	blocker.free()

## The badge number is derived, never stored. This is the check that would
## catch a future regression back to a hardcoded field, and the reason the
## card can no longer print a number the rules disagree with.
func _test_badge_value_derives_from_effects(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._value_label.text, str(BattleConfig.JAB_DAMAGE),
		"an attack card's badge shows its damage")
	t.check_eq(jab._cost_label.text, str(BattleConfig.JAB_COST),
		"the cost badge shows the card's AP cost as a bare number")
	jab.free()

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._value_label.text, str(BattleConfig.BLOCK_GUARD),
		"a defense card's badge shows its guard, not its (zero) damage")
	blocker.free()

	# Neither damage nor guard: an empty badge beats a misleading "0".
	var view: CardView = CardView.create(_no_illustration_card())
	t.check_eq(view._value_label.text, "",
		"a card with no damage and no guard shows an empty badge rather than 0")
	view.free()

## The fallback is now an empty WINDOW inside a complete frame, not a coloured
## rectangle. Every card always has a frame -- it is chosen by tag, not looked
## up by id -- so the old coloured-box branch became unreachable and was
## removed rather than left as dead code.
func _test_missing_illustration_keeps_a_complete_frame(t: TestRunner) -> void:
	var view: CardView = CardView.create(_no_illustration_card())

	t.check(view._illustration.texture == null, "a card with no illustration gets no illustration texture")
	t.check(view._frame.texture != null, "it still gets a frame")
	t.check(view._title_label.visible, "the title still renders")
	t.check(view._cost_label.visible, "the cost still renders")
	t.check_eq(view._title_label.text, "TEST CARD", "the title is the card's display name")
	view.free()

## Positions come from CardTemplate, and the two variants must actually differ
## -- if both frames got the attack geometry the defense number would sit off
## the shield, which draws fine and reads wrong.
func _test_zones_are_laid_out_from_the_template(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))

	var expected_window: Rect2 = CardTemplate.to_pixels(
		CardTemplate.WINDOW_ZONE, CardView.CARD_SIZE)
	t.check(jab._illustration.position.is_equal_approx(expected_window.position),
		"the illustration is positioned at the template's window zone")

	t.check(jab._value_label.get_rect().get_center().x
			> blocker._value_label.get_rect().get_center().x,
		"the attack badge sits right of the burst while the defense badge is centred in the shield")
	t.check(jab._cost_label.position.x != blocker._cost_label.position.x,
		"the two frames' cost circles are in different places and the labels follow")

	jab.free()
	blocker.free()

## The discriminating case _test_badge_value_derives_from_effects cannot cover:
## its zero-badge fixture has no effects at all, so both totals are zero
## regardless of the fallback. Here the card actually grants guard but was
## never tagged `defense` -- the mistake CardTemplate.variant_for() has no way
## to catch, since it reads the tag, not the effects. Before the fallback this
## rendered an empty attack burst badge, silently hiding a real authoring
## error; the fallback surfaces the guard number on the wrong frame instead.
func _test_badge_falls_back_to_the_other_total_when_mistagged(t: TestRunner) -> void:
	var card := CardData.new()
	card.id = &"mistagged_guard_card"
	card.display_name = "MISTAGGED"
	card.cost = 1
	var guard := GuardEffect.new()
	guard.amount = 5
	card.effects = [guard] as Array[CardEffect]
	# Deliberately no `defense` tag, so variant_for() picks ATTACK.

	t.check_eq(CardTemplate.variant_for(card), CardTemplate.ATTACK,
		"a guard-granting card without the defense tag still wears the attack frame")

	var view: CardView = CardView.create(card)
	t.check_eq(view._value_label.text, "5",
		"the badge falls back to the guard total instead of rendering empty")
	view.free()

## Guards the exact regression that shipped once: lerping from the LIVE
## modulate instead of a fixed base drifts the tint further gold on every
## refresh, and refresh_states() runs on every model event.
func _test_combo_armed_idempotent(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"straight"))

	view.set_combo_armed(true)
	var once: Color = view._frame.modulate

	view.set_combo_armed(true)
	view.set_combo_armed(true)
	t.check_eq(view._frame.modulate, once,
		"calling set_combo_armed(true) three times matches calling it once")
	t.check(view._frame.modulate != Color.WHITE, "the frame is actually tinted while combo-armed")

	# "Not white" is too weak a bar, and this is the check that says why. The
	# first implementation lerped 25% toward gold, which on an ALREADY-GOLD
	# frame moved mean rendered luma 167.4 -> 170.1 -- a 1.6% shift, invisible
	# on a card swaying in a fan, and passing "!= Color.WHITE" the whole time.
	# The tint has to be overbright (Godot treats modulate > 1.0 as a boost) so
	# the card reads as lit up rather than fractionally warmer.
	# ">1.0" alone is too loose a bar too: (1.001, 1.001, 0.99) would pass it
	# and still read as "fractionally warmer," not "lit up." Require a real
	# margin on red and green, and pin blue below 1.0 -- the design intent
	# above is "brightens toward gold, not white," which a blue channel
	# allowed to cross 1.0 would quietly violate.
	const MIN_BRIGHT_MARGIN: float = 1.15
	t.check(view._frame.modulate.r > MIN_BRIGHT_MARGIN and view._frame.modulate.g > MIN_BRIGHT_MARGIN,
		"the armed tint brightens the frame by a real margin, not a hair above white")
	t.check(view._frame.modulate.b < 1.0,
		"blue stays below 1.0 so the tint reads as gold, not white")

	view.set_combo_armed(false)
	t.check_eq(view._frame.modulate, Color.WHITE, "un-arming returns the frame to its untinted colour")

	# The artwork itself must never be tinted -- the gold belongs on the gold
	# frame, and tinting the illustration would misrepresent the art.
	t.check_eq(view._illustration.modulate, Color.WHITE, "the illustration is never tinted")
	view.free()
