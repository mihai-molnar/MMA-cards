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

## DECK_COMPOSITION expanded to a flat id list -- the single source RunState
## seeds its run deck from and build_starting_deck() builds from.
static func starting_deck_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		var copies: int = BattleConfig.DECK_COMPOSITION[card_id]
		for _i: int in range(copies):
			ids.append(card_id)
	return ids

## Loads a deck from an id list (the run's persistent deck). Unloadable ids
## are skipped -- load_card already push_errors, which the test wrapper
## treats as failure.
static func build_deck(ids: Array[StringName]) -> Array[CardData]:
	var deck: Array[CardData] = []
	for card_id: StringName in ids:
		var card: CardData = load_card(card_id)
		if card != null:
			deck.append(card)
	return deck

static func build_starting_deck() -> Array[CardData]:
	return build_deck(starting_deck_ids())

## Every distinct card id in the game: the starting deck's plus the reward
## pool's. Only the dev menu enumerates this -- the run itself always works
## from a specific deck list.
static func all_card_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		ids.append(card_id)
	for card_id: StringName in BattleConfig.REWARD_CARDS:
		if not ids.has(card_id):
			ids.append(card_id)
	return ids
