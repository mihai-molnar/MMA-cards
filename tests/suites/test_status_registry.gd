extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_strength_math(t)
	_test_registry_dispatch(t)

func _test_strength_math(t) -> void:
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 0), 8, "0 strength leaves damage unchanged")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 2), 12, "2 strength turns 8 into 12")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 1), 10, "1 strength turns 8 into 10")
	# 9 * 1.25 = 11.25 -> floors to 11
	t.check_eq(StrengthStatus.modify_outgoing_damage(9, 1), 11, "strength bonus floors, never rounds up")
	t.check_eq(StrengthStatus.modify_incoming_damage(8, 2), 8, "strength does not change incoming damage")

func _test_registry_dispatch(t) -> void:
	var bag := StatusBag.new()
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 8, "empty bag applies no modifiers")

	bag.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "registry routes through strength")
	t.check_eq(StatusRegistry.modify_incoming(bag, 8), 8, "registry incoming is pass-through for strength")
	t.check_eq(StatusRegistry.display_name(StrengthStatus.ID), "STR", "registry exposes display names")

	bag.apply(&"unregistered_status", 5, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "unregistered status is ignored, not crashing")
