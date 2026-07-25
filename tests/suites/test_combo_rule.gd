extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func _card(card_id: StringName, tag: StringName, damage: int) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id).to_upper()
	card.tags = [tag] as Array[StringName]
	var effect := DamageEffect.new()
	effect.amount = damage
	card.effects = [effect] as Array[CardEffect]
	return card

func _jab() -> CardData:
	return _card(&"jab", &"jab", 6)

func _straight() -> CardData:
	return _card(&"straight", &"straight", 9)

func _block() -> CardData:
	var card := CardData.new()
	card.id = &"block"
	card.tags = [&"defense"] as Array[StringName]
	var effect := GuardEffect.new()
	effect.amount = 5
	card.effects = [effect] as Array[CardEffect]
	return card

func run(t: TestRunner) -> void:
	var rule := ComboRule.jab_straight()

	# The headline case: jab then straight is 6 + 9 + floor(15 * 0.5) = 22 total.
	t.check_eq(rule.evaluate([_jab()], _straight()), 7, "jab into straight grants a 7 damage bonus")

	# An intervening card breaks the chain.
	t.check_eq(rule.evaluate([_jab(), _block()], _straight()), 0, "a block between jab and straight breaks the combo")

	# Order matters.
	t.check_eq(rule.evaluate([_straight()], _jab()), 0, "straight into jab is not a combo")

	# Wrong candidate, right history.
	t.check_eq(rule.evaluate([_jab()], _jab()), 0, "jab into jab is not a combo")

	# Nothing played yet.
	t.check_eq(rule.evaluate([], _straight()), 0, "a straight opening the turn gets no bonus")

	# Only the immediately preceding card is consulted.
	t.check_eq(rule.evaluate([_block(), _jab()], _straight()), 7, "only the card immediately before matters")

	# A longer history still matches on its tail.
	t.check_eq(rule.evaluate([_jab(), _straight(), _jab()], _straight()), 7, "a second combo in the same turn still triggers")
