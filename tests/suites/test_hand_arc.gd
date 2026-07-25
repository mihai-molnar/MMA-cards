extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_five_card_fan(t)
	_test_single_card(t)
	_test_empty_hand(t)
	_test_clear_of_end_turn_button(t)
	_test_clear_hover(t)

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
