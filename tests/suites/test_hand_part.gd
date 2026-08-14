extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

## Hand parting: hovering a card makes its neighbours slide aside. The offset
## is a fourth additive compose layer on CardView (like idle sway and cursor
## tilt), driven by HandView from Juice.part_offset(), so it never touches the
## shared _tween slot and cannot fight the hover lift.

func run(t: TestRunner) -> void:
	_test_card_records_part_target(t)
	_test_hover_signal_fires(t)
	_test_hover_parts_the_neighbours(t)
	_test_hover_out_closes_the_fan(t)
	_test_stale_hover_off_keeps_current_parting(t)

func _hand_with(ids: Array) -> HandView:
	var battle := BattleState.new(12345)
	battle.start()
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand
	var view := HandView.new()
	view.rebuild(battle)
	return view

func _test_card_records_part_target(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	t.check_eq(view.debug_part_target(), Vector2.ZERO, "a fresh card has no part offset")
	view.set_part_offset(24.0)
	t.check_eq(view.debug_part_target(), Vector2(24.0, 0.0),
		"set_part_offset records a horizontal part target")
	view.free()

func _test_hover_signal_fires(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	var seen: Array = []
	view.hover_changed.connect(
		func(card: CardView, hovered: bool) -> void: seen.append([card, hovered]))
	view.apply_hover(true)
	view.apply_hover(false)
	view.apply_hover(false)
	t.check_eq(seen.size(), 2, "hover_changed fires once per actual state change")
	t.check(seen[0][0] == view and seen[0][1] == true, "hover on reports the card and true")
	t.check(seen[1][1] == false, "hover off reports false")
	view.free()

func _test_hover_parts_the_neighbours(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	var hovered: CardView = view.get_child(2) as CardView
	hovered.apply_hover(true)
	for index: int in range(view.get_child_count()):
		var card: CardView = view.get_child(index) as CardView
		t.check_eq(card.debug_part_target(), Vector2(Juice.part_offset(index, 2), 0.0),
			"hovering card 2 gives card %d its Juice.part_offset target" % index)
	view.free()

func _test_hover_out_closes_the_fan(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight", &"jab"])
	var hovered: CardView = view.get_child(1) as CardView
	hovered.apply_hover(true)
	hovered.apply_hover(false)
	for index: int in range(view.get_child_count()):
		var card: CardView = view.get_child(index) as CardView
		t.check_eq(card.debug_part_target(), Vector2.ZERO,
			"hover out returns card %d to an unparted fan" % index)
	view.free()

## The cursor can slide from card A onto overlapping card B so that B's hover
## on arrives before A's hover off. The late hover off from A must not clear
## the parting B just established.
func _test_stale_hover_off_keeps_current_parting(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight", &"jab"])
	var first: CardView = view.get_child(0) as CardView
	var second: CardView = view.get_child(1) as CardView
	first.apply_hover(true)
	second.apply_hover(true)
	first.apply_hover(false)
	var last: CardView = view.get_child(2) as CardView
	t.check_eq(last.debug_part_target(), Vector2(Juice.part_offset(2, 1), 0.0),
		"a stale hover off from the previous card leaves the new parting intact")
	view.free()
