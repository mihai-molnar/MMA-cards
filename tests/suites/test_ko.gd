extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_certain_ko_ends_the_fight(t)
	_test_impossible_ko_emits_failed(t)
	_test_blocked_hit_never_rolls(t)
	_test_no_damage_never_rolls(t)
	_test_seeded_rolls_are_deterministic(t)
	_test_describe_prints_the_chance(t)
	_test_dev_play_ignores_ap_and_hand(t)
	_test_lethal_hit_failed_roll_stays_silent(t)

func _make_ko_card(damage: int, chance: float) -> CardData:
	var card := CardData.new()
	card.id = &"test_ko_card"
	card.display_name = "TEST KO"
	card.cost = 0
	card.tags = [&"attack"] as Array[StringName]
	var hit := DamageEffect.new()
	hit.amount = damage
	var ko := KOChanceEffect.new()
	ko.chance = chance
	card.effects = [hit, ko] as Array[CardEffect]
	return card

func _test_certain_ko_ends_the_fight(t: TestRunner) -> void:
	var battle := BattleState.new(1234)
	battle.start()
	var overs: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: overs.append(player_won))
	var scored: Array = []
	battle.ko_scored.connect(func() -> void: scored.append(true))
	battle.dev_play(_make_ko_card(3, 1.0))
	t.check(battle.is_over, "a certain KO ends the fight")
	t.check(battle.won_by_ko, "the win is recorded as a KO")
	t.check(battle.enemy.is_alive(), "the enemy still has hp -- the KO won, not the damage")
	t.check_eq(scored.size(), 1, "ko_scored emitted once")
	t.check_eq(overs, [true], "battle_over announces a player win")

func _test_impossible_ko_emits_failed(t: TestRunner) -> void:
	var battle := BattleState.new(1234)
	battle.start()
	var failed: Array = []
	battle.ko_failed.connect(func() -> void: failed.append(true))
	battle.dev_play(_make_ko_card(3, 0.0))
	t.check(not battle.is_over, "a failed KO leaves the fight running")
	t.check(not battle.won_by_ko, "no KO win recorded")
	t.check_eq(failed.size(), 1, "ko_failed emitted once")

func _test_blocked_hit_never_rolls(t: TestRunner) -> void:
	var battle := BattleState.new(1234)
	battle.start()
	battle.enemy.add_guard(50)
	var announced: Array = []
	battle.ko_failed.connect(func() -> void: announced.append(true))
	battle.ko_scored.connect(func() -> void: announced.append(true))
	battle.dev_play(_make_ko_card(3, 1.0))
	t.check(not battle.is_over, "a fully absorbed hit cannot KO even at 100%")
	t.check(announced.is_empty(), "no roll happened -- neither KO signal fired")

func _test_no_damage_never_rolls(t: TestRunner) -> void:
	var battle := BattleState.new(1234)
	battle.start()
	var card := CardData.new()
	card.id = &"test_ko_only"
	card.display_name = "TEST"
	var ko := KOChanceEffect.new()
	ko.chance = 1.0
	card.effects = [ko] as Array[CardEffect]
	var announced: Array = []
	battle.ko_failed.connect(func() -> void: announced.append(true))
	battle.ko_scored.connect(func() -> void: announced.append(true))
	battle.dev_play(card)
	t.check(not battle.is_over and announced.is_empty(),
		"a card with no damage result never rolls")

func _test_seeded_rolls_are_deterministic(t: TestRunner) -> void:
	var outcomes: Array = []
	for _i: int in range(2):
		var battle := BattleState.new(777)
		battle.start()
		battle.dev_play(_make_ko_card(3, 0.5))
		outcomes.append(battle.won_by_ko)
	t.check_eq(outcomes[0], outcomes[1], "same seed, same roll")

func _test_describe_prints_the_chance(t: TestRunner) -> void:
	var ko := KOChanceEffect.new()
	ko.chance = 0.3
	t.check_eq(ko.describe(), "30% chance to KO.", "describe derives the percentage")
	t.check(not KOChanceEffect.keyword_description().is_empty(),
		"the KO keyword has a tooltip body")

func _test_dev_play_ignores_ap_and_hand(t: TestRunner) -> void:
	var battle := BattleState.new(42)
	battle.start()
	var ap_before: int = battle.ap
	var hand_before: int = battle.deck.hand.size()
	var hp_before: int = battle.enemy.hp
	battle.dev_play(_make_ko_card(3, 0.0))
	t.check_eq(battle.ap, ap_before, "dev_play costs no AP")
	t.check_eq(battle.deck.hand.size(), hand_before, "dev_play touches no hand card")
	t.check(battle.enemy.hp < hp_before, "dev_play's effects are real")
	t.check_eq(battle.deck.total_cards(), 14, "the deck invariant is untouched")

func _test_lethal_hit_failed_roll_stays_silent(t: TestRunner) -> void:
	var battle := BattleState.new(1234)
	battle.start()
	battle.enemy.hp = 1
	var failed: Array = []
	battle.ko_failed.connect(func() -> void: failed.append(true))
	var overs: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: overs.append(player_won))
	battle.dev_play(_make_ko_card(3, 0.0))
	t.check(failed.is_empty(), "a failed roll on the killing blow announces nothing")
	t.check_eq(overs, [true], "the win is a plain win")
	t.check(not battle.won_by_ko, "and not recorded as a KO")
