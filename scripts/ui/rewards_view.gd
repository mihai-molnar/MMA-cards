class_name RewardsView
extends Control

## Full-screen reward chooser after a won fight (run not complete): pick one
## card to add to the run deck, or skip. Modelled on PileView: a full-rect
## modal overlay (STOP mouse filter), real CardViews with the same absolute
## hover zoom so rules text reads at hand size, and hover relayed outward so
## BattleView can drive the keyword tooltip -- this screen is where the
## player first reads Burn, STR and Prepared, so the tooltips matter here.
## Continue/Skip are plain Buttons ON PURPOSE: placeholder until real art
## exists (the End Turn plate treatment is the model to follow then).

signal finished(card_id: StringName)
signal card_hovered(view: CardView, hovered: bool)

## Same reasoning as PileView.PILE_Z: covers every resting battle element
## while a hovered card (REWARDS_Z + HOVER_Z = 60) stays under the tooltip's
## 70. Raising this above 20 silently puts hovered cards over their tooltips.
const REWARDS_Z: int = 10

const CANVAS: Vector2 = Vector2(1152, 648)
## Bigger than PileView's 0.55: three cards are the whole show here.
const CARD_REST_SCALE: float = 0.7
## The selected card sits visibly proud of its neighbours; the armed-frame
## tint (set_combo_armed) carries the state at a glance. Judged from the
## rewards capture, not from these numbers.
const SELECTED_SCALE: float = 0.78
const CARD_GAP: float = 48.0
const CARD_TOP: float = 170.0
const TITLE_Y: float = 60.0
const BUTTON_Y: float = 560.0
const BUTTON_SIZE: Vector2 = Vector2(180, 48)

var _background: TextureRect
var _title: Label
var _row: Control
var _continue_button: Button
var _skip_button: Button
var _card_views: Array = []
var _selected: CardView = null

func _init() -> void:
	visible = false
	z_index = REWARDS_Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.texture = CardArt.background_for(&"rewards_bg")
	# stretch/expand BEFORE position/size -- see FighterPanel._make_icon.
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_title = Label.new()
	HudText.style(_title, 28)
	_title.text = "CHOOSE A CARD"
	_title.position = Vector2(0.0, TITLE_Y)
	_title.size = Vector2(CANVAS.x, 36.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# IGNORE on the row, so each CardView is hit-tested on its own.
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_continue_button = _make_button("CONTINUE", Vector2(CANVAS.x / 2.0 + 20.0, BUTTON_Y))
	_continue_button.disabled = true
	_continue_button.pressed.connect(_on_continue_pressed)
	_skip_button = _make_button("SKIP", Vector2(CANVAS.x / 2.0 - BUTTON_SIZE.x - 20.0, BUTTON_Y))
	_skip_button.pressed.connect(_on_skip_pressed)

func _make_button(text: String, at: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.custom_minimum_size = BUTTON_SIZE
	# No keyboard nav anywhere in the game: a focused button wears Godot's
	# default white focus rectangle, which reads as a rendering glitch.
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

## Rebuilds the offer row and shows the view. Safe to call while open.
func open(card_ids: Array[StringName]) -> void:
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.free()
	_card_views = []
	_selected = null
	_continue_button.disabled = true

	for i: int in range(card_ids.size()):
		var view: CardView = CardView.create(CardLibrary.load_card(card_ids[i]))
		view.card_selected.connect(_on_card_clicked)
		view.hover_changed.connect(func(v: CardView, hovered: bool) -> void:
			card_hovered.emit(v, hovered))
		_row.add_child(view)
		view.set_rest_transform(_rest_for(i, card_ids.size()), 0.0, i, CARD_REST_SCALE)
		_card_views.append(view)
	visible = true

## Where card `index` of `count` rests -- the row is centred on the canvas,
## and the card scales about its bottom-centre pivot, so the rest point is
## the SAME for every scale: x centres the unscaled rect on the cell, y puts
## the unscaled bottom on the cell's bottom (same arithmetic as PileView's
## grid, minus its scale-dependent offset -- anchoring the pivot at the cell
## bottom is what lets a selected card grow in place).
func _rest_for(index: int, count: int) -> Vector2:
	var cell: Vector2 = CardView.CARD_SIZE * CARD_REST_SCALE
	var row_width: float = count * cell.x + (count - 1) * CARD_GAP
	var cell_left: float = (CANVAS.x - row_width) / 2.0 + index * (cell.x + CARD_GAP)
	return Vector2(
		cell_left + cell.x / 2.0 - CardView.CARD_SIZE.x / 2.0,
		CARD_TOP + cell.y - CardView.CARD_SIZE.y)

func _on_card_clicked(view: CardView) -> void:
	_selected = null if _selected == view else view
	for i: int in range(_card_views.size()):
		var card_view: CardView = _card_views[i]
		var chosen: bool = card_view == _selected
		# The armed-frame tint doubles as the selection tint: same "this card
		# is charged" read, already verified legible on both colourways.
		card_view.set_combo_armed(chosen)
		card_view.set_rest_transform(_rest_for(i, _card_views.size()), 0.0, i,
			SELECTED_SCALE if chosen else CARD_REST_SCALE)
	_continue_button.disabled = _selected == null

func _on_continue_pressed() -> void:
	if _selected == null:
		return
	var chosen_id: StringName = _selected.card.id
	visible = false
	finished.emit(chosen_id)

func _on_skip_pressed() -> void:
	visible = false
	finished.emit(&"")

## Silent hide for transitions, mirroring PileView.dismiss().
func dismiss() -> void:
	visible = false

func debug_card_views() -> Array:
	return _card_views

func debug_continue_button() -> Button:
	return _continue_button

func debug_skip_button() -> Button:
	return _skip_button

func debug_selected_id() -> StringName:
	return _selected.card.id if _selected != null else &""
