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
	_test_guard_break_bonus_effect(t)

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

## The One-Two mechanic: reads the LAST DamageResult in context["results"];
## a break resolves a second full hit through the same pipeline. No result
## or no break means no bonus hit (fail closed).
func _test_guard_break_bonus_effect(t: TestRunner) -> void:
	var source := Fighter.new("A", 50)
	var effect := GuardBreakBonusEffect.new()
	effect.amount = 5

	# No preceding result at all: nothing happens.
	var empty_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var untouched := Fighter.new("B", 50)
	effect.apply(source, untouched, empty_context)
	t.check_eq(untouched.hp, 50, "no preceding result means no bonus hit")
	t.check_eq((empty_context["results"] as Array).size(), 0, "and no result appended")

	# First hit breaks guard exactly: the bonus hit lands on hp.
	var broken := Fighter.new("B", 50)
	broken.add_guard(5)
	var break_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var first := DamageEffect.new()
	first.amount = 5
	first.apply(source, broken, break_context)
	effect.apply(source, broken, break_context)
	t.check_eq(broken.hp, 45, "the bonus hit landed for its full 5")
	t.check_eq((break_context["results"] as Array).size(), 2, "both hits recorded results")

	# First hit leaves guard standing: one hit only.
	var guarded := Fighter.new("B", 50)
	guarded.add_guard(8)
	var held_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	first.apply(source, guarded, held_context)
	effect.apply(source, guarded, held_context)
	t.check_eq(guarded.hp, 50, "guard held; no bonus hit")
	t.check_eq(guarded.guard, 3, "only the first hit chipped it")

	# Strength boosts BOTH hits -- each resolves through the full pipeline.
	var strong := Fighter.new("A", 50)
	strong.statuses.apply(&"strength", 2, BattleConfig.STATUS_PERMANENT)
	var victim := Fighter.new("B", 50)
	victim.add_guard(7)  # floori(5 * 1.5) = 7 breaks it exactly
	var strong_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	first.apply(strong, victim, strong_context)
	effect.apply(strong, victim, strong_context)
	t.check_eq(victim.hp, 43, "the boosted bonus hit landed for 7")
