extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_null_fighters_match_todays_output(t)
	_test_injured_source_halves_the_previewed_damage(t)
	_test_healthy_source_matches_todays_output(t)
	_test_card_view_update_rules_preview(t)
	_test_one_two_previews_its_hit(t)

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

## One-Two has a sole DamageEffect (the bonus is a GuardBreakBonusEffect,
## not a DamageEffect), so the preview machinery applies to its single
## printed 5 -- the break sentence carries no number ("hits twice"), so the
## previewed value is true for both hits by construction (the bonus hit
## resolves through the same pipeline with the same base).
func _test_one_two_previews_its_hit(t: TestRunner) -> void:
	var one_two: CardData = CardLibrary.load_card(&"one_two")
	var strong := Fighter.new("Strong", 50)
	strong.statuses.apply(&"strength", 2, BattleConfig.STATUS_PERMANENT)
	var target := Fighter.new("Target", 50)

	var bbcode: String = CardTemplate.rules_bbcode(one_two, strong, target)
	var boosted: int = Combat.preview_damage(BattleConfig.ONE_TWO_DAMAGE, strong, target)
	t.check_eq(boosted, 7, "2 strength stacks boost 5 to floori(5 * 1.5) = 7")
	t.check_eq(bbcode.count("]%d[" % boosted), 1, "the single damage span previews the boosted value")
	t.check(not bbcode.contains("]%d[" % BattleConfig.ONE_TWO_DAMAGE),
		"the base 5 no longer appears as a coloured span")
	t.check(not bbcode.contains(CardTemplate.RULES_WEAKENED_COLOR.to_html(false)),
		"a BUFFED number stays damage-red -- weakened orange is for reductions only")
