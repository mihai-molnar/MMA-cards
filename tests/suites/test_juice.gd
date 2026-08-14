extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_compose(t)
	_test_idle_is_bounded(t)
	_test_idle_phases_differ(t)
	_test_screen_shake_amplitude(t)
	_test_rect_shake_amplitude(t)
	_test_hit_stop_duration(t)
	_test_part_offset(t)
	_test_play_impact_delay(t)

func _test_compose(t: TestRunner) -> void:
	# A still card must sit exactly where layout put it, with no drift from
	# composing zero offsets.
	t.check_eq(Juice.compose_position(Vector2(300, 430), Vector2.ZERO, Vector2.ZERO),
		Vector2(300, 430), "zero idle and tilt compose to the anim value exactly")
	t.check_eq(Juice.compose_rotation(0.2, 0.0, 0.0), 0.2,
		"zero idle and tilt rotation compose to the anim rotation exactly")

	t.check_eq(Juice.compose_position(Vector2(300, 430), Vector2(2, -1), Vector2(0, 3)),
		Vector2(302, 432), "idle and tilt offsets add onto the anim position")
	t.check_eq(Juice.compose_position(Vector2(300, 430), Vector2.ZERO, Vector2.ZERO, Vector2(10, 0)),
		Vector2(310, 430), "the part offset adds onto the anim position as a fourth layer")
	t.check_eq(Juice.compose_rotation(0.2, 0.05, -0.01), 0.24,
		"idle and tilt rotation add onto the anim rotation")

func _test_idle_is_bounded(t: TestRunner) -> void:
	# Idle sway must stay small: cards carry five lines of rules text, and a
	# large wobble would blur it.
	var max_seen: float = 0.0
	var max_rot: float = 0.0
	for step: int in range(400):
		var time: float = step * 0.05
		var offset: Vector2 = Juice.idle_offset(time, 0.0)
		max_seen = maxf(max_seen, maxf(absf(offset.x), absf(offset.y)))
		max_rot = maxf(max_rot, absf(Juice.idle_rotation(time, 0.0)))
	t.check(max_seen <= Juice.IDLE_SWAY_PX + 0.001,
		"idle sway never exceeds its configured pixel amplitude")
	t.check(max_rot <= deg_to_rad(Juice.IDLE_SWAY_DEG) + 0.001,
		"idle rotation never exceeds its configured degree amplitude")
	t.check(max_seen > 0.0, "idle sway actually moves the card")

func _test_idle_phases_differ(t: TestRunner) -> void:
	# The hand must not breathe in unison, or it reads as one object.
	var a: Vector2 = Juice.idle_offset(1.0, 0.0)
	var b: Vector2 = Juice.idle_offset(1.0, PI)
	t.check(a != b, "different phases produce different sway offsets")

func _test_screen_shake_amplitude(t: TestRunner) -> void:
	t.check_eq(Juice.screen_shake_amplitude(0), Juice.SHAKE_MIN,
		"a zero-damage hit clamps to the minimum screen shake")
	t.check_eq(Juice.screen_shake_amplitude(999), Juice.SHAKE_MAX,
		"a huge hit clamps to the maximum screen shake")
	t.check(Juice.screen_shake_amplitude(16) > Juice.screen_shake_amplitude(6),
		"a 16 damage combo shakes the screen harder than a 6 damage jab")

func _test_play_impact_delay(t: TestRunner) -> void:
	# The blow lands NEAR the end of the card's travel, not at the start and
	# not exactly at the end: after the windup and most of the strike, while
	# the card is dissolving into the target.
	t.check(Juice.play_impact_delay() > Juice.ANTICIPATE_TIME,
		"the impact lands after the windup, during the strike")
	t.check(Juice.play_impact_delay() < Juice.ANTICIPATE_TIME + Juice.LUNGE_TIME,
		"the impact lands before the card's travel fully completes")
	t.check_eq(Juice.play_impact_delay(),
		Juice.ANTICIPATE_TIME + Juice.LUNGE_TIME * Juice.LUNGE_IMPACT_RATIO,
		"the impact delay is the windup plus the impact fraction of the strike")

func _test_hit_stop_duration(t: TestRunner) -> void:
	# Big hits must freeze the world longer than small ones, within clamps, so
	# a combo Straight lands heavier than a jab.
	t.check_eq(Juice.hit_stop_duration(0), Juice.HITSTOP_MIN_TIME,
		"a zero-damage hit clamps to the minimum hit stop")
	t.check_eq(Juice.hit_stop_duration(999), Juice.HITSTOP_MAX_TIME,
		"a huge hit clamps to the maximum hit stop")
	t.check(Juice.hit_stop_duration(16) > Juice.hit_stop_duration(6),
		"a 16 damage combo freezes longer than a 6 damage jab")

func _test_part_offset(t: TestRunner) -> void:
	# Neighbours of the hovered card slide away to make room, with falloff by
	# distance, so the fan feels physical rather than a stack of rects.
	t.check_eq(Juice.part_offset(2, -1), 0.0, "no hovered card means no parting")
	t.check_eq(Juice.part_offset(2, 2), 0.0, "the hovered card itself never parts")
	t.check(Juice.part_offset(3, 2) > 0.0, "a right neighbour parts rightward")
	t.check(Juice.part_offset(1, 2) < 0.0, "a left neighbour parts leftward")
	t.check_eq(Juice.part_offset(1, 2), -Juice.part_offset(3, 2),
		"parting is symmetric about the hovered card")
	t.check(absf(Juice.part_offset(4, 2)) < absf(Juice.part_offset(3, 2)),
		"parting falls off with distance from the hovered card")

func _test_rect_shake_amplitude(t: TestRunner) -> void:
	# Must match FighterPanel's existing formula exactly so Task 6 can delegate
	# without changing observable behaviour.
	t.check_eq(Juice.rect_shake_amplitude(1), 3.0, "rect shake clamps to its minimum")
	t.check_eq(Juice.rect_shake_amplitude(60), 10.0, "rect shake clamps to its maximum")
	t.check_eq(Juice.rect_shake_amplitude(12), 6.0, "rect shake scales linearly between clamps")
