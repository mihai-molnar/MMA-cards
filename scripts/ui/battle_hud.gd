class_name BattleHud
extends Control

## Everything that is not a card: turn and intent readouts, the two fighter
## panels, the log, pile counts, AP, buttons, and the result banner.
## Renders what it is told; computes no rules.

signal end_turn_pressed()
signal restart_pressed()

const PLAYER_COLOR: Color = Color(0.20, 0.40, 0.85)
const ENEMY_COLOR: Color = Color(0.85, 0.25, 0.25)
## The log sits at y=120 (see _log_label below), in the empty band between
## the two fighter panels, well above even a hovered centre card -- whose top
## edge reaches only ≈295 (HAND_BASE_Y minus the arch, minus HOVER_LIFT,
## minus the growth HOVER_SCALE adds above its bottom-centre pivot; see
## HandView.HAND_BASE_Y and Juice.HOVER_LIFT / HOVER_SCALE). 4 lines was
## sized for the log's old position directly under the fan and is kept
## unchanged -- the relocation removed the crowding that value was chosen
## for, but there is no reason to grow it back.
const LOG_LINES: int = 4

## z_index lifts a node above its parent's later siblings, so the banner must
## outrank a hovered (50) or lunging (60) card or they redraw over it.
const RESULT_PANEL_Z: int = 100

const PLAYER_PANEL_AT: Vector2 = Vector2(60, 90)
const ENEMY_PANEL_AT: Vector2 = Vector2(832, 90)
const END_TURN_AT: Vector2 = Vector2(900, 520)
const END_TURN_SIZE: Vector2 = Vector2(180, 48)

var _turn_label: Label
var _intent_label: Label
var _ap_label: Label
var _pile_label: Label
var _log_label: Label
var _player_panel: FighterPanel
var _enemy_panel: FighterPanel
var _result_panel: Control
var _result_label: Label

var _log_lines: Array[String] = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.09, 0.09, 0.12)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_turn_label = _add_label("TURN 1", Vector2(24, 20), 20)

	_intent_label = _add_label("", Vector2(820, 20), 20)
	_intent_label.size = Vector2(300, 28)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_intent_label.modulate = Color(1.0, 0.75, 0.35)

	# Fighters face each other: player left, enemy right, numbers under each.
	_player_panel = FighterPanel.create("Player", PLAYER_COLOR, false)
	_player_panel.position = PLAYER_PANEL_AT
	add_child(_player_panel)

	_enemy_panel = FighterPanel.create("Enemy", ENEMY_COLOR, true)
	_enemy_panel.position = ENEMY_PANEL_AT
	add_child(_enemy_panel)

	_log_label = _add_label("", Vector2(430, 120), 14)
	_log_label.modulate = Color(0.75, 0.75, 0.80)

	_pile_label = _add_label("", Vector2(24, 560), 14)

	_ap_label = _add_label("", Vector2(900, 470), 24)

	var end_turn := Button.new()
	end_turn.text = "END TURN"
	end_turn.position = END_TURN_AT
	end_turn.custom_minimum_size = END_TURN_SIZE
	end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	add_child(end_turn)

	_build_result_panel()

func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	_result_panel.z_index = RESULT_PANEL_Z
	add_child(_result_panel)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_result_panel.add_child(dim)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.position = Vector2(430, 210)
	_result_panel.add_child(_result_label)

	var restart := Button.new()
	restart.text = "RESTART"
	restart.position = Vector2(470, 285)
	restart.custom_minimum_size = Vector2(180, 48)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	_result_panel.add_child(restart)

func _add_label(text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func update_turn(turn_number: int) -> void:
	_turn_label.text = "TURN %d" % turn_number

func update_intent(text: String) -> void:
	_intent_label.text = "INTENT: %s" % text

func update_ap(current: int, maximum: int) -> void:
	_ap_label.text = "AP  %d / %d" % [current, maximum]

func update_fighters(battle: BattleState) -> void:
	_player_panel.update(battle.player)
	_enemy_panel.update(battle.enemy)
	_pile_label.text = "draw %d    discard %d" % [
		battle.deck.draw_pile.size(), battle.deck.discard_pile.size()
	]

## The larger of the two panels' most recent damage pulses, or 0 if neither
## took damage. Lets the view react to a hit without BattleState carrying a
## damage payload.
func last_damage_amount() -> int:
	var player_hit: int = _player_panel.debug_last_pulse_amount if _player_panel.debug_last_pulse_kind == &"damage" else 0
	var enemy_hit: int = _enemy_panel.debug_last_pulse_amount if _enemy_panel.debug_last_pulse_kind == &"damage" else 0
	return maxi(player_hit, enemy_hit)

## Anchor a played attack card flies toward.
func enemy_centre() -> Vector2:
	return _enemy_panel.centre_point()

## Anchor a played Block card pulls back toward.
func player_centre() -> Vector2:
	return _player_panel.centre_point()

## Pass-throughs so BattleView can mark the next fighters_changed update as a
## guard expiry rather than an absorption (see FighterPanel.
## suppress_next_guard_pulse). Kept per-panel: the player's legitimate absorb
## pulse can land on the same fighters_changed as the enemy's expiry, so a
## single global flag would wrongly swallow it too.
func suppress_player_guard_pulse() -> void:
	_player_panel.suppress_next_guard_pulse()

func suppress_enemy_guard_pulse() -> void:
	_enemy_panel.suppress_next_guard_pulse()

func append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)

func clear_log() -> void:
	_log_lines.clear()
	_log_label.text = ""

func show_result(player_won: bool) -> void:
	_result_label.text = "YOU WIN" if player_won else "YOU LOSE"
	_result_label.modulate = Color(0.5, 1.0, 0.5) if player_won else Color(1.0, 0.5, 0.5)
	_result_panel.visible = true

func hide_result() -> void:
	_result_panel.visible = false

## Called by BattleView once the hand has been parented, so the banner is the
## last child as well as the highest z_index.
func bring_result_panel_to_front() -> void:
	_result_panel.move_to_front()
