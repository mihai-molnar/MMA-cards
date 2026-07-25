extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)

func _test_card_view_text(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)
	t.check(view != null, "CardView.create returns a view")
	t.check_eq(view.card.id, &"jab", "the view remembers its card")
	var text: String = view.debug_text()
	t.check(text.contains("JAB"), "the card shows its name")
	t.check(text.contains("1 AP"), "the card shows its cost")
	t.check(text.contains("6"), "the card shows its damage")
	view.free()

	var blocker: CardData = CardLibrary.load_card(&"block")
	var block_view: CardView = CardView.create(blocker)
	t.check(block_view.debug_text().contains("5"), "the block card shows its guard value")
	block_view.free()

func _test_affordability(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"straight")
	var view: CardView = CardView.create(card)
	view.set_affordable(true)
	t.check(not view.disabled, "an affordable card accepts clicks")
	t.check_eq(view.modulate.a, 1.0, "an affordable card renders at full opacity")

	view.set_affordable(false)
	t.check(view.disabled, "an unaffordable card refuses clicks")
	t.check(view.modulate.a < 1.0, "an unaffordable card is dimmed")
	view.free()

func _test_hand_view_rebuild(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	battle.deck.hand = [
		CardLibrary.load_card(&"jab"),
		CardLibrary.load_card(&"straight"),
	] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)
	t.check_eq(hand.get_child_count(), 2, "the hand view shows one node per card")

	# 3 AP: both are affordable.
	hand.refresh_states(battle)
	var first: CardView = hand.get_child(0) as CardView
	var second: CardView = hand.get_child(1) as CardView
	t.check(not first.disabled, "the jab is affordable with 3 AP")
	t.check(not second.disabled, "the straight is affordable with 3 AP")

	# 1 AP: the 2-cost straight is not.
	battle.ap = 1
	hand.refresh_states(battle)
	t.check(not first.disabled, "the 1 AP jab stays affordable")
	t.check(second.disabled, "the 2 AP straight is disabled at 1 AP")

	hand.free()
