class_name GuardBreakBonusEffect
extends CardEffect

## One-Two's second hit: lands only if the PRECEDING DamageEffect broke the
## target's guard (see Combat.DamageResult.broke_guard). Reads the last
## result in context["results"]; no preceding result means no bonus hit
## (fail closed, like ApplyStatusEffect.require_hp_damage). Deliberately NOT
## a DamageEffect subclass: total_base_damage() must not count a conditional
## hit (combo math would see a phantom double), and the first-DamageEffect-
## consumes-the-combo-bonus rule stays untouched. The bonus hit resolves
## through the full pipeline, so strength boosts it like any other hit.

@export var amount: int = 0

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	var results: Array = context["results"]
	var last_result: Combat.DamageResult = results.back() if not results.is_empty() else null
	if last_result == null or not last_result.broke_guard:
		return
	var result: Combat.DamageResult = Combat.resolve_damage(amount, source, target)
	context["results"].append(result)
	context["log"].append("%s breaks through for %d more damage" % [source.display_name, result.raw])

func describe() -> String:
	return "Breaks guard: deal %d damage again." % amount
