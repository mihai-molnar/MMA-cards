extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_display(t)
	_test_status_chips_show_registry_numbers(t)
	_test_chip_hover_emits_status_hovered(t)
	_test_guard_chip(t)
	_test_damage_pulse(t)
	_test_guard_pulse(t)
	_test_no_pulse_cases(t)
	_test_shake_amplitude(t)
	_test_centre_point(t)
	_test_suppressed_guard_pulse_reads_as_none(t)
	_test_suppress_flag_does_not_affect_damage(t)
	_test_suppress_flag_clears_after_one_update(t)
	_test_hp_value_overflow_rule(t)

func _new_panel(align_right: bool) -> FighterPanel:
	return FighterPanel.create("Enemy", align_right)

func _test_initial_display(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(true)
	var fighter := Fighter.new("Enemy", 48)
	panel.update(fighter)
	t.check(panel.debug_hp_text().contains("48"), "hp text shows current hp")
	t.check_eq(panel.fighter_name(), "ENEMY", "the name is stored, not painted on the hp row")
	t.check_eq(panel.debug_last_pulse_kind, &"none", "the first update never pulses")
	panel.free()

## EVERY status gets a chip in the dedicated area under the health readout
## -- multiple at once. The number beside each icon is what the registry
## says to show: remaining TURNS for leg injury (counting down each turn),
## stacks for a magnitude like strength.
func _test_status_chips_show_registry_numbers(t: TestRunner) -> void:
	var panel: FighterPanel = FighterPanel.create("Enemy", true)
	var fighter := Fighter.new("Enemy", 48)
	fighter.statuses.apply(&"leg_injury", 1, 3)
	fighter.statuses.apply(&"strength", 2, 2)

	panel.update(fighter)
	t.check_eq(panel.debug_status_chips(), [[&"leg_injury", 3], [&"strength", 2]],
		"both statuses chip up at once: leg injury by turns, strength by stacks")

	fighter.statuses.tick_turn_end()
	panel.update(fighter)
	t.check_eq(panel.debug_status_chips(), [[&"leg_injury", 2], [&"strength", 2]],
		"the countdown ticks while the magnitude holds")

	fighter.statuses.tick_turn_end()
	panel.update(fighter)
	t.check_eq(panel.debug_status_chips(), [[&"leg_injury", 1]],
		"an expired status drops its chip while others remain")

	fighter.statuses.tick_turn_end()
	panel.update(fighter)
	t.check_eq(panel.debug_status_chips(), [], "the area empties with the last status")
	panel.free()

## Chips observe the mouse and report hover outward -- BattleView owns the
## tooltip, so the panel only says WHICH status and WHERE (bottom-centre of
## the chip, in the panel's parent space, so the tooltip can hang below it).
func _test_chip_hover_emits_status_hovered(t: TestRunner) -> void:
	var panel: FighterPanel = FighterPanel.create("Player", false)
	panel.position = Vector2(24, 56)
	var fighter := Fighter.new("Player", 50)
	fighter.statuses.apply(&"leg_injury", 1, 3)
	panel.update(fighter)

	var chips: Array = panel.debug_status_chip_nodes()
	t.check_eq(chips.size(), 1, "one chip node per status")
	if chips.is_empty():
		panel.free()
		return
	var chip := chips[0] as Control
	t.check(chip.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"a chip observes the mouse, or the tooltip can never fire")

	var events: Array = []
	panel.status_hovered.connect(
		func(id: StringName, anchor: Vector2, hovered: bool) -> void:
			events.append([id, anchor, hovered]))
	chip.mouse_entered.emit()
	chip.mouse_exited.emit()
	t.check_eq(events.size(), 2, "enter and exit both report")
	if events.size() == 2:
		t.check_eq(events[0][0], &"leg_injury", "the chip reports its status id")
		t.check_eq(events[0][2], true, "entering reports hovered")
		t.check_eq(events[1][2], false, "exiting reports unhovered")
		var anchor: Vector2 = events[0][1]
		t.check(anchor.y >= panel.position.y,
			"the anchor is in the panel's PARENT space -- offset by the panel position")
	panel.free()

## Guard renders as a chip now -- the icon beside the blue +n -- hidden
## while the fighter holds none, and hover reports outward for the tooltip
## exactly like a status chip (guard is NOT a status, so it has its own
## signal rather than a registry id).
func _test_guard_chip(t: TestRunner) -> void:
	var panel: FighterPanel = FighterPanel.create("Player", false)
	panel.position = Vector2(24, 56)
	var fighter := Fighter.new("Player", 50)
	panel.update(fighter)
	t.check(not panel.debug_guard_chip().visible,
		"no guard, no chip")

	fighter.add_guard(8)
	panel.update(fighter)
	t.check(panel.debug_guard_chip().visible, "gaining guard shows the chip")
	t.check_eq(panel.debug_guard_text(), "+8", "the chip carries the block number")

	fighter.absorb_into_guard(3)
	panel.update(fighter)
	t.check_eq(panel.debug_guard_text(), "+5", "the number tracks the remaining guard")

	var chip: Control = panel.debug_guard_chip()
	t.check(chip.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the guard chip observes the mouse, or the tooltip can never fire")
	var events: Array = []
	panel.guard_hovered.connect(
		func(anchor: Vector2, hovered: bool) -> void:
			events.append([anchor, hovered]))
	chip.mouse_entered.emit()
	chip.mouse_exited.emit()
	t.check_eq(events.size(), 2, "enter and exit both report")
	if events.size() == 2:
		t.check_eq(events[0][1], true, "entering reports hovered")
		t.check_eq(events[1][1], false, "exiting reports unhovered")
		t.check((events[0][0] as Vector2).y >= panel.position.y,
			"the anchor is in the panel's parent space")

	fighter.expire_guard()
	panel.suppress_next_guard_pulse()
	panel.update(fighter)
	t.check(not panel.debug_guard_chip().visible, "expired guard hides the chip")
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

func _test_suppressed_guard_pulse_reads_as_none(t: TestRunner) -> void:
	# Guard expiring at its owner's turn start looks identical, in an hp/guard
	# diff, to guard absorbing a hit. suppress_next_guard_pulse() is how the
	# caller tells the panel which one this update actually is.
	var panel: FighterPanel = _new_panel(false)
	var fighter := Fighter.new("Player", 50)
	fighter.add_guard(8)
	panel.update(fighter)

	panel.suppress_next_guard_pulse()
	fighter.expire_guard()
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"none",
		"a suppressed guard clear reads as no pulse")
	t.check_eq(panel.debug_last_pulse_amount, 0,
		"a suppressed guard clear reports no amount")
	panel.free()

func _test_suppress_flag_does_not_affect_damage(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(false)
	var fighter := Fighter.new("Player", 50)
	panel.update(fighter)

	panel.suppress_next_guard_pulse()
	fighter.apply_hp_loss(6)
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"damage",
		"the suppress flag does not swallow a damage pulse")
	t.check_eq(panel.debug_last_pulse_amount, 6,
		"the damage pulse still reports its own amount")
	panel.free()

func _test_suppress_flag_clears_after_one_update(t: TestRunner) -> void:
	var panel: FighterPanel = _new_panel(false)
	var fighter := Fighter.new("Player", 50)
	fighter.add_guard(8)
	panel.update(fighter)

	panel.suppress_next_guard_pulse()
	fighter.expire_guard()
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"none", "the expiry itself is suppressed")

	# A genuine absorb on the following update -- with no further suppress
	# call -- must pulse normally, proving the flag did not leak forward.
	fighter.add_guard(8)
	panel.update(fighter)
	fighter.absorb_into_guard(5)
	panel.update(fighter)
	t.check_eq(panel.debug_last_pulse_kind, &"guard",
		"a genuine absorb after the suppressed update still pulses")
	t.check_eq(panel.debug_last_pulse_amount, 5,
		"the following absorb reports its own amount, undiminished")
	panel.free()

func _test_hp_value_overflow_rule(t: TestRunner) -> void:
	var panel := FighterPanel.create("Player", false)
	var fighter := Fighter.new("Player", 50)
	panel.update(fighter)
	t.check(not panel.debug_value_overflowed(), "a short hp value centres in the icon window")
	var big := Fighter.new("Player", 5000)
	big.hp = 5000
	panel.update(big)
	t.check(panel.debug_value_overflowed(), "an overlong value anchors at the icon centre and grows right")
	panel.free()
