class_name HandView
extends HBoxContainer

## The row of cards in hand. Rebuilds from BattleState and reports which index
## was clicked; it does not decide whether the play is legal.

signal card_chosen(index: int)

const CARD_SPACING: int = 12

func _init() -> void:
	add_theme_constant_override("separation", CARD_SPACING)
	alignment = BoxContainer.ALIGNMENT_CENTER

func rebuild(battle: BattleState) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	for index: int in range(battle.deck.hand.size()):
		var view: CardView = CardView.create(battle.deck.hand[index])
		var captured_index: int = index
		view.card_selected.connect(func(_v: CardView) -> void: card_chosen.emit(captured_index))
		add_child(view)

	refresh_states(battle)

## Updates affordability dimming and combo highlights without rebuilding.
func refresh_states(battle: BattleState) -> void:
	for index: int in range(get_child_count()):
		var view: CardView = get_child(index) as CardView
		if view == null:
			continue
		view.set_affordable(battle.can_play(index))
		view.set_combo_armed(battle.combo_bonus_for(index) > 0)
