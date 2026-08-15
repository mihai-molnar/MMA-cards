extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_apply_and_read(t)
	_test_stacking(t)
	_test_extend_duration(t)
	_test_turns_are_readable(t)
	_test_expiry_countdown(t)
	_test_permanent(t)
	_test_clear(t)

## The default re-apply keeps the LONGER duration (a refresh); extend mode
## ADDS the durations instead -- the Low Kick semantics, where each kick
## keeps the leg hurt one turn longer. Stacks do not accumulate in extend
## mode: a leg is injured or it is not, so re-applying keeps the larger
## stack count rather than summing.
func _test_extend_duration(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"leg_injury", 1, 1, true)
	bag.apply(&"leg_injury", 1, 1, true)
	t.check_eq(bag.get_turns(&"leg_injury"), 2, "extending adds the durations (1 + 1 = 2)")
	t.check_eq(bag.get_stacks(&"leg_injury"), 1, "extending does not stack the stacks")

	# Permanence still dominates: extending a permanent status leaves it
	# permanent rather than arithmetic-ing on the -1 sentinel.
	var permanent := StatusBag.new()
	permanent.apply(&"strength", 1, BattleConfig.STATUS_PERMANENT)
	permanent.apply(&"strength", 1, 2, true)
	permanent.tick_turn_end()
	permanent.tick_turn_end()
	permanent.tick_turn_end()
	t.check(permanent.has(&"strength"), "extending a permanent status keeps it permanent")

func _test_turns_are_readable(t: TestRunner) -> void:
	var bag := StatusBag.new()
	t.check_eq(bag.get_turns(&"leg_injury"), 0, "unknown status reads as 0 turns")
	bag.apply(&"leg_injury", 1, 3)
	t.check_eq(bag.get_turns(&"leg_injury"), 3, "an applied status reports its remaining turns")
	bag.tick_turn_end()
	t.check_eq(bag.get_turns(&"leg_injury"), 2, "the readable turns count down")

func _test_apply_and_read(t: TestRunner) -> void:
	var bag := StatusBag.new()
	t.check_eq(bag.get_stacks(&"strength"), 0, "unknown status reads as 0 stacks")
	t.check(not bag.has(&"strength"), "unknown status is absent")
	bag.apply(&"strength", 2, 2)
	t.check_eq(bag.get_stacks(&"strength"), 2, "applied status reports its stacks")
	t.check(bag.has(&"strength"), "applied status is present")
	t.check_eq(bag.ids(), [&"strength"], "ids() lists applied statuses")

func _test_stacking(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.apply(&"strength", 3, 1)
	t.check_eq(bag.get_stacks(&"strength"), 5, "re-applying adds stacks")

func _test_expiry_countdown(t: TestRunner) -> void:
	# A 2-turn buff must survive the turn it was applied on and expire at the
	# end of the following turn. This is the enemy buff timing.
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 2, "2-turn buff survives its own turn end")
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 0, "2-turn buff expires at the next turn end")
	t.check(not bag.has(&"strength"), "expired status is removed, not left at 0")

func _test_permanent(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 1, -1)
	bag.tick_turn_end()
	bag.tick_turn_end()
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 1, "permanent status never expires")

func _test_clear(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.clear()
	t.check_eq(bag.get_stacks(&"strength"), 0, "clear() removes everything")
