class_name EnemyBrain
extends RefCounted

## A fixed attack -> block -> buff cycle. The next action is always known, so
## the player can read it before committing to a turn.
##
## Actions are built from the same CardEffect classes the player's cards use —
## the enemy has no separate combat path.

enum Action { ATTACK, BLOCK, BUFF }

const CYCLE: Array = [Action.ATTACK, Action.BLOCK, Action.BUFF]

var current_action: Action = Action.ATTACK

var _index: int = 0

func advance() -> void:
	_index = (_index + 1) % CYCLE.size()
	current_action = CYCLE[_index]

func reset() -> void:
	_index = 0
	current_action = CYCLE[0]

func build_effects() -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	match current_action:
		Action.ATTACK:
			var damage := DamageEffect.new()
			damage.amount = BattleConfig.ENEMY_ATTACK_DAMAGE
			effects.append(damage)
		Action.BLOCK:
			var guard := GuardEffect.new()
			guard.amount = BattleConfig.ENEMY_GUARD_AMOUNT
			effects.append(guard)
		Action.BUFF:
			var buff := ApplyStatusEffect.new()
			buff.status_id = StrengthStatus.ID
			buff.stacks = BattleConfig.ENEMY_BUFF_STRENGTH
			buff.turns = BattleConfig.ENEMY_BUFF_DURATION
			buff.target_self = true
			effects.append(buff)
	return effects

## ASCII only — the default font has no glyphs for sword/shield symbols.
func intent_text(enemy: Fighter) -> String:
	match current_action:
		Action.ATTACK:
			return "ATTACK %d" % Combat.preview_damage(BattleConfig.ENEMY_ATTACK_DAMAGE, enemy)
		Action.BLOCK:
			return "BLOCK %d" % BattleConfig.ENEMY_GUARD_AMOUNT
		Action.BUFF:
			return "BUFF +%d STR" % BattleConfig.ENEMY_BUFF_STRENGTH
	return "?"
