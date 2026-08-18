extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cards_load(t)
	_test_starting_deck(t)
	_test_effect_totals(t)
	_test_straight_rules_text_matches_the_combo_rule(t)
	_test_reward_cards_load(t)
	_test_reward_cards_stay_out_of_the_starting_deck(t)
	_test_ko_cards_load(t)

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

## The three reward cards, pinned against BattleConfig exactly like the
## starting four -- the .tres files are baked, and this is the guard that
## catches an edited constant with a forgotten regen.
func _test_reward_cards_load(t: TestRunner) -> void:
	var one_two: CardData = CardLibrary.load_card(&"one_two")
	t.check(one_two != null, "one_two.tres loads")
	t.check_eq(one_two.cost, BattleConfig.ONE_TWO_COST, "one-two costs BattleConfig.ONE_TWO_COST AP")
	t.check_eq(one_two.total_base_damage(), BattleConfig.ONE_TWO_DAMAGE,
		"one-two's BASE damage counts the first hit only -- the conditional hit must not feed combo math")
	t.check_eq(one_two.effects.size(), 2, "one-two: a damage effect and the break bonus")
	var bonus: GuardBreakBonusEffect = one_two.effects[1] as GuardBreakBonusEffect
	t.check(bonus != null, "one-two's second effect is the guard-break bonus")
	t.check_eq(bonus.amount, BattleConfig.ONE_TWO_DAMAGE, "the bonus hit deals the same 5")
	t.check(not one_two.burn, "one-two does not burn")

	var strength_up: CardData = CardLibrary.load_card(&"strength_up")
	t.check_eq(strength_up.cost, BattleConfig.STRENGTH_UP_COST, "strength up costs 0 AP")
	t.check(strength_up.burn, "strength up burns")
	t.check_eq(strength_up.effects.size(), 1, "strength up has one effect")
	var buff: ApplyStatusEffect = strength_up.effects[0] as ApplyStatusEffect
	t.check(buff != null, "strength up applies a status")
	t.check_eq(buff.status_id, &"strength", "the status is strength")
	t.check_eq(buff.stacks, BattleConfig.STRENGTH_UP_STACKS, "it grants STRENGTH_UP_STACKS stacks")
	t.check_eq(buff.turns, BattleConfig.STATUS_PERMANENT, "the strength is permanent for the fight")
	t.check(buff.target_self, "it buffs the player, not the enemy")
	t.check(strength_up.rules_text.contains("Burn"),
		"strength up's rules text names the Burn keyword")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	t.check_eq(prepared.cost, BattleConfig.PREPARED_COST, "prepared costs 1 AP")
	t.check_eq(prepared.total_guard(), BattleConfig.PREPARED_GUARD,
		"prepared's immediate guard is PREPARED_GUARD")
	t.check(prepared.has_tag(&"defense"), "prepared is a defense card (blue frame)")
	t.check_eq(prepared.effects.size(), 2, "prepared: immediate guard plus the delayed status")
	var delayed: ApplyStatusEffect = prepared.effects[1] as ApplyStatusEffect
	t.check(delayed != null, "prepared's second effect applies a status")
	t.check_eq(delayed.status_id, PreparedStatus.ID, "the status is prepared")
	t.check_eq(delayed.stacks, BattleConfig.PREPARED_GUARD, "the delayed guard equals the immediate one")
	t.check_eq(delayed.turns, BattleConfig.PREPARED_STATUS_TURNS, "with the lifecycle-ceiling duration")
	t.check(delayed.target_self, "the delayed guard is the player's own")

func _test_reward_cards_stay_out_of_the_starting_deck(t: TestRunner) -> void:
	t.check_eq(CardLibrary.build_starting_deck().size(), 14,
		"the starting deck is unchanged -- reward cards enter only via the rewards screen")
	for card_id: StringName in BattleConfig.REWARD_CARDS:
		t.check(not BattleConfig.DECK_COMPOSITION.has(card_id),
			"%s is not in DECK_COMPOSITION" % card_id)

func _test_ko_cards_load(t: TestRunner) -> void:
	var high_kick: CardData = CardLibrary.load_card(&"high_kick")
	t.check(high_kick != null, "high_kick.tres loads")
	t.check_eq(high_kick.cost, BattleConfig.HIGH_KICK_COST, "high kick costs HIGH_KICK_COST AP")
	t.check_eq(high_kick.total_base_damage(), BattleConfig.HIGH_KICK_DAMAGE,
		"high kick deals HIGH_KICK_DAMAGE")
	t.check(high_kick.has_tag(&"kick"), "high kick carries the kick tag (kick hit sound)")
	var hk_ko: KOChanceEffect = high_kick.effects[1] as KOChanceEffect
	t.check(hk_ko != null, "high kick's second effect is the KO roll")
	t.check_eq(hk_ko.chance, BattleConfig.HIGH_KICK_KO_CHANCE, "high kick's KO chance is baked")
	t.check(high_kick.rules_text.contains("KO"), "high kick names the KO keyword")

	var knee: CardData = CardLibrary.load_card(&"flying_knee")
	t.check_eq(knee.cost, BattleConfig.FLYING_KNEE_COST, "flying knee costs FLYING_KNEE_COST AP")
	t.check_eq(knee.total_base_damage(), BattleConfig.FLYING_KNEE_DAMAGE,
		"flying knee deals FLYING_KNEE_DAMAGE")
	t.check(knee.has_tag(&"kick"), "flying knee carries the kick tag")
	t.check_eq((knee.effects[1] as KOChanceEffect).chance, BattleConfig.FLYING_KNEE_KO_CHANCE,
		"flying knee's KO chance is baked")

	var elbow: CardData = CardLibrary.load_card(&"elbow")
	t.check_eq(elbow.cost, BattleConfig.ELBOW_COST, "elbow costs ELBOW_COST AP")
	t.check_eq(elbow.total_base_damage(), BattleConfig.ELBOW_DAMAGE, "elbow deals ELBOW_DAMAGE")
	t.check(not elbow.has_tag(&"kick"), "elbow punches, not kicks")
	t.check_eq(elbow.effects.size(), 3, "elbow: damage, KO roll, bleed")
	t.check_eq((elbow.effects[1] as KOChanceEffect).chance, BattleConfig.ELBOW_KO_CHANCE,
		"elbow's KO chance is baked")
	var bleed: ApplyStatusEffect = elbow.effects[2] as ApplyStatusEffect
	t.check(bleed != null, "elbow's third effect applies a status")
	t.check_eq(bleed.status_id, &"bleed", "the status is bleed")
	t.check_eq(bleed.chance, BattleConfig.ELBOW_BLEED_CHANCE, "the bleed chance is baked")
	t.check_eq(bleed.turns, BattleConfig.BLEED_TURNS, "bleed lasts BLEED_TURNS")
	t.check(not bleed.target_self, "the bleed lands on the opponent")
	t.check(bleed.extend_duration, "a second elbow extends the bleed")
	t.check(bleed.require_hp_damage, "a blocked elbow bleeds nothing")
	t.check(elbow.rules_text.contains("Bleed"), "elbow names the Bleed keyword")
