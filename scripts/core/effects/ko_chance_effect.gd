class_name KOChanceEffect
extends CardEffect

## A chance to end the fight on the spot. Rolls ONLY when the card's
## preceding DamageEffect dealt hp damage -- a fully blocked strike never
## KOs (the same fail-closed read as ApplyStatusEffect.require_hp_damage,
## which is why this effect sits AFTER the card's DamageEffect). Writes
## context["ko_attempted"] / context["ko"]; BattleState reads them
## generically -- no card branch anywhere. The roll comes from
## context["rng"], BattleState's seeded per-battle RNG, so tests are
## deterministic; no rng in the context fails closed (no roll).

@export var chance: float = 0.0

func apply(_source: Fighter, target: Fighter, context: Dictionary) -> void:
	var results: Array = context["results"]
	var last_result: Combat.DamageResult = results.back() if not results.is_empty() else null
	if last_result == null or last_result.hp_loss <= 0:
		return
	var rng: RandomNumberGenerator = context.get("rng")
	if rng == null:
		return
	context["ko_attempted"] = true
	var success: bool = rng.randf() < chance
	context["ko"] = success
	if success:
		context["log"].append("KO! %s is finished" % target.display_name)
	else:
		context["log"].append("%s shakes it off and stays standing" % target.display_name)

func describe() -> String:
	return "%d%% chance to KO." % roundi(chance * 100.0)

## The KO keyword tooltip's body -- kept in core beside the mechanic it
## describes, like ComboRule.keyword_description() and Deck.burn_description().
static func keyword_description() -> String:
	return "A chance to end the fight instantly with a win by knockout. Only rolls when the hit deals damage past guard -- a fully blocked strike never KOs."
