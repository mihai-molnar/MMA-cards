extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_null_fighters_match_todays_output(t)
	_test_injured_source_halves_the_previewed_damage(t)
	_test_healthy_source_matches_todays_output(t)
	_test_card_view_update_rules_preview(t)

## The null-source form (every existing caller/test) must render byte-for-
## byte identical to what CardTemplate.rules_bbcode(card) always produced --
## the live-preview feature is additive, not a behaviour change for anyone
## who never passes fighters.
func _test_null_fighters_match_todays_output(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check_eq(CardTemplate.rules_bbcode(jab), CardTemplate.rules_bbcode(jab, null, null),
		"omitting source/target renders identically to passing them as null")

## An injured source halves the jab's previewed damage (floori(6 * 0.5) = 3)
## and the halved number is coloured the weakened colour, not the plain
## damage red -- the base 6 must no longer appear as a coloured damage span.
func _test_injured_source_halves_the_previewed_damage(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	var injured := Fighter.new("Injured", 50)
	injured.statuses.apply(LegInjuryStatus.ID, 1, 3)
	var target := Fighter.new("Target", 50)

	var bbcode: String = CardTemplate.rules_bbcode(jab, injured, target)
	t.check(bbcode.contains("]3["), "the previewed damage span shows the halved value")
	t.check(bbcode.contains(CardTemplate.RULES_WEAKENED_COLOR.to_html(false)),
		"the weakened value is coloured with the weakened colour")
	t.check(not bbcode.contains("]6["),
		"the base 6 no longer appears as a damage span once weakened")

## A healthy source (no modifying statuses) previews to the same base value,
## so the rendered bbcode matches the null-fighter form exactly.
func _test_healthy_source_matches_todays_output(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	var healthy := Fighter.new("Healthy", 50)
	var target := Fighter.new("Target", 50)
	t.check_eq(CardTemplate.rules_bbcode(jab, healthy, target), CardTemplate.rules_bbcode(jab),
		"an unmodified source previews to the same base value as no preview at all")

## CardView.update_rules_preview re-renders the rules label from live
## fighters, on a detached view -- no scene tree required, matching how the
## rest of card_view.gd's tests read state back.
func _test_card_view_update_rules_preview(t: TestRunner) -> void:
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	var injured := Fighter.new("Injured", 50)
	injured.statuses.apply(LegInjuryStatus.ID, 1, 3)
	var target := Fighter.new("Target", 50)

	view.update_rules_preview(injured, target)
	t.check_eq(view._rules_label.text, CardTemplate.rules_bbcode(view.card, injured, target),
		"update_rules_preview re-sets the rules label to the live-preview bbcode")
	view.free()
