extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_five_card_fan(t)
	_test_single_card(t)
	_test_empty_hand(t)
	_test_clear_of_end_turn_button(t)
	_test_clear_of_draw_label(t)
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
	# End Turn is short (48px tall) and sits low (BattleHud.END_TURN_AT), so
	# it only occupies part of the fanned hand's height -- unlike the single
	# furthest-right point rotated_right_edge() reports (the rightmost
	# card's top-right corner, which sits well above the button), what
	# actually has to clear it is the card's edge specifically at the
	# button's own row. rotated_right_edge_at_y() finds that: the straight
	# line between the rotated top-right and bottom-right corners, evaluated
	# at END_TURN_AT.y. That row is the binding one across the button's
	# height -- the edge only gets less extreme (smaller x) further down,
	# toward the bottom-right corner -- see
	# _test_layout_invariants_across_hand_sizes for the full derivation.
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	var rightmost: CardView = view.get_child(4) as CardView
	var right_edge: float = HandView.rotated_right_edge_at_y(
		rightmost.rest_position.x, rightmost.rest_position.y, rightmost.rest_rotation,
		BattleHud.END_TURN_AT.y)
	t.check(right_edge < BattleHud.END_TURN_AT.x,
		"the fan stays clear of the End Turn button (right edge %f)" % right_edge)
	view.free()

## Mirror of _test_clear_of_end_turn_button for the draw-pile label,
## bottom-left. Previously nothing checked this side at all -- the reflow
## pushed both corner controls toward the edges, and while the End Turn side
## was the tighter of the two (see above), the left side is a real
## constraint now too, not a formality. (Retargeted from the old bottom-left
## AP text label to the draw-pile label beneath it: the AP readout moved
## into the FighterPanel's icon cluster, but the draw label still sits at
## the same corner and is checked by the same rotated-silhouette method.)
func _test_clear_of_draw_label(t: TestRunner) -> void:
	var font: Font = ThemeDB.fallback_font
	var deck_total: int = 0
	for copies: int in BattleConfig.DECK_COMPOSITION.values():
		deck_total += copies
	var draw_text: String = "draw %d" % deck_total
	var draw_right_edge: float = BattleHud.DRAW_LABEL_AT.x \
		+ font.get_string_size(draw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x

	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	var leftmost: CardView = view.get_child(0) as CardView
	var left_edge: float = HandView.rotated_left_edge_at_y(
		leftmost.rest_position.x, leftmost.rest_position.y, leftmost.rest_rotation,
		BattleHud.DRAW_LABEL_AT.y)
	t.check(left_edge > draw_right_edge,
		"the fan stays clear of the draw label (left edge %f, label right edge %f)" % [
			left_edge, draw_right_edge])
	view.free()

func _test_clear_hover(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight"])
	var card: CardView = view.get_child(0) as CardView
	card.apply_hover(true)
	view.clear_hover()
	t.check(not card.is_card_hovered(), "clear_hover drops every card back to rest")
	view.free()

## Rotation-aware, row-aware clearance of both corner controls: the
## rightmost card's true edge at End Turn's row (HandView.
## rotated_right_edge_at_y, evaluated at BattleHud.END_TURN_AT.y) holds
## clear only up to n=5 (~967, 18px slack); n=6 would reach ~1037 and
## overlap it. The mirrored left-edge check against the AP label tells the
## same story on that side: n=5 leaves ~73px of slack (182 vs the label's
## ~109px worst-case right edge), but n=6 would reach only ~112 -- just 3px
## clear of that same ~109. Both are exactly why HAND_SIZE's ceiling stays
## at 5 (see _test_hand_size_ceiling). Both invariants below are asserted
## across every hand size the game can actually deal, not just the
## five-card case above, so a future change to HAND_SIZE or the arc
## constants trips a test instead of silently breaking a corner control or
## clipping the bottom of the design space.
func _test_layout_invariants_across_hand_sizes(t: TestRunner) -> void:
	var pool: Array[StringName] = [
		&"jab", &"straight", &"jab", &"block", &"straight"
	]
	var font: Font = ThemeDB.fallback_font
	var ap_right_edge: float = BattleHud.AP_LABEL_AT.x + font.get_string_size(
		"AP  %d / %d" % [BattleConfig.AP_PER_TURN, BattleConfig.AP_PER_TURN],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x

	for n: int in range(1, 6):
		var ids: Array = pool.slice(0, n)
		var view: HandView = _hand_with(ids)
		t.check_eq(view.get_child_count(), n, "hand of %d builds %d cards" % [n, n])

		var rightmost: CardView = view.get_child(n - 1) as CardView
		var right_edge: float = HandView.rotated_right_edge_at_y(
			rightmost.rest_position.x, rightmost.rest_position.y, rightmost.rest_rotation,
			BattleHud.END_TURN_AT.y)
		t.check(right_edge < BattleHud.END_TURN_AT.x,
			"hand of %d clears the End Turn button (right edge %f)" % [n, right_edge])

		var leftmost: CardView = view.get_child(0) as CardView
		var left_edge: float = HandView.rotated_left_edge_at_y(
			leftmost.rest_position.x, leftmost.rest_position.y, leftmost.rest_rotation,
			BattleHud.AP_LABEL_AT.y)
		t.check(left_edge > ap_right_edge,
			"hand of %d clears the AP label (left edge %f, label right edge %f)" % [
				n, left_edge, ap_right_edge])

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

## Raising HAND_SIZE past 5 would silently break both corner controls (see
## _test_layout_invariants_across_hand_sizes) because the fan's clearance
## arithmetic only holds through n=5 on either side. This turns that into a
## loud test failure instead.
##
## This bound is rotation- and row-aware: it is measured against
## HandView.rotated_right_edge_at_y() / rotated_left_edge_at_y(), each
## card's true edge at the row of the control being checked, not the
## axis-aligned rect edge (which understates how far a tilted card reaches)
## nor the single furthest-reaching corner regardless of row (which
## overstates it for a short, low control like End Turn or the AP label --
## see rotated_right_edge_at_y()'s doc comment).
##
## At CARD_STEP_X = 140 and END_TURN_AT.x = 985, n=5's true right edge at
## End Turn's row is ~967, 18px clear; n=6 would reach ~1037, past the
## button. On the left, n=5's true left edge at the AP label's row is ~182,
## ~73px clear of the label's ~109px worst-case right edge; n=6 would reach
## only ~112, just 3px clear. Hence the ceiling stays at 5.
func _test_hand_size_ceiling(t: TestRunner) -> void:
	t.check(BattleConfig.HAND_SIZE <= 5,
		"HAND_SIZE must stay <= 5 -- the fan only clears both corner controls up to 5 cards")
