extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_fresh_run(t)
	_test_victory_advances_and_carries_hp(t)
	_test_defeat_holds_position(t)
	_test_completion(t)
	_test_reset(t)
	_test_hp_carries_into_the_next_battle(t)

func _test_fresh_run(t: TestRunner) -> void:
	var run := RunState.new()
	t.check_eq(run.fight_number(), 1, "a fresh run starts at fight 1")
	t.check_eq(run.player_hp, BattleConfig.PLAYER_MAX_HP, "a fresh run starts at full hp")
	t.check_eq(run.current_opponent().id, &"brawler", "fight 1 is the brawler")
	t.check(not run.is_complete(), "a fresh run is not complete")

func _test_victory_advances_and_carries_hp(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 33)
	t.check_eq(run.fight_number(), 2, "a win advances to the next fight")
	t.check_eq(run.player_hp, 33, "the winner's remaining hp carries forward")
	t.check_eq(run.current_opponent().id, &"kickboxer", "fight 2 is the kickboxer")
	t.check(not run.is_complete(), "the run continues after fight 1")

func _test_defeat_holds_position(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(false, 0)
	t.check_eq(run.fight_number(), 1, "a loss does not advance the run")
	t.check(not run.is_complete(), "a lost run is not complete -- it restarts instead")

func _test_completion(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 20)
	run.record_result(true, 11)
	t.check(run.is_complete(), "beating every opponent completes the run")
	t.check_eq(run.current_opponent(), null, "a complete run has no next opponent")

func _test_reset(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 20)
	run.reset()
	t.check_eq(run.fight_number(), 1, "reset returns to fight 1")
	t.check_eq(run.player_hp, BattleConfig.PLAYER_MAX_HP, "reset restores full hp")

func _test_hp_carries_into_the_next_battle(t: TestRunner) -> void:
	var run := RunState.new()
	var first := BattleState.new(12345, run.current_opponent(), run.player_hp)
	first.start()
	first.player.apply_hp_loss(17)
	first.enemy.hp = 1
	first.deck.hand = [CardLibrary.load_card(&"jab")] as Array[CardData]
	first.play_card(0)
	t.check(first.is_over, "the finishing jab ends fight 1")

	run.record_result(true, first.player.hp)
	var second := BattleState.new(12345, run.current_opponent(), run.player_hp)
	second.start()
	t.check_eq(second.player.hp, 33, "fight 2 starts at the carried 33 hp")
	t.check_eq(second.player.max_hp, BattleConfig.PLAYER_MAX_HP, "max hp is unchanged")
	t.check_eq(second.enemy.display_name, "Kickboxer", "fight 2 faces the kickboxer")
	t.check_eq(second.player.guard, 0, "no guard carries between fights")
	t.check_eq(second.player.statuses.get_stacks(StrengthStatus.ID), 0, "no statuses carry between fights")
	t.check_eq(second.deck.total_cards(), 14, "the deck is rebuilt fresh")
	t.check_eq(second.deck.hand.size(), BattleConfig.HAND_SIZE, "a fresh opening hand is drawn")
