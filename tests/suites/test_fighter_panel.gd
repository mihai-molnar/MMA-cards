extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_display(t)
	_test_damage_pulse(t)
	_test_guard_pulse(t)
	_test_no_pulse_cases(t)
	_test_shake_amplitude(t)
	_test_centre_point(t)

func _new_panel(align_right: bool) -> FighterPanel:
	return FighterPanel.create("Enemy", Color(0.85, 0.25, 0.25), align_right)

func _test_initial_display(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(true)
	var fighter := Fighter.new("Enemy", 48)
	panel.update(fighter)
	t.check(panel.debug_hp_text().contains("48"), "hp text shows current hp")
	t.check(panel.debug_hp_text().contains("ENEMY"), "hp text names the fighter")
	t.check_eq(panel.debug_last_pulse_kind, &"none", "the first update never pulses")
	panel.free()

func _test_damage_pulse(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(true)
	var fighter := Fighter.new("Enemy", 48)
	panel.update(fighter)
	fighter.apply_hp_loss(6)
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"damage", "losing hp pulses damage")
	t.check_eq(panel.debug_last_pulse_amount, 6, "damage pulse reports the hp lost")
	t.check(panel.debug_hp_text().contains("42"), "hp text updates to the new value")
	panel.free()

func _test_guard_pulse(t: TestRunner) -> void:
	# A fully absorbed hit leaves hp untouched. Without this branch the player
	# gets no feedback at all and cannot tell whether Block worked.
	var panel: FighterPanel = _new_panel(false)
	var fighter := Fighter.new("Player", 50)
	fighter.add_guard(8)
	panel.update(fighter)
	fighter.absorb_into_guard(6)
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"guard", "guard absorbing a hit pulses guard")
	t.check_eq(panel.debug_last_pulse_amount, 6, "guard pulse reports the guard consumed")
	panel.free()

func _test_no_pulse_cases(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(false)
	var fighter := Fighter.new("Player", 50)
	fighter.apply_hp_loss(20)
	panel.update(fighter)

	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"none", "an unchanged fighter does not pulse")

	# restart() restores hp; a reset must not read as healing.
	fighter.reset()
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"none", "hp increasing does not pulse")
	panel.free()

func _test_shake_amplitude(t: TestRunner) -> void:
	t.check_eq(FighterPanel.shake_amplitude(1), 3.0, "small hits clamp to the minimum shake")
	t.check_eq(FighterPanel.shake_amplitude(60), 10.0, "huge hits clamp to the maximum shake")
	t.check(FighterPanel.shake_amplitude(16) > FighterPanel.shake_amplitude(6),
		"a 16 damage combo shakes harder than a 6 damage jab")

func _test_centre_point(t: TestRunner) -> void:
	var left: FighterPanel = _new_panel(false)
	left.position = Vector2(60, 90)
	var right: FighterPanel = _new_panel(true)
	right.position = Vector2(832, 90)
	t.check(right.centre_point().x > left.centre_point().x,
		"the right-aligned panel's centre is to the right of the left one's")
	t.check_eq(left.centre_point().y, right.centre_point().y,
		"both panels sit at the same height")
	left.free()
	right.free()
