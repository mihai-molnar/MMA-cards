class_name OpponentLibrary
extends RefCounted

## Builds every opponent in code from BattleConfig constants -- the opponent
## analogue of CardLibrary, minus the .tres step: opponents have no art or
## composed face to bake, so a generator would add nothing.
##
## Adding an opponent: write a _make_*() below, register its id in
## opponent(), add its constants to BattleConfig, and append the id to
## BattleConfig.RUN_OPPONENTS.

static func opponent(id: StringName) -> OpponentData:
	match id:
		&"brawler":
			return _make_brawler()
		&"kickboxer":
			return _make_kickboxer()
	push_error("OpponentLibrary: unknown opponent id %s" % id)
	return null

static func _make_brawler() -> OpponentData:
	var rotation: Array[Array] = [
		[_attack(BattleConfig.BRAWLER_ATTACK_DAMAGE)],
		[_attack(BattleConfig.BRAWLER_ATTACK_DAMAGE), _block(BattleConfig.BRAWLER_GUARD_AMOUNT)],
		[_block(BattleConfig.BRAWLER_GUARD_AMOUNT), _buff(BattleConfig.BRAWLER_BUFF_STRENGTH, BattleConfig.BRAWLER_BUFF_DURATION)],
	]
	return OpponentData.new(&"brawler", "Brawler", BattleConfig.BRAWLER_MAX_HP, rotation)

static func _make_kickboxer() -> OpponentData:
	var rotation: Array[Array] = [
		[_leg_kick()],
		[_attack(BattleConfig.KICKBOXER_ATTACK_DAMAGE)],
		[_attack(BattleConfig.KICKBOXER_ATTACK_DAMAGE), _block(BattleConfig.KICKBOXER_GUARD_AMOUNT)],
		[_block(BattleConfig.KICKBOXER_GUARD_AMOUNT), _buff(BattleConfig.KICKBOXER_BUFF_STRENGTH, BattleConfig.KICKBOXER_BUFF_DURATION)],
	]
	return OpponentData.new(&"kickboxer", "Kickboxer", BattleConfig.KICKBOXER_MAX_HP, rotation)

static func _attack(amount: int) -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = amount
	var effects: Array[CardEffect] = [damage]
	return OpponentMove.new("ATTACK", effects)

static func _block(amount: int) -> OpponentMove:
	var guard := GuardEffect.new()
	guard.amount = amount
	var effects: Array[CardEffect] = [guard]
	return OpponentMove.new("BLOCK", effects)

static func _buff(stacks: int, turns: int) -> OpponentMove:
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = stacks
	buff.turns = turns
	buff.target_self = true
	var effects: Array[CardEffect] = [buff]
	return OpponentMove.new("BUFF", effects)

## The player's own Low Kick, mirrored back: chip damage plus Leg Injury on
## the TARGET. Shares LEG_INJURY_TURNS and extend_duration semantics with
## the player's card so the mirror stays exact by construction.
static func _leg_kick() -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.KICKBOXER_LEG_KICK_DAMAGE
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = BattleConfig.LEG_INJURY_TURNS
	injury.target_self = false
	injury.extend_duration = true
	var effects: Array[CardEffect] = [damage, injury]
	return OpponentMove.new("LEG KICK", effects)
