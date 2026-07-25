extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_apply_and_read(t)
	_test_stacking(t)
	_test_expiry_countdown(t)
	_test_permanent(t)
	_test_clear(t)

func _test_apply_and_read(t) -> void:
	var bag := StatusBag.new()
	t.check_eq(bag.get_stacks(&"strength"), 0, "unknown status reads as 0 stacks")
	t.check(not bag.has(&"strength"), "unknown status is absent")
	bag.apply(&"strength", 2, 2)
	t.check_eq(bag.get_stacks(&"strength"), 2, "applied status reports its stacks")
	t.check(bag.has(&"strength"), "applied status is present")
	t.check_eq(bag.ids(), [&"strength"], "ids() lists applied statuses")

func _test_stacking(t) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.apply(&"strength", 3, 1)
	t.check_eq(bag.get_stacks(&"strength"), 5, "re-applying adds stacks")

func _test_expiry_countdown(t) -> void:
	# A 2-turn buff must survive the turn it was applied on and expire at the
	# end of the following turn. This is the enemy buff timing.
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 2, "2-turn buff survives its own turn end")
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 0, "2-turn buff expires at the next turn end")
	t.check(not bag.has(&"strength"), "expired status is removed, not left at 0")

func _test_permanent(t) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 1, -1)
	bag.tick_turn_end()
	bag.tick_turn_end()
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 1, "permanent status never expires")

func _test_clear(t) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.clear()
	t.check_eq(bag.get_stacks(&"strength"), 0, "clear() removes everything")
