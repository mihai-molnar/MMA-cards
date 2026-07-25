extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cards_load(t)
	_test_starting_deck(t)

func _test_cards_load(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check(jab != null, "jab.tres loads")
	t.check_eq(jab.cost, 1, "jab costs 1 AP")
	t.check_eq(jab.total_base_damage(), 6, "jab deals 6 damage")
	t.check(jab.has_tag(&"jab"), "jab carries the jab tag")

	var straight: CardData = CardLibrary.load_card(&"straight")
	t.check_eq(straight.cost, 2, "straight costs 2 AP")
	t.check_eq(straight.total_base_damage(), 9, "straight deals 9 damage")
	t.check(straight.has_tag(&"straight"), "straight carries the straight tag")

	var blocker: CardData = CardLibrary.load_card(&"block")
	t.check_eq(blocker.cost, 1, "block costs 1 AP")
	t.check_eq(blocker.total_base_damage(), 0, "block deals no damage")
	t.check_eq(blocker.effects.size(), 1, "block has one effect")
	t.check_eq((blocker.effects[0] as GuardEffect).amount, 5, "block grants 5 guard")

func _test_starting_deck(t: TestRunner) -> void:
	var deck: Array[CardData] = CardLibrary.build_starting_deck()
	t.check_eq(deck.size(), 12, "starting deck holds 12 cards")

	var counts: Dictionary = {}
	for card: CardData in deck:
		counts[card.id] = counts.get(card.id, 0) + 1
	t.check_eq(counts.get(&"jab", 0), 5, "deck holds 5 jabs")
	t.check_eq(counts.get(&"straight", 0), 4, "deck holds 4 straights")
	t.check_eq(counts.get(&"block", 0), 3, "deck holds 3 blocks")

	# Each deck entry must be an independent instance — a shared resource would
	# let per-card state leak between copies later.
	t.check(deck[0] != deck[1] or deck[0].id != deck[1].id, "deck entries are separate instances")
