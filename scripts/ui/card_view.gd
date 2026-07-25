class_name CardView
extends Button

## One card, rendered as a labelled rectangle. Knows how to draw a card and
## report clicks; knows nothing about whether playing it is legal.

signal card_selected(view: CardView)

const CARD_SIZE: Vector2 = Vector2(120, 170)
const ATTACK_COLOR: Color = Color(0.32, 0.16, 0.16)
const DEFENSE_COLOR: Color = Color(0.16, 0.20, 0.32)
const COMBO_BORDER_COLOR: Color = Color(1.0, 0.80, 0.20)
const UNAFFORDABLE_ALPHA: float = 0.45

var card: CardData

var _background: ColorRect
var _name_label: Label
var _cost_label: Label
var _text_label: Label

static func create(p_card: CardData) -> CardView:
	var view := CardView.new()
	view.configure(p_card)
	return view

func _init() -> void:
	custom_minimum_size = CARD_SIZE
	flat = true
	clip_contents = true
	_build()

func _build() -> void:
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_top = 8
	column.offset_right = -8
	column.offset_bottom = -8
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_name_label = _make_label(18)
	column.add_child(_name_label)

	_cost_label = _make_label(14)
	_cost_label.modulate = Color(0.85, 0.85, 0.60)
	column.add_child(_cost_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_text_label = _make_label(13)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text_label)

	pressed.connect(_on_pressed)

func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func configure(p_card: CardData) -> void:
	card = p_card
	if card == null:
		return
	_name_label.text = card.display_name
	_cost_label.text = "%d AP" % card.cost
	_text_label.text = _rules_text()
	_background.color = DEFENSE_COLOR if card.has_tag(&"defense") else ATTACK_COLOR
	set_combo_armed(false)

func _rules_text() -> String:
	if not card.rules_text.is_empty():
		return card.rules_text
	var parts: Array[String] = []
	for effect: CardEffect in card.effects:
		var description: String = effect.describe()
		if not description.is_empty():
			parts.append(description)
	return " ".join(parts)

func set_affordable(value: bool) -> void:
	disabled = not value
	modulate.a = 1.0 if value else UNAFFORDABLE_ALPHA

func set_combo_armed(value: bool) -> void:
	if value:
		add_theme_constant_override("outline_size", 3)
		_background.color = _background.color.lerp(COMBO_BORDER_COLOR, 0.25)
	else:
		remove_theme_constant_override("outline_size")
		if card != null:
			_background.color = DEFENSE_COLOR if card.has_tag(&"defense") else ATTACK_COLOR

## Everything the card displays, for tests.
func debug_text() -> String:
	return "%s | %s | %s" % [_name_label.text, _cost_label.text, _text_label.text]

func _on_pressed() -> void:
	card_selected.emit(self)
