class_name HandView
extends Control

## The hand, fanned along an arc. Reports which index was clicked and hands the
## played card off to a detached lunge animation. It decides nothing about
## legality — affordability and combo state come from BattleState.

signal card_chosen(index: int)

const MAX_FAN_ANGLE_DEG: float = 12.0
const FAN_ARCH_HEIGHT: float = 20.0
## Less than CARD_SIZE.x, so cards overlap slightly like a real fan.
const CARD_STEP_X: float = 100.0
const HAND_CENTRE_X: float = 576.0
const HAND_BASE_Y: float = 470.0

## Where a played card flies. Defaults are replaced by BattleView with the real
## fighter panel centres.
var _attack_anchor: Vector2 = Vector2(1000.0, 170.0)
var _defend_anchor: Vector2 = Vector2(130.0, 170.0)

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ignore input itself so clicks fall through to the cards.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_lunge_anchors(attack_anchor: Vector2, defend_anchor: Vector2) -> void:
	_attack_anchor = attack_anchor
	_defend_anchor = defend_anchor

func rebuild(battle: BattleState) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	for index: int in range(battle.deck.hand.size()):
		var view: CardView = CardView.create(battle.deck.hand[index])
		var captured_index: int = index
		view.card_selected.connect(
			func(selected: CardView) -> void: _on_card_selected(captured_index, selected))
		add_child(view)

	layout_cards()
	refresh_states(battle)

## Fans the children along an arc. Derived purely from index and count, so
## calling it repeatedly is idempotent.
func layout_cards() -> void:
	var count: int = get_child_count()
	if count == 0:
		return
	var spread: float = (count - 1) / 2.0 * CARD_STEP_X
	for index: int in range(count):
		var view: CardView = get_child(index) as CardView
		if view == null:
			continue
		var t: float = 0.0 if count == 1 else (2.0 * index / float(count - 1)) - 1.0
		var centre_x: float = HAND_CENTRE_X + t * spread
		var arch: float = 0.0 if count == 1 else (1.0 - t * t) * FAN_ARCH_HEIGHT
		view.set_rest_transform(
			Vector2(centre_x - CardView.CARD_SIZE.x / 2.0, HAND_BASE_Y - arch),
			deg_to_rad(t * MAX_FAN_ANGLE_DEG),
			index)

## Updates affordability dimming and combo highlights without rebuilding.
func refresh_states(battle: BattleState) -> void:
	for index: int in range(get_child_count()):
		var view: CardView = get_child(index) as CardView
		if view == null:
			continue
		view.set_affordable(battle.can_play(index))
		view.set_combo_armed(battle.combo_bonus_for(index) > 0)

func clear_hover() -> void:
	for child: Node in get_children():
		var view: CardView = child as CardView
		if view != null:
			view.apply_hover(false)

## A disabled Button emits no `pressed` signal, and set_affordable() mirrors
## battle.can_play(), so only legal plays reach here. Do NOT add a rules check —
## that would put game logic in the view.
func _on_card_selected(index: int, view: CardView) -> void:
	_launch(view)
	card_chosen.emit(index)

## Reparents the card out of the hand before animating it. Two reasons: the
## rebuild triggered by playing it would otherwise free the node mid-tween, and
## HandView's children must stay exactly equal to the cards in hand.
func _launch(view: CardView) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var anchor: Vector2 = _attack_anchor
	if view.card != null and view.card.has_tag(&"defense"):
		anchor = _defend_anchor
	var handover_position: Vector2 = view.position + position
	remove_child(view)
	host.add_child(view)
	view.position = handover_position
	view.lunge_to(anchor)
