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

## The ENTIRE fighter-side reaction is deferred for a played card -- HP text,
## panel flash, damage number, rect shake AND the whole-view impact -- not
## just the screen effects. Deferring only the impact (the old behaviour)
## let FighterPanel's own diff-driven feedback fire the instant the model
## changed, so HP visibly dropped while the card was still leaving the hand.
## The model updates immediately; the VIEW of the fighters lags by exactly
## the card's travel-to-impact time. An enemy attack has no card animation
## (_pending_reaction_delay is 0.0), so it lands immediately, exactly as
## before. Hand affordability is NOT deferred: AP was genuinely spent the
## moment the card was played, and the hand should dim right away.
func _on_fighters_changed() -> void:
	hand_view.refresh_states(battle)
	var delay: float = _pending_reaction_delay
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_land_fighter_update)
	else:
		_land_fighter_update()

## FighterPanel diffs hp/guard itself and records what it saw, so the
## whole-view impact can be driven from that without BattleState needing a
## payload. Safe to run late or twice: a second update with nothing new to
## diff records "none" and last_damage_amount() returns 0.
func _land_fighter_update() -> void:
	hud.update_fighters(battle)
	var amount: int = hud.last_damage_amount()
	if amount > 0:
		_fire_impact(amount)

func _fire_impact(amount: int) -> void:
	# Both the freeze and the kick scale with the damage that landed, so a
	# combo Straight reads meaningfully heavier than a jab.
	screen_fx.hit_stop(Juice.hit_stop_duration(amount))
	screen_fx.shake(Juice.screen_shake_amplitude(amount))
	screen_fx.flash()

func _on_card_chosen(index: int) -> void:
	# battle.play_card() emits fighters_changed synchronously, before this
	# call returns, so the delay for _on_fighters_changed must be armed before
	# calling it -- there is no "after the fact" hook to detect a played card
	# from inside the signal handler.
	_pending_reaction_delay = Juice.play_impact_delay()
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

## The banner waits for the killing blow to land (plus a beat) when the win
## came from a played card -- battle_over is emitted synchronously from
## inside play_card(), while the card has not even left the hand, and a
## banner at that instant hides the entire payoff. RESULT_BEAT stacks on the
## impact delay so this timer always fires after _land_fighter_update's.
func _on_battle_over(player_won: bool) -> void:
	var delay: float = _pending_reaction_delay
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay + Juice.RESULT_BEAT).timeout.connect(
			_show_result.bind(player_won))
	else:
		_show_result(player_won)

func _show_result(player_won: bool) -> void:
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
