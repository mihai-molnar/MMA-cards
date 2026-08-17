class_name CardData
extends Resource

## A card is data: what it costs, what it is tagged as, and what it does.
## Adding a card means authoring a .tres — never editing a play function.

@export var id: StringName = &""
@export var display_name: String = ""
@export var cost: int = 0
## Combo rules match on these.
@export var tags: Array[StringName] = []
@export var effects: Array[CardEffect] = []
@export var rules_text: String = ""
## When true, playing this card sends it to the deck's burned pile instead of
## the discard: gone for the rest of the fight (it returns next fight, since
## every fight builds a fresh deck). Burn triggers on PLAY only -- an
## unplayed copy discards normally at end of turn.
@export var burn: bool = false

## Base damage before any modifiers. Combo bonuses are computed from this, so
## it is derived from the effects rather than duplicated in a field.
func total_base_damage() -> int:
	var total: int = 0
	for effect: CardEffect in effects:
		if effect is DamageEffect:
			total += (effect as DamageEffect).amount
	return total

## Total guard this card grants. Mirrors total_base_damage(), and exists for
## the same reason: the composed card face derives its badge number from the
## effects rather than from a stored field, so the printed value cannot drift
## from what the card actually does.
func total_guard() -> int:
	var total: int = 0
	for effect: CardEffect in effects:
		if effect is GuardEffect:
			total += (effect as GuardEffect).amount
	return total

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
