extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_deal_leaves_every_card_at_rest(t)
	_test_deal_is_safe_for_an_empty_hand(t)

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

func _test_deal_leaves_every_card_at_rest(t: TestRunner) -> void:
	# The stagger animates cards in from below. If it left any card short of
	# its slot, the fan would be silently wrong.
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	view.deal_in()
	var all_at_rest: bool = true
	for child: Node in view.get_children():
		var card: CardView = child as CardView
		if card == null:
			continue
		if card.target_position != card.rest_position:
			all_at_rest = false
	t.check(all_at_rest, "every card ends the deal at exactly its rest position")
	t.check_eq(view.get_child_count(), 5, "dealing does not add or drop cards")
	view.free()

func _test_deal_is_safe_for_an_empty_hand(t: TestRunner) -> void:
	var view: HandView = _hand_with([])
	view.deal_in()
	t.check_eq(view.get_child_count(), 0, "dealing an empty hand is safe")
	view.free()
