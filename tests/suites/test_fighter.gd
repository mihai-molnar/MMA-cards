extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_state(t)
	_test_guard(t)
	_test_hp_loss(t)
	_test_reset(t)

func _test_initial_state(t: TestRunner) -> void:
	var f := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	t.check_eq(f.display_name, "Player", "fighter keeps its display name")
	t.check_eq(f.hp, 50, "fighter starts at full hp")
	t.check_eq(f.max_hp, 50, "fighter records its max hp")
	t.check_eq(f.guard, 0, "fighter starts with no guard")
	t.check(f.is_alive(), "fighter starts alive")

func _test_guard(t: TestRunner) -> void:
	var f := Fighter.new("Player", 50)
	f.add_guard(5)
	t.check_eq(f.guard, 5, "add_guard raises guard")
	f.add_guard(5)
	t.check_eq(f.guard, 10, "guard from two blocks accumulates")
	t.check_eq(f.absorb_into_guard(4), 4, "absorb returns the amount taken by guard")
	t.check_eq(f.guard, 6, "absorbed damage reduces guard")
	t.check_eq(f.absorb_into_guard(99), 6, "absorb is capped at remaining guard")
	t.check_eq(f.guard, 0, "guard bottoms out at 0")
	f.add_guard(8)
	f.expire_guard()
	t.check_eq(f.guard, 0, "expire_guard clears guard")

func _test_hp_loss(t: TestRunner) -> void:
	var f := Fighter.new("Enemy", 48)
	t.check_eq(f.apply_hp_loss(6), 6, "apply_hp_loss returns hp actually lost")
	t.check_eq(f.hp, 42, "hp drops by the loss")
	t.check(f.is_alive(), "fighter above 0 hp is alive")
	t.check_eq(f.apply_hp_loss(999), 42, "overkill only reports the hp that existed")
	t.check_eq(f.hp, 0, "hp floors at 0, never negative")
	t.check(not f.is_alive(), "fighter at 0 hp is not alive")

func _test_reset(t: TestRunner) -> void:
	var f := Fighter.new("Player", 50)
	f.apply_hp_loss(20)
	f.add_guard(5)
	f.statuses.apply(StrengthStatus.ID, 2, 2)
	f.reset()
	t.check_eq(f.hp, 50, "reset restores full hp")
	t.check_eq(f.guard, 0, "reset clears guard")
	t.check_eq(f.statuses.get_stacks(StrengthStatus.ID), 0, "reset clears statuses")
