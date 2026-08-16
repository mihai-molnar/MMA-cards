extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_open_builds_sorted_grid(t)
	_test_grid_cards_rest_scaled_inside_the_canvas(t)
	_test_close_button(t)
	_test_hover_relay(t)
	_test_empty_pile_opens(t)

func _cards(ids: Array) -> Array[CardData]:
	var cards: Array[CardData] = []
	for id: StringName in ids:
		cards.append(CardLibrary.load_card(id))
	return cards

## The draw pile's internal order IS the upcoming draw order, so the grid
## sorts by display name -- the view shows WHAT is left without revealing
## WHEN it comes. (Slay the Spire's rule, deliberately.)
func _test_open_builds_sorted_grid(t: TestRunner) -> void:
	var view := PileView.new()
	view.open(_cards([&"straight", &"jab", &"block", &"jab"]), "DRAW PILE (4)")
	t.check(view.visible, "opening shows the view")
	t.check_eq(view.debug_card_ids(), [&"block", &"jab", &"jab", &"straight"],
		"cards sort by display name, duplicates kept")
	t.check_eq(view.debug_title(), "DRAW PILE (4)", "the title is what the caller passed")

	view.open(_cards([&"low_kick"]), "DISCARDED (1)")
	t.check_eq(view.debug_card_ids(), [&"low_kick"],
		"reopening rebuilds the grid for the new pile")
	view.free()

## Grid cards rest at a reduced scale (a 14-card pile must fit the canvas)
## and every card's VISUAL rect -- bottom-centre pivot, so the scaled rect
## shrinks toward the card's bottom-centre -- stays inside the 1152x648
## design space. Hover still zooms to the absolute hand-sized scale, which
## is what makes rules text readable, so rest scale must survive an
## unhover round-trip.
func _test_grid_cards_rest_scaled_inside_the_canvas(t: TestRunner) -> void:
	var view := PileView.new()
	var fourteen: Array = []
	for i: int in range(14):
		fourteen.append([&"jab", &"straight", &"block", &"low_kick"][i % 4])
	view.open(_cards(fourteen), "DRAW PILE (14)")

	var views: Array = view.debug_card_views()
	t.check_eq(views.size(), 14, "one CardView per card in the pile")
	if views.is_empty():
		view.free()
		return
	var positions_seen: Dictionary = {}
	for card_view: CardView in views:
		var s: float = card_view.target_scale.x
		t.check(s < 1.0, "grid cards rest below full size (scale %f)" % s)
		var visual_left: float = card_view.rest_position.x + CardView.CARD_SIZE.x * (1.0 - s) / 2.0
		var visual_top: float = card_view.rest_position.y + CardView.CARD_SIZE.y * (1.0 - s)
		var visual_right: float = visual_left + CardView.CARD_SIZE.x * s
		var visual_bottom: float = visual_top + CardView.CARD_SIZE.y * s
		t.check(visual_left >= 0.0 and visual_right <= 1152.0
			and visual_top >= 0.0 and visual_bottom <= 648.0,
			"every grid card sits inside the canvas (%s)" % card_view.rest_position)
		positions_seen[card_view.rest_position] = true
	t.check_eq(positions_seen.size(), 14, "every grid card gets its own slot")

	var first: CardView = views[0] as CardView
	var rest_scale: Vector2 = first.target_scale
	first.apply_hover(true)
	t.check_eq(first.target_scale, Vector2.ONE * Juice.HOVER_SCALE,
		"hover zooms a grid card to the same absolute size as a hand card")
	first.apply_hover(false)
	t.check_eq(first.target_scale, rest_scale,
		"unhover settles back to the grid rest scale, not full size")
	view.free()

func _test_close_button(t: TestRunner) -> void:
	var view := PileView.new()
	view.open(_cards([&"jab"]), "DRAW PILE (1)")
	var button: TextureButton = view.debug_close_button()
	t.check(button != null, "the close button exists")
	if button == null:
		view.free()
		return
	t.check(button.texture_normal != null and button.texture_pressed != null,
		"the close button wears both art variants")
	t.check(button.texture_normal != button.texture_pressed,
		"pressing visibly swaps the close art")
	t.check_eq(button.focus_mode, Control.FOCUS_NONE, "no focus rectangle after a click")
	t.check_eq(button.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND,
		"the close button shows the pointer cursor")
	t.check(button.position.x + button.size.x > 1152.0 * 0.9,
		"the close button sits at the top right")

	var closes: Array = []
	view.closed.connect(func() -> void: closes.append(true))
	button.pressed.emit()
	t.check(not view.visible, "clicking close hides the view")
	t.check_eq(closes.size(), 1, "closing reports outward, once")
	view.free()

## Hover on grid cards works exactly like the hand: the view relays each
## card's hover_changed so BattleView can drive the keyword tooltip.
func _test_hover_relay(t: TestRunner) -> void:
	var view := PileView.new()
	view.open(_cards([&"low_kick"]), "DISCARDED (1)")
	var events: Array = []
	view.card_hovered.connect(
		func(card_view: CardView, hovered: bool) -> void:
			events.append([card_view.card.id, hovered]))
	var views: Array = view.debug_card_views()
	if views.is_empty():
		t.check(false, "no card views built to hover")
		view.free()
		return
	var first: CardView = views[0] as CardView
	first.apply_hover(true)
	first.apply_hover(false)
	t.check_eq(events, [[&"low_kick", true], [&"low_kick", false]],
		"the view relays its cards' hover changes")
	view.free()

func _test_empty_pile_opens(t: TestRunner) -> void:
	var view := PileView.new()
	view.open([] as Array[CardData], "DISCARDED (0)")
	t.check(view.visible, "an empty pile still opens -- title and close, no cards")
	t.check_eq(view.debug_card_ids(), [], "no cards, no views")
	view.free()
