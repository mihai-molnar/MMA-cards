class_name PreparedStatus
extends RefCounted

## Delayed guard, made visible: the stacks are the guard amount granted at
## the owner's NEXT turn start -- after the old guard expires, so the payout
## never stacks on leftovers. on_turn_start returns true, consuming the
## status: it pays out exactly once and the chip disappears. Every status
## definition must provide ID, DISPLAY_NAME, description() and all THREE
## statics -- StatusRegistry calls them unconditionally.

const ID: StringName = &"prepared"
const DISPLAY_NAME: String = "Prepared"
## The interesting number is the pending guard magnitude; the payout moment
## is fixed (next turn start), not a countdown worth printing.
const SHOW_TURNS: bool = false

static func description() -> String:
	return "Gains its stacks as guard at the start of its owner's next turn, after the old guard expires."

static func modify_outgoing_damage(amount: int, _stacks: int) -> int:
	return amount

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount

static func on_turn_start(fighter: Fighter, stacks: int) -> bool:
	fighter.add_guard(stacks)
	return true
