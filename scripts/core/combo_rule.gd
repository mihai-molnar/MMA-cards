class_name ComboRule
extends RefCounted

## Matches a sequence of tags against the cards played consecutively this turn.
## Adding a combo is constructing another rule — no code changes elsewhere.

var sequence: Array[StringName] = []
var bonus_ratio: float = 0.0

func _init(p_sequence: Array[StringName], p_bonus_ratio: float) -> void:
	sequence = p_sequence
	bonus_ratio = p_bonus_ratio

static func jab_straight() -> ComboRule:
	return ComboRule.new([&"jab", &"straight"] as Array[StringName], BattleConfig.COMBO_BONUS_RATIO)

## Bonus damage if playing `candidate` now completes the sequence, else 0.
## `history` is this turn's plays, oldest first.
func evaluate(history: Array, candidate: CardData) -> int:
	var length: int = sequence.size()
	if length == 0:
		return 0
	if not candidate.has_tag(sequence[length - 1]):
		return 0

	var prefix_length: int = length - 1
	if history.size() < prefix_length:
		return 0

	var matched: Array[CardData] = []
	var start: int = history.size() - prefix_length
	for i: int in range(prefix_length):
		var card: CardData = history[start + i]
		if not card.has_tag(sequence[i]):
			return 0
		matched.append(card)
	matched.append(candidate)

	var total_damage: int = 0
	for card: CardData in matched:
		total_damage += card.total_base_damage()
	return floori(total_damage * bonus_ratio)

func describe() -> String:
	var names: Array[String] = []
	for tag: StringName in sequence:
		names.append(String(tag).to_upper())
	return " -> ".join(names)
