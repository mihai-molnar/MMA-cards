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

const HOVER_LIFT: float = 28.0
const HOVER_SCALE: float = 1.08
const HOVER_TIME: float = 0.12
const HOVER_Z: int = 50
const LUNGE_Z: int = 60
const LUNGE_TIME: float = 0.28
const LUNGE_SCALE: float = 1.15

var card: CardData

## Where this card sits when not hovered. HandView sets these when it fans.
var rest_position: Vector2 = Vector2.ZERO
var rest_rotation: float = 0.0
var rest_z_index: int = 0

## Where the current animation is heading. Tweens need real frames, which
## headless tests do not have, so tests assert these rather than the live
## transform. Always recomputed from rest_*, so hovering cannot drift.
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE

var _hovered: bool = false
var _tween: Tween

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
	size = CARD_SIZE
	# Bottom-centre, so rotation reads as a held fan rather than a pinwheel.
	pivot_offset = Vector2(CARD_SIZE.x / 2.0, CARD_SIZE.y)
	flat = true
	clip_contents = true
	_build()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

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

## Base (non-armed) background color for the current card.
func _base_color() -> Color:
	if card == null:
		return ATTACK_COLOR
	return DEFENSE_COLOR if card.has_tag(&"defense") else ATTACK_COLOR

## Idempotent: always computed from the base color, so calling this N times
## with the same value equals calling it once. refresh_states() calls this
## once per model event, so drifting from repeated lerps would compound.
func set_combo_armed(value: bool) -> void:
	if value:
		add_theme_constant_override("outline_size", 3)
		_background.color = _base_color().lerp(COMBO_BORDER_COLOR, 0.25)
	else:
		remove_theme_constant_override("outline_size")
		_background.color = _base_color()

## Everything the card displays, for tests.
func debug_text() -> String:
	return "%s | %s | %s" % [_name_label.text, _cost_label.text, _text_label.text]

func _on_pressed() -> void:
	card_selected.emit(self)

## Called by HandView when it fans the hand. Snaps immediately unless the card
## is mid-hover, so a rebuild never yanks a lifted card out from under the cursor.
func set_rest_transform(p_position: Vector2, p_rotation: float, p_z_index: int) -> void:
	rest_position = p_position
	rest_rotation = p_rotation
	rest_z_index = p_z_index
	if _hovered:
		return
	target_position = p_position
	target_rotation = p_rotation
	target_scale = Vector2.ONE
	position = p_position
	rotation = p_rotation
	scale = Vector2.ONE
	z_index = p_z_index

## Named is_card_hovered() rather than is_hovered(): BaseButton (our ancestor)
## already defines a native is_hovered() backed by the engine's own mouse
## tracking. GDScript cannot actually override it — calls resolve to the native
## getter regardless of a script method of the same name, so a same-named
## override silently returns the wrong value (confirmed: it kept reading false
## after apply_hover(true) in headless tests, which never generate real mouse
## input). This is a script-level notion of "hover" driven entirely by
## apply_hover(), which is why it needs its own name.
func is_card_hovered() -> bool:
	return _hovered

## Exposed separately from the mouse signals so tests can drive hover without
## synthesising input events.
func apply_hover(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	if value:
		z_index = HOVER_Z
		_animate_to(rest_position - Vector2(0.0, HOVER_LIFT), 0.0, Vector2.ONE * HOVER_SCALE)
	else:
		z_index = rest_z_index
		_animate_to(rest_position, rest_rotation, Vector2.ONE)

## The played-card animation. The card must already have been reparented out of
## HandView, or the imminent rebuild will free it mid-tween.
func lunge_to(anchor: Vector2) -> void:
	z_index = LUNGE_Z
	disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(self, "position", anchor - CARD_SIZE / 2.0, LUNGE_TIME)
	tween.parallel().tween_property(self, "scale", Vector2.ONE * LUNGE_SCALE, LUNGE_TIME)
	tween.parallel().tween_property(self, "rotation", 0.0, LUNGE_TIME)
	tween.parallel().tween_property(self, "modulate:a", 0.0, LUNGE_TIME)
	tween.chain().tween_callback(queue_free)

func _animate_to(p_position: Vector2, p_rotation: float, p_scale: Vector2) -> void:
	target_position = p_position
	target_rotation = p_rotation
	target_scale = p_scale
	if not is_inside_tree():
		position = p_position
		rotation = p_rotation
		scale = p_scale
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", p_position, HOVER_TIME)
	_tween.parallel().tween_property(self, "rotation", p_rotation, HOVER_TIME)
	_tween.parallel().tween_property(self, "scale", p_scale, HOVER_TIME)

func _on_mouse_entered() -> void:
	apply_hover(true)

func _on_mouse_exited() -> void:
	apply_hover(false)
