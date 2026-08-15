extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cards_load(t)
	_test_starting_deck(t)
	_test_effect_totals(t)
	_test_straight_rules_text_matches_the_combo_rule(t)

func _test_cards_load(t: TestRunner) -> void:
	# Compared against BattleConfig, not literals: the .tres files are baked
	# by tools/generate_cards.gd and do not update themselves when a constant
	# changes, so this is the guard that catches that drift.
	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check(jab != null, "jab.tres loads")
	t.check_eq(jab.cost, BattleConfig.JAB_COST, "jab costs BattleConfig.JAB_COST AP")
	t.check_eq(jab.total_base_damage(), BattleConfig.JAB_DAMAGE, "jab deals BattleConfig.JAB_DAMAGE damage")
	t.check(jab.has_tag(&"jab"), "jab carries the jab tag")

	var straight: CardData = CardLibrary.load_card(&"straight")
	t.check_eq(straight.cost, BattleConfig.STRAIGHT_COST, "straight costs BattleConfig.STRAIGHT_COST AP")
	t.check_eq(straight.total_base_damage(), BattleConfig.STRAIGHT_DAMAGE, "straight deals BattleConfig.STRAIGHT_DAMAGE damage")
	t.check(straight.has_tag(&"straight"), "straight carries the straight tag")

	var blocker: CardData = CardLibrary.load_card(&"block")
	t.check_eq(blocker.cost, BattleConfig.BLOCK_COST, "block costs BattleConfig.BLOCK_COST AP")
	t.check_eq(blocker.total_base_damage(), 0, "block deals no damage")
	t.check_eq(blocker.effects.size(), 1, "block has one effect")
	t.check_eq((blocker.effects[0] as GuardEffect).amount, BattleConfig.BLOCK_GUARD, "block grants BattleConfig.BLOCK_GUARD guard")

	var kick: CardData = CardLibrary.load_card(&"low_kick")
	t.check_eq(kick.cost, BattleConfig.LOW_KICK_COST, "low kick costs BattleConfig.LOW_KICK_COST AP")
	t.check_eq(kick.total_base_damage(), BattleConfig.LOW_KICK_DAMAGE,
		"low kick deals BattleConfig.LOW_KICK_DAMAGE damage")
	t.check(kick.has_tag(&"kick"), "low kick carries the kick tag")
	t.check_eq(kick.effects.size(), 2, "low kick has a damage effect and a status effect")
	var injury: ApplyStatusEffect = kick.effects[1] as ApplyStatusEffect
	t.check(injury != null, "low kick's second effect applies a status")
	t.check_eq(injury.status_id, &"leg_injury", "the status is leg injury")
	t.check_eq(injury.turns, BattleConfig.LEG_INJURY_TURNS,
		"the injury lasts BattleConfig.LEG_INJURY_TURNS turn")
	t.check(not injury.target_self, "the injury lands on the opponent, not the kicker")
	t.check(injury.extend_duration, "a second kick extends the injury instead of refreshing it")
	t.check(kick.rules_text.contains("Leg Injury"),
		"the rules text names the keyword the tooltip explains")

func _test_starting_deck(t: TestRunner) -> void:
	var deck: Array[CardData] = CardLibrary.build_starting_deck()
	t.check_eq(deck.size(), 14, "starting deck holds 14 cards")

	var counts: Dictionary = {}
	for card: CardData in deck:
		counts[card.id] = counts.get(card.id, 0) + 1
	t.check_eq(counts.get(&"jab", 0), 5, "deck holds 5 jabs")
	t.check_eq(counts.get(&"straight", 0), 4, "deck holds 4 straights")
	t.check_eq(counts.get(&"block", 0), 3, "deck holds 3 blocks")
	t.check_eq(counts.get(&"low_kick", 0), 2, "deck holds 2 low kicks")

	# Each deck entry must be an independent instance — a shared resource would
	# let per-card state leak between copies later.
	t.check(deck[0] != deck[1] or deck[0].id != deck[1].id, "deck entries are separate instances")

	# Top-level identity alone proves nothing: duplicate() always allocates a
	# new CardData wrapper, shallow or deep. The real hazard is two copies of
	# the same card sharing an *effect* object underneath — find two jabs
	# (the deck guarantees at least two) and prove their effects are distinct,
	# independently mutable objects rather than the same DamageEffect.
	var jabs: Array[CardData] = deck.filter(func(card: CardData) -> bool: return card.id == &"jab")
	t.check(jabs.size() >= 2, "deck has at least two jabs to compare")
	var jab_a: CardData = jabs[0]
	var jab_b: CardData = jabs[1]
	t.check(jab_a.effects[0] != jab_b.effects[0], "duplicated jabs do not share an effect object")

	var effect_a: DamageEffect = jab_a.effects[0] as DamageEffect
	var effect_b: DamageEffect = jab_b.effects[0] as DamageEffect
	var original_amount: int = effect_b.amount
	effect_a.amount += 1000
	t.check_eq(effect_b.amount, original_amount, "mutating one jab's effect leaves the other jab's effect unchanged")

## The badge number on a composed card face is derived from these two, never
## stored, so they are what stops a card printing a value the rules disagree
## with. Both must return 0 rather than push_error for a card of the other
## kind -- CardView reads both and shows the one its frame calls for.
func _test_effect_totals(t: TestRunner) -> void:
	var blocker: CardData = CardLibrary.load_card(&"block")
	t.check_eq(blocker.total_guard(), BattleConfig.BLOCK_GUARD,
		"block's total_guard() is BattleConfig.BLOCK_GUARD")
	t.check_eq(blocker.total_base_damage(), 0,
		"a card with no DamageEffect totals zero damage")

	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check_eq(jab.total_guard(), 0, "a card with no GuardEffect totals zero guard")
	t.check_eq(jab.total_base_damage(), BattleConfig.JAB_DAMAGE,
		"jab's total_base_damage() is BattleConfig.JAB_DAMAGE")

	var empty := CardData.new()
	t.check_eq(empty.total_guard(), 0, "a card with no effects at all totals zero guard")
	t.check_eq(empty.total_base_damage(), 0, "a card with no effects at all totals zero damage")

## The card face names the keyword and the trigger; the MECHANIC lives in
## the Combo tooltip, whose text is derived from the live
## BattleConfig.COMBO_BONUS_RATIO -- so changing the ratio can never leave
## a stale number printed anywhere, which is precisely what the old painted
## card face did for the whole of its life.
func _test_straight_rules_text_matches_the_combo_rule(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	var straight: CardData = CardLibrary.load_card(&"straight")

	t.check_eq(straight.rules_text,
		"Deal %d damage. Combo right after Jab." % BattleConfig.STRAIGHT_DAMAGE,
		"straight names the Combo keyword and its trigger, nothing more")
	# The old painted face said "earlier this turn", which is wrong -- any card
	# in between breaks the combo. The wording must say immediately.
	t.check(straight.rules_text.contains("right after Jab"),
		"straight's rules text states the combo needs Jab immediately before")

	# The explanation the tooltip shows, tied to the live ratio.
	t.check(ComboRule.keyword_description().contains(
			"%d%%" % roundi(BattleConfig.COMBO_BONUS_RATIO * 100.0)),
		"the combo keyword description states the bonus ratio from config")

	# The other cards stay combo-free.
	t.check(not jab.rules_text.contains("Combo"), "jab's rules text mentions no combo")
