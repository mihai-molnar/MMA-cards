extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_reward_pool(t)
	_test_open_builds_the_offer(t)
	_test_selection_state_machine(t)
	_test_finished_payloads(t)
	_test_buttons_take_no_focus(t)

func _test_reward_pool(t: TestRunner) -> void:
	var options: Array[StringName] = RewardPool.options()
	t.check_eq(options, BattleConfig.REWARD_CARDS, "the pool is the configured reward list")
	options.append(&"tampered")
	t.check_eq(RewardPool.options().size(), BattleConfig.REWARD_CARDS.size(),
		"options() returns a copy -- callers cannot mutate the config")

func _test_open_builds_the_offer(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	t.check(view.visible, "opening shows the view")
	t.check_eq(view.debug_card_views().size(), 3, "one CardView per offered card")
	t.check(view.debug_continue_button().disabled, "continue starts disabled -- nothing selected")
	t.check(not view.debug_skip_button().disabled, "skip is always available")
	t.check_eq(view.debug_selected_id(), &"", "nothing selected on open")
	# Reopening rebuilds cleanly (fight 2 of a longer run someday).
	view.open(RewardPool.options())
	t.check_eq(view.debug_card_views().size(), 3, "reopening rebuilds, not accumulates")
	view.free()

func _test_selection_state_machine(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	var first: CardView = view.debug_card_views()[0]
	var second: CardView = view.debug_card_views()[1]

	first.card_selected.emit(first)
	t.check_eq(view.debug_selected_id(), first.card.id, "clicking a card selects it")
	t.check(not view.debug_continue_button().disabled, "continue enables on selection")

	second.card_selected.emit(second)
	t.check_eq(view.debug_selected_id(), second.card.id, "clicking another moves the selection")

	second.card_selected.emit(second)
	t.check_eq(view.debug_selected_id(), &"", "clicking the selected card deselects")
	t.check(view.debug_continue_button().disabled, "continue disables again")
	view.free()

func _test_finished_payloads(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	var captured: Array = []
	view.finished.connect(func(card_id: StringName) -> void: captured.append(card_id))

	var chosen: CardView = view.debug_card_views()[2]
	chosen.card_selected.emit(chosen)
	view.debug_continue_button().pressed.emit()
	t.check_eq(captured.size(), 1, "continue emits finished once")
	t.check_eq(captured[0], chosen.card.id, "continue carries the selected id")
	t.check(not view.visible, "the view hides on finish")

	view.open(RewardPool.options())
	view.debug_skip_button().pressed.emit()
	t.check_eq(captured[1], &"", "skip carries the empty id")
	t.check(not view.visible, "the view hides on skip")
	view.free()

func _test_buttons_take_no_focus(t: TestRunner) -> void:
	var view := RewardsView.new()
	t.check_eq(view.debug_continue_button().focus_mode, Control.FOCUS_NONE,
		"continue takes no focus -- no white focus rectangle")
	t.check_eq(view.debug_skip_button().focus_mode, Control.FOCUS_NONE,
		"skip takes no focus")
	view.free()
