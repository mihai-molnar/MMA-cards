class_name EnemyBrain
extends RefCounted

## Steps through an OpponentData's fixed rotation. The current turn is
## always known, so the player can read the telegraph before committing.
##
## The rotation's OpponentMoves carry ONE CardEffect instance each, reused
## every cycle -- legal because CardEffect.apply() mutates only the fighters
## and the context, never the effect itself.

var opponent: OpponentData

var _index: int = 0

func _init(p_opponent: OpponentData) -> void:
	opponent = p_opponent

func advance() -> void:
	_index = (_index + 1) % opponent.rotation.size()

func reset() -> void:
	_index = 0

func rotation_index() -> int:
	return _index

func current_moves() -> Array:
	return opponent.rotation[_index]

func build_effects() -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	for move: OpponentMove in current_moves():
		effects.append_array(move.effects)
	return effects

## ASCII only -- the default font has no glyphs for sword/shield symbols.
## Multi-move turns join with " + ": "ATTACK 8 + BLOCK 8".
func intent_text(enemy: Fighter, target: Fighter) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for move: OpponentMove in current_moves():
		parts.append(move.intent_text(enemy, target))
	return " + ".join(parts)
