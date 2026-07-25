class_name CardLibrary
extends RefCounted

## Loads card resources and builds the starting deck.
## Uses load() rather than preload() so this script parses even before the
## generator has produced the .tres files.

const CARD_DIR: String = "res://resources/cards"

static func load_card(card_id: StringName) -> CardData:
	var path: String = "%s/%s.tres" % [CARD_DIR, card_id]
	var resource: Resource = load(path)
	if resource == null:
		push_error("CardLibrary: no card resource at %s" % path)
		return null
	# Duplicate so every deck entry is an independent instance.
	return (resource as CardData).duplicate(true)

static func all_ids() -> Array:
	return BattleConfig.DECK_COMPOSITION.keys()

static func build_starting_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		var copies: int = BattleConfig.DECK_COMPOSITION[card_id]
		for _i: int in range(copies):
			var card: CardData = load_card(card_id)
			if card != null:
				deck.append(card)
	return deck
