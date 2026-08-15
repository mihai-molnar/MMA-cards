extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_combo_integration(t)
	_test_combo_broken(t)
	_test_combo_history_clears_across_turns(t)
	_test_buff_timing_across_turns(t)
	_test_low_kick_weakens_the_telegraphed_attack(t)
	_test_low_kicks_stack_duration(t)
	_test_win(t)
	_test_loss(t)
	_test_no_intent_after_fatal_enemy_attack(t)

func _new_battle() -> BattleState:
	var battle := BattleState.new(12345)
	battle.start()
	return battle

func _stack_hand(battle: BattleState, ids: Array) -> void:
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand

## Low Kick is the whole debuff loop in one card: chip damage, a status on
## the OPPONENT, a telegraph that must update in real time (preview_damage's
## own doc: the telegraph must never diverge from what resolve_damage would
## produce -- an "ATTACK 8" on screen while the real hit is 4 is exactly
## that lie), and an expiry after exactly one weakened attack.
func _test_low_kick_weakens_the_telegraphed_attack(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"low_kick"])

	# The enemy's first action in the cycle is ATTACK, telegraphed at full 8.
	t.check_eq(battle.brain.intent_text(battle.enemy, battle.player), "ATTACK 8",
		"before the kick the telegraph shows the full attack")

	var intents: Array[String] = []
	battle.intent_changed.connect(func(text: String) -> void: intents.append(text))
	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 46, "the low kick itself deals 2")
	t.check_eq(battle.ap, BattleConfig.AP_PER_TURN, "a 0-cost card spends no AP")
	t.check(battle.enemy.statuses.has(&"leg_injury"), "the enemy is leg-injured")
	t.check(intents.size() >= 1, "playing a card re-emits the intent")
	t.check_eq(intents.back(), "ATTACK 4", "the telegraph halves in real time (8 -> 4)")

	var hp_before: int = battle.player.hp
	battle.end_turn()
	t.check_eq(hp_before - battle.player.hp, 4,
		"the injured enemy attack lands for 4 instead of 8")
	t.check(not battle.enemy.statuses.has(&"leg_injury"),
		"the injury expires at the enemy's own turn end -- exactly one weakened attack")

## Each additional kick keeps the leg hurt one enemy turn longer -- the
## duration EXTENDS; the injury itself never deepens (stacks stay 1, the
## halving is not multiplied).
func _test_low_kicks_stack_duration(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"low_kick", &"low_kick"])

	battle.play_card(0)
	battle.play_card(0)
	t.check_eq(battle.enemy.statuses.get_turns(&"leg_injury"), 2,
		"two kicks extend the injury to 2 turns")
	t.check_eq(battle.enemy.statuses.get_stacks(&"leg_injury"), 1,
		"the injury never deepens, only lengthens")

	battle.end_turn()
	t.check_eq(battle.enemy.statuses.get_turns(&"leg_injury"), 1,
		"one enemy turn later a turn remains")
	battle.end_turn()
	t.check(not battle.enemy.statuses.has(&"leg_injury"),
		"the extended injury expires after the second enemy turn")

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

## A jab played on one turn must not be able to arm a straight's combo bonus
## on a later turn — only battle_state.gd's _play_history.clear() in
## _begin_player_turn() prevents that.
func _test_combo_history_clears_across_turns(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"jab"])
	battle.play_card(0)   # jab played on turn 1

	battle.end_turn()   # advance to turn 2; history should clear
	_stack_hand(battle, [&"straight"])
	t.check_eq(battle.combo_bonus_for(0), 0, "a jab from last turn cannot arm this turn's straight")

	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 48 - 6 - 9, "the cross-turn straight deals its plain 9, no combo bonus")

func _test_buff_timing_across_turns(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Brawler cycle: 1 ATTACK, 2 ATTACK+BLOCK, 3 BLOCK+BUFF, then wraps.
	battle.end_turn()   # ATTACK 8
	t.check_eq(battle.player.hp, 42, "the brawler's opening attack deals 8")

	battle.end_turn()   # ATTACK 8 + BLOCK 8
	t.check_eq(battle.player.hp, 34, "the second turn's attack also lands for 8")
	t.check_eq(battle.enemy.guard, 8, "the second turn also raises 8 guard")

	battle.end_turn()   # BLOCK 8 + BUFF +2 STR
	t.check_eq(battle.player.hp, 34, "the block-and-buff turn deals no damage")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the brawler holds 2 strength after buffing")
	t.check_eq(battle.brain.intent_text(battle.enemy, battle.player), "ATTACK 12", "the telegraph warns of a 12 damage attack")

	battle.end_turn()   # ATTACK, buffed: 12
	t.check_eq(battle.player.hp, 22, "the buffed attack deals 12")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 0, "strength expires after the attack it paid for")

	battle.end_turn()   # ATTACK 8 + BLOCK, unbuffed again
	t.check_eq(battle.player.hp, 14, "the following attack is back to a plain 8")

	battle.end_turn()   # BLOCK + BUFF
	battle.end_turn()   # ATTACK, buffed again
	t.check_eq(battle.player.hp, 2, "the next cycle's buffed attack also deals 12")

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

func _test_no_intent_after_fatal_enemy_attack(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Arrays, not plain bools: lambda captures of outer locals in GDScript are
	# by value, so a mutable container is needed for the closures below to
	# actually record what happened.
	var battle_over_fired: Array = []
	var intents_after_over: Array = []
	battle.battle_over.connect(func(_player_won: bool) -> void: battle_over_fired.append(true))
	battle.intent_changed.connect(func(text: String) -> void:
		if not battle_over_fired.is_empty():
			intents_after_over.append(text)
	)

	battle.player.hp = 5
	battle.end_turn()   # enemy attacks for 8, a fatal blow

	t.check(battle.is_over, "the battle ends on the fatal enemy attack")
	t.check_eq(battle_over_fired.size(), 1, "battle_over fires once on the fatal attack")
	t.check_eq(intents_after_over.size(), 0, "no intent_changed fires after battle_over on a fatal enemy attack")
