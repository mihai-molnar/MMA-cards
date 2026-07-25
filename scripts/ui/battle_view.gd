class_name BattleView
extends Node2D

## Entry point, attached to level.tscn. Owns the BattleState, builds the UI, and
## translates signals in both directions. It never computes rules.

var battle: BattleState
var hud: BattleHud
var hand_view: HandView

func _ready() -> void:
	battle = BattleState.new()
	_build_ui()
	_connect_battle()
	battle.start()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = BattleHud.new()
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	layer.add_child(hud)

	hand_view = HandView.new()
	hand_view.card_chosen.connect(_on_card_chosen)
	hud.add_child(hand_view)

	# Attacks fly at the enemy, Block pulls back to the player.
	hand_view.set_lunge_anchors(hud.enemy_centre(), hud.player_centre())

	hud.bring_result_panel_to_front()

func _connect_battle() -> void:
	battle.turn_started.connect(_on_turn_started)
	battle.ap_changed.connect(_on_ap_changed)
	battle.hand_changed.connect(_on_hand_changed)
	battle.fighters_changed.connect(_on_fighters_changed)
	battle.intent_changed.connect(hud.update_intent)
	battle.log_line.connect(hud.append_log)
	battle.battle_over.connect(_on_battle_over)

func _on_turn_started(turn_number: int) -> void:
	# Player turn start clears the player's guard by expiry (BattleState
	# expires it here, before this signal). turn_started fires before
	# fighters_changed, so this lands in time to suppress that panel's pulse.
	hud.suppress_player_guard_pulse()
	hud.update_turn(turn_number)
	hud.append_log("-- Turn %d --" % turn_number)

func _on_ap_changed(current: int, maximum: int) -> void:
	hud.update_ap(current, maximum)
	hand_view.refresh_states(battle)

func _on_hand_changed() -> void:
	hand_view.rebuild(battle)

func _on_fighters_changed() -> void:
	hud.update_fighters(battle)
	hand_view.refresh_states(battle)

func _on_card_chosen(index: int) -> void:
	# The card only departs the hand once BattleState confirms the play; a
	# rejected play must leave HandView untouched (see HandView.launch_play).
	if battle.play_card(index):
		hand_view.launch_play(index)

func _on_end_turn_pressed() -> void:
	# Enemy turn start clears the enemy's guard by expiry, inside end_turn().
	# Suppress before calling it so that expiry doesn't read as an absorb.
	hud.suppress_enemy_guard_pulse()
	battle.end_turn()

func _on_battle_over(player_won: bool) -> void:
	# Drop any lifted card before the banner appears, so nothing is left raised
	# behind it.
	hand_view.clear_hover()
	hud.show_result(player_won)
	hand_view.refresh_states(battle)

func _on_restart_pressed() -> void:
	hud.hide_result()
	hud.clear_log()
	# A player who wins at full HP while still holding guard would otherwise
	# get a spurious pulse when restart() zeroes it out.
	hud.suppress_player_guard_pulse()
	hud.suppress_enemy_guard_pulse()
	battle.restart()
