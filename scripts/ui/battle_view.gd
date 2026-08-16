class_name BattleView
extends Node2D

## Entry point, attached to level.tscn. Owns the BattleState, builds the UI, and
## translates signals in both directions. It never computes rules.

var battle: BattleState
var run: RunState
var hud: BattleHud
var hand_view: HandView
var status_tooltip: StatusTooltip
var screen_fx: ScreenFx
var sound_fx: SoundFx

## Set by _on_card_chosen just before calling battle.play_card(), which emits
## fighters_changed synchronously -- so this is the only way _react_to_damage
## can tell "a card is about to travel to its target" from "an enemy attack
## landed with no card animation at all". Non-zero only for the duration of
## that call; cleared back to 0.0 right after, so enemy turns (which never
## touch this) always react immediately.
var _pending_reaction_delay: float = 0.0

## The hit sound the in-flight attack warrants, armed the same way and for
## the same reason as _pending_reaction_delay: fighters_changed fires
## synchronously from inside play_card()/end_turn(), so the sound choice
## must be decided before the call and captured per-event -- the deferred
## fighter update binds it, so a racing second event cannot overwrite an
## in-flight one. Empty for every fighters_changed that is not an attack
## resolving (guard expiry, buffs), which therefore stays silent.
var _pending_hit_sound: StringName = &""

## Set by _on_turn_started, which BattleState always emits immediately before
## hand_changed when a genuinely new hand is drawn (see _begin_player_turn).
## Consumed by the very next _on_hand_changed so only that rebuild deals the
## hand in -- an ordinary hand_changed from playing a single card (or from
## discarding at end_turn) must not re-deal the cards still in hand.
var _pending_deal: bool = false

func _ready() -> void:
	run = RunState.new()
	_build_ui()
	_start_fight()

## One call per fight: a fresh BattleState against the run's current
## opponent, seeded with the carried hp. The old BattleState (and its
## signal connections) is dropped with the reassignment -- deferred
## timers that fire afterwards re-read `battle` and see the new fight.
## The stage slams first; battle.start() -- and with it the deal -- waits
## for the collision to settle, so the fight opens on the impact, not
## under it. Model state is never gated on animation: nothing exists to
## input into until start() runs.
func _start_fight() -> void:
	var opponent: OpponentData = run.current_opponent()
	battle = BattleState.new(0, opponent, run.player_hp)
	_connect_battle()
	hud.set_enemy_name(battle.enemy.display_name)
	hand_view.clear()
	status_tooltip.hide_tooltip()
	hud.stage().set_portraits(&"player", opponent.id)
	hud.stage().slam_in(_on_slam_impact, _on_slam_settled)

## The collision frame: the metal-plates hit the user asked for.
func _on_slam_impact() -> void:
	screen_fx.hit_stop(Juice.SLAM_HIT_STOP)
	screen_fx.shake(Juice.SLAM_SHAKE_AMPLITUDE)
	screen_fx.flash()
	sound_fx.play(&"slam")

func _on_slam_settled() -> void:
	battle.start()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = BattleHud.new()
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	hud.continue_pressed.connect(_on_continue_pressed)
	layer.add_child(hud)

	hand_view = HandView.new()
	hand_view.card_chosen.connect(_on_card_chosen)
	hand_view.card_hovered.connect(_on_card_hovered)
	hud.add_child(hand_view)

	# A sibling of HandView, never a child: rebuild() frees every hand child.
	# Its own z_index keeps it above hovered and lunging cards.
	status_tooltip = StatusTooltip.new()
	hud.add_child(status_tooltip)

	# Attacks fly at the enemy, Block pulls back to the player.
	hand_view.set_lunge_anchors(hud.enemy_centre(), hud.player_centre())

	screen_fx = ScreenFx.new()
	add_child(screen_fx)
	sound_fx = SoundFx.new()
	add_child(sound_fx)
	# The CanvasLayer is what shake offsets; the HUD is a Control, so the
	# full-screen flash can anchor to it.
	screen_fx.bind(layer, hud)

	hud.bring_result_panel_to_front()

func _connect_battle() -> void:
	battle.turn_started.connect(_on_turn_started)
	battle.ap_changed.connect(_on_ap_changed)
	battle.hand_changed.connect(_on_hand_changed)
	battle.fighters_changed.connect(_on_fighters_changed)
	battle.intent_changed.connect(_on_intent_changed)
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
	# The rebuild frees every card view, including a hovered one -- its
	# hover-off signal dies with it, so the tooltip must be dismissed here.
	status_tooltip.hide_tooltip()
	hand_view.rebuild(battle, deal)
	# Only a genuinely fresh hand fans in; playing or discarding a card
	# rebuilds too and must stay silent.
	if deal:
		sound_fx.play(&"card_fan")

## Shows the status tooltip above the hovered card when its text names a
## registered status (StatusTooltip itself hides for cards that name none).
## rest_position is in HandView space and the tooltip is a HUD sibling, so
## offset by HandView's position. The anchor is the ZOOMED card's top-centre
## -- bottom-centre pivot, so the top rises by the scale delta plus the
## hover lift -- and the panel hangs above that, clear of the enlarged card.
func _on_card_hovered(view: CardView, hovered: bool) -> void:
	if not hovered or view.card == null:
		status_tooltip.hide_tooltip()
		return
	var zoomed_top: float = view.rest_position.y \
		+ CardView.CARD_SIZE.y * (1.0 - Juice.HOVER_SCALE) - Juice.HOVER_LIFT
	var anchor: Vector2 = hand_view.position + Vector2(
		view.rest_position.x + CardView.CARD_SIZE.x / 2.0, zoomed_top)
	status_tooltip.show_for_card(view.card, anchor)

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
	# Bound rather than re-read at fire time: the sound belongs to the attack
	# that caused THIS update, not to whatever is pending when the timer fires.
	var hit_sound: StringName = _pending_hit_sound
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(
			_land_fighter_update.bind(hit_sound))
	else:
		_land_fighter_update(hit_sound)

## The telegraph obeys the same rule as the fighter panels above: the model
## re-emits intent synchronously from inside play_card(), while the card is
## still leaving the hand -- so a Low Kick's halved "ATTACK 4" would appear
## before the kick visibly lands. Defer by the same impact delay, and
## re-read the CURRENT intent at fire time rather than capturing the emitted
## text: an immediate update racing a still-in-flight deferred one (playing
## a card, then ending the turn inside the delay window) then cannot be
## overwritten by stale text -- the late timer rewrites the same current
## value. Enemy-turn updates have no card animation (delay 0) and land
## immediately, exactly like the fighter update.
func _on_intent_changed(text: String) -> void:
	var delay: float = _pending_reaction_delay
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay).timeout.connect(_land_intent_update)
	else:
		hud.update_intent(text)

func _land_intent_update() -> void:
	hud.update_intent(battle.brain.intent_text(battle.enemy, battle.player))

## FighterPanel diffs hp/guard itself and records what it saw, so the
## whole-view impact can be driven from that without BattleState needing a
## payload. Safe to run late or twice: a second update with nothing new to
## diff records "none" and last_damage_amount() returns 0.
func _land_fighter_update(hit_sound: StringName = &"") -> void:
	hud.update_fighters(battle)
	var amount: int = hud.last_damage_amount()
	# A fully blocked hit costs no hp, so it takes none of the impact juice
	# below -- but it still SOUNDS: impact_sound swaps the attack's own sound
	# for a slap when guard soaked all of it.
	var sound: StringName = SoundFx.impact_sound(
		hit_sound, amount, hud.last_absorb_amount())
	if sound != &"":
		sound_fx.play(sound)
	if amount > 0:
		_fire_impact(amount)
		var side: StringName = hud.last_damage_side()
		hud.stage().flash_hit(side)
		hud.stage().shake(side, Juice.portrait_shake_amplitude(amount))

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
	var card: CardData = battle.deck.hand[index] \
		if index >= 0 and index < battle.deck.hand.size() else null
	_pending_hit_sound = SoundFx.hit_sound_for_card(card)
	_pending_reaction_delay = Juice.play_impact_delay()
	var played: bool = battle.play_card(index)
	_pending_reaction_delay = 0.0
	_pending_hit_sound = &""
	# The card only departs the hand once BattleState confirms the play; a
	# rejected play must leave HandView untouched (see HandView.launch_play).
	if played:
		hand_view.launch_play(index)

func _on_end_turn_pressed() -> void:
	sound_fx.play(&"click")
	# Enemy turn start clears the enemy's guard by expiry, inside end_turn().
	# Suppress before calling it so that expiry doesn't read as an absorb.
	hud.suppress_enemy_guard_pulse()
	# The enemy attack has no card animation and lands immediately, so its
	# hit sound is decided from the coming turn's moves before they resolve.
	_pending_hit_sound = SoundFx.hit_sound_for_moves(battle.brain.current_moves())
	battle.end_turn()
	_pending_hit_sound = &""

## The banner waits for the killing blow to land (plus a beat) when the win
## came from a played card -- battle_over is emitted synchronously from
## inside play_card(), while the card has not even left the hand, and a
## banner at that instant hides the entire payoff. RESULT_BEAT stacks on the
## impact delay so this timer always fires after _land_fighter_update's.
## The run records the result immediately (model state, like the battle
## itself); only the banner is deferred.
func _on_battle_over(player_won: bool) -> void:
	run.record_result(player_won, battle.player.hp)
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
	if not player_won:
		hud.show_defeat()
	elif run.is_complete():
		hud.show_run_complete()
	else:
		hud.show_fight_intro(run.fight_number(), run.current_opponent().display_name)
	hand_view.refresh_states(battle)

## CONTINUE: the next fight of the same run, carried hp and all.
func _on_continue_pressed() -> void:
	sound_fx.play(&"click")
	hud.hide_result()
	_suppress_transition_guard_pulses()
	_start_fight()

## RESTART: the whole run from fight 1 at full hp -- a loss and a completed
## run both land here.
func _on_restart_pressed() -> void:
	sound_fx.play(&"click")
	hud.hide_result()
	_suppress_transition_guard_pulses()
	run.reset()
	_start_fight()

## A fighter who ends a battle still holding guard would otherwise read the
## fresh fight's zeroed guard as an absorb and pulse. Same reasoning as the
## per-turn expiry suppressions -- a fight boundary is a guard expiry, not
## a block.
func _suppress_transition_guard_pulses() -> void:
	hud.suppress_player_guard_pulse()
	hud.suppress_enemy_guard_pulse()
