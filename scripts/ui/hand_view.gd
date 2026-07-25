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
## similar for the other two). At CARD_SIZE.x = 200 (the reflow that made
## room for larger cards -- see CardView.CARD_SIZE) that is a visible body of
## 200 * (852.0 / 1024.0) ≈ 166.4px.
##
## Raised from 100 to 140 in the same reflow, keeping proportionally similar
## overlap: 166.4 - 140 ≈ 26.4px (~16% of the visible body, close to the old
## step's ~23% at the smaller card size). The rotation-aware clearance this
## depends on is documented at rotated_right_edge() below and re-verified in
## BattleHud.END_TURN_AT's own doc comment -- at CARD_STEP_X = 140 the
## rightmost card's true right edge crosses END_TURN_AT.y (570) at x ≈ 967,
## 18px clear of the button's new left edge (985).
const CARD_STEP_X: float = 140.0
const HAND_CENTRE_X: float = 576.0
## Bottom-most point of a tilted outer card must stay inside the 648-tall
## design space: HAND_BASE_Y + CARD_SIZE.y + (CARD_SIZE.x / 2) *
## sin(MAX_FAN_ANGLE_DEG) = 311 + 300 + 100 * sin(12deg) ≈ 631.8, leaving
## ~16px of margin. See test_hand_arc.gd's
## _test_layout_invariants_across_hand_sizes for the assertion.
##
## Also the reflow's other binding vertical check: a hovered *outer* card
## straightens (rotation -> 0) and lifts by Juice.HOVER_LIFT while scaling up
## by Juice.HOVER_SCALE about its bottom-centre pivot, so its top edge
## reaches HAND_BASE_Y - HOVER_LIFT - CARD_SIZE.y * (HOVER_SCALE - 1) =
## 311 - 34 - 36 = 241. BattleHud's fighter panels end at y = 232
## (PLAYER_PANEL_AT.y + FighterPanel.PANEL_SIZE.y), so that is only 9px of
## clearance -- tight, but confirmed clear; see test_hand_arc.gd.
const HAND_BASE_Y: float = 311.0

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
	# Recorded before freeing, keyed by CardData identity -- CardLibrary.
	# load_card() duplicates a fresh instance per deck entry, so every card in
	# hand is a distinct object and this holds even for two copies of the same
	# card id. The played card itself is never a HandView child by this point
	# (_hand_off reparents it out the moment it is clicked, well before
	# battle.play_card() triggers this rebuild), so it is never captured here
	# and never a candidate to re-fan.
	var previous_positions: Dictionary = {}
	for child: Node in get_children():
		var view: CardView = child as CardView
		if view != null and view.card != null:
			previous_positions[view.card] = view.target_position
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
	else:
		_refan_survivors(previous_positions)

## Slides every surviving card from its pre-rebuild position to its freshly
## laid-out rest slot, staggered slightly so the fan resettles organically
## rather than as one rigid block. A card whose CardData is not in
## `previous_positions` is genuinely new this rebuild (just drawn) and keeps
## ordinary rest placement -- slide_from() is simply never called for it.
func _refan_survivors(previous_positions: Dictionary) -> void:
	var stagger_index: int = 0
	for child: Node in get_children():
		var view: CardView = child as CardView
		if view == null or view.card == null:
			continue
		if not previous_positions.has(view.card):
			continue
		var start: Vector2 = previous_positions[view.card]
		view.slide_from(start, stagger_index * Juice.REFAN_STAGGER)
		stagger_index += 1

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

## True rightmost point of a card whose unrotated rect's left edge sits at
## `rect_x`, once rotated by `rotation_rad` about its bottom-centre pivot
## (see CardView.pivot_offset). `rect_x + CARD_SIZE.x` -- the axis-aligned
## box edge every clearance check used to use -- understates this: the top
## outer corner swings past the box as the card tilts. At MAX_FAN_ANGLE_DEG
## (12deg) on a 156x234 card the true corner sits ~47px right of the box
## edge, which is how the rightmost card in the fan came to overlap the AP
## label and End Turn button despite every existing check reporting
## clearance. Any clearance assertion against the fan's outer edge must use
## this, not the raw rect. (Cards later grew to 200x300 for the larger-card
## reflow -- see CardView.CARD_SIZE and CARD_STEP_X above -- but the same
## principle and the same helper apply; only the numbers changed.)
static func rotated_right_edge(rect_x: float, rotation_rad: float) -> float:
	var half_width: float = CardView.CARD_SIZE.x / 2.0
	var pivot_x: float = rect_x + half_width
	var corner_offset: float = half_width * cos(rotation_rad) + CardView.CARD_SIZE.y * sin(rotation_rad)
	return pivot_x + corner_offset

## Mirror of rotated_right_edge() for the leftmost card, which rotates the
## other way (negative rotation_rad) and so swings its top-outer corner past
## the box to the *left* by the same magnitude.
static func rotated_left_edge(rect_x: float, rotation_rad: float) -> float:
	var half_width: float = CardView.CARD_SIZE.x / 2.0
	var pivot_x: float = rect_x + half_width
	var corner_offset: float = half_width * cos(rotation_rad) - CardView.CARD_SIZE.y * sin(rotation_rad)
	return pivot_x - corner_offset

## The card's four corners once rotated by `rotation_rad` about its
## bottom-centre pivot, for a card whose unrotated rect has its top-left at
## (rect_x, card_y). Order: top-left, top-right, bottom-left, bottom-right.
## rotated_right_edge()/rotated_left_edge() above only ever needed the outer
## top corner's x, because the controls they were checked against (the old,
## taller End Turn button) spanned the card's entire relevant height. The
## reflow's controls are short and sit low, occupying only part of the fan's
## height, so a clearance check against them needs to know where the card's
## edge actually is at that control's y -- which needs all four corners, not
## just the single furthest-reaching one.
static func rotated_corners(rect_x: float, card_y: float, rotation_rad: float) -> Array[Vector2]:
	var half_width: float = CardView.CARD_SIZE.x / 2.0
	var height: float = CardView.CARD_SIZE.y
	var pivot: Vector2 = Vector2(rect_x + half_width, card_y + height)
	var locals: Array[Vector2] = [
		Vector2(-half_width, -height), Vector2(half_width, -height),
		Vector2(-half_width, 0.0), Vector2(half_width, 0.0),
	]
	var corners: Array[Vector2] = []
	for local: Vector2 in locals:
		corners.append(pivot + local.rotated(rotation_rad))
	return corners

## X of the card's right-side edge -- the straight line between its rotated
## top-right and bottom-right corners -- at a given `at_y`. Clamped to the
## segment between the two corners. Use this instead of rotated_right_edge()
## whenever the control being checked does not span the card's whole height:
## rotated_right_edge() reports the single furthest-right point (the
## top-right corner), which for a tilted card sits well above a short,
## low control like End Turn and overstates what actually needs to clear it.
static func rotated_right_edge_at_y(rect_x: float, card_y: float, rotation_rad: float, at_y: float) -> float:
	var corners: Array[Vector2] = rotated_corners(rect_x, card_y, rotation_rad)
	var top_right: Vector2 = corners[1]
	var bottom_right: Vector2 = corners[3]
	if is_equal_approx(top_right.y, bottom_right.y):
		return maxf(top_right.x, bottom_right.x)
	var frac: float = clampf((at_y - top_right.y) / (bottom_right.y - top_right.y), 0.0, 1.0)
	return lerpf(top_right.x, bottom_right.x, frac)

## Mirror of rotated_right_edge_at_y() for the card's left-side edge (the
## line between its rotated top-left and bottom-left corners).
static func rotated_left_edge_at_y(rect_x: float, card_y: float, rotation_rad: float, at_y: float) -> float:
	var corners: Array[Vector2] = rotated_corners(rect_x, card_y, rotation_rad)
	var top_left: Vector2 = corners[0]
	var bottom_left: Vector2 = corners[2]
	if is_equal_approx(top_left.y, bottom_left.y):
		return minf(top_left.x, bottom_left.x)
	var frac: float = clampf((at_y - top_left.y) / (bottom_left.y - top_left.y), 0.0, 1.0)
	return lerpf(top_left.x, bottom_left.x, frac)

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
