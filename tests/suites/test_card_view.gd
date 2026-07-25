extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)
	_test_art_found_hides_labels_and_shows_texture(t)
	_test_art_missing_keeps_fallback_appearance(t)
	_test_combo_armed_idempotent(t)
	_test_combo_armed_idempotent_with_art(t)

## A CardData with no matching res://assets/cards/card_<id>.png -- exercises
## CardView's fallback path the same way a freshly authored card (.tres
## written, art not painted yet) would on day one.
func _no_art_card() -> CardData:
	var card := CardData.new()
	card.id = &"no_such_card_id"
	card.display_name = "TEST CARD"
	card.cost = 1
	return card

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

## jab has real art (res://assets/cards/card_jab.png), so this exercises the
## "found" branch of _apply_art(): the texture is set and visible, and the
## name/cost/rules-text labels plus the coloured background and border --
## all baked into or superseded by the art -- are hidden. debug_text() must
## still report the label text (per its own contract), even though nothing
## on screen shows it.
func _test_art_found_hides_labels_and_shows_texture(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)

	t.check(view._art.texture != null, "a card with matching art gets a texture")
	t.check_eq(view._art.texture, CardArt.texture_for(&"jab"),
		"the view's texture is the one CardArt resolves for this card's id")
	t.check(view._art.visible, "the art node is shown")
	t.check(not view._name_label.visible, "the name label is hidden -- it is baked into the art")
	t.check(not view._cost_label.visible, "the cost label is hidden -- it is baked into the art")
	t.check(not view._text_label.visible, "the rules-text label is hidden -- it is baked into the art")
	t.check(not view._background.visible, "the coloured background is hidden behind the art")
	t.check(not view._border.visible, "the synthetic border is hidden -- the art has its own gold frame")

	var text: String = view.debug_text()
	t.check(text.contains("JAB") and text.contains("1 AP") and text.contains("6"),
		"debug_text() still reports real label text even though the labels are hidden")
	view.free()

## A card with no matching PNG must keep exactly today's appearance: this is
## a real fallback, not defensive padding -- it is what a freshly authored
## card looks like before its art exists.
func _test_art_missing_keeps_fallback_appearance(t: TestRunner) -> void:
	var view: CardView = CardView.create(_no_art_card())

	t.check(view._art.texture == null, "a card with no matching art gets no texture")
	t.check(not view._art.visible, "the art node stays hidden")
	t.check(view._name_label.visible, "the name label stays shown")
	t.check(view._cost_label.visible, "the cost label stays shown")
	t.check(view._text_label.visible, "the rules-text label stays shown")
	t.check(view._background.visible, "the coloured background stays shown")
	t.check(view._border.visible, "the synthetic border stays shown")
	view.free()

## Uses the synthetic no-art card so this exercises the _background lerp
## branch of set_combo_armed() specifically (a jab CardView would take the
## art-modulate branch instead, tested separately below).
func _test_combo_armed_idempotent(t: TestRunner) -> void:
	var view: CardView = CardView.create(_no_art_card())

	view.set_combo_armed(true)
	var once: Color = view._background.color

	view.set_combo_armed(true)
	view.set_combo_armed(true)
	t.check_eq(view._background.color, once, "calling set_combo_armed(true) three times matches calling it once")
	view.free()

## jab has real art, so set_combo_armed() here must take the _art.modulate
## branch, not the (hidden) background. Same regression this guards against
## as the fallback version above: a lerp from the *current* modulate instead
## of a fixed base would drift the tint further gold on every refresh.
func _test_combo_armed_idempotent_with_art(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)

	view.set_combo_armed(true)
	var once: Color = view._art.modulate

	view.set_combo_armed(true)
	view.set_combo_armed(true)
	t.check_eq(view._art.modulate, once, "calling set_combo_armed(true) three times matches calling it once")
	t.check(view._art.modulate != Color.WHITE, "the art is actually tinted while combo-armed")

	view.set_combo_armed(false)
	t.check_eq(view._art.modulate, Color.WHITE, "un-arming returns the art to its untinted colour")
	view.free()
