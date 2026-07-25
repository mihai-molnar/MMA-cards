class_name BattleHud
extends Control

## Every static UI element: fighter rectangles, hp/guard/status readouts, turn
## and AP counters, intent, log, buttons, and the result banner.
## Renders what it is told; computes no rules.

signal end_turn_pressed()
signal restart_pressed()

const PLAYER_COLOR: Color = Color(0.20, 0.40, 0.85)
const ENEMY_COLOR: Color = Color(0.85, 0.25, 0.25)
const FIGHTER_SIZE: Vector2 = Vector2(140, 160)
const LOG_LINES: int = 5

var _turn_label: Label
var _intent_label: Label
var _enemy_hp_label: Label
var _enemy_status_label: Label
var _player_hp_label: Label
var _player_status_label: Label
var _ap_label: Label
var _pile_label: Label
var _log_label: Label
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
	_intent_label = _add_label("", Vector2(640, 20), 20)
	_intent_label.modulate = Color(1.0, 0.75, 0.35)

	# Enemy block
	_add_rect(ENEMY_COLOR, Vector2(200, 60))
	_add_label("ENEMY", Vector2(228, 130), 16)
	_enemy_hp_label = _add_label("", Vector2(380, 70), 22)
	_enemy_status_label = _add_label("", Vector2(380, 104), 16)
	_enemy_status_label.modulate = Color(1.0, 0.8, 0.4)

	# Player block
	_add_rect(PLAYER_COLOR, Vector2(60, 250))
	_add_label("PLAYER", Vector2(84, 320), 16)
	_player_hp_label = _add_label("", Vector2(230, 260), 22)
	_player_status_label = _add_label("", Vector2(230, 294), 16)
	_player_status_label.modulate = Color(0.6, 0.9, 1.0)

	_ap_label = _add_label("", Vector2(820, 260), 24)
	_pile_label = _add_label("", Vector2(24, 430), 14)
	_log_label = _add_label("", Vector2(430, 330), 14)
	_log_label.modulate = Color(0.75, 0.75, 0.80)

	var end_turn := Button.new()
	end_turn.text = "END TURN"
	end_turn.position = Vector2(820, 310)
	end_turn.custom_minimum_size = Vector2(160, 44)
	end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	add_child(end_turn)

	_build_result_panel()

func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	add_child(_result_panel)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_result_panel.add_child(dim)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.position = Vector2(430, 240)
	_result_panel.add_child(_result_label)

	var restart := Button.new()
	restart.text = "RESTART"
	restart.position = Vector2(470, 320)
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

func _add_rect(color: Color, at: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = at
	rect.size = FIGHTER_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect

func update_turn(turn_number: int) -> void:
	_turn_label.text = "TURN %d" % turn_number

func update_intent(text: String) -> void:
	_intent_label.text = "INTENT: %s" % text

func update_ap(current: int, maximum: int) -> void:
	_ap_label.text = "AP  %d / %d" % [current, maximum]

func update_fighters(battle: BattleState) -> void:
	_enemy_hp_label.text = "ENEMY  %d / %d" % [battle.enemy.hp, battle.enemy.max_hp]
	_enemy_status_label.text = _status_line(battle.enemy)
	_player_hp_label.text = "PLAYER  %d / %d" % [battle.player.hp, battle.player.max_hp]
	_player_status_label.text = _status_line(battle.player)
	_pile_label.text = "draw %d    discard %d" % [
		battle.deck.draw_pile.size(), battle.deck.discard_pile.size()
	]

## Guard and statuses, omitted entirely when zero.
func _status_line(fighter: Fighter) -> String:
	var parts: Array[String] = []
	if fighter.guard > 0:
		parts.append("GUARD %d" % fighter.guard)
	for id: StringName in fighter.statuses.ids():
		parts.append("%s %d" % [StatusRegistry.display_name(id), fighter.statuses.get_stacks(id)])
	return "   ".join(parts)

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
