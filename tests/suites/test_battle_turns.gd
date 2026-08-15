extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_start(t)
	_test_turn_counter(t)
	_test_ap(t)
	_test_player_guard_timing(t)
	_test_enemy_guard_timing(t)
	_test_restart_resets_full_state(t)

func _new_battle() -> BattleState:
	var battle := BattleState.new(12345)
	battle.start()
	return battle

func _test_start(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	t.check_eq(battle.turn_number, 1, "the player's first turn is turn 1")
	t.check_eq(battle.player.hp, 50, "player starts at 50 hp")
	t.check_eq(battle.enemy.hp, 48, "enemy starts at 48 hp")
	t.check_eq(battle.ap, 3, "the player starts with 3 AP")
	t.check_eq(battle.deck.hand.size(), 5, "the opening hand holds 5 cards")
	t.check(not battle.is_over, "the battle is not over at the start")

func _test_turn_counter(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()
	t.check_eq(battle.turn_number, 2, "ending a turn advances the counter once, not twice")
	battle.end_turn()
	battle.end_turn()
	t.check_eq(battle.turn_number, 4, "the counter advances once per full round")

	battle.restart()
	t.check_eq(battle.turn_number, 1, "restart returns to turn 1")

func _test_ap(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Stack a known hand: two straights (2 AP each) and a jab.
	battle.deck.hand = [
		CardLibrary.load_card(&"straight"),
		CardLibrary.load_card(&"straight"),
		CardLibrary.load_card(&"jab"),
	] as Array[CardData]

	t.check(battle.can_play(0), "a 2 AP straight is playable with 3 AP")
	t.check(battle.play_card(0), "playing the straight succeeds")
	t.check_eq(battle.ap, 1, "AP drops from 3 to 1")

	t.check(not battle.can_play(0), "the second straight is unaffordable with 1 AP")
	t.check(not battle.play_card(0), "playing an unaffordable card is refused")
	t.check_eq(battle.ap, 1, "a refused play does not spend AP")

	t.check(battle.play_card(1), "the 1 AP jab is still playable")
	t.check_eq(battle.ap, 0, "AP reaches 0 and never goes negative")

	battle.end_turn()
	t.check_eq(battle.ap, 3, "AP resets to 3 at the start of the next turn")
	t.check_eq(battle.deck.hand.size(), 5, "a fresh hand of 5 is drawn")

func _test_player_guard_timing(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.deck.hand = [CardLibrary.load_card(&"block")] as Array[CardData]
	battle.play_card(0)
	t.check_eq(battle.player.guard, 5, "block grants the player 5 guard")

	battle.end_turn()
	# Guard must have survived the enemy turn and then cleared at the start of
	# the player's new turn. The enemy's opening attack is 8, so 3 gets through.
	t.check_eq(battle.player.hp, 47, "player guard absorbed 5 of the enemy's 8 damage")
	t.check_eq(battle.player.guard, 0, "guard clears at the start of the player's next turn")

func _test_enemy_guard_timing(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()   # brawler turn 1: ATTACK
	battle.end_turn()   # brawler turn 2: ATTACK + BLOCK -> gains 8 guard
	t.check_eq(battle.enemy.guard, 8, "the enemy has guard up during the player's turn")

	battle.deck.hand = [CardLibrary.load_card(&"jab")] as Array[CardData]
	battle.play_card(0)
	t.check_eq(battle.enemy.guard, 2, "the enemy's guard absorbs the jab")
	t.check_eq(battle.enemy.hp, 48, "the enemy takes no hp damage behind guard")

	battle.end_turn()   # brawler turn 3: BLOCK + BUFF
	# 8, not 10: the leftover 2 guard expired at the enemy's own turn start
	# (guard never survives into its owner's next turn) before turn 3's
	# fresh block landed. 10 here would mean expiry silently stopped.
	t.check_eq(battle.enemy.guard, 8, "expiry cleared the leftover guard before the fresh block landed")

## restart() touches two Fighters, the Deck, the EnemyBrain, and is_over —
## _test_turn_counter above only ever checked turn_number. Drive every one
## of those away from its start value, then confirm restart() puts all of
## them back.
func _test_restart_resets_full_state(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()   # brawler turn 1: ATTACK
	battle.end_turn()   # brawler turn 2: ATTACK + BLOCK

	t.check(battle.turn_number > 1, "several turns passed before restart")
	t.check_eq(battle.brain.rotation_index(), 2, "the enemy brain advanced past its opening turn before restart")

	# Push both fighters into a damaged, guarded, buffed state right before
	# restarting, so restart() is what has to undo it, not natural expiry.
	battle.player.apply_hp_loss(20)
	battle.enemy.apply_hp_loss(20)
	battle.player.add_guard(5)
	battle.enemy.add_guard(5)
	battle.player.statuses.apply(StrengthStatus.ID, 2, 2)
	battle.enemy.statuses.apply(StrengthStatus.ID, 2, 2)

	t.check(battle.player.hp < battle.player.max_hp, "player took damage before restart")
	t.check(battle.enemy.hp < battle.enemy.max_hp, "enemy took damage before restart")

	battle.restart()

	t.check_eq(battle.player.hp, battle.player.max_hp, "restart returns the player to full hp")
	t.check_eq(battle.enemy.hp, battle.enemy.max_hp, "restart returns the enemy to full hp")
	t.check_eq(battle.player.guard, 0, "restart clears the player's guard")
	t.check_eq(battle.enemy.guard, 0, "restart clears the enemy's guard")
	t.check_eq(battle.player.statuses.get_stacks(StrengthStatus.ID), 0, "restart clears the player's statuses")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 0, "restart clears the enemy's statuses")
	t.check_eq(battle.ap, BattleConfig.AP_PER_TURN, "restart resets AP to 3")
	t.check_eq(battle.deck.hand.size(), BattleConfig.HAND_SIZE, "restart deals a fresh hand of 5")
	t.check_eq(battle.deck.total_cards(), 14, "restart preserves the 14-card deck total")
	t.check_eq(battle.brain.rotation_index(), 0, "restart returns the enemy brain to the top of its rotation")
	t.check(not battle.is_over, "restart clears is_over")
	t.check_eq(battle.turn_number, 1, "restart returns to turn 1")
