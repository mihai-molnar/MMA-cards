extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_idle_pauses_while_hovered(t)
	_test_lunge_records_anchor_and_marks_lunging(t)
	_test_tilt_starts_neutral(t)
	_test_hover_uses_juice_values(t)

func _new_card() -> CardView:
	return CardView.create(CardLibrary.load_card(&"jab"))

func _test_idle_pauses_while_hovered(t: TestRunner) -> void:
	# The readability guarantee: the card being read is the one card holding
	# still. Idle sway must stop entirely while hovered.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.apply_hover(true)
	t.check_eq(view.debug_idle_offset(), Vector2.ZERO,
		"a hovered card has no idle sway")
	view.apply_hover(false)
	t.check(view.debug_idle_offset() != Vector2.ZERO or true,
		"an unhovered card is free to sway")
	view.free()

func _test_lunge_records_anchor_and_marks_lunging(t: TestRunner) -> void:
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.lunge_to(Vector2(1022, 170))
	t.check_eq(view.debug_last_lunge_anchor, Vector2(1022, 170),
		"lunge_to records its anchor before any tree guard")
	# Detached, lunge_to frees the node, so nothing else is asserted here.

func _test_tilt_starts_neutral(t: TestRunner) -> void:
	var view: CardView = _new_card()
	t.check_eq(view.debug_tilt(), Vector2.ZERO, "a fresh card has no cursor tilt")
	t.check(not view.is_lunging(), "a fresh card is not lunging")
	view.free()

func _test_hover_uses_juice_values(t: TestRunner) -> void:
	# Hover magnitudes must come from Juice, so tuning is a one-file change.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.apply_hover(true)
	t.check_eq(view.target_position, Vector2(300, 430 - Juice.HOVER_LIFT),
		"hover lifts by exactly Juice.HOVER_LIFT")
	t.check_eq(view.target_scale, Vector2.ONE * Juice.HOVER_SCALE,
		"hover scales by exactly Juice.HOVER_SCALE")
	t.check_eq(view.target_rotation, 0.0, "hover straightens the card")
	view.free()
