class_name ApplyStatusEffect
extends CardEffect

@export var status_id: StringName = &""
@export var stacks: int = 0
## Turn countdown; BattleConfig.STATUS_PERMANENT (-1) never expires.
@export var turns: int = BattleConfig.STATUS_PERMANENT
@export var target_self: bool = true

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	var recipient: Fighter = source if target_self else target
	recipient.statuses.apply(status_id, stacks, turns)
	context["log"].append("%s gains %d %s" % [
		recipient.display_name, stacks, StatusRegistry.display_name(status_id)
	])

func describe() -> String:
	return "Gain %d %s." % [stacks, StatusRegistry.display_name(status_id)]
