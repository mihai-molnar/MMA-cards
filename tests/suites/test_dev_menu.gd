extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_all_card_ids_covers_the_whole_game(t)
	_test_open_builds_one_view_per_card(t)
	_test_clicking_a_card_emits_card_picked(t)
	_test_close_and_dismiss(t)

func _test_all_card_ids_covers_the_whole_game(t: TestRunner) -> void:
	var ids: Array[StringName] = CardLibrary.all_card_ids()
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		t.check(ids.has(card_id), "%s (starting deck) is enumerated" % card_id)
	for card_id: StringName in BattleConfig.REWARD_CARDS:
		t.check(ids.has(card_id), "%s (reward pool) is enumerated" % card_id)
	var seen: Dictionary = {}
	for card_id: StringName in ids:
		seen[card_id] = true
	t.check_eq(seen.size(), ids.size(), "no id is listed twice")

func _test_open_builds_one_view_per_card(t: TestRunner) -> void:
	var menu := DevMenu.new()
	t.check(not menu.visible, "the menu starts hidden")
	menu.open(CardLibrary.build_deck(CardLibrary.all_card_ids()))
	t.check(menu.visible, "open shows the menu")
	t.check_eq(menu.debug_card_views().size(), CardLibrary.all_card_ids().size(),
		"one CardView per library card")
	menu.open(CardLibrary.build_deck(CardLibrary.all_card_ids()))
	t.check_eq(menu.debug_card_views().size(), CardLibrary.all_card_ids().size(),
		"reopening rebuilds, not accumulates")
	menu.free()

func _test_clicking_a_card_emits_card_picked(t: TestRunner) -> void:
	var menu := DevMenu.new()
	menu.open(CardLibrary.build_deck(CardLibrary.all_card_ids()))
	var picked: Array = []
	menu.card_picked.connect(func(card: CardData) -> void: picked.append(card.id))
	var first: CardView = menu.debug_card_views()[0]
	first.card_selected.emit(first)
	t.check_eq(picked.size(), 1, "a card click emits card_picked once")
	t.check_eq(picked[0], first.card.id, "with the clicked card")
	t.check(menu.visible, "the menu stays open for repeat plays")
	menu.free()

func _test_close_and_dismiss(t: TestRunner) -> void:
	var menu := DevMenu.new()
	menu.open(CardLibrary.build_deck(CardLibrary.all_card_ids()))
	var closes: Array = []
	menu.closed.connect(func() -> void: closes.append(true))
	menu.close()
	t.check(not menu.visible and closes.size() == 1, "close hides and announces")
	menu.open(CardLibrary.build_deck(CardLibrary.all_card_ids()))
	menu.dismiss()
	t.check(not menu.visible and closes.size() == 1, "dismiss hides silently")
	menu.free()
