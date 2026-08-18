extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_bleed_ticks_at_turn_start(t)
	_test_bleed_ignores_guard(t)
	_test_bleed_expires(t)
	_test_bleed_can_finish_the_enemy_before_it_acts(t)
	_test_chance_gated_application(t)
	_test_registry_metadata(t)

func _bleeding_fighter(hp: int) -> Fighter:
	var fighter := Fighter.new("Dummy", hp)
	fighter.statuses.apply(&"bleed", 1, BattleConfig.BLEED_TURNS, true)
	return fighter

func _test_bleed_ticks_at_turn_start(t: TestRunner) -> void:
	var fighter := _bleeding_fighter(30)
	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.hp, 30 - BattleConfig.BLEED_DAMAGE_PER_TURN,
		"bleed deals BLEED_DAMAGE_PER_TURN at turn start")
	t.check(fighter.statuses.get_stacks(&"bleed") > 0,
		"the tick does not consume the status")

func _test_bleed_ignores_guard(t: TestRunner) -> void:
	var fighter := _bleeding_fighter(30)
	fighter.add_guard(10)
	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.hp, 30 - BattleConfig.BLEED_DAMAGE_PER_TURN,
		"bleed goes straight to hp")
	t.check_eq(fighter.guard, 10, "guard absorbs none of it")

func _test_bleed_expires(t: TestRunner) -> void:
	var fighter := _bleeding_fighter(30)
	for _i: int in range(BattleConfig.BLEED_TURNS):
		fighter.tick_statuses_turn_end()
	t.check_eq(fighter.statuses.get_stacks(&"bleed"), 0,
		"bleed ends after BLEED_TURNS turn-end ticks")

func _test_bleed_can_finish_the_enemy_before_it_acts(t: TestRunner) -> void:
	var battle := BattleState.new(42)
	battle.start()
	battle.enemy.hp = 1
	battle.enemy.statuses.apply(&"bleed", 1, BattleConfig.BLEED_TURNS, true)
	var overs: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: overs.append(player_won))
	var player_hp_before: int = battle.player.hp
	battle.end_turn()
	t.check_eq(overs, [true], "the enemy bleeds out at its turn start and loses")
	t.check_eq(battle.player.hp, player_hp_before,
		"the dead enemy never got its attack")

func _test_chance_gated_application(t: TestRunner) -> void:
	for certain: bool in [true, false]:
		var battle := BattleState.new(9)
		battle.start()
		var card := CardData.new()
		card.id = &"test_bleeder"
		card.display_name = "TEST"
		var hit := DamageEffect.new()
		hit.amount = 3
		var bleed := ApplyStatusEffect.new()
		bleed.status_id = &"bleed"
		bleed.stacks = 1
		bleed.turns = BattleConfig.BLEED_TURNS
		bleed.target_self = false
		bleed.extend_duration = true
		bleed.require_hp_damage = true
		bleed.chance = 1.0 if certain else 0.0
		card.effects = [hit, bleed] as Array[CardEffect]
		battle.dev_play(card)
		if certain:
			t.check(battle.enemy.statuses.get_stacks(&"bleed") > 0,
				"chance 1.0 always applies")
		else:
			t.check_eq(battle.enemy.statuses.get_stacks(&"bleed"), 0,
				"chance 0.0 never applies")

func _test_registry_metadata(t: TestRunner) -> void:
	t.check_eq(StatusRegistry.display_name(&"bleed"), "Bleed", "Bleed registers its name")
	t.check(StatusRegistry.shows_turns(&"bleed"), "the chip counts down turns")
	t.check(StatusRegistry.description(&"bleed").contains(str(BattleConfig.BLEED_DAMAGE_PER_TURN)),
		"the tooltip derives its number from BattleConfig")
