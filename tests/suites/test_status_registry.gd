extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_strength_math(t)
	_test_leg_injury_math(t)
	_test_registry_dispatch(t)
	_test_status_descriptions(t)
	_test_turn_start_hook(t)

func _test_leg_injury_math(t: TestRunner) -> void:
	t.check_eq(LegInjuryStatus.modify_outgoing_damage(8, 1), 4, "leg injury halves 8 to 4")
	# 9 * 0.5 = 4.5 -> floors to 4
	t.check_eq(LegInjuryStatus.modify_outgoing_damage(9, 1), 4, "leg injury floors, never rounds up")
	t.check_eq(LegInjuryStatus.modify_outgoing_damage(8, 0), 8, "0 stacks leaves damage unchanged")
	t.check_eq(LegInjuryStatus.modify_incoming_damage(8, 1), 8,
		"leg injury does not change incoming damage")

	var bag := StatusBag.new()
	bag.apply(LegInjuryStatus.ID, 1, 1)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 4, "registry routes through leg injury")
	t.check_eq(StatusRegistry.display_name(LegInjuryStatus.ID), "Leg Injury",
		"leg injury's display name is the keyword the cards print")

## Every registered status carries a description -- it is what the on-hover
## tooltip shows, so an empty one would render an unexplained keyword.
## Derived from BattleConfig, not written as a literal, so a balance change
## cannot leave the tooltip quietly lying.
func _test_status_descriptions(t: TestRunner) -> void:
	t.check(StatusRegistry.description(LegInjuryStatus.ID).contains("50%"),
		"leg injury's description states the reduction from config")
	t.check(not StatusRegistry.description(StrengthStatus.ID).is_empty(),
		"strength has a description too -- the tooltip works for every status")
	t.check_eq(StatusRegistry.description(&"unregistered_status"), "",
		"an unregistered id describes as empty rather than crashing")

	# Which number the fighter panel prints beside a status: leg injury is a
	# countdown (turns), strength a magnitude (stacks).
	t.check(StatusRegistry.shows_turns(LegInjuryStatus.ID),
		"leg injury displays its remaining turns")
	t.check(not StatusRegistry.shows_turns(StrengthStatus.ID),
		"strength displays its stacks")
	t.check(not StatusRegistry.shows_turns(&"unregistered_status"),
		"an unregistered id defaults to stacks rather than crashing")

func _test_strength_math(t: TestRunner) -> void:
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 0), 8, "0 strength leaves damage unchanged")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 2), 12, "2 strength turns 8 into 12")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 1), 10, "1 strength turns 8 into 10")
	# 9 * 1.25 = 11.25 -> floors to 11
	t.check_eq(StrengthStatus.modify_outgoing_damage(9, 1), 11, "strength bonus floors, never rounds up")
	t.check_eq(StrengthStatus.modify_incoming_damage(8, 2), 8, "strength does not change incoming damage")

func _test_registry_dispatch(t: TestRunner) -> void:
	var bag := StatusBag.new()
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 8, "empty bag applies no modifiers")

	bag.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "registry routes through strength")
	t.check_eq(StatusRegistry.modify_incoming(bag, 8), 8, "registry incoming is pass-through for strength")
	t.check_eq(StatusRegistry.display_name(StrengthStatus.ID), "STR", "registry exposes display names")

	bag.apply(&"unregistered_status", 5, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "unregistered status is ignored, not crashing")

## The third mandatory status static: on_turn_start(fighter, stacks) -> bool,
## called for every active status at its owner's turn start (after guard
## expiry); returning true consumes the status. Prepared pays its stacks out
## as guard exactly once; the damage-modifier statuses pass through.
func _test_turn_start_hook(t: TestRunner) -> void:
	var fighter := Fighter.new("A", 50)
	fighter.statuses.apply(PreparedStatus.ID, 4, BattleConfig.PREPARED_STATUS_TURNS)
	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.guard, 4, "prepared paid its stacks out as guard")
	t.check(not fighter.statuses.has(PreparedStatus.ID), "prepared consumed itself")

	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.guard, 4, "a second turn start pays nothing more")

	# Pass-through statuses survive the hook untouched.
	var buffed := Fighter.new("B", 50)
	buffed.statuses.apply(&"strength", 2, 2)
	buffed.statuses.apply(&"leg_injury", 1, 1)
	StatusRegistry.apply_turn_start(buffed)
	t.check(buffed.statuses.has(&"strength"), "strength is not consumed by turn start")
	t.check(buffed.statuses.has(&"leg_injury"), "leg injury is not consumed by turn start")
	t.check_eq(buffed.guard, 0, "pass-through statuses grant nothing")

	# Registry metadata for the new status.
	t.check_eq(StatusRegistry.display_name(PreparedStatus.ID), "Prepared", "display name registered")
	t.check(not StatusRegistry.shows_turns(PreparedStatus.ID),
		"prepared shows its magnitude (the pending guard), not a countdown")
	t.check(StatusRegistry.description(PreparedStatus.ID).length() > 0, "prepared describes itself")
