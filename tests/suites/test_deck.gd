extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_state(t)
	_test_draw(t)
	_test_conservation(t)
	_test_reshuffle(t)
	_test_take_from_hand(t)

func _new_deck() -> Deck:
	return Deck.new(CardLibrary.build_starting_deck(), 12345)

func _test_initial_state(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.total_cards(), 12, "deck starts with 12 cards")
	t.check_eq(deck.draw_pile.size(), 12, "all cards start in the draw pile")
	t.check_eq(deck.hand.size(), 0, "hand starts empty")
	t.check_eq(deck.discard_pile.size(), 0, "discard starts empty")

func _test_draw(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.draw(5), 5, "draw reports how many it drew")
	t.check_eq(deck.hand.size(), 5, "hand holds 5 after a draw")
	t.check_eq(deck.draw_pile.size(), 7, "draw pile drops to 7")
	t.check_eq(deck.total_cards(), 12, "drawing conserves the card count")

func _test_conservation(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	for _turn: int in range(6):
		deck.draw(BattleConfig.HAND_SIZE)
		t.check_eq(deck.total_cards(), 12, "card count stays 12 after drawing")
		deck.discard_hand()
		t.check_eq(deck.total_cards(), 12, "card count stays 12 after discarding")
		t.check_eq(deck.hand.size(), 0, "discard_hand empties the hand")

func _test_reshuffle(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	# Turn 1: 12 -> draw 5 -> draw pile 7, discard 5
	deck.draw(5)
	deck.discard_hand()
	# Turn 2: draw 5 -> draw pile 2, discard 10
	deck.draw(5)
	deck.discard_hand()
	t.check_eq(deck.draw_pile.size(), 2, "draw pile is down to 2 before the reshuffle")
	t.check_eq(deck.discard_pile.size(), 10, "discard has grown to 10")

	# Turn 3: only 2 left, so the discard must reshuffle in to complete the draw.
	t.check_eq(deck.draw(5), 5, "draw completes by reshuffling the discard")
	t.check_eq(deck.hand.size(), 5, "hand is full after the reshuffle")
	t.check_eq(deck.discard_pile.size(), 0, "discard was consumed by the reshuffle")
	t.check_eq(deck.draw_pile.size(), 7, "remaining cards return to the draw pile")
	t.check_eq(deck.total_cards(), 12, "reshuffling conserves the card count")

func _test_take_from_hand(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	deck.draw(5)
	var card: CardData = deck.take_from_hand(2)
	t.check(card != null, "take_from_hand returns the card")
	t.check_eq(deck.hand.size(), 4, "the card leaves the hand")
	t.check_eq(deck.discard_pile.size(), 1, "the played card goes to the discard")
	t.check_eq(deck.total_cards(), 12, "playing conserves the card count")
	t.check(deck.take_from_hand(99) == null, "an out-of-range index returns null safely")
