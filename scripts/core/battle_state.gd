class_name BattleState
extends RefCounted

## The turn state machine and the only thing that mutates the battle. Emits
## signals for the view; never touches the scene tree itself.
##
## Turn order per round:
##   player turn start -> player acts -> player turn end -> enemy turn -> repeat
##
## Guard expires at its owner's turn START (so it survives the opponent's turn).
## Turn-start status hooks (Prepared's delayed guard) fire right after that expiry.
## Status timers decrement at its owner's turn END.

signal turn_started(turn_number: int)
signal ap_changed(current: int, maximum: int)
signal hand_changed()
signal card_played(card: CardData, combo_bonus: int)
## A play produced a SECOND damage result (One-Two breaking guard): the
## follow-up hit's own hp/absorb split, announced BEFORE fighters_changed so
## the view can split the fighter update into two visible beats. The model
## itself is already at its final state -- this is presentation information,
## not a second mutation.
signal follow_up_hit(hp_loss: int, absorbed: int)
## A play attempted a KO roll (a KOChanceEffect whose hit dealt hp damage).
## Exactly one of these fires per attempt, BEFORE fighters_changed -- the
## view binds the splash into the same deferred update, like follow_up_hit.
## On a scored KO, battle_over(true) still follows at the end of the play.
signal ko_scored()
signal ko_failed()
signal fighters_changed()
signal intent_changed(text: String)
signal log_line(text: String)
signal battle_over(player_won: bool)

var player: Fighter
var enemy: Fighter
var deck: Deck
var brain: EnemyBrain
var turn_number: int = 0
var ap: int = 0
var is_over: bool = false
## True when the current battle ended by a scored KO rather than hp reaching
## zero. Cleared by start().
var won_by_ko: bool = false

var _combo_rules: Array[ComboRule] = []
var _play_history: Array[CardData] = []
var _rng_seed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## `opponent` null means the first opponent of the run -- every pre-run call
## site (and test) that wrote BattleState.new() or BattleState.new(seed)
## keeps working and keeps fighting the brawler. `starting_hp <= 0` means
## full hp; a run passes the carried hp here. `deck_ids` empty means the
## starting deck; a run passes its persistent deck here. Note restart() returns the
## player to FULL hp regardless of starting_hp -- only tests call it; the
## run flow builds a fresh BattleState per fight instead.
func _init(rng_seed: int = 0, opponent: OpponentData = null, starting_hp: int = -1,
		deck_ids: Array[StringName] = []) -> void:
	_rng_seed = rng_seed
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	var chosen: OpponentData = opponent if opponent != null else OpponentLibrary.opponent(BattleConfig.RUN_OPPONENTS[0])
	player = Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	if starting_hp > 0:
		player.hp = mini(starting_hp, BattleConfig.PLAYER_MAX_HP)
	enemy = Fighter.new(chosen.display_name, chosen.max_hp)
	var cards: Array[CardData] = CardLibrary.build_starting_deck() if deck_ids.is_empty() \
		else CardLibrary.build_deck(deck_ids)
	deck = Deck.new(cards, rng_seed)
	brain = EnemyBrain.new(chosen)
	_combo_rules = [ComboRule.jab_straight()] as Array[ComboRule]

func start() -> void:
	is_over = false
	won_by_ko = false
	turn_number = 0
	_begin_player_turn()

func restart() -> void:
	player.reset()
	enemy.reset()
	deck.reset(CardLibrary.build_starting_deck())
	brain.reset()
	start()

## Bonus damage the card at `index` would gain from a combo right now.
func combo_bonus_for(index: int) -> int:
	if index < 0 or index >= deck.hand.size():
		return 0
	var card: CardData = deck.hand[index]
	var best: int = 0
	for rule: ComboRule in _combo_rules:
		best = maxi(best, rule.evaluate(_play_history, card))
	return best

func can_play(index: int) -> bool:
	if is_over:
		return false
	if index < 0 or index >= deck.hand.size():
		return false
	return deck.hand[index].cost <= ap

func play_card(index: int) -> bool:
	if not can_play(index):
		return false

	var bonus: int = combo_bonus_for(index)
	var card: CardData = deck.take_from_hand(index)
	ap -= card.cost
	_resolve_play(card, bonus, true)
	return true

## DEV ONLY (the backquote dev menu): plays `card` against the enemy with no
## AP cost and no hand involvement, through the exact same resolve path as
## play_card, so KO, Bleed and every signal fire normally. The card is a
## fresh instance outside the deck's piles -- the deck invariant is
## untouched. Guarded like end_turn: nothing plays before start() opens
## turn 1 or after the fight ends.
func dev_play(card: CardData) -> void:
	if is_over or turn_number == 0 or card == null:
		return
	_resolve_play(card, 0, false)

## The shared back half of a play: applies `card`'s effects player->enemy,
## announces everything, and settles KO / battle-over. `record_history` is
## true for a real hand play (combo history) and false for dev_play.
func _resolve_play(card: CardData, bonus: int, record_history: bool) -> void:
	var context: Dictionary = {"bonus_damage": bonus, "results": [], "log": [], "rng": _rng}
	for effect: CardEffect in card.effects:
		effect.apply(player, enemy, context)

	if record_history:
		_play_history.append(card)
	_emit_log(context)

	# Two damage results means a follow-up hit landed (today: One-Two through
	# broken guard). Announced before the *_changed signals below so the view
	# can bind the split into the same deferred update those signals drive.
	var results: Array = context["results"]
	if results.size() == 2:
		var second: Combat.DamageResult = results[1]
		follow_up_hit.emit(second.hp_loss, second.absorbed)

	# A KO attempt is announced the same way -- before fighters_changed --
	# so the view lands the splash with the hit. The fight itself ends at
	# the bottom of this function, where battle_over always fires.
	var ko_success: bool = context.get("ko", false)
	if context.get("ko_attempted", false):
		if ko_success:
			ko_scored.emit()
		else:
			ko_failed.emit()

	card_played.emit(card, bonus)
	ap_changed.emit(ap, BattleConfig.AP_PER_TURN)
	hand_changed.emit()
	fighters_changed.emit()
	# A card can change what the telegraphed enemy action will actually do --
	# Low Kick halves the coming attack the moment it lands -- and
	# preview_damage's contract is that the telegraph never diverges from
	# what resolve_damage would produce. Re-telegraph after every play, so
	# "ATTACK 8" becomes "ATTACK 4" in real time instead of lying until the
	# turn ends.
	intent_changed.emit(brain.intent_text(enemy, player))
	if ko_success and not is_over:
		is_over = true
		won_by_ko = true
		log_line.emit("You win by KO!")
		battle_over.emit(true)
	else:
		_check_battle_over()

func end_turn() -> void:
	if is_over:
		return
	# turn_number is 0 until start() opens turn 1. The view defers start()
	# behind the slam animation while the End Turn button already exists, so
	# a click in that window must not run an enemy turn or draw a hand.
	if turn_number == 0:
		return
	deck.discard_hand()
	player.tick_statuses_turn_end()
	hand_changed.emit()

	_run_enemy_turn()
	if is_over:
		return
	_begin_player_turn()

func _begin_player_turn() -> void:
	turn_number += 1
	player.expire_guard()
	StatusRegistry.apply_turn_start(player)
	if _check_battle_over():
		return
	_play_history.clear()
	deck.draw(BattleConfig.HAND_SIZE)
	ap = BattleConfig.AP_PER_TURN

	turn_started.emit(turn_number)
	ap_changed.emit(ap, BattleConfig.AP_PER_TURN)
	hand_changed.emit()
	fighters_changed.emit()
	intent_changed.emit(brain.intent_text(enemy, player))

func _run_enemy_turn() -> void:
	enemy.expire_guard()
	StatusRegistry.apply_turn_start(enemy)
	# A turn-start status (Bleed) can finish a fighter before it acts.
	if _check_battle_over():
		return

	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	_emit_log(context)

	fighters_changed.emit()
	if _check_battle_over():
		return

	enemy.tick_statuses_turn_end()
	brain.advance()
	intent_changed.emit(brain.intent_text(enemy, player))

## Ends the battle if either fighter is down. Returns true if it ended.
func _check_battle_over() -> bool:
	if is_over:
		return true
	if not enemy.is_alive():
		is_over = true
		log_line.emit("Enemy is down. You win!")
		battle_over.emit(true)
		return true
	if not player.is_alive():
		is_over = true
		log_line.emit("You are down. You lose.")
		battle_over.emit(false)
		return true
	return false

func _emit_log(context: Dictionary) -> void:
	for line: String in context["log"]:
		log_line.emit(line)
