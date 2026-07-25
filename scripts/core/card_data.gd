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

## Base damage before any modifiers. Combo bonuses are computed from this, so
## it is derived from the effects rather than duplicated in a field.
func total_base_damage() -> int:
	var total: int = 0
	for effect: CardEffect in effects:
		if effect is DamageEffect:
			total += (effect as DamageEffect).amount
	return total

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
