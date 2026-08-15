class_name OpponentMove
extends RefCounted

## One named enemy action inside a rotation turn: the label the intent
## telegraph prints, plus the CardEffects the action resolves with. The
## enemy has no separate combat path -- these are the same effect classes
## the player's cards use.

var label: String
var effects: Array[CardEffect] = []

func _init(p_label: String, p_effects: Array[CardEffect]) -> void:
	label = p_label
	effects = p_effects

## Telegraph for this move. Damage previews through Combat.preview_damage so
## the telegraph can never diverge from what resolve_damage would produce
## (a Low Kick must halve "ATTACK 8" to "ATTACK 4" in real time). Guard and
## buff amounts are static and print as authored. Priority order: a move
## with any damage telegraphs as damage -- the leg kick reads "LEG KICK 5",
## not as its rider debuff.
func intent_text(enemy: Fighter, target: Fighter) -> String:
	for effect: CardEffect in effects:
		if effect is DamageEffect:
			return "%s %d" % [label, Combat.preview_damage((effect as DamageEffect).amount, enemy, target)]
	for effect: CardEffect in effects:
		if effect is GuardEffect:
			return "%s %d" % [label, (effect as GuardEffect).amount]
	for effect: CardEffect in effects:
		if effect is ApplyStatusEffect:
			var status := effect as ApplyStatusEffect
			return "%s +%d %s" % [label, status.stacks, StatusRegistry.display_name(status.status_id)]
	return label
