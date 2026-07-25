class_name FighterPanel
extends Control

## One fighter's rectangle, name, HP and status badges, plus every bit of damage
## feedback. Instantiated twice — player on the left, enemy on the right, mirrored
## by `align_right` — so the animation exists once rather than in two copies that
## can drift apart.
##
## `fighters_changed` carries no payload, so rather than changing BattleState for a
## cosmetic feature this panel remembers the previous hp/guard and diffs them.

const PANEL_SIZE: Vector2 = Vector2(210, 176)
const RECT_SIZE: Vector2 = Vector2(104, 120)

const DAMAGE_FLASH: Color = Color(1.0, 0.35, 0.35)
const GUARD_FLASH: Color = Color(0.55, 0.85, 1.0)
const STATUS_COLOR: Color = Color(1.0, 0.82, 0.40)

var align_right: bool = false

## What the most recent update() decided. Test hooks — the animation reads the
## same values, so asserting these asserts the real decision.
var debug_last_pulse_kind: StringName = &"none"
var debug_last_pulse_amount: int = 0

var _rect: ColorRect
var _name_label: Label
var _hp_label: Label
var _status_label: Label
var _rect_home: Vector2 = Vector2.ZERO
## The rect's colour at build time -- what _flash_rect must always return to.
## Reading _rect.color live instead (the old bug) captures whatever colour a
## still-in-flight flash tween happens to be passing through, so two pulses
## inside one flash window ratchet the "home" colour toward DAMAGE_FLASH a
## little more each time and never reset.
var _rect_colour_home: Color = Color.WHITE
var _flash_tween: Tween

var _last_hp: int = -1
var _last_guard: int = 0
var _suppress_guard_pulse: bool = false

static func create(display_name: String, rect_color: Color, p_align_right: bool) -> FighterPanel:
	var panel := FighterPanel.new()
	panel.align_right = p_align_right
	panel._build(display_name, rect_color)
	return panel

func _init() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Delegates to Juice so every tuning value lives in one file. Kept as a static
## on FighterPanel because tests and callers already reference it here.
static func shake_amplitude(amount: int) -> float:
	return Juice.rect_shake_amplitude(amount)

func _build(display_name: String, rect_color: Color) -> void:
	_rect = ColorRect.new()
	_rect.color = rect_color
	_rect.size = RECT_SIZE
	_rect.position = Vector2(PANEL_SIZE.x - RECT_SIZE.x, 0.0) if align_right else Vector2.ZERO
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_home = _rect.position
	_rect_colour_home = rect_color
	add_child(_rect)

	# The fighter's name sits inside its rectangle, centred, and is parented to
	# the rectangle itself (not a FighterPanel sibling) so the damage shake --
	# which tweens `_rect.position` -- carries the name along with it instead
	# of leaving it behind mid-hit. Position is therefore rect-relative.
	_name_label = Label.new()
	_name_label.text = display_name.to_upper()
	_name_label.add_theme_font_size_override("font_size", 16)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.position = Vector2(0.0, RECT_SIZE.y / 2.0 - 12.0)
	_name_label.size = Vector2(RECT_SIZE.x, 24.0)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.add_child(_name_label)

	# Font sizes dropped from 22/16 to 18/14 alongside the panel shrink: the
	# text itself still fits either way (measured against ThemeDB's fallback
	# font, "PLAYER  50 / 50" is 161px wide at 22, comfortably under the new
	# PANEL_SIZE.x = 210), but the smaller sizes trim a few pixels off the
	# status row's vertical footprint -- worth having given how close a
	# hovered outer card's lifted top edge (~241, see HandView's doc
	# comments) sits to these panels' bottom (232).
	_hp_label = _make_row_label(18, RECT_SIZE.y + 12.0)
	_status_label = _make_row_label(14, RECT_SIZE.y + 44.0)
	_status_label.modulate = STATUS_COLOR

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
	_hp_label.text = "%s  %d / %d" % [
		fighter.display_name.to_upper(), fighter.hp, fighter.max_hp
	]
	_status_label.text = _status_line(fighter)

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

## Guard and statuses, omitted entirely when zero.
func _status_line(fighter: Fighter) -> String:
	var parts: Array[String] = []
	if fighter.guard > 0:
		parts.append("GUARD %d" % fighter.guard)
	for id: StringName in fighter.statuses.ids():
		parts.append("%s %d" % [
			StatusRegistry.display_name(id), fighter.statuses.get_stacks(id)
		])
	return "   ".join(parts)

## Centre of the fighter rectangle, in the panel's parent coordinate space.
## Used as the anchor a played card lunges toward.
func centre_point() -> Vector2:
	return position + _rect_home + RECT_SIZE / 2.0

func _pulse_damage(amount: int) -> void:
	if not is_inside_tree():
		return
	_punch(_hp_label, DAMAGE_FLASH)
	_float_number("-%d" % amount, DAMAGE_FLASH)
	_shake(shake_amplitude(amount))
	_flash_rect(DAMAGE_FLASH)
	ParticleBurst.spawn(self, _rect_home + RECT_SIZE / 2.0, DAMAGE_FLASH, Juice.PARTICLES_HIT)

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
	floater.position = _hp_label.position - Vector2(0.0, Juice.NUMBER_RISE * 0.4)
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

## Hard flash on the struck fighter's rectangle, then back to its own colour.
func _flash_rect(colour: Color) -> void:
	if not is_inside_tree():
		return
	# Kill any flash still in flight before starting another, same as _shake's
	# sibling tween below -- otherwise two pulses inside one flash window both
	# drive _rect.color at once and fight each other.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_rect, "color", colour, Juice.FLASH_TIME * 0.35)
	_flash_tween.tween_property(_rect, "color", _rect_colour_home, Juice.FLASH_TIME)

func _shake(amplitude: float) -> void:
	var step_time: float = Juice.SHAKE_TIME / float(Juice.SHAKE_STEPS + 1)
	var tween := create_tween()
	for i: int in range(Juice.SHAKE_STEPS):
		var direction: float = -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(_rect, "position",
			_rect_home + Vector2(direction * amplitude, 0.0), step_time)
	tween.tween_property(_rect, "position", _rect_home, step_time)

func debug_hp_text() -> String:
	return _hp_label.text

func debug_status_text() -> String:
	return _status_label.text
