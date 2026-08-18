class_name BleedStatus
extends RefCounted

## A cut that costs hp at the start of each of its owner's turns. Goes
## STRAIGHT to hp -- Fighter.apply_hp_loss, not Combat.resolve_damage, on
## purpose: bleed pierces guard, and it is not an attack so no damage
## modifiers apply. Not stack-scaled (a cut bleeds or it does not);
## re-application extends the duration through ApplyStatusEffect's
## extend_duration, like Leg Injury.

const ID: StringName = &"bleed"
const DISPLAY_NAME: String = "Bleed"
## The interesting number is how long the bleeding lasts.
const SHOW_TURNS: bool = true

static func description() -> String:
	return "Takes %d damage at the start of each turn, ignoring guard. Only applied when the hit deals damage past guard." % BattleConfig.BLEED_DAMAGE_PER_TURN

static func modify_outgoing_damage(amount: int, _stacks: int) -> int:
	return amount

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount

## Returns false: the tick never consumes the status -- it expires through
## the normal turn-end countdown.
static func on_turn_start(fighter: Fighter, stacks: int) -> bool:
	if stacks > 0:
		fighter.apply_hp_loss(BattleConfig.BLEED_DAMAGE_PER_TURN)
	return false
