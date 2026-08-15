extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_damage_effect(t)
	_test_bonus_consumed_once(t)
	_test_guard_effect(t)
	_test_apply_status_effect(t)
	_test_require_hp_damage_blocks_on_full_block(t)
	_test_require_hp_damage_applies_on_partial_block(t)
	_test_require_hp_damage_blocks_with_no_preceding_result(t)
	_test_card_data(t)

func _new_context(bonus: int) -> Dictionary:
	return {"bonus_damage": bonus, "results": [], "log": []}

func _test_damage_effect(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := DamageEffect.new()
	effect.amount = 6
	var context: Dictionary = _new_context(0)
	effect.apply(player, enemy, context)
	t.check_eq(enemy.hp, 42, "damage effect routes through the pipeline")
	t.check_eq(context["results"].size(), 1, "damage effect records its result")

func _test_bonus_consumed_once(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := DamageEffect.new()
	effect.amount = 9
	var context: Dictionary = _new_context(7)
	effect.apply(player, enemy, context)
	t.check_eq(enemy.hp, 48 - 16, "combo bonus is added to the straight's damage")
	t.check_eq(context["bonus_damage"], 0, "bonus is consumed so a second hit cannot reuse it")

	# A second damage effect in the same play gets no bonus.
	var effect2 := DamageEffect.new()
	effect2.amount = 9
	effect2.apply(player, enemy, context)
	t.check_eq(enemy.hp, 48 - 16 - 9, "a second hit deals plain damage")

func _test_guard_effect(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := GuardEffect.new()
	effect.amount = 5
	effect.apply(player, enemy, _new_context(0))
	t.check_eq(player.guard, 5, "guard effect protects the source")
	t.check_eq(enemy.guard, 0, "guard effect does not touch the target")

func _test_apply_status_effect(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var effect := ApplyStatusEffect.new()
	effect.status_id = StrengthStatus.ID
	effect.stacks = 2
	effect.turns = 2
	effect.target_self = true
	effect.apply(enemy, player, _new_context(0))
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "self-targeted status lands on the source")
	t.check_eq(player.statuses.get_stacks(StrengthStatus.ID), 0, "self-targeted status spares the target")
	t.check_eq(effect.describe(), "Gain 2 STR.", "a self-targeted status describes itself as a gain")

	var opponent_effect := ApplyStatusEffect.new()
	opponent_effect.status_id = StrengthStatus.ID
	opponent_effect.stacks = 2
	opponent_effect.turns = 2
	opponent_effect.target_self = false
	t.check_eq(opponent_effect.describe(), "Apply 2 STR.", "a target-directed status describes itself as an apply")

## A fully-blocked kick lands no hp damage, so require_hp_damage must fail
## the status closed: a kicked-but-guarded fighter's leg never gets hurt.
func _test_require_hp_damage_blocks_on_full_block(t: TestRunner) -> void:
	var kicker := Fighter.new("Kicker", 50)
	var blocker := Fighter.new("Blocker", 48)
	var context: Dictionary = _new_context(0)
	context["results"].append(Combat.DamageResult.new(5, 5, 0))

	var effect := ApplyStatusEffect.new()
	effect.status_id = LegInjuryStatus.ID
	effect.stacks = 1
	effect.turns = 1
	effect.target_self = false
	effect.require_hp_damage = true
	effect.apply(kicker, blocker, context)

	t.check(not blocker.statuses.has(LegInjuryStatus.ID),
		"a fully blocked kick applies no injury")
	t.check(context["log"].back().contains("blocks the"),
		"a blocked application logs that the status was blocked")

## A partial block still lets some hp damage through, so the status must
## still land.
func _test_require_hp_damage_applies_on_partial_block(t: TestRunner) -> void:
	var kicker := Fighter.new("Kicker", 50)
	var blocker := Fighter.new("Blocker", 48)
	var context: Dictionary = _new_context(0)
	context["results"].append(Combat.DamageResult.new(5, 2, 3))

	var effect := ApplyStatusEffect.new()
	effect.status_id = LegInjuryStatus.ID
	effect.stacks = 1
	effect.turns = 1
	effect.target_self = false
	effect.require_hp_damage = true
	effect.apply(kicker, blocker, context)

	t.check(blocker.statuses.has(LegInjuryStatus.ID),
		"a partially blocked kick still lands the injury")

## No preceding DamageEffect result at all -- fail closed, same as a full
## block, rather than applying by default.
func _test_require_hp_damage_blocks_with_no_preceding_result(t: TestRunner) -> void:
	var kicker := Fighter.new("Kicker", 50)
	var blocker := Fighter.new("Blocker", 48)
	var context: Dictionary = _new_context(0)

	var effect := ApplyStatusEffect.new()
	effect.status_id = LegInjuryStatus.ID
	effect.stacks = 1
	effect.turns = 1
	effect.target_self = false
	effect.require_hp_damage = true
	effect.apply(kicker, blocker, context)

	t.check(not blocker.statuses.has(LegInjuryStatus.ID),
		"an empty results list fails closed -- no application")

func _test_card_data(t: TestRunner) -> void:
	var card := CardData.new()
	card.id = &"straight"
	card.display_name = "STRAIGHT"
	card.cost = 2
	card.tags = [&"straight"] as Array[StringName]
	var effect := DamageEffect.new()
	effect.amount = 9
	card.effects = [effect] as Array[CardEffect]
	t.check_eq(card.total_base_damage(), 9, "total_base_damage sums damage effects")

	var blocker := CardData.new()
	blocker.id = &"block"
	var guard := GuardEffect.new()
	guard.amount = 5
	blocker.effects = [guard] as Array[CardEffect]
	t.check_eq(blocker.total_base_damage(), 0, "a card with no damage effects reports 0")
