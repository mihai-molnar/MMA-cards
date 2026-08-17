class_name RunState
extends RefCounted

## What persists ACROSS fights: the player's hp, the deck the player has
## assembled -- reward picks persist here, and the position in the
## opponent sequence. A battle is BattleState's problem; the run is this
## class's. Today the sequence is a linear walk of
## BattleConfig.RUN_OPPONENTS -- a future Slay-the-Spire-style map replaces
## only HOW the next opponent is chosen; current_opponent(),
## record_result(), is_complete() and reset() are the seam and survive
## unchanged.

var player_hp: int = BattleConfig.PLAYER_MAX_HP

## The run's deck as card ids: DECK_COMPOSITION expanded, plus every reward
## pick. Each fight builds a fresh Deck from this list -- which is also what
## returns burned cards to play next fight.
var deck_ids: Array[StringName] = CardLibrary.starting_deck_ids()

var _fight_index: int = 0

## The opponent the next (or current) battle is fought against; null once
## every opponent is beaten.
func current_opponent() -> OpponentData:
	if is_complete():
		return null
	return OpponentLibrary.opponent(BattleConfig.RUN_OPPONENTS[_fight_index])

## 1-based, for banner text ("FIGHT 2: ...").
func fight_number() -> int:
	return _fight_index + 1

## The rewards screen's only write.
func add_card(card_id: StringName) -> void:
	deck_ids.append(card_id)

## Called once per battle_over. Carries the survivor's hp either way; only
## a win advances the sequence -- a loss holds position and the view resets
## the whole run instead.
func record_result(won: bool, remaining_hp: int) -> void:
	player_hp = remaining_hp
	if won:
		_fight_index += 1

func is_complete() -> bool:
	return _fight_index >= BattleConfig.RUN_OPPONENTS.size()

func reset() -> void:
	player_hp = BattleConfig.PLAYER_MAX_HP
	_fight_index = 0
	deck_ids = CardLibrary.starting_deck_ids()
