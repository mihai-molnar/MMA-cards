extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

## Coverage for HandView's play-animation hand-off, previously untested: the
## anchor choice, the reparenting, and the post-play children invariant.
## lunge_to() is entirely frame-free (it only schedules a tween), so these
## assert the real decision via CardView.debug_last_lunge_anchor rather than
## the live transform.

func run(t: TestRunner) -> void:
	_test_attack_card_lunges_to_attack_anchor(t)
	_test_defense_card_lunges_to_defend_anchor(t)
	_test_confirmed_play_removes_card_from_hand(t)
	_test_rejected_play_keeps_card_in_hand(t)

## Builds a HandView parented under `host`, so _hand_off has somewhere to
## reparent the played card to -- exactly like BattleView parenting HandView
## under BattleHud. Without a parent, _hand_off (and today's _launch) is a
## no-op, which is exactly why this path had zero coverage before.
func _build_hand(ids: Array, host: Control) -> HandView:
	var battle := BattleState.new(12345)
	battle.start()
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand
	var view := HandView.new()
	host.add_child(view)
	view.rebuild(battle)
	return view

## Stands in for BattleView, which calls launch_play(index) synchronously
## after battle.play_card(index) returns true -- itself synchronous with
## card_chosen.emit() inside _on_card_selected.
func _confirm_plays(view: HandView) -> void:
	view.card_chosen.connect(func(index: int) -> void: view.launch_play(index))

func _test_attack_card_lunges_to_attack_anchor(t: TestRunner) -> void:
	var host := Control.new()
	var view: HandView = _build_hand([&"jab", &"block"], host)
	var attack_anchor := Vector2(999.0, 111.0)
	var defend_anchor := Vector2(-999.0, -111.0)
	view.set_lunge_anchors(attack_anchor, defend_anchor)
	_confirm_plays(view)

	var card: CardView = view.get_child(0) as CardView
	card.card_selected.emit(card)

	t.check_eq(card.debug_last_lunge_anchor, attack_anchor,
		"an attack card lunges toward the attack anchor")
	host.free()

func _test_defense_card_lunges_to_defend_anchor(t: TestRunner) -> void:
	var host := Control.new()
	var view: HandView = _build_hand([&"jab", &"block"], host)
	var attack_anchor := Vector2(999.0, 111.0)
	var defend_anchor := Vector2(-999.0, -111.0)
	view.set_lunge_anchors(attack_anchor, defend_anchor)
	_confirm_plays(view)

	var card: CardView = view.get_child(1) as CardView
	card.card_selected.emit(card)

	t.check_eq(card.debug_last_lunge_anchor, defend_anchor,
		"a defense-tagged card lunges toward the defend anchor")
	host.free()

func _test_confirmed_play_removes_card_from_hand(t: TestRunner) -> void:
	var host := Control.new()
	var view: HandView = _build_hand([&"jab", &"block", &"straight"], host)
	_confirm_plays(view)

	var card: CardView = view.get_child(0) as CardView
	card.card_selected.emit(card)

	t.check_eq(view.get_child_count(), 2,
		"a confirmed play leaves HandView with exactly the remaining hand")
	var remaining: Array[Node] = view.get_children()
	t.check(not remaining.has(card), "the played card is no longer a child of HandView")
	host.free()

func _test_rejected_play_keeps_card_in_hand(t: TestRunner) -> void:
	var host := Control.new()
	var view: HandView = _build_hand([&"jab", &"block", &"straight"], host)
	# No confirmation is wired up -- simulates battle.play_card() returning
	# false, so nothing ever calls launch_play().

	var card: CardView = view.get_child(1) as CardView
	card.card_selected.emit(card)

	t.check_eq(view.get_child_count(), 3, "a rejected play leaves the card in the hand")
	t.check_eq(view.get_child(1), card, "the card returns to its original seat")
	t.check_eq(card.debug_last_lunge_anchor, Vector2.ZERO,
		"a rejected play never calls lunge_to")
	host.free()
