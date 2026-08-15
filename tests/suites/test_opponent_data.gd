extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_attack_move_previews_through_the_pipeline(t)
	_test_guard_move_prints_its_amount(t)
	_test_buff_move_prints_stacks_and_keyword(t)
	_test_multi_effect_move_telegraphs_its_damage(t)
	_test_opponent_data_holds_its_rotation(t)

func _attack_move(amount: int) -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = amount
	var effects: Array[CardEffect] = [damage]
	return OpponentMove.new("ATTACK", effects)

func _test_attack_move_previews_through_the_pipeline(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var move := _attack_move(8)
	t.check_eq(move.intent_text(enemy, player), "ATTACK 8", "an unbuffed attack move telegraphs its base damage")

	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(move.intent_text(enemy, player), "ATTACK 12", "a buffed attack move previews through the live damage pipeline")

func _test_guard_move_prints_its_amount(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var guard := GuardEffect.new()
	guard.amount = 8
	var effects: Array[CardEffect] = [guard]
	var move := OpponentMove.new("BLOCK", effects)
	t.check_eq(move.intent_text(enemy, player), "BLOCK 8", "a guard move telegraphs its static amount")

func _test_buff_move_prints_stacks_and_keyword(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = 2
	buff.turns = 2
	buff.target_self = true
	var effects: Array[CardEffect] = [buff]
	var move := OpponentMove.new("BUFF", effects)
	t.check_eq(move.intent_text(enemy, player), "BUFF +2 STR", "a buff move telegraphs stacks and the status keyword")

func _test_multi_effect_move_telegraphs_its_damage(t: TestRunner) -> void:
	# Shaped like the kickboxer's leg kick: damage plus a debuff on the target.
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var damage := DamageEffect.new()
	damage.amount = 5
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = 1
	injury.target_self = false
	var effects: Array[CardEffect] = [damage, injury]
	var move := OpponentMove.new("LEG KICK", effects)
	t.check_eq(move.intent_text(enemy, player), "LEG KICK 5", "a damage-plus-debuff move telegraphs label and damage")

func _test_opponent_data_holds_its_rotation(t: TestRunner) -> void:
	var turn_one: Array = [_attack_move(8)]
	var turn_two: Array = [_attack_move(8), _attack_move(8)]
	var rotation: Array[Array] = [turn_one, turn_two]
	var opponent := OpponentData.new(&"test_dummy", "Test Dummy", 40, rotation)
	t.check_eq(opponent.id, &"test_dummy", "OpponentData keeps its id")
	t.check_eq(opponent.display_name, "Test Dummy", "OpponentData keeps its display name")
	t.check_eq(opponent.max_hp, 40, "OpponentData keeps its max hp")
	t.check_eq(opponent.rotation.size(), 2, "OpponentData keeps its rotation")
	t.check_eq((opponent.rotation[1] as Array).size(), 2, "a rotation turn can hold multiple moves")
