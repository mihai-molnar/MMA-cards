extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_brawler_cycle_intents(t)
	_test_multi_move_turn_applies_every_effect(t)
	_test_buffed_attack_previews_real_damage(t)
	_test_reset(t)

func _new_brawler_brain() -> EnemyBrain:
	return EnemyBrain.new(OpponentLibrary.opponent(&"brawler"))

func _test_brawler_cycle_intents(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var brain := _new_brawler_brain()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8", "the brawler opens by attacking")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8 + BLOCK 8", "turn two attacks behind a block")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "BLOCK 8 + BUFF +2 STR", "turn three blocks and buffs")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8", "the cycle wraps back to the opening attack")

func _test_multi_move_turn_applies_every_effect(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var brain := _new_brawler_brain()
	brain.advance()   # ATTACK + BLOCK
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, BattleConfig.PLAYER_MAX_HP - 8, "the attack half of the turn lands for 8")
	t.check_eq(enemy.guard, 8, "the block half of the same turn raises 8 guard")

	brain.advance()   # BLOCK + BUFF
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.guard, 16, "the third turn stacks another 8 guard")
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the third turn also grants 2 strength")

func _test_buffed_attack_previews_real_damage(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var brain := _new_brawler_brain()
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 12", "a buffed attack telegraphs its real damage")

func _test_reset(t: TestRunner) -> void:
	var brain := _new_brawler_brain()
	brain.advance()
	brain.advance()
	t.check_eq(brain.rotation_index(), 2, "advance walks the rotation")
	brain.reset()
	t.check_eq(brain.rotation_index(), 0, "reset returns to the top of the rotation")
