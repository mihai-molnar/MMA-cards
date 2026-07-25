extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_combo_integration(t)
	_test_combo_broken(t)
	_test_buff_timing_across_turns(t)
	_test_win(t)
	_test_loss(t)

func _new_battle() -> BattleState:
	var battle := BattleState.new(12345)
	battle.start()
	return battle

func _stack_hand(battle: BattleState, ids: Array) -> void:
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand

func _test_combo_integration(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"jab", &"straight"])

	t.check_eq(battle.combo_bonus_for(1), 0, "a straight played first gets no bonus")
	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 42, "the jab deals 6")
	t.check_eq(battle.combo_bonus_for(0), 7, "the straight is now armed for a 7 bonus")

	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 26, "the combo straight deals 16, taking 48 to 26")
	t.check_eq(battle.ap, 0, "the combo consumed all 3 AP")

func _test_combo_broken(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"jab", &"block", &"straight"])
	battle.play_card(0)   # jab, 1 AP
	battle.play_card(0)   # block, 1 AP — breaks the chain
	t.check_eq(battle.combo_bonus_for(0), 0, "a block between jab and straight breaks the combo")
	battle.play_card(0)   # straight, 1 AP left... refused, costs 2
	t.check_eq(battle.enemy.hp, 42, "only the jab landed; the straight was unaffordable")

	# Verify the break directly with enough AP available.
	var battle2: BattleState = _new_battle()
	_stack_hand(battle2, [&"jab", &"block", &"straight"])
	battle2.ap = 10
	battle2.play_card(0)
	battle2.play_card(0)
	battle2.play_card(0)
	t.check_eq(battle2.enemy.hp, 48 - 6 - 9, "the broken-combo straight deals a plain 9")

func _test_buff_timing_across_turns(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Enemy cycle: turn 1 attack, turn 2 block, turn 3 buff, turn 4 attack.
	battle.end_turn()   # enemy attacks for 8
	t.check_eq(battle.player.hp, 42, "the enemy's opening attack deals 8")

	battle.end_turn()   # enemy blocks
	t.check_eq(battle.player.hp, 42, "a blocking enemy deals no damage")

	battle.end_turn()   # enemy buffs
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the enemy holds 2 strength after buffing")
	t.check_eq(battle.brain.intent_text(battle.enemy), "ATTACK 12", "the telegraph warns of a 12 damage attack")

	battle.end_turn()   # enemy attacks, buffed
	t.check_eq(battle.player.hp, 30, "the buffed attack deals 12")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 0, "strength expires after the attack it paid for")

	battle.end_turn()   # enemy blocks
	battle.end_turn()   # enemy buffs
	battle.end_turn()   # enemy attacks buffed again
	t.check_eq(battle.player.hp, 30 - 12, "the next cycle's buffed attack also deals 12")

func _test_win(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	var won: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: won.append(player_won))

	battle.enemy.hp = 6
	_stack_hand(battle, [&"jab"])
	battle.play_card(0)

	t.check_eq(battle.enemy.hp, 0, "the finishing blow drops the enemy to exactly 0")
	t.check(battle.is_over, "the battle is marked over")
	t.check_eq(won.size(), 1, "battle_over fires exactly once")
	t.check_eq(won[0], true, "the player is reported as the winner")

	t.check(not battle.play_card(0), "cards cannot be played after the battle ends")

func _test_loss(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	var won: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: won.append(player_won))

	battle.player.hp = 5
	battle.end_turn()   # enemy attacks for 8

	t.check_eq(battle.player.hp, 0, "the player's hp floors at 0")
	t.check(battle.is_over, "the battle is marked over on a loss")
	t.check_eq(won.size(), 1, "battle_over fires exactly once on a loss")
	t.check_eq(won[0], false, "the player is reported as the loser")
