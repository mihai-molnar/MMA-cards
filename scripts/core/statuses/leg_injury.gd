class_name LegInjuryStatus
extends RefCounted

## The injured fighter cannot put weight on the leg: outgoing damage is
## multiplied by BattleConfig.LEG_INJURY_DAMAGE_MULT (floored). Not
## stack-scaled -- a leg is injured or it is not; extra applications refresh
## the duration through StatusBag's usual rules rather than deepening the
## debuff. Every status definition must provide ID, DISPLAY_NAME,
## description() and all THREE statics -- StatusRegistry calls them
## unconditionally.
##
## DISPLAY_NAME doubles as the card-text KEYWORD: CardTemplate colours it
## yellow in rules text and the hover tooltip explains it via description().

const ID: StringName = &"leg_injury"
const DISPLAY_NAME: String = "Leg Injury"
## The interesting number is HOW LONG the leg stays hurt, not the stack
## count (which is always 1) -- the panel prints the countdown.
const SHOW_TURNS: bool = true

static func description() -> String:
	return "Attacks deal %d%% less damage. Only applied when the kick deals damage past guard." % roundi(
		(1.0 - BattleConfig.LEG_INJURY_DAMAGE_MULT) * 100.0)

static func modify_outgoing_damage(amount: int, stacks: int) -> int:
	if stacks <= 0:
		return amount
	return floori(amount * BattleConfig.LEG_INJURY_DAMAGE_MULT)

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount

## Pass-through: nothing happens at turn start and the status is kept.
static func on_turn_start(_fighter: Fighter, _stacks: int) -> bool:
	return false
