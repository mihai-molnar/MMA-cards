class_name BattleHud
extends Control

## Everything that is not a card: turn and intent readouts, the two fighter
## panels, pile counts, AP, buttons, and the result banner. Renders what it
## is told; computes no rules.

signal end_turn_pressed()
signal restart_pressed()
signal continue_pressed()

## z_index lifts a node above its parent's later siblings, so the banner must
## outrank a hovered (50) or lunging (60) card or they redraw over it.
const RESULT_PANEL_Z: int = 100

## Panels shrank and moved up to free vertical room for the larger card fan.
## (24, 56): a 24px margin from the left edge, mirrored by ENEMY_PANEL_AT's
## 24px margin from the right (1152 - 24 - PANEL_SIZE.x = 918). Panels then
## occupy y 56..232 (FighterPanel.PANEL_SIZE.y = 176), clear of the deal-in
## fan (HandView.HAND_BASE_Y = 311) with margin to spare even for a hovered
## outer card -- see the HandView.HOVER_LIFT/HOVER_SCALE arithmetic in
## HandView's own doc comments for that specific, tighter number.
const PLAYER_PANEL_AT: Vector2 = Vector2(24, 56)
const ENEMY_PANEL_AT: Vector2 = Vector2(918, 56)

## Corner controls, pushed toward the edges to give the enlarged card fan the
## centre of the screen. END_TURN_AT.x = 985: the fanned hand's rightmost
## card is rotated up to HandView.MAX_FAN_ANGLE_DEG about its bottom-centre
## pivot, so its true right-side edge is a line between two corners, not the
## axis-aligned rect edge (see HandView.rotated_right_edge_at_y). That edge
## crosses this button's top edge (y=570, the tightest point across the
## button's height -- see test_hand_arc.gd) at x ≈ 967, ~18px clear.
## END_TURN_SIZE.x = 150 puts the button's right edge at 1135, 17px from the
## design space's right edge (1152).
const END_TURN_AT: Vector2 = Vector2(985, 570)
const END_TURN_SIZE: Vector2 = Vector2(150, 48)

## Bottom-left corner control. DRAW_LABEL_AT.x = 16 mirrors
## DISCARD_LABEL_AT on the right. The leftmost fanned card's true left-side
## edge (HandView.rotated_left_edge_at_y) clears its row -- see
## test_hand_arc.gd for the exact figures. (The bottom-left AP text label
## that used to sit above this is gone -- the AP readout moved into the
## player FighterPanel's icon cluster.)
const DRAW_LABEL_AT: Vector2 = Vector2(16, 596)

## Bottom-right pile count, mirroring DRAW_LABEL_AT. Right-aligned within
## DISCARD_LABEL_SIZE so its rendered right edge lands at
## DISCARD_LABEL_AT.x + DISCARD_LABEL_SIZE.x = 1136 (16px from the design
## space's right edge) regardless of digit count, rather than growing
## rightward off the edge the way a left-aligned label would.
const DISCARD_LABEL_AT: Vector2 = Vector2(936, 620)
const DISCARD_LABEL_SIZE: Vector2 = Vector2(200, 24)

var _stage: FightStage
var _turn_label: Label
var _intent_label: Label
var _draw_label: Label
var _discard_label: Label
var _player_panel: FighterPanel
var _enemy_panel: FighterPanel
var _result_panel: Control
var _result_label: Label
var _restart_button: Button
var _continue_button: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	_stage = FightStage.new()
	add_child(_stage)

	_turn_label = _add_label("TURN 1", Vector2(0, 16), 20)
	_turn_label.size = Vector2(1152, 28)
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	HudText.style(_turn_label, 20)

	# Wide enough for the longest multi-move telegraph
	# ("INTENT: BLOCK 10 + BUFF +2 STR") without clipping; right-aligned so
	# growth extends leftward into empty space.
	_intent_label = _add_label("", Vector2(620, 20), 20)
	_intent_label.size = Vector2(500, 28)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	HudText.style(_intent_label, 20)

	# Fighters face each other: player left, enemy right, numbers under each.
	_player_panel = FighterPanel.create("Player", false, true)
	_player_panel.position = PLAYER_PANEL_AT
	add_child(_player_panel)

	_enemy_panel = FighterPanel.create("Enemy", true, false)
	_enemy_panel.position = ENEMY_PANEL_AT
	add_child(_enemy_panel)

	# Draw sits bottom-left, End Turn and discard bottom-right -- the AP
	# readout moved into the player FighterPanel's icon cluster, and the
	# combat log that used to occupy the centre band is gone, so the middle
	# of the screen is free for the larger card fan.
	_draw_label = _add_label("", DRAW_LABEL_AT, 14)
	HudText.style(_draw_label, 14)

	_discard_label = _add_label("", DISCARD_LABEL_AT, 14)
	_discard_label.size = DISCARD_LABEL_SIZE
	_discard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	HudText.style(_discard_label, 14)

	var end_turn := Button.new()
	end_turn.text = "END TURN"
	end_turn.position = END_TURN_AT
	end_turn.custom_minimum_size = END_TURN_SIZE
	# No keyboard nav anywhere in the game: a focused button wears Godot's
	# default white focus rectangle, which reads as a rendering glitch.
	end_turn.focus_mode = Control.FOCUS_NONE
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
	# Full design-space width and centred: banner text now varies in length
	# ("FIGHT 2: KICKBOXER", "RUN COMPLETE"), so a fixed x would park long
	# strings visibly off-centre.
	_result_label.position = Vector2(0, 180)
	_result_label.size = Vector2(1152, 60)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)

	_restart_button = _add_banner_button("RESTART", func() -> void: restart_pressed.emit())
	_continue_button = _add_banner_button("CONTINUE", func() -> void: continue_pressed.emit())

## Both banner buttons share one slot; _show_banner picks which is visible.
func _add_banner_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(476, 260)
	button.custom_minimum_size = Vector2(180, 48)
	# Same reason as End Turn's: no focus, no white focus rectangle.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	_result_panel.add_child(button)
	return button

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
	_player_panel.update_ap(current, maximum)

func update_fighters(battle: BattleState) -> void:
	_player_panel.update(battle.player)
	_enemy_panel.update(battle.enemy)
	_draw_label.text = "draw %d" % battle.deck.draw_pile.size()
	_discard_label.text = "discard %d" % battle.deck.discard_pile.size()

## The larger of the two panels' most recent damage pulses, or 0 if neither
## took damage. Lets the view react to a hit without BattleState carrying a
## damage payload.
func last_damage_amount() -> int:
	var player_hit: int = _player_panel.debug_last_pulse_amount if _player_panel.debug_last_pulse_kind == &"damage" else 0
	var enemy_hit: int = _enemy_panel.debug_last_pulse_amount if _enemy_panel.debug_last_pulse_kind == &"damage" else 0
	return maxi(player_hit, enemy_hit)

## The absorb mirror of last_damage_amount(): the larger of the two panels'
## most recent guard-absorb pulses, or 0 if neither soaked a hit. A
## suppressed expiry records kind "none", so it never counts here.
func last_absorb_amount() -> int:
	var player_soak: int = _player_panel.debug_last_pulse_amount if _player_panel.debug_last_pulse_kind == &"guard" else 0
	var enemy_soak: int = _enemy_panel.debug_last_pulse_amount if _enemy_panel.debug_last_pulse_kind == &"guard" else 0
	return maxi(player_soak, enemy_soak)

## Which side the most recent fighter update hurt -- drives the portrait
## flash/shake. Mirrors last_damage_amount()'s larger-pulse-wins rule.
func last_damage_side() -> StringName:
	var player_hit: int = _player_panel.debug_last_pulse_amount if _player_panel.debug_last_pulse_kind == &"damage" else 0
	var enemy_hit: int = _enemy_panel.debug_last_pulse_amount if _enemy_panel.debug_last_pulse_kind == &"damage" else 0
	if player_hit == 0 and enemy_hit == 0:
		return &"none"
	return &"player" if player_hit >= enemy_hit else &"enemy"

func stage() -> FightStage:
	return _stage

func debug_player_panel() -> FighterPanel:
	return _player_panel

## Anchor a played attack card flies toward.
func enemy_centre() -> Vector2:
	return _stage.enemy_centre()

## Anchor a played Block card pulls back toward.
func player_centre() -> Vector2:
	return _stage.player_centre()

## Pass-throughs so BattleView can mark the next fighters_changed update as a
## guard expiry rather than an absorption (see FighterPanel.
## suppress_next_guard_pulse). Kept per-panel: the player's legitimate absorb
## pulse can land on the same fighters_changed as the enemy's expiry, so a
## single global flag would wrongly swallow it too.
func suppress_player_guard_pulse() -> void:
	_player_panel.suppress_next_guard_pulse()

func suppress_enemy_guard_pulse() -> void:
	_enemy_panel.suppress_next_guard_pulse()

## The run swaps the real opponent name in at each fight start.
func set_enemy_name(p_name: String) -> void:
	_enemy_panel.set_fighter_name(p_name)

## Test hooks -- banner internals the suites assert without walking children.
func debug_result_text() -> String:
	return _result_label.text

func debug_restart_button() -> Button:
	return _restart_button

func debug_continue_button() -> Button:
	return _continue_button

func debug_enemy_panel() -> FighterPanel:
	return _enemy_panel

func show_defeat() -> void:
	_show_banner("YOU LOSE", Color(1.0, 0.5, 0.5), _restart_button)

func show_run_complete() -> void:
	_show_banner("RUN COMPLETE", Color(0.5, 1.0, 0.5), _restart_button)

func show_fight_intro(fight_number: int, opponent_name: String) -> void:
	_show_banner("FIGHT %d: %s" % [fight_number, opponent_name.to_upper()],
		Color(1.0, 0.75, 0.35), _continue_button)

func _show_banner(text: String, colour: Color, button: Button) -> void:
	_result_label.text = text
	_result_label.modulate = colour
	_restart_button.visible = button == _restart_button
	_continue_button.visible = button == _continue_button
	_result_panel.visible = true

func hide_result() -> void:
	_result_panel.visible = false

## Called by BattleView once the hand has been parented, so the banner is the
## last child as well as the highest z_index.
func bring_result_panel_to_front() -> void:
	_result_panel.move_to_front()
