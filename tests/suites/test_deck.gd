extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_state(t)
	_test_draw(t)
	_test_conservation(t)
	_test_reshuffle(t)
	_test_take_from_hand(t)
	_test_burn_card_routes_to_burned_pile(t)
	_test_burned_cards_never_reshuffle(t)
	_test_unplayed_burn_card_discards_normally(t)
	_test_reset_clears_the_burned_pile(t)

func _new_deck() -> Deck:
	return Deck.new(CardLibrary.build_starting_deck(), 12345)

func _test_initial_state(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.total_cards(), 14, "deck starts with 14 cards")
	t.check_eq(deck.draw_pile.size(), 14, "all cards start in the draw pile")
	t.check_eq(deck.hand.size(), 0, "hand starts empty")
	t.check_eq(deck.discard_pile.size(), 0, "discard starts empty")

func _test_draw(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.draw(5), 5, "draw reports how many it drew")
	t.check_eq(deck.hand.size(), 5, "hand holds 5 after a draw")
	t.check_eq(deck.draw_pile.size(), 9, "draw pile drops to 9")
	t.check_eq(deck.total_cards(), 14, "drawing conserves the card count")

func _test_conservation(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	for _turn: int in range(6):
		deck.draw(BattleConfig.HAND_SIZE)
		t.check_eq(deck.total_cards(), 14, "card count stays 14 after drawing")
		deck.discard_hand()
		t.check_eq(deck.total_cards(), 14, "card count stays 14 after discarding")
		t.check_eq(deck.hand.size(), 0, "discard_hand empties the hand")

func _test_reshuffle(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	# Turn 1: 14 -> draw 5 -> draw pile 9, discard 5
	deck.draw(5)
	deck.discard_hand()
	# Turn 2: draw 5 -> draw pile 4, discard 10
	deck.draw(5)
	deck.discard_hand()
	t.check_eq(deck.draw_pile.size(), 4, "draw pile is down to 4 before the reshuffle")
	t.check_eq(deck.discard_pile.size(), 10, "discard has grown to 10")

	# Turn 3: only 4 left, so the discard must reshuffle in to complete the draw.
	t.check_eq(deck.draw(5), 5, "draw completes by reshuffling the discard")
	t.check_eq(deck.hand.size(), 5, "hand is full after the reshuffle")
	t.check_eq(deck.discard_pile.size(), 0, "discard was consumed by the reshuffle")
	t.check_eq(deck.draw_pile.size(), 9, "remaining cards return to the draw pile")
	t.check_eq(deck.total_cards(), 14, "reshuffling conserves the card count")

func _test_take_from_hand(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	deck.draw(5)
	var card: CardData = deck.take_from_hand(2)
	t.check(card != null, "take_from_hand returns the card")
	t.check_eq(deck.hand.size(), 4, "the card leaves the hand")
	t.check_eq(deck.discard_pile.size(), 1, "the played card goes to the discard")
	t.check_eq(deck.total_cards(), 14, "playing conserves the card count")
	t.check(deck.take_from_hand(99) == null, "an out-of-range index returns null safely")

## A burn card helper: id and flag are all the deck logic reads.
func _burn_card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.burn = true
	return card

func _plain_card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	return card

## Playing a burn card sends it to the burned pile, not the discard, and the
## total across all FOUR piles stays invariant.
func _test_burn_card_routes_to_burned_pile(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember"), _plain_card(&"jab")] as Array[CardData], 7)
	deck.draw(2)
	var burn_index: int = 0 if deck.hand[0].burn else 1
	var taken: CardData = deck.take_from_hand(burn_index)
	t.check(taken.burn, "the taken card is the burn card")
	t.check_eq(deck.burned_pile.size(), 1, "the burn card landed in the burned pile")
	t.check_eq(deck.discard_pile.size(), 0, "the burn card did not land in the discard")
	t.check_eq(deck.total_cards(), 2, "total_cards counts the burned pile")

	var plain_taken: CardData = deck.take_from_hand(0)
	t.check(not plain_taken.burn, "the remaining card is the plain one")
	t.check_eq(deck.discard_pile.size(), 1, "a plain card still routes to the discard")

## Exhausting the draw pile reshuffles the discard only -- a burned card is
## out for the rest of the fight.
func _test_burned_cards_never_reshuffle(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember"), _plain_card(&"jab")] as Array[CardData], 7)
	deck.draw(2)
	deck.take_from_hand(0 if deck.hand[0].burn else 1)
	deck.discard_hand()
	var drawn: int = deck.draw(5)
	t.check_eq(drawn, 1, "only the discarded plain card comes back")
	t.check_eq(deck.hand[0].burn, false, "the burned card stayed out")
	t.check_eq(deck.burned_pile.size(), 1, "the burned pile survived the reshuffle")

## Burn triggers on PLAY. A burn card still in hand at end of turn discards
## normally and can be drawn again.
func _test_unplayed_burn_card_discards_normally(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember")] as Array[CardData], 7)
	deck.draw(1)
	deck.discard_hand()
	t.check_eq(deck.discard_pile.size(), 1, "an unplayed burn card goes to the discard")
	t.check_eq(deck.burned_pile.size(), 0, "nothing burned")
	t.check_eq(deck.draw(1), 1, "and it can be drawn again")

func _test_reset_clears_the_burned_pile(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember")] as Array[CardData], 7)
	deck.draw(1)
	deck.take_from_hand(0)
	deck.reset([_plain_card(&"jab")] as Array[CardData])
	t.check_eq(deck.burned_pile.size(), 0, "reset clears the burned pile")
	t.check_eq(deck.total_cards(), 1, "reset leaves only the new cards")
