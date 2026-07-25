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

## Overlapping same-coloured cards otherwise fuse into one shape; this border
## reads as the gap between fanned cards because it matches the page background.
const BORDER_WIDTH: float = 3.0
const BORDER_COLOR: Color = Color(0.05, 0.05, 0.07)

const HOVER_Z: int = 50
const LUNGE_Z: int = 60

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

## The anchor most recently passed to lunge_to(). Test hook, set before the
## is_inside_tree() guard so it is observable even though tests instantiate
## cards detached and never see the tween itself run.
var debug_last_lunge_anchor: Vector2 = Vector2.ZERO

var _hovered: bool = false
var _tween: Tween

## Continuous-motion layers, added on top of the tweened target_* values every
## frame. See _process.
var _idle_phase: float = 0.0
var _idle_offset: Vector2 = Vector2.ZERO
var _idle_rotation: float = 0.0
var _tilt_offset: Vector2 = Vector2.ZERO
var _tilt_rotation: float = 0.0
var _elapsed: float = 0.0
var _lunging: bool = false

var _border: ColorRect
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
	_idle_phase = randf() * TAU
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)

## The live transform is composed from three layers every frame:
##   target_* : absolute values the tweens drive (hover, squash, lunge, deal)
##   idle     : continuous sway, additive, paused while hovered or lunging
##   tilt     : cursor lean, additive, hovered card only
##
## Tweens therefore must NEVER target position/rotation/scale directly — this
## loop would overwrite them every frame and the result would be jitter rather
## than a clean failure.
func _process(delta: float) -> void:
	_elapsed += delta
	_update_idle()
	_update_tilt(delta)
	position = Juice.compose_position(target_position, _idle_offset, _tilt_offset)
	rotation = Juice.compose_rotation(target_rotation, _idle_rotation, _tilt_rotation)
	scale = target_scale

func _update_idle() -> void:
	# Hovering stops the sway: the card being read is the one card holding
	# still. A lunging card is already fully driven by its tween.
	if _hovered or _lunging:
		_idle_offset = Vector2.ZERO
		_idle_rotation = 0.0
		return
	_idle_offset = Juice.idle_offset(_elapsed, _idle_phase)
	_idle_rotation = Juice.idle_rotation(_elapsed, _idle_phase)

## Leans the hovered card toward the cursor, Balatro-style. Only the hovered
## card tilts — cheaper, and unread cards stay still.
func _update_tilt(delta: float) -> void:
	var want_offset := Vector2.ZERO
	var want_rotation: float = 0.0
	if _hovered and not _lunging and is_inside_tree():
		var to_cursor: Vector2 = get_global_mouse_position() - (global_position + CARD_SIZE / 2.0)
		var nx: float = clampf(to_cursor.x / (CARD_SIZE.x * 1.5), -1.0, 1.0)
		var ny: float = clampf(to_cursor.y / (CARD_SIZE.y * 1.5), -1.0, 1.0)
		want_rotation = deg_to_rad(nx * Juice.TILT_MAX_DEG)
		want_offset = Vector2(nx, ny) * Juice.TILT_MAX_PX
	var weight: float = clampf(delta * Juice.TILT_LERP_SPEED, 0.0, 1.0)
	_tilt_offset = _tilt_offset.lerp(want_offset, weight)
	_tilt_rotation = lerpf(_tilt_rotation, want_rotation, weight)

func debug_idle_offset() -> Vector2:
	return _idle_offset

func debug_tilt() -> Vector2:
	return _tilt_offset

func is_lunging() -> bool:
	return _lunging

func _build() -> void:
	_border = ColorRect.new()
	_border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_border.color = BORDER_COLOR
	_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_border)

	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.offset_left = BORDER_WIDTH
	_background.offset_top = BORDER_WIDTH
	_background.offset_right = -BORDER_WIDTH
	_background.offset_bottom = -BORDER_WIDTH
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
		_animate_to(rest_position - Vector2(0.0, Juice.HOVER_LIFT), 0.0, Vector2.ONE * Juice.HOVER_SCALE)
	else:
		z_index = rest_z_index
		_animate_to(rest_position, rest_rotation, Vector2.ONE)
	_update_idle()

## The played-card animation: a short backswing away from the target, then the
## strike. The card must already have been reparented out of HandView.
func lunge_to(anchor: Vector2) -> void:
	debug_last_lunge_anchor = anchor
	_lunging = true
	z_index = LUNGE_Z
	disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		queue_free()
		return

	var centre: Vector2 = target_position + CARD_SIZE / 2.0
	var toward: Vector2 = (anchor - centre).normalized()
	var wind_up: Vector2 = target_position - toward * Juice.ANTICIPATE_DIST

	var tween := create_tween()
	# Anticipation: pull back before striking, so the punch has a windup.
	tween.tween_property(self, "target_position", wind_up, Juice.ANTICIPATE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "target_scale", Juice.SQUASH_SCALE, Juice.ANTICIPATE_TIME)
	# The strike: accelerate into the target, stretched along travel.
	tween.chain().tween_property(self, "target_position", anchor - CARD_SIZE / 2.0, Juice.LUNGE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "target_scale",
		Juice.STRETCH_SCALE * Juice.LUNGE_SCALE, Juice.LUNGE_TIME)
	tween.parallel().tween_property(self, "target_rotation", 0.0, Juice.LUNGE_TIME)
	tween.parallel().tween_property(self, "modulate:a", 0.0, Juice.LUNGE_TIME)
	tween.chain().tween_callback(queue_free)
	_tween = tween

func _animate_to(p_position: Vector2, p_rotation: float, p_scale: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	target_position = p_position
	target_rotation = p_rotation
	target_scale = p_scale
	if not is_inside_tree():
		# No _process off-tree, so snap the live transform for tests.
		position = p_position
		rotation = p_rotation
		scale = p_scale
		return
	_tween = Juice.spring(create_tween())
	_tween.tween_property(self, "target_position", p_position, Juice.HOVER_TIME)
	_tween.parallel().tween_property(self, "target_rotation", p_rotation, Juice.HOVER_TIME)
	_tween.parallel().tween_property(self, "target_scale", p_scale, Juice.HOVER_TIME)

## Compresses the card the instant it is pressed, before anything else happens.
## Immediate physical response to a click is most of what makes it feel good.
func _on_button_down() -> void:
	if not is_inside_tree():
		return
	var tween := create_tween()
	tween.tween_property(self, "target_scale", Juice.SQUASH_SCALE, Juice.SQUASH_TIME)
	tween.tween_property(self, "target_scale",
		Vector2.ONE * Juice.HOVER_SCALE if _hovered else Vector2.ONE, Juice.SQUASH_TIME)

func _on_mouse_entered() -> void:
	apply_hover(true)

func _on_mouse_exited() -> void:
	apply_hover(false)
