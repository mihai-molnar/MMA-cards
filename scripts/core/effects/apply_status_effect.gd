class_name ApplyStatusEffect
extends CardEffect

@export var status_id: StringName = &""
@export var stacks: int = 0
## Turn countdown; BattleConfig.STATUS_PERMANENT (-1) never expires.
@export var turns: int = BattleConfig.STATUS_PERMANENT
@export var target_self: bool = true
## When true, re-applying ADDS the durations (each Low Kick keeps the leg
## hurt one turn longer) instead of refreshing to the longer one.
@export var extend_duration: bool = false
## When true, the status lands only if the card's PRECEDING DamageEffect
## dealt hp damage -- a fully blocked kick injures nothing. Reads the last
## Combat.DamageResult in context["results"]; no preceding result means no
## application (fail closed).
@export var require_hp_damage: bool = false
## Probability the status lands at all, rolled on context["rng"]
## (BattleState's seeded per-battle RNG). 1.0 -- the default, and every
## pre-existing card -- never rolls and never touches the rng, so contexts
## built without one keep working.
@export var chance: float = 1.0

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	var recipient: Fighter = source if target_self else target
	if require_hp_damage:
		var results: Array = context["results"]
		var last_result: Combat.DamageResult = results.back() if not results.is_empty() else null
		if last_result == null or last_result.hp_loss <= 0:
			context["log"].append("%s blocks the %s" % [
				recipient.display_name, StatusRegistry.display_name(status_id)
			])
			return
	if chance < 1.0:
		var rng: RandomNumberGenerator = context.get("rng")
		if rng == null or rng.randf() >= chance:
			context["log"].append("%s shrugs off the %s" % [
				recipient.display_name, StatusRegistry.display_name(status_id)
			])
			return
	recipient.statuses.apply(status_id, stacks, turns, extend_duration)
	context["log"].append("%s gains %d %s" % [
		recipient.display_name, stacks, StatusRegistry.display_name(status_id)
	])

func describe() -> String:
	var verb: String = "Gain" if target_self else "Apply"
	return "%s %d %s." % [verb, stacks, StatusRegistry.display_name(status_id)]
