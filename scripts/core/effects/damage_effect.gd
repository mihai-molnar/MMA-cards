class_name DamageEffect
extends CardEffect

@export var amount: int = 0

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	# The combo bonus applies to the first damage effect only.
	var bonus: int = context.get("bonus_damage", 0)
	context["bonus_damage"] = 0

	var result: Combat.DamageResult = Combat.resolve_damage(amount + bonus, source, target)
	context["results"].append(result)
	context["log"].append("%s deals %d damage" % [source.display_name, result.raw])

func describe() -> String:
	return "Deal %d damage." % amount
