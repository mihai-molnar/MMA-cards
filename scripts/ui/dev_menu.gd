class_name DevMenu
extends Control

## DEV ONLY overlay, toggled by the backquote key in BattleView: every
## library card in a grid; clicking one plays it instantly through
## BattleState.dev_play -- no AP, no hand. Modeled on PileView: modal
## full-rect, dimmed octagon backdrop, real CardViews, and the same z cake
## (MENU_Z 10 + HOVER_Z 50 keeps a hovered card under the tooltip's 70).
## The menu stays open after a pick, so effects can be spammed for testing.

signal closed
signal card_picked(card: CardData)
signal card_hovered(view: CardView, hovered: bool)

const MENU_Z: int = 10
const CANVAS: Vector2 = Vector2(1152, 648)
const CARD_REST_SCALE: float = 0.55
const COLUMNS: int = 5
const CARD_GAP: Vector2 = Vector2(24.0, 24.0)
const GRID_TOP: float = 92.0
const TITLE_Y: float = 28.0
const CLOSE_SIZE: float = 64.0
const CLOSE_MARGIN: float = 16.0
## The octagon is the fight's own backdrop; dimming it here is what reads
## as "a different screen" rather than a frozen fight.
const BG_DIM: Color = Color(0.45, 0.45, 0.5)

var _background: TextureRect
var _title: Label
var _close_button: TextureButton
var _grid: Control
var _card_views: Array = []

func _init() -> void:
	visible = false
	z_index = MENU_Z
	# Modal: swallow every click that is not a grid card or the close button.
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.texture = CardArt.background_for(&"octagon")
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.self_modulate = BG_DIM
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_title = Label.new()
	HudText.style(_title, 24)
	_title.text = "DEV: PLAY ANY CARD"
	_title.position = Vector2(0.0, TITLE_Y)
	_title.size = Vector2(CANVAS.x, 32.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# IGNORE on the grid, so each CardView is hit-tested on its own.
	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)

	_close_button = TextureButton.new()
	_close_button.texture_normal = CardArt.ui_icon_for(&"close_button")
	_close_button.texture_pressed = CardArt.ui_icon_for(&"close_button_clicked")
	_close_button.ignore_texture_size = true
	_close_button.stretch_mode = TextureButton.STRETCH_SCALE
	_close_button.position = Vector2(CANVAS.x - CLOSE_SIZE - CLOSE_MARGIN, CLOSE_MARGIN)
	_close_button.size = Vector2.ONE * CLOSE_SIZE
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_close_button.pressed.connect(close)
	add_child(_close_button)

## Rebuilds the grid for `cards` and shows the view. Safe to call while
## already open (pressing backquote again while spamming re-targets in
## place).
func open(cards: Array[CardData]) -> void:
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	_card_views = []

	var sorted: Array[CardData] = cards.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		return a.display_name < b.display_name)

	var cell: Vector2 = CardView.CARD_SIZE * CARD_REST_SCALE
	var grid_width: float = COLUMNS * cell.x + (COLUMNS - 1) * CARD_GAP.x
	var grid_left: float = (CANVAS.x - grid_width) / 2.0
	for i: int in range(sorted.size()):
		var view: CardView = CardView.create(sorted[i])
		view.hover_changed.connect(_on_card_hover_changed)
		view.card_selected.connect(_on_card_selected)
		_grid.add_child(view)
		var visual := Vector2(
			grid_left + (i % COLUMNS) * (cell.x + CARD_GAP.x),
			GRID_TOP + float(i / COLUMNS) * (cell.y + CARD_GAP.y))
		# The card scales about its bottom-centre pivot, so the unscaled
		# rect's top-left must be offset for the visual rect to land on the
		# cell.
		var rest := Vector2(
			visual.x - CardView.CARD_SIZE.x * (1.0 - CARD_REST_SCALE) / 2.0,
			visual.y - CardView.CARD_SIZE.y * (1.0 - CARD_REST_SCALE))
		view.set_rest_transform(rest, 0.0, i, CARD_REST_SCALE)
		_card_views.append(view)
	visible = true

## The close button's path: hide and tell BattleView (click sound, tooltip
## cleanup live there).
func close() -> void:
	visible = false
	closed.emit()

## Silent hide for fight transitions -- no closed signal, so no click sound
## plays over the slam.
func dismiss() -> void:
	visible = false

func _on_card_hover_changed(view: CardView, hovered: bool) -> void:
	card_hovered.emit(view, hovered)

func _on_card_selected(view: CardView) -> void:
	card_picked.emit(view.card)

func debug_card_ids() -> Array:
	var ids: Array = []
	for view: CardView in _card_views:
		ids.append(view.card.id)
	return ids

func debug_card_views() -> Array:
	return _card_views

func debug_title() -> String:
	return _title.text

func debug_close_button() -> TextureButton:
	return _close_button
