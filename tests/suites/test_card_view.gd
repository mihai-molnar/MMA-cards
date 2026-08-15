extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)
	_test_frame_and_illustration_resolve(t)
	_test_type_plate_follows_the_tag(t)
	_test_title_curves_along_the_banner(t)
	_test_rules_label_renders_the_colored_bbcode(t)
	_test_missing_illustration_keeps_a_complete_frame(t)
	_test_zones_are_laid_out_from_the_template(t)
	_test_combo_armed_idempotent(t)
	_test_no_focus_outline(t)

## Clicking a Button grabs keyboard focus, and Godot draws its default white
## focus rectangle over the focused control -- flat = true hides the normal
## stylebox but NOT the focus one. The game is mouse-driven with no keyboard
## navigation, so no button should ever take focus: this is what put a white
## border over a card after every click.
func _test_no_focus_outline(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(view.focus_mode, Control.FOCUS_NONE,
		"a card never grabs focus, so it never wears the focus outline")
	view.free()

	var hud := BattleHud.new()
	var buttons: Array[Button] = []
	_collect_buttons(hud, buttons)
	t.check(buttons.size() >= 2, "the hud exposes its buttons (End Turn, Restart)")
	for button: Button in buttons:
		t.check_eq(button.focus_mode, Control.FOCUS_NONE,
			"hud button '%s' never grabs focus" % button.text)
	hud.free()

func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child: Node in node.get_children():
		var button: Button = child as Button
		if button != null:
			out.append(button)
		_collect_buttons(child, out)

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
	t.check(text.contains("ATTACK"), "the card shows its type on the plate")
	t.check(text.contains("Deal 6 damage."), "the card shows its rules text, damage number included")
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

## Every card wears the ONE master frame; only the illustration is per card.
## A card that got its frame by id would break the moment a card shipped
## without one -- and a card that somehow got a different frame would break
## the single-template design on sight.
func _test_frame_and_illustration_resolve(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._frame.texture, CardArt.frame_for(CardTemplate.FRAME),
		"an attack card wears the master frame")
	t.check_eq(jab._illustration.texture, CardArt.illustration_for(&"jab"),
		"the illustration is the one CardArt resolves for this card's id")

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._frame.texture, jab._frame.texture,
		"a defense card wears the SAME master frame as an attack card")
	jab.free()
	blocker.free()

## The type plate under the artwork prints the variant, so attack and defense
## still read differently at a glance now that the frame no longer does it.
func _test_type_plate_follows_the_tag(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(jab._type_label.text, "ATTACK", "an attack card's plate reads ATTACK")
	t.check_eq(jab._cost_label.text, str(BattleConfig.JAB_COST),
		"the cost badge shows the card's AP cost as a bare number")
	jab.free()

	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))
	t.check_eq(blocker._type_label.text, "DEFENSE", "a defense card's plate reads DEFENSE")
	blocker.free()

## The banner on the master template is a shallow arch -- its midline sags
## ~1.7% of card height from the centre to either end -- so the title is an
## ArcTitleLabel that offsets each glyph down a parabola instead of a flat
## Label. The curve itself is judged from a render (only the picture can say
## it matches the paint); what a test CAN hold is the arc function's shape:
## anchored at zero in the middle, symmetric, and sagging DOWNWARD (positive
## y) toward the ends -- an upward bow would read as mocking the banner.
func _test_title_curves_along_the_banner(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check(view._title_label is ArcTitleLabel, "the title is an ArcTitleLabel, not a flat Label")
	t.check_eq(view._title_label.text, "JAB", "the arc label still exposes the card's name")
	view.free()

	var label := ArcTitleLabel.new()
	label.size = Vector2(124.0, 22.5)
	t.check_eq(label.arc_offset(0.0), 0.0, "the arc is anchored at the banner's apex mid-span")
	t.check(label.arc_offset(1.0) > 0.0, "the arc sags downward toward the ends")
	t.check_eq(label.arc_offset(-1.0), label.arc_offset(1.0), "the arc is symmetric")
	t.check(label.arc_offset(0.5) < label.arc_offset(1.0),
		"the sag grows toward the ends -- a parabola, not a step")
	label.free()

## The value badge is gone: the number now lives INSIDE the rules text,
## coloured by CardTemplate.rules_bbcode(). The label must be a RichTextLabel
## with bbcode on, showing exactly that markup -- and the parsed (visible)
## text must be the plain rules, so the colour tags never leak to the player.
func _test_rules_label_renders_the_colored_bbcode(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"straight")
	var view: CardView = CardView.create(card)
	t.check(view._rules_label is RichTextLabel, "the rules label is a RichTextLabel")
	t.check(view._rules_label.bbcode_enabled, "bbcode is enabled so the colour tags parse")
	t.check_eq(view._rules_label.text, CardTemplate.rules_bbcode(card),
		"the rules label shows the coloured markup from CardTemplate")
	t.check_eq(view._rules_label.get_parsed_text(), CardTemplate.rules_plain(card),
		"the visible text is the plain rules -- tags colour it, never appear in it")
	view.free()

## The fallback is an empty WINDOW inside a complete frame, not a coloured
## rectangle. Every card always has a frame -- there is only one, shared --
## so a missing illustration degrades to unpainted art, never a broken card.
func _test_missing_illustration_keeps_a_complete_frame(t: TestRunner) -> void:
	var view: CardView = CardView.create(_no_illustration_card())

	t.check(view._illustration.texture == null, "a card with no illustration gets no illustration texture")
	t.check(view._frame.texture != null, "it still gets a frame")
	t.check(view._title_label.visible, "the title still renders")
	t.check(view._cost_label.visible, "the cost still renders")
	t.check_eq(view._title_label.text, "TEST CARD", "the title is the card's display name")
	view.free()

## Positions come from CardTemplate. With one shared frame the zones are the
## same for every card -- including the cost octagon, which used to move
## between the two frames and now must not.
func _test_zones_are_laid_out_from_the_template(t: TestRunner) -> void:
	var jab: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	var blocker: CardView = CardView.create(CardLibrary.load_card(&"block"))

	var expected_window: Rect2 = CardTemplate.to_pixels(
		CardTemplate.WINDOW_ZONE, CardView.CARD_SIZE)
	t.check(jab._illustration.position.is_equal_approx(expected_window.position),
		"the illustration is positioned at the template's window zone")

	var expected_type: Rect2 = CardTemplate.to_pixels(
		CardTemplate.TYPE_ZONE, CardView.CARD_SIZE)
	t.check(jab._type_label.position.is_equal_approx(expected_type.position),
		"the type plate label is positioned at the template's type zone")

	var expected_cost_centre: Vector2 = CardTemplate.COST_CENTRE * CardView.CARD_SIZE
	t.check(jab._cost_label.get_rect().get_center().is_equal_approx(expected_cost_centre),
		"the cost label is centred on the template's cost octagon")
	t.check(jab._cost_label.position.is_equal_approx(blocker._cost_label.position),
		"the shared frame puts every card's cost label in the same place")

	jab.free()
	blocker.free()

## Guards the exact regression that shipped once: lerping from the LIVE
## modulate instead of a fixed base drifts the tint further on every
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

	# "Not white" is too weak a bar, and this is the check that says why. An
	# early implementation lerped 25% toward gold, which moved mean rendered
	# luma by 1.6% -- invisible on a card swaying in a fan, and passing
	# "!= Color.WHITE" the whole time. The tint has to be overbright (Godot
	# treats modulate > 1.0 as a boost) so the card reads as lit up rather
	# than fractionally warmer. ">1.0" alone is too loose a bar too: require
	# a real margin on red and green, and pin blue below 1.0 so the boost
	# reads warm rather than white.
	const MIN_BRIGHT_MARGIN: float = 1.15
	t.check(view._frame.modulate.r > MIN_BRIGHT_MARGIN and view._frame.modulate.g > MIN_BRIGHT_MARGIN,
		"the armed tint brightens the frame by a real margin, not a hair above white")
	t.check(view._frame.modulate.b < 1.0,
		"blue stays below 1.0 so the tint reads as warm, not white")

	view.set_combo_armed(false)
	t.check_eq(view._frame.modulate, Color.WHITE, "un-arming returns the frame to its untinted colour")

	# The artwork itself must never be tinted -- the glow belongs on the
	# frame, and tinting the illustration would misrepresent the art.
	t.check_eq(view._illustration.modulate, Color.WHITE, "the illustration is never tinted")
	view.free()
