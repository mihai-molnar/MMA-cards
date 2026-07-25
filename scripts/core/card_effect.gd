class_name CardEffect
extends Resource

## One thing a card does. Cards are lists of these, so adding a card is
## composing effects rather than adding a branch to a play function.
##
## context keys (built by BattleState per play):
##   "bonus_damage": int  — combo bonus; the first DamageEffect consumes it
##   "results": Array     — Combat.DamageResult objects appended by damage
##   "log": Array         — human-readable strings for the combat log

func apply(_source: Fighter, _target: Fighter, _context: Dictionary) -> void:
	push_error("CardEffect.apply() must be overridden by %s" % get_script().resource_path)

func describe() -> String:
	return ""
