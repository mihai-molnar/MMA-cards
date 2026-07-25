extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cycle_order(t)
	_test_effects(t)
	_test_intent_text(t)
	_test_reset(t)

func _test_cycle_order(t: TestRunner) -> void:
	var brain := EnemyBrain.new()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "the enemy opens by attacking")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.BLOCK, "attack is followed by block")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.BUFF, "block is followed by buff")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "the cycle wraps back to attack")

func _test_effects(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}

	var brain := EnemyBrain.new()
	# ATTACK
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, 42, "the enemy attack deals 8")

	# BLOCK
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.guard, 8, "the enemy block grants 8 guard")

	# BUFF
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the enemy buff grants 2 strength")

	# The buffed attack, one cycle later.
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, 42 - 12, "the attack after a buff deals 12")

func _test_intent_text(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var brain := EnemyBrain.new()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8", "unbuffed attack telegraphs 8")

	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 12", "a buffed attack telegraphs its real damage")

	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "BLOCK 8", "block intent shows the guard amount")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "BUFF +2 STR", "buff intent shows the strength gain")

func _test_reset(t: TestRunner) -> void:
	var brain := EnemyBrain.new()
	brain.advance()
	brain.advance()
	brain.reset()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "reset returns to the start of the cycle")
