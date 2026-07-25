class_name BattleView
extends Node2D

## Entry point, attached to level.tscn. Owns the BattleState, builds the UI, and
## translates signals in both directions. It never computes rules.

var battle: BattleState
var hud: BattleHud
var hand_view: HandView
var screen_fx: ScreenFx

## Set by _on_card_chosen just before calling battle.play_card(), which emits
## fighters_changed synchronously -- so this is the only way _react_to_damage
## can tell "a card is about to travel to its target" from "an enemy attack
## landed with no card animation at all". Non-zero only for the duration of
## that call; cleared back to 0.0 right after, so enemy turns (which never
## touch this) always react immediately.
var _pending_reaction_delay: float = 0.0

## Set by _on_turn_started, which BattleState always emits immediately before
## hand_changed when a genuinely new hand is drawn (see _begin_player_turn).
## Consumed by the very next _on_hand_changed so only that rebuild deals the
## hand in -- an ordinary hand_changed from playing a single card (or from
## discarding at end_turn) must not re-deal the cards still in hand.
var _pending_deal: bool = false

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

	screen_fx = ScreenFx.new()
	add_child(screen_fx)
	# The CanvasLayer is what shake offsets; the HUD is a Control, so the
	# full-screen flash can anchor to it.
	screen_fx.bind(layer, hud)

	hud.bring_result_panel_to_front()

func _connect_battle() -> void:
	battle.turn_started.connect(_on_turn_started)
	battle.ap_changed.connect(_on_ap_changed)
	battle.hand_changed.connect(_on_hand_changed)
	battle.fighters_changed.connect(_on_fighters_changed)
	battle.intent_changed.connect(hud.update_intent)
	battle.battle_over.connect(_on_battle_over)

func _on_turn_started(turn_number: int) -> void:
	# Player turn start clears the player's guard by expiry (BattleState
	# expires it here, before this signal). turn_started fires before
	# fighters_changed, so this lands in time to suppress that panel's pulse.
	hud.suppress_player_guard_pulse()
	hud.update_turn(turn_number)
	# turn_started always fires immediately before the hand_changed for the
	# freshly-drawn hand (see BattleState._begin_player_turn) -- arm the very
	# next rebuild to deal the hand in, rather than every rebuild.
	_pending_deal = true

func _on_ap_changed(current: int, maximum: int) -> void:
	hud.update_ap(current, maximum)
	hand_view.refresh_states(battle)

func _on_hand_changed() -> void:
	var deal: bool = _pending_deal
	_pending_deal = false
	hand_view.rebuild(battle, deal)

func _on_fighters_changed() -> void:
	hud.update_fighters(battle)
	hand_view.refresh_states(battle)
	_react_to_damage()

## FighterPanel diffs hp/guard itself and records what it saw, so the whole-view
## reaction can be driven from that without BattleState needing a payload.
##
## For a played card, the card itself takes _pending_reaction_delay seconds to
## travel to its target (see _on_card_chosen), so the reaction is deferred to
## land with the blow instead of firing the instant the card is clicked. An
## enemy attack has no card animation -- _pending_reaction_delay is 0.0 for
## those, so it reacts immediately, exactly as before.
func _react_to_damage() -> void:
	var amount: int = hud.last_damage_amount()
	if amount <= 0:
		return
	var delay: float = _pending_reaction_delay
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_fire_impact.bind(amount))
	else:
		_fire_impact(amount)

func _fire_impact(amount: int) -> void:
	screen_fx.hit_stop()
	screen_fx.shake(Juice.screen_shake_amplitude(amount))
	screen_fx.flash()

func _on_card_chosen(index: int) -> void:
	# battle.play_card() emits fighters_changed synchronously, before this
	# call returns, so the delay for _react_to_damage must be armed before
	# calling it -- there is no "after the fact" hook to detect a played card
	# from inside the signal handler.
	_pending_reaction_delay = Juice.ANTICIPATE_TIME + Juice.LUNGE_TIME
	var played: bool = battle.play_card(index)
	_pending_reaction_delay = 0.0
	# The card only departs the hand once BattleState confirms the play; a
	# rejected play must leave HandView untouched (see HandView.launch_play).
	if played:
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
	# A player who wins at full HP while still holding guard would otherwise
	# get a spurious pulse when restart() zeroes it out.
	hud.suppress_player_guard_pulse()
	hud.suppress_enemy_guard_pulse()
	battle.restart()
