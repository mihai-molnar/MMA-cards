class_name StrengthStatus
extends RefCounted

## Each stack adds BattleConfig.STRENGTH_DAMAGE_PER_STACK of base outgoing damage.
## Every status definition must provide ID, DISPLAY_NAME, and BOTH modifier
## statics — StatusRegistry calls them unconditionally.

const ID: StringName = &"strength"
const DISPLAY_NAME: String = "STR"
## The interesting number is the magnitude (each stack is +25% damage), so
## display code prints stacks, not the timer.
const SHOW_TURNS: bool = false

static func description() -> String:
	return "Attacks deal %d%% more damage per stack." % roundi(
		BattleConfig.STRENGTH_DAMAGE_PER_STACK * 100.0)

static func modify_outgoing_damage(amount: int, stacks: int) -> int:
	if stacks <= 0:
		return amount
	return floori(amount * (1.0 + BattleConfig.STRENGTH_DAMAGE_PER_STACK * stacks))

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount
