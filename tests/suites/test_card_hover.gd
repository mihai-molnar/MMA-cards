extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_rest_transform(t)
	_test_hover_lifts_and_straightens(t)
	_test_hover_out_restores_exactly(t)
	_test_hover_is_idempotent(t)
	_test_unaffordable_still_lifts(t)
	_test_pivot_is_bottom_centre(t)
	_test_z_order_below_result_panel(t)

func _new_card() -> CardView:
	return CardView.create(CardLibrary.load_card(&"jab"))

func _test_rest_transform(t: TestRunner) -> void:
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 470), 0.2, 3)
	t.check_eq(view.rest_position, Vector2(300, 470), "rest position is stored")
	t.check_eq(view.rest_rotation, 0.2, "rest rotation is stored")
	t.check_eq(view.rest_z_index, 3, "rest z index is stored")
	t.check_eq(view.position, Vector2(300, 470), "an unhovered card snaps to its rest position")
	view.free()

func _test_hover_lifts_and_straightens(t: TestRunner) -> void:
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 470), 0.2, 3)
	view.apply_hover(true)
	t.check(view.is_card_hovered(), "the card knows it is hovered")
	t.check(view.target_position.y < 470.0, "hovering lifts the card")
	t.check_eq(view.target_rotation, 0.0, "hovering straightens the card so it is readable")
	t.check(view.target_scale.x > 1.0, "hovering scales the card up")
	t.check_eq(view.z_index, CardView.HOVER_Z, "a hovered card draws above its neighbours")
	view.free()

func _test_hover_out_restores_exactly(t: TestRunner) -> void:
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 470), 0.2, 3)
	view.apply_hover(true)
	view.apply_hover(false)
	t.check(not view.is_card_hovered(), "the card knows the cursor left")
	t.check_eq(view.target_position, Vector2(300, 470), "hover out returns to the exact rest position")
	t.check_eq(view.target_rotation, 0.2, "hover out returns to the exact rest rotation")
	t.check_eq(view.target_scale, Vector2.ONE, "hover out returns to unscaled")
	t.check_eq(view.z_index, 3, "hover out restores the resting z index")
	view.free()

func _test_hover_is_idempotent(t: TestRunner) -> void:
	# set_combo_armed had exactly this bug during the POC: it lerped from the
	# current colour, so repeated calls drifted. Targets are always recomputed
	# from rest_*, so three round trips must land bit-identically.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 470), 0.2, 3)
	for _i: int in range(3):
		view.apply_hover(true)
		view.apply_hover(false)
	t.check_eq(view.target_position, Vector2(300, 470), "three hover round trips do not drift position")
	t.check_eq(view.target_rotation, 0.2, "three hover round trips do not drift rotation")
	view.free()

func _test_unaffordable_still_lifts(t: TestRunner) -> void:
	# You should be able to read a card you cannot afford.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 470), 0.2, 3)
	view.set_affordable(false)
	view.apply_hover(true)
	t.check(view.target_position.y < 470.0, "an unaffordable card still lifts on hover")
	t.check(view.disabled, "an unaffordable card stays disabled while hovered")
	view.free()

func _test_pivot_is_bottom_centre(t: TestRunner) -> void:
	# Rotating about bottom-centre is what makes the fan read as a held hand
	# rather than cards pinwheeling about their middles.
	var view: CardView = _new_card()
	t.check_eq(view.pivot_offset, Vector2(CardView.CARD_SIZE.x / 2.0, CardView.CARD_SIZE.y),
		"cards rotate about their bottom centre")
	view.free()

func _test_z_order_below_result_panel(t: TestRunner) -> void:
	# z_index lifts a node above its parent's later siblings, so a hovered card
	# must stay below the game-over banner or it redraws over it.
	t.check(CardView.HOVER_Z < BattleHud.RESULT_PANEL_Z,
		"a hovered card cannot draw over the game over banner")
	t.check(CardView.LUNGE_Z < BattleHud.RESULT_PANEL_Z,
		"a lunging card cannot draw over the game over banner")
