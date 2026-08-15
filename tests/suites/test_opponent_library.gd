extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_brawler_shape(t)
	_test_kickboxer_shape(t)
	_test_leg_kick_composition(t)
	_test_run_sequence(t)

func _labels(turn: Array) -> Array:
	var result: Array = []
	for move: OpponentMove in turn:
		result.append(move.label)
	return result

func _test_brawler_shape(t: TestRunner) -> void:
	var brawler: OpponentData = OpponentLibrary.opponent(&"brawler")
	t.check_eq(brawler.id, &"brawler", "the brawler knows its id")
	t.check_eq(brawler.display_name, "Brawler", "the brawler has a display name")
	t.check_eq(brawler.max_hp, BattleConfig.BRAWLER_MAX_HP, "the brawler's hp comes from BattleConfig")
	t.check_eq(brawler.rotation.size(), 3, "the brawler runs a 3-turn rotation")
	t.check_eq(_labels(brawler.rotation[0]), ["ATTACK"], "turn 1 is a plain attack")
	t.check_eq(_labels(brawler.rotation[1]), ["ATTACK", "BLOCK"], "turn 2 attacks behind a block")
	t.check_eq(_labels(brawler.rotation[2]), ["BLOCK", "BUFF"], "turn 3 blocks and buffs")

func _test_kickboxer_shape(t: TestRunner) -> void:
	var kickboxer: OpponentData = OpponentLibrary.opponent(&"kickboxer")
	t.check_eq(kickboxer.display_name, "Kickboxer", "the kickboxer has a display name")
	t.check_eq(kickboxer.max_hp, BattleConfig.KICKBOXER_MAX_HP, "the kickboxer's hp comes from BattleConfig")
	t.check_eq(kickboxer.rotation.size(), 4, "the kickboxer runs a 4-turn rotation")
	t.check_eq(_labels(kickboxer.rotation[0]), ["LEG KICK"], "the kickboxer opens with the leg kick")
	t.check_eq(_labels(kickboxer.rotation[1]), ["ATTACK"], "turn 2 is a plain attack")
	t.check_eq(_labels(kickboxer.rotation[2]), ["ATTACK", "BLOCK"], "turn 3 attacks behind a block")
	t.check_eq(_labels(kickboxer.rotation[3]), ["BLOCK", "BUFF"], "turn 4 blocks and buffs")

func _test_leg_kick_composition(t: TestRunner) -> void:
	var kickboxer: OpponentData = OpponentLibrary.opponent(&"kickboxer")
	var leg_kick: OpponentMove = kickboxer.rotation[0][0]
	t.check_eq(leg_kick.effects.size(), 2, "the leg kick is damage plus a rider")
	var damage := leg_kick.effects[0] as DamageEffect
	t.check_eq(damage.amount, BattleConfig.KICKBOXER_LEG_KICK_DAMAGE, "the kick's damage comes from BattleConfig")
	var injury := leg_kick.effects[1] as ApplyStatusEffect
	t.check_eq(injury.status_id, LegInjuryStatus.ID, "the rider applies Leg Injury")
	t.check(not injury.target_self, "the injury lands on the TARGET -- the player")
	t.check_eq(injury.turns, BattleConfig.LEG_INJURY_TURNS, "the injury shares the player Low Kick's duration constant")
	t.check(injury.extend_duration, "repeat kicks extend the injury, mirroring the player's Low Kick")

func _test_run_sequence(t: TestRunner) -> void:
	t.check_eq(BattleConfig.RUN_OPPONENTS.size(), 2, "the run is two fights long")
	t.check_eq(BattleConfig.RUN_OPPONENTS[0], &"brawler", "fight 1 is the brawler")
	t.check_eq(BattleConfig.RUN_OPPONENTS[1], &"kickboxer", "fight 2 is the kickboxer")
