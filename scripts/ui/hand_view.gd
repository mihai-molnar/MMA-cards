class_name HandView
extends Control

## The hand, fanned along an arc. Reports which index was clicked and hands the
## played card off to a detached lunge animation. It decides nothing about
## legality — affordability and combo state come from BattleState.

signal card_chosen(index: int)

const MAX_FAN_ANGLE_DEG: float = 12.0
const FAN_ARCH_HEIGHT: float = 20.0
## Less than CARD_SIZE.x, so cards overlap slightly like a real fan.
##
## Chosen from the art's own margins, not CARD_SIZE.x: the card images carry
## a wide transparent glow border, so the *visible* card body is narrower
## than the CardView rect. Measured across all three source images the solid
## body spans ~852 of 1024px width, i.e. ~83.2% (x[85..937] for card_jab.png,
## similar for the other two). At CARD_SIZE.x = 156 (cards were enlarged 30%
## from an original 120px rect, keeping the 2:3 aspect) that is a visible
## body of 156 * (852.0 / 1024.0) ≈ 129.8px. This value overlaps those
## visible bodies by 129.8 - 116 ≈ 13.8px -- matching the ~13.8px overlap the
## fan had at the original size (86px step against a 99.8px visible body at
## CARD_SIZE.x = 120), so the fan reads the same regardless of card size.
const CARD_STEP_X: float = 116.0
const HAND_CENTRE_X: float = 576.0
## Bottom-most point of a tilted outer card must stay inside the 648-tall
## design space: HAND_BASE_Y + CARD_SIZE.y + (CARD_SIZE.x / 2) *
## sin(MAX_FAN_ANGLE_DEG) = 377 + 234 + 78 * sin(12deg) ≈ 627.2, leaving
## ~21px of margin. See test_hand_arc.gd's
## _test_layout_invariants_across_hand_sizes for the assertion.
const HAND_BASE_Y: float = 377.0

## Where a played card flies. Defaults are replaced by BattleView with the real
## fighter panel centres.
var _attack_anchor: Vector2 = Vector2(1000.0, 170.0)
var _defend_anchor: Vector2 = Vector2(130.0, 170.0)

## Set while a click is being resolved: the card has been pulled out of the
## hand and is waiting to hear whether the play landed. launch_play() claims
## it to send it flying; if nothing has claimed it by the time
## _on_card_selected returns, the play was rejected and the card is put back.
var _pending_view: CardView = null
var _pending_index: int = -1

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Ignore input itself so clicks fall through to the cards.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_lunge_anchors(attack_anchor: Vector2, defend_anchor: Vector2) -> void:
	_attack_anchor = attack_anchor
	_defend_anchor = defend_anchor

## `deal` is true only when a genuinely new hand has arrived (BattleView passes
## it on turn_started). An ordinary hand_changed rebuild -- e.g. after playing
## a single card -- must default to false: without that, every play rebuilds
## the whole hand and dealt every remaining card in again, dropping it off the
## bottom of the screen and flying it back for a card that never left.
func rebuild(battle: BattleState, deal: bool = false) -> void:
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
	if deal:
		deal_in()

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
## battle.can_play(), so today every click that reaches here is legal. Even
## so, the card does not depart until BattleView confirms play_card()
## accepted it (see launch_play) -- Do NOT add a rules check here. HandView
## still does not decide legality, it only waits to be told the outcome.
func _on_card_selected(index: int, view: CardView) -> void:
	_hand_off(view, index)
	card_chosen.emit(index)
	# card_chosen is handled synchronously: if a confirmed play were coming,
	# launch_play() would already have claimed _pending_view above. Nothing
	# claiming it means the play was rejected, so put the card back.
	if _pending_view != null:
		_return_pending()

## Pulls the card out of the hand and marks it pending, before the model
## update a confirmed play would trigger. Two reasons: hand_changed fires
## synchronously from inside battle.play_card() and would free an in-place
## child mid-tween, and HandView's children must stay exactly equal to the
## cards in hand. Nothing is animated yet -- that only happens if
## launch_play() claims this card below.
func _hand_off(view: CardView, index: int) -> void:
	var host: Node = get_parent()
	if host == null:
		return
	# Derived from target_position -- the composed source of truth _process
	# reads from -- not the live `position`, which also carries the idle-sway
	# and cursor-tilt offsets. Writing those into target_position would bake
	# them in permanently; only _process may write `position` (see
	# card_view.gd). `position` (HandView's own) compensates for the
	# coordinate-space change from reparenting into `host`; it is only ever
	# (0, 0) today, but this keeps the handoff correct if that changes.
	var handover_position: Vector2 = view.target_position + position
	remove_child(view)
	host.add_child(view)
	view.target_position = handover_position
	_pending_view = view
	_pending_index = index

## Called by BattleView once battle.play_card(index) has returned true. Only
## now does the card actually leave -- a rejected play never reaches here, so
## the lunge animation never runs for it.
func launch_play(index: int) -> void:
	if _pending_view == null or _pending_index != index:
		return
	var view: CardView = _pending_view
	_pending_view = null
	_pending_index = -1
	var anchor: Vector2 = _attack_anchor
	if view.card != null and view.card.has_tag(&"defense"):
		anchor = _defend_anchor
	view.lunge_to(anchor)

## The play was rejected: put the card back exactly where it was, including
## its original position among its siblings.
func _return_pending() -> void:
	var view: CardView = _pending_view
	var index: int = _pending_index
	_pending_view = null
	_pending_index = -1
	var host: Node = get_parent()
	if host != null:
		host.remove_child(view)
	add_child(view)
	move_child(view, index)
	view.set_rest_transform(view.rest_position, view.rest_rotation, view.rest_z_index)

## Flies the hand in from below, one card at a time, so a new hand arrives
## rather than appearing. Each card springs from DEAL_FROM_BELOW up into its
## slot, staggered by DEAL_STAGGER.
##
## Off-tree (in tests) there is no tween, so the cards are simply left at rest —
## the invariant either way is that every card ends at its rest position.
func deal_in() -> void:
	if not is_inside_tree():
		return
	for index: int in range(get_child_count()):
		var view: CardView = get_child(index) as CardView
		if view == null:
			continue
		var landed: Vector2 = view.rest_position
		view.target_position = landed + Vector2(0.0, Juice.DEAL_FROM_BELOW)
		view.position = view.target_position
		view.spring_to(landed, index * Juice.DEAL_STAGGER)
