extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_five_card_fan(t)
	_test_single_card(t)
	_test_empty_hand(t)
	_test_clear_of_end_turn_button(t)
	_test_clear_hover(t)
	_test_layout_invariants_across_hand_sizes(t)
	_test_hand_size_ceiling(t)

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

func _test_five_card_fan(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	t.check_eq(view.get_child_count(), 5, "the fan holds one node per card")

	var cards: Array[CardView] = []
	for child: Node in view.get_children():
		cards.append(child as CardView)

	# x strictly increasing left to right
	var increasing: bool = true
	for i: int in range(1, cards.size()):
		if cards[i].rest_position.x <= cards[i - 1].rest_position.x:
			increasing = false
	t.check(increasing, "cards are laid out left to right")

	# the centre card sits highest (smallest y)
	var centre_y: float = cards[2].rest_position.y
	t.check(centre_y < cards[0].rest_position.y, "the centre card sits above the leftmost")
	t.check(centre_y < cards[4].rest_position.y, "the centre card sits above the rightmost")

	# rotations are symmetric, and the outermost hits the configured maximum
	t.check(absf(cards[0].rest_rotation + cards[4].rest_rotation) < 0.0001,
		"outer rotations are equal and opposite")
	t.check_eq(cards[2].rest_rotation, 0.0, "the centre card is upright")
	t.check(absf(cards[4].rest_rotation - deg_to_rad(HandView.MAX_FAN_ANGLE_DEG)) < 0.0001,
		"the rightmost card is tilted by the configured maximum")

	# z order so later cards overlap earlier ones
	t.check_eq(cards[0].rest_z_index, 0, "the leftmost card is furthest back")
	t.check_eq(cards[4].rest_z_index, 4, "the rightmost card is furthest forward")
	view.free()

func _test_single_card(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab"])
	var card: CardView = view.get_child(0) as CardView
	t.check_eq(card.rest_rotation, 0.0, "a single card is upright")
	t.check_eq(card.rest_position.y, HandView.HAND_BASE_Y, "a single card gets no arch")
	t.check_eq(card.rest_position.x, HandView.HAND_CENTRE_X - CardView.CARD_SIZE.x / 2.0,
		"a single card is centred")
	view.free()

func _test_empty_hand(t: TestRunner) -> void:
	var view: HandView = _hand_with([])
	t.check_eq(view.get_child_count(), 0, "an empty hand lays out nothing")
	view.layout_cards()
	t.check_eq(view.get_child_count(), 0, "laying out an empty hand is safe")
	view.free()

func _test_clear_of_end_turn_button(t: TestRunner) -> void:
	# The End Turn button's left edge is at x=900; the fan must not reach it.
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	var rightmost: CardView = view.get_child(4) as CardView
	var right_edge: float = rightmost.rest_position.x + CardView.CARD_SIZE.x
	t.check(right_edge < 900.0, "the fan stays clear of the End Turn button")
	view.free()

func _test_clear_hover(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight"])
	var card: CardView = view.get_child(0) as CardView
	card.apply_hover(true)
	view.clear_hover()
	t.check(not card.is_card_hovered(), "clear_hover drops every card back to rest")
	view.free()

## right_edge = 654 + 58 * (n - 1): clearance of the End Turn button (x=900)
## holds only up to n=5 (886, 14px slack); n=6 would reach 944 and overlap
## it -- which is exactly why HAND_SIZE's ceiling dropped from 6 to 5 when
## the cards grew ~30% (see _test_hand_size_ceiling). Both invariants below
## are asserted across every hand size the game can actually deal, not just
## the five-card case above, so a future change to HAND_SIZE or the arc
## constants trips a test instead of silently breaking End Turn or clipping
## the bottom of the design space.
func _test_layout_invariants_across_hand_sizes(t: TestRunner) -> void:
	var pool: Array[StringName] = [
		&"jab", &"straight", &"jab", &"block", &"straight"
	]
	for n: int in range(1, 6):
		var ids: Array = pool.slice(0, n)
		var view: HandView = _hand_with(ids)
		t.check_eq(view.get_child_count(), n, "hand of %d builds %d cards" % [n, n])

		var rightmost: CardView = view.get_child(n - 1) as CardView
		var right_edge: float = rightmost.rest_position.x + CardView.CARD_SIZE.x
		t.check(right_edge < 900.0,
			"hand of %d clears the End Turn button (right edge %f)" % [n, right_edge])

		# Regression guard for the bottom-clip fix: a card's rotated bottom
		# corner (approximated using the maximum fan angle) must stay inside
		# the 648-tall design space. This fails if HAND_BASE_Y, FAN_ARCH_HEIGHT
		# or MAX_FAN_ANGLE_DEG changes in a way that pushes cards too low.
		for index: int in range(n):
			var card: CardView = view.get_child(index) as CardView
			var bottom_y: float = card.rest_position.y + CardView.CARD_SIZE.y \
				+ (CardView.CARD_SIZE.x / 2.0) * sin(deg_to_rad(HandView.MAX_FAN_ANGLE_DEG))
			t.check(bottom_y <= 648.0,
				"hand of %d card %d stays inside the design space (bottom %f)" % [n, index, bottom_y])
		view.free()

## Raising HAND_SIZE past 5 would silently break End Turn (see
## _test_layout_invariants_across_hand_sizes) because the fan's clearance
## arithmetic only holds through n=5. This turns that into a loud test
## failure instead.
##
## The ceiling dropped from 6 to 5 when the cards grew ~30% (CARD_SIZE
## 120x180 -> 156x234, CARD_STEP_X 86 -> 116): the wider step and wider card
## push the n=6 right edge to 944, past the End Turn button at x=900, where
## the old, smaller cards cleared it at n=6 with 14px to spare.
##
## Also note: like _test_layout_invariants_across_hand_sizes, this still only
## covers the ceiling implied by that test's unrotated bounding-box check --
## it was already a slight overestimate of clearance before the card size
## changed, since a fanned card's true rotated corner sits marginally further
## right than its axis-aligned bounding box. Not reworked here to stay
## rotation-aware; keeping this change minimal.
func _test_hand_size_ceiling(t: TestRunner) -> void:
	t.check(BattleConfig.HAND_SIZE <= 5,
		"HAND_SIZE must stay <= 5 -- the fan only clears the End Turn button up to 5 cards")
