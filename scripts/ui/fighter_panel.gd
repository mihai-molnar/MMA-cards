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
const STATUS_ICON_SIZE: float = 28.0
const STATUS_ICON_GAP: float = 4.0

## The guard chip sits directly under the heart (0-72); the status chip
## row under that -- the space the AP bolt vacated when it moved to the
## HUD's bottom-left corner.
const GUARD_ROW_Y: float = 74.0
const STATUS_ROW_Y: float = 116.0
const STATUS_CHIP_GAP: float = 6.0
const STATUS_CHIP_PAD: float = 3.0
## Same dark ground as StatusTooltip's panel: the chip's job is to make the
## icon stand out against the bright portrait behind it.
const STATUS_CHIP_BG: Color = Color(0.08, 0.08, 0.10, 0.9)

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

## A chip under the health readout was hovered (or unhovered): which status,
## and the chip's bottom-centre in the panel's parent space -- the anchor a
## tooltip hangs below.
signal status_hovered(id: StringName, anchor: Vector2, hovered: bool)
## The guard chip's hover. Guard is NOT a status (no registry id), so it
## reports on its own signal and BattleView shows an info tooltip.
signal guard_hovered(anchor: Vector2, hovered: bool)

var align_right: bool = false

## What the most recent update() decided. Test hooks — the animation reads the
## same values, so asserting these asserts the real decision.
var debug_last_pulse_kind: StringName = &"none"
var debug_last_pulse_amount: int = 0

## One chip per active status, in a row under the health readout. Parented
## to the icon cluster so the damage shake carries them.
var _status_row: HBoxContainer
## What the row currently displays, as [[id, number], ...]. Doubles as the
## rebuild guard: an update that changes nothing keeps the existing chips,
## so a hovered chip is not freed out from under the cursor. Test hook.
var _status_chip_entries: Array = []
var _status_chip_nodes: Array = []

var _fighter_name: String = ""
var _icon_cluster: Control
var _hp_icon: TextureRect
var _hp_value: Label
## Guard renders as a chip like the statuses -- icon plus the blue +n --
## but persistent: built once, toggled by visibility, so a hover can never
## be interrupted by an update that changed nothing.
var _guard_row: HBoxContainer
var _guard_chip: PanelContainer
var _guard_value: Label
## The cluster's rest position -- what every shake returns to.
var _cluster_home: Vector2 = Vector2.ZERO
var _cluster_tween: Tween

var _last_hp: int = -1
var _last_guard: int = 0
var _suppress_guard_pulse: bool = false

static func create(display_name: String, p_align_right: bool) -> FighterPanel:
	var panel := FighterPanel.new()
	panel.align_right = p_align_right
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

	_guard_row = _make_chip_row(GUARD_ROW_Y)
	_guard_chip = _make_chip(GUARD_FLASH)
	_guard_chip.visible = false
	_guard_chip.mouse_entered.connect(_on_guard_hover.bind(true))
	_guard_chip.mouse_exited.connect(_on_guard_hover.bind(false))
	var guard_box: HBoxContainer = _guard_chip.get_child(0)
	guard_box.add_child(_make_chip_icon(CardArt.status_icon_for(&"guard")))
	_guard_value = Label.new()
	HudText.style(_guard_value, 14)
	# Tinted via the theme colour, NOT modulate: _punch tweens modulate and
	# always lands back on WHITE, which would bleach a modulate tint.
	_guard_value.add_theme_color_override("font_color", GUARD_FLASH)
	_guard_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_guard_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guard_box.add_child(_guard_value)
	_guard_row.add_child(_guard_chip)

	_status_row = _make_chip_row(STATUS_ROW_Y)

## A side-aligned row the chips flow in. IGNORE on the row, STOP on each
## chip: the row must not swallow clicks over the whole panel width, but
## the chips themselves observe the mouse for the tooltip.
func _make_chip_row(y: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(STATUS_CHIP_GAP))
	row.position = Vector2(0.0, y)
	row.size = Vector2(PANEL_SIZE.x, STATUS_ICON_SIZE + 2.0 * STATUS_CHIP_PAD)
	row.alignment = BoxContainer.ALIGNMENT_END if align_right \
		else BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_cluster.add_child(row)
	return row

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

## Refreshes the display and reacts to whatever changed since the last call.
##
## The optional overrides (negative means "off") present an INTERMEDIATE
## snapshot: a multi-hit play mutates the model once, but the view replays
## it as beats -- the first beat shows the state with the follow-up hit
## held back, the second the real fighter. The diff brain runs against the
## SHOWN values both times, so each beat pulses exactly its own hit.
## Statuses always render live: no status changes between the two beats.
func update(fighter: Fighter, hp_override: int = -1, guard_override: int = -1) -> void:
	var shown_hp: int = fighter.hp if hp_override < 0 else hp_override
	var shown_guard: int = fighter.guard if guard_override < 0 else guard_override
	_hp_value.text = "%d / %d" % [shown_hp, fighter.max_hp]
	_layout_value_label(_hp_value, _hp_icon.position.x, ICON_SIZE)
	_guard_value.text = "+%d" % shown_guard
	_guard_chip.visible = shown_guard > 0
	_rebuild_status_chips(fighter)

	var kind: StringName = &"none"
	var amount: int = 0
	if _last_hp >= 0:
		if shown_hp < _last_hp:
			kind = &"damage"
			amount = _last_hp - shown_hp
		elif shown_hp == _last_hp and shown_guard < _last_guard:
			kind = &"guard"
			amount = _last_guard - shown_guard
	_last_hp = shown_hp
	_last_guard = shown_guard

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

## One chip per active status -- EVERY status, icon or not. The number is
## whichever counter the registry says matters: remaining turns for a
## countdown like Leg Injury, stacks for a magnitude like strength. Skips
## the rebuild when nothing changed, so a hovered chip is never freed out
## from under the cursor by a no-op update.
func _rebuild_status_chips(fighter: Fighter) -> void:
	var entries: Array = []
	for id: StringName in fighter.statuses.ids():
		var value: int = fighter.statuses.get_turns(id) if StatusRegistry.shows_turns(id) \
			else fighter.statuses.get_stacks(id)
		entries.append([id, value])
	if entries == _status_chip_entries:
		return
	_status_chip_entries = entries
	_status_chip_nodes = []
	for child: Node in _status_row.get_children():
		_status_row.remove_child(child)
		child.free()
	for entry: Array in entries:
		_status_row.add_child(_make_status_chip(entry[0], entry[1]))

## The chip shell shared by the status chips and the guard chip: dark
## ground (what makes the icon stand out against the portrait), bordered
## in the readout's colour, an HBox inside for icon + number.
func _make_chip(border_color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = STATUS_CHIP_BG
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(STATUS_CHIP_PAD)
	chip.add_theme_stylebox_override("panel", style)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(STATUS_ICON_GAP))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(box)
	return chip

func _make_chip_icon(texture: Texture2D) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = Vector2.ONE * STATUS_ICON_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

## A status chip: icon (or the registry's short name while a status has no
## icon asset yet) plus its number, bordered in the status yellow.
func _make_status_chip(id: StringName, value: int) -> Control:
	var chip := _make_chip(STATUS_COLOR)
	chip.mouse_entered.connect(_on_chip_hover.bind(id, chip, true))
	chip.mouse_exited.connect(_on_chip_hover.bind(id, chip, false))
	var box: HBoxContainer = chip.get_child(0)

	var icon: Texture2D = CardArt.status_icon_for(id)
	if icon != null:
		box.add_child(_make_chip_icon(icon))
	else:
		var name_label := Label.new()
		name_label.text = StatusRegistry.display_name(id)
		HudText.style(name_label, 12)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(name_label)

	var number := Label.new()
	number.text = str(value)
	HudText.style(number, 14)
	number.modulate = STATUS_COLOR
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(number)

	_status_chip_nodes.append(chip)
	return chip

## The anchor is the chip's bottom-centre in the panel's PARENT space (the
## HUD), from rest geometry -- _cluster_home, not the live shaken position
## -- so a tooltip anchored mid-shake does not land crooked.
func _on_chip_hover(id: StringName, chip: Control, hovered: bool) -> void:
	var anchor: Vector2 = position + _cluster_home + _status_row.position \
		+ chip.position + Vector2(chip.size.x / 2.0, chip.size.y)
	status_hovered.emit(id, anchor, hovered)

## Mirrors _on_chip_hover for the guard chip: bottom-centre anchor in the
## panel's parent space, from rest geometry.
func _on_guard_hover(hovered: bool) -> void:
	var anchor: Vector2 = position + _cluster_home + _guard_row.position \
		+ _guard_chip.position + Vector2(_guard_chip.size.x / 2.0, _guard_chip.size.y)
	guard_hovered.emit(anchor, hovered)

func debug_guard_chip() -> Control:
	return _guard_chip

func debug_guard_text() -> String:
	return _guard_value.text

func debug_status_chips() -> Array:
	return _status_chip_entries

func debug_status_chip_nodes() -> Array:
	return _status_chip_nodes

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
	# The guard readout is the thing that just worked, so it is what punches.
	_punch(_guard_value, GUARD_FLASH)
	_float_number("-%d guard" % amount, GUARD_FLASH)

func _punch(label: Label, flash: Color) -> void:
	label.pivot_offset = label.size / 2.0
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE * Juice.PUNCH_SCALE, Juice.PUNCH_TIME * 0.4)
	tween.parallel().tween_property(label, "modulate", flash, Juice.PUNCH_TIME * 0.4)
	tween.tween_property(label, "scale", Vector2.ONE, Juice.PUNCH_TIME * 0.6)
	tween.parallel().tween_property(label, "modulate", Color.WHITE, Juice.PUNCH_TIME * 0.6)

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

func debug_hp_text() -> String:
	return _hp_value.text
