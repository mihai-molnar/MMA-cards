class_name FighterPanel
extends Control

## One fighter's HP heart, AP bolt, guard badge and status badges, plus every
## bit of damage feedback. Instantiated twice — player on the left, enemy on
## the right, mirrored by `align_right` — so the animation exists once rather
## than in two copies that can drift apart.
##
## `fighters_changed` carries no payload, so rather than changing BattleState for a
## cosmetic feature this panel remembers the previous hp/guard and diffs them.

const PANEL_SIZE: Vector2 = Vector2(210, 176)
const ICON_SIZE: float = 72.0
const AP_ICON_SIZE: float = 56.0
const STATUS_ICON_SIZE: float = 24.0
const STATUS_ICON_GAP: float = 4.0

const DAMAGE_FLASH: Color = Color(1.0, 0.35, 0.35)
const GUARD_FLASH: Color = Color(0.55, 0.85, 1.0)
const STATUS_COLOR: Color = Color(1.0, 0.82, 0.40)

## Fraction of the icon's width treated as its "dark window" for
## _layout_value_label's fitting rule. Measured against the Kreon display
## font actually rendered here (HudText.FONT), not guessed: "50 / 50" at the
## hp value's size 16 is 51px wide, which a smaller fraction (e.g. 0.62,
## 44.6px at ICON_SIZE) would wrongly flag as overflowing a perfectly
## ordinary two-digit/two-digit reading.
const VALUE_WINDOW_FRACTION: float = 0.75

var align_right: bool = false

## What the most recent update() decided. Test hooks — the animation reads the
## same values, so asserting these asserts the real decision.
var debug_last_pulse_kind: StringName = &"none"
var debug_last_pulse_amount: int = 0

var _status_label: Label
## Icon + countdown badges for statuses that have an icon asset, sitting
## in a row below the icon cluster. Parented to the icon cluster so the
## damage shake carries them.
var _status_icon_row: HBoxContainer
## What the row currently displays, as [[id, number], ...]. Test hook.
var _status_icon_entries: Array = []

var _fighter_name: String = ""
var _show_ap: bool = false
var _icon_cluster: Control
var _hp_icon: TextureRect
var _hp_value: Label
var _guard_label: Label
var _ap_icon: TextureRect
var _ap_value: Label = null
## The cluster's rest position -- what every shake returns to.
var _cluster_home: Vector2 = Vector2.ZERO
var _cluster_tween: Tween

var _last_hp: int = -1
var _last_guard: int = 0
var _suppress_guard_pulse: bool = false

static func create(display_name: String, p_align_right: bool, p_show_ap: bool) -> FighterPanel:
	var panel := FighterPanel.new()
	panel.align_right = p_align_right
	panel._show_ap = p_show_ap
	panel._fighter_name = display_name.to_upper()
	panel._build()
	return panel

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Delegates to Juice so every tuning value lives in one file. Kept as a static
## on FighterPanel because tests and callers already reference it here.
static func shake_amplitude(amount: int) -> float:
	return Juice.rect_shake_amplitude(amount)

## The panel is built once with a placeholder name; the run swaps in each
## opponent's real name at fight start.
func set_fighter_name(p_name: String) -> void:
	_fighter_name = p_name.to_upper()

func fighter_name() -> String:
	return _fighter_name

func _build() -> void:
	var icon_x: float = PANEL_SIZE.x - ICON_SIZE if align_right else 0.0

	# Everything that shakes on a hit lives in one cluster with one stored
	# home -- the icon stands in for the old fighter rectangle.
	_icon_cluster = Control.new()
	_icon_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.size = PANEL_SIZE
	_cluster_home = _icon_cluster.position
	add_child(_icon_cluster)

	_hp_icon = _make_icon(&"hp", Vector2(icon_x, 0.0), ICON_SIZE)
	_hp_value = Label.new()
	HudText.style(_hp_value, 16)
	_hp_value.position = Vector2(icon_x, ICON_SIZE * 0.36)
	_hp_value.size = Vector2(ICON_SIZE, 22.0)
	_hp_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_hp_value)

	_guard_label = Label.new()
	HudText.style(_guard_label, 14)
	_guard_label.add_theme_color_override("font_color", GUARD_FLASH)
	_guard_label.position = Vector2(icon_x, 74.0)
	_guard_label.size = Vector2(ICON_SIZE, 20.0)
	_guard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guard_label.visible = false
	_guard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_guard_label)

	if _show_ap:
		var ap_x: float = icon_x + (ICON_SIZE - AP_ICON_SIZE) / 2.0
		_ap_icon = _make_icon(&"ap", Vector2(ap_x, 96.0), AP_ICON_SIZE)
		_ap_value = Label.new()
		HudText.style(_ap_value, 13)
		_ap_value.position = Vector2(ap_x, 96.0 + AP_ICON_SIZE * 0.36)
		_ap_value.size = Vector2(AP_ICON_SIZE, 18.0)
		_ap_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_ap_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon_cluster.add_child(_ap_value)

	var rows_y: float = 150.0 if _show_ap else 120.0
	_status_label = _make_row_label(14, rows_y + 26.0)
	HudText.style(_status_label, 14)
	_status_label.add_theme_color_override("font_color", STATUS_COLOR)

	_status_icon_row = HBoxContainer.new()
	_status_icon_row.add_theme_constant_override("separation", int(STATUS_ICON_GAP))
	_status_icon_row.position = Vector2(0.0, rows_y)
	_status_icon_row.size = Vector2(PANEL_SIZE.x, STATUS_ICON_SIZE)
	_status_icon_row.alignment = BoxContainer.ALIGNMENT_END if align_right \
		else BoxContainer.ALIGNMENT_BEGIN
	_status_icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(_status_icon_row)

func _make_icon(icon_name: StringName, at: Vector2, icon_size: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = CardArt.ui_icon_for(icon_name)
	# expand_mode must be set BEFORE position/size: Control.set_size() clamps
	# against get_minimum_size(), and TextureRect's default expand_mode
	# (EXPAND_KEEP_SIZE) reports the texture's own pixel size as that
	# minimum. Assigning `.size` first (as this used to) silently clamped
	# the icon back up to the source PNG's native 1254x1254 -- confirmed by
	# probing the exact sequence headless: `.size` read back as (1254, 1254)
	# with this order reversed, (72, 72) with expand_mode set first. Setting
	# expand_mode first makes the minimum size 0, so size sticks.
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.position = at
	icon.size = Vector2.ONE * icon_size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(icon)
	return icon

func _make_row_label(font_size: int, y: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.position = Vector2(0.0, y)
	label.size = Vector2(PANEL_SIZE.x, float(font_size) + 10.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

## Refreshes the display and reacts to whatever changed since the last call.
func update(fighter: Fighter) -> void:
	_hp_value.text = "%d / %d" % [fighter.hp, fighter.max_hp]
	_layout_value_label(_hp_value, _hp_icon.position.x, ICON_SIZE)
	_guard_label.text = "+%d" % fighter.guard
	_guard_label.visible = fighter.guard > 0
	_status_label.text = _status_line(fighter)
	_rebuild_status_icons(fighter)

	var kind: StringName = &"none"
	var amount: int = 0
	if _last_hp >= 0:
		if fighter.hp < _last_hp:
			kind = &"damage"
			amount = _last_hp - fighter.hp
		elif fighter.hp == _last_hp and fighter.guard < _last_guard:
			kind = &"guard"
			amount = _last_guard - fighter.guard
	_last_hp = fighter.hp
	_last_guard = fighter.guard

	# Guard also clears at its owner's turn start (expiry), which looks
	# identical to absorption in this diff. suppress_next_guard_pulse() marks
	# the next update as an expiry so it doesn't misreport as "Block worked".
	# Only a `&"guard"` result is affected, and the flag always clears after
	# this one update so it cannot leak into a later, genuine absorb.
	if _suppress_guard_pulse:
		if kind == &"guard":
			kind = &"none"
			amount = 0
		_suppress_guard_pulse = false

	debug_last_pulse_kind = kind
	debug_last_pulse_amount = amount

	if kind == &"damage":
		_pulse_damage(amount)
	elif kind == &"guard":
		_pulse_guard(amount)

## Call before a model update that is expected to clear guard through expiry
## rather than absorption. Guard expires at its owner's turn start, which is
## indistinguishable from absorption in an hp/guard diff.
func suppress_next_guard_pulse() -> void:
	_suppress_guard_pulse = true

## Icon-less statuses, omitted entirely when none. A status with an icon
## renders in _status_icon_row instead -- never in both places. Guard has
## its own label now, so it does not appear here.
func _status_line(fighter: Fighter) -> String:
	var parts: Array[String] = []
	for id: StringName in fighter.statuses.ids():
		if CardArt.status_icon_for(id) != null:
			continue
		parts.append("%s %d" % [
			StatusRegistry.display_name(id), fighter.statuses.get_stacks(id)
		])
	return "   ".join(parts)

## One icon + number pair per status that has an icon asset. The number is
## whichever counter the registry says matters for that status: remaining
## turns for a countdown like Leg Injury, stacks for a magnitude.
func _rebuild_status_icons(fighter: Fighter) -> void:
	for child: Node in _status_icon_row.get_children():
		_status_icon_row.remove_child(child)
		child.free()
	_status_icon_entries = []
	for id: StringName in fighter.statuses.ids():
		var icon: Texture2D = CardArt.status_icon_for(id)
		if icon == null:
			continue
		var value: int = fighter.statuses.get_turns(id) if StatusRegistry.shows_turns(id) \
			else fighter.statuses.get_stacks(id)
		_status_icon_entries.append([id, value])

		var image := TextureRect.new()
		image.texture = icon
		image.custom_minimum_size = Vector2.ONE * STATUS_ICON_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_icon_row.add_child(image)

		var number := Label.new()
		number.text = str(value)
		number.add_theme_font_size_override("font_size", 14)
		number.modulate = STATUS_COLOR
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_icon_row.add_child(number)

func debug_status_icons() -> Array:
	return _status_icon_entries

## Centre of the hp icon in the panel's parent space -- the floater/particle
## anchor. Card lunges now aim at the PORTRAITS (FightStage centres).
func centre_point() -> Vector2:
	return position + _cluster_home + _hp_icon.position + Vector2.ONE * ICON_SIZE / 2.0

func _pulse_damage(amount: int) -> void:
	if not is_inside_tree():
		return
	_punch(_hp_value, DAMAGE_FLASH)
	_float_number("-%d" % amount, DAMAGE_FLASH)
	_shake(shake_amplitude(amount))
	ParticleBurst.spawn(self, _cluster_home + _hp_icon.position + Vector2.ONE * ICON_SIZE / 2.0,
		DAMAGE_FLASH, Juice.PARTICLES_HIT)

func _pulse_guard(amount: int) -> void:
	if not is_inside_tree():
		return
	_punch(_status_label, GUARD_FLASH)
	_float_number("-%d guard" % amount, GUARD_FLASH)

func _punch(label: Label, flash: Color) -> void:
	label.pivot_offset = label.size / 2.0
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE * Juice.PUNCH_SCALE, Juice.PUNCH_TIME * 0.4)
	tween.parallel().tween_property(label, "modulate", flash, Juice.PUNCH_TIME * 0.4)
	tween.tween_property(label, "scale", Vector2.ONE, Juice.PUNCH_TIME * 0.6)
	tween.parallel().tween_property(label, "modulate", _label_rest_color(label), Juice.PUNCH_TIME * 0.6)

func _label_rest_color(label: Label) -> Color:
	return STATUS_COLOR if label == _status_label else Color.WHITE

## A damage number that arcs and tumbles rather than drifting straight up --
## motion with a direction reads as thrown, not faded.
func _float_number(text: String, colour: Color) -> void:
	var floater := Label.new()
	floater.text = text
	floater.add_theme_font_size_override("font_size", 22)
	floater.modulate = colour
	floater.position = _hp_value.position - Vector2(0.0, Juice.NUMBER_RISE * 0.4)
	floater.size = Vector2(PANEL_SIZE.x, 28.0)
	floater.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
	floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floater.pivot_offset = floater.size / 2.0
	add_child(floater)

	# Arc away from the fighter's own side, so the two panels throw numbers
	# outward rather than both drifting the same way.
	var arc_x: float = Juice.NUMBER_ARC_X if align_right else -Juice.NUMBER_ARC_X
	var landing: Vector2 = floater.position + Vector2(arc_x, -Juice.NUMBER_RISE)

	var tween := create_tween()
	tween.tween_property(floater, "position", landing, Juice.NUMBER_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(floater, "rotation",
		deg_to_rad(Juice.NUMBER_SPIN_DEG if align_right else -Juice.NUMBER_SPIN_DEG),
		Juice.NUMBER_TIME)
	tween.parallel().tween_property(floater, "modulate:a", 0.0, Juice.NUMBER_TIME)
	tween.chain().tween_callback(floater.queue_free)

func _shake(amplitude: float) -> void:
	if _cluster_tween != null and _cluster_tween.is_valid():
		_cluster_tween.kill()
		_icon_cluster.position = _cluster_home
	var step_time: float = Juice.SHAKE_TIME / float(Juice.SHAKE_STEPS + 1)
	_cluster_tween = create_tween()
	for i: int in range(Juice.SHAKE_STEPS):
		var direction: float = -1.0 if i % 2 == 0 else 1.0
		_cluster_tween.tween_property(_icon_cluster, "position",
			_cluster_home + Vector2(direction * amplitude, 0.0), step_time)
	_cluster_tween.tween_property(_icon_cluster, "position", _cluster_home, step_time)

var _value_overflowed: bool = false

## The user-specified fitting rule: the value centres in the icon's dark
## window; when it is too wide it anchors at the icon's horizontal centre
## and grows rightward instead.
func _layout_value_label(label: Label, icon_x: float, icon_size: float) -> void:
	var font: Font = label.get_theme_font("font")
	var width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, label.get_theme_font_size("font_size")).x
	var window: float = icon_size * VALUE_WINDOW_FRACTION
	_value_overflowed = width > window
	if _value_overflowed:
		label.position.x = icon_x + icon_size / 2.0
		label.size.x = width + 4.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		label.position.x = icon_x + (icon_size - window) / 2.0
		label.size.x = window
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func debug_value_overflowed() -> bool:
	return _value_overflowed

func update_ap(current: int, maximum: int) -> void:
	if not _show_ap:
		return
	_ap_value.text = "%d / %d" % [current, maximum]
	_layout_value_label(_ap_value, _ap_icon.position.x, AP_ICON_SIZE)

func debug_ap_text() -> String:
	return "" if _ap_value == null else _ap_value.text

func debug_hp_text() -> String:
	return _hp_value.text

func debug_status_text() -> String:
	return _status_label.text
