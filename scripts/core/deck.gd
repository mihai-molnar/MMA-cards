class_name Deck
extends RefCounted

## Draw pile, hand, and discard. The total card count is invariant: cards only
## ever move between the three piles.

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(cards: Array[CardData], rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	reset(cards)

func reset(cards: Array[CardData]) -> void:
	draw_pile = cards.duplicate()
	hand.clear()
	discard_pile.clear()
	_shuffle(draw_pile)

## Draws up to `count` cards, reshuffling the discard pile if the draw pile
## runs out. Returns how many were actually drawn.
func draw(count: int) -> int:
	var drawn: int = 0
	for _i: int in range(count):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			_reshuffle_discard_into_draw()
		hand.append(draw_pile.pop_back())
		drawn += 1
	return drawn

func discard_hand() -> void:
	for card: CardData in hand:
		discard_pile.append(card)
	hand.clear()

## Removes a card from the hand and sends it to the discard. Returns null if
## the index is out of range.
func take_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var card: CardData = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)
	return card

func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()

func _reshuffle_discard_into_draw() -> void:
	for card: CardData in discard_pile:
		draw_pile.append(card)
	discard_pile.clear()
	_shuffle(draw_pile)

func _shuffle(pile: Array[CardData]) -> void:
	# Fisher-Yates using the seeded RNG so tests are deterministic.
	for i: int in range(pile.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var temp: CardData = pile[i]
		pile[i] = pile[j]
		pile[j] = temp
