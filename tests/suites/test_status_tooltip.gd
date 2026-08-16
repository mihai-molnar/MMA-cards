extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_tooltip_populates_for_keyword_cards(t)
	_test_tooltip_explains_the_combo(t)
	_test_tooltip_hides_for_plain_cards(t)
	_test_tooltip_for_single_status(t)
	_test_label_tooltip(t)
	_test_card_tooltip_can_hang_below(t)
	_test_info_tooltip(t)

## Guard is not a status, so its chip tooltip carries a caller-supplied
## title and body -- same panel, same below-the-chip placement.
func _test_info_tooltip(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_info("Guard", Fighter.guard_description(), Vector2(200.0, 130.0))
	t.check(tip.visible, "an info tooltip shows")
	t.check(tip.debug_text().contains("Guard"), "it carries the title")
	t.check(tip.debug_text().contains(Fighter.guard_description()),
		"it carries the body")
	t.check(tip.position.y >= 130.0, "it hangs below the chip anchor")
	t.check(absf(tip.position.x + tip.size.x / 2.0 - 200.0) < 1.0,
		"it is centred on the anchor")
	tip.free()

## A top-row pile card has no room above its zoomed self, so BattleView can
## ask for the card tooltip below the anchor instead -- same content, other
## side.
func _test_card_tooltip_can_hang_below(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_card(CardLibrary.load_card(&"low_kick"), Vector2(400.0, 420.0), true)
	t.check(tip.visible, "the below-anchor variant still shows")
	t.check(tip.position.y >= 420.0, "it hangs below the anchor when asked")
	t.check(absf(tip.position.x + tip.size.x / 2.0 - 400.0) < 1.0,
		"still centred on the anchor")
	tip.free()

## Combo has no status behind it -- the tooltip explains game-rule keywords
## too, with the ratio pulled from config via ComboRule.
func _test_tooltip_explains_the_combo(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_card(CardLibrary.load_card(&"straight"), Vector2(400.0, 300.0))
	t.check(tip.visible, "a card naming Combo shows the tooltip")
	t.check(tip.debug_text().contains("Combo"), "the tooltip names the keyword")
	t.check(tip.debug_text().contains("50%"),
		"the tooltip explains the bonus ratio from config")
	tip.free()
	_test_tooltip_sits_above_its_anchor(t)
	_test_hand_relays_hover(t)

func _test_tooltip_populates_for_keyword_cards(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_card(CardLibrary.load_card(&"low_kick"), Vector2(400.0, 300.0))
	t.check(tip.visible, "a card naming a status shows the tooltip")
	t.check(tip.debug_text().contains("Leg Injury"), "the tooltip names the status")
	t.check(tip.debug_text().contains("50%"),
		"the tooltip explains the status from the registry description")
	tip.free()

## A hovered status chip explains ONE status, and the panel hangs BELOW its
## anchor -- the chips sit at the top of the screen under the hp readout,
## so above-the-anchor (the card behaviour) would cover what it explains.
func _test_tooltip_for_single_status(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_status(&"leg_injury", Vector2(200.0, 120.0))
	t.check(tip.visible, "a chip hover shows the tooltip")
	t.check(tip.debug_text().contains("Leg Injury"), "it names the status")
	t.check(tip.debug_text().contains("50%"),
		"it explains the status from the registry description")
	t.check(tip.position.y >= 120.0, "the tooltip hangs below the chip anchor")
	t.check(absf(tip.position.x + tip.size.x / 2.0 - 200.0) < 1.0,
		"the tooltip is centred on the chip")

	tip.show_for_status(&"not_a_status", Vector2(200.0, 120.0))
	t.check(not tip.visible,
		"an unregistered id hides the tooltip rather than showing an empty panel")
	tip.free()

## A bare label tooltip -- the End Turn button's art carries no words, so
## hovering it shows the words here, above the button like a card tooltip.
func _test_label_tooltip(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_label("END TURN", Vector2(800.0, 525.0))
	t.check(tip.visible, "a label tooltip shows")
	t.check(tip.debug_text().contains("END TURN"), "it carries the given words")
	t.check(tip.position.y + tip.size.y < 525.0,
		"it hangs above its anchor, clear of the button")
	t.check(absf(tip.position.x + tip.size.x / 2.0 - 800.0) < 1.0,
		"it is centred on the anchor")
	tip.free()

func _test_tooltip_hides_for_plain_cards(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_card(CardLibrary.load_card(&"low_kick"), Vector2(400.0, 300.0))
	tip.show_for_card(CardLibrary.load_card(&"jab"), Vector2(400.0, 300.0))
	t.check(not tip.visible,
		"a card naming no status hides the tooltip rather than showing it empty")

	tip.show_for_card(CardLibrary.load_card(&"low_kick"), Vector2(400.0, 300.0))
	tip.hide_tooltip()
	t.check(not tip.visible, "hide_tooltip hides it on unhover")
	tip.free()

## The anchor is the hovered card's top-centre; the tooltip hangs its bottom
## edge above it, centred, so it never covers the card it explains.
func _test_tooltip_sits_above_its_anchor(t: TestRunner) -> void:
	var tip := StatusTooltip.new()
	tip.show_for_card(CardLibrary.load_card(&"low_kick"), Vector2(400.0, 300.0))
	t.check(tip.size.y > 0.0, "the tooltip has laid itself out")
	t.check(tip.position.y + tip.size.y < 300.0, "the tooltip's bottom edge sits above the anchor")
	t.check(absf(tip.position.x + tip.size.x / 2.0 - 400.0) < 1.0,
		"the tooltip is centred on the anchor")
	tip.free()

## BattleView owns the tooltip (a card cannot -- CardView clips its
## contents), so HandView must relay its cards' hover changes outward.
func _test_hand_relays_hover(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	battle.deck.hand = [CardLibrary.load_card(&"low_kick")] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)
	var events: Array = []
	hand.card_hovered.connect(func(view: CardView, hovered: bool) -> void:
		events.append([view, hovered]))

	var card: CardView = hand.get_child(0) as CardView
	card.apply_hover(true)
	t.check_eq(events.size(), 1, "hovering a card reaches HandView's relay")
	t.check_eq(events[0][1], true, "the relay carries the hover state")
	card.apply_hover(false)
	t.check_eq(events.size(), 2, "unhovering relays too")
	t.check_eq(events[1][1], false, "the relay carries the unhover state")
	hand.free()
