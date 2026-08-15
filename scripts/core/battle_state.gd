class_name BattleState
extends RefCounted

## The turn state machine and the only thing that mutates the battle. Emits
## signals for the view; never touches the scene tree itself.
##
## Turn order per round:
##   player turn start -> player acts -> player turn end -> enemy turn -> repeat
##
## Guard expires at its owner's turn START (so it survives the opponent's turn).
## Status timers decrement at its owner's turn END.

signal turn_started(turn_number: int)
signal ap_changed(current: int, maximum: int)
signal hand_changed()
signal card_played(card: CardData, combo_bonus: int)
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

var _combo_rules: Array[ComboRule] = []
var _play_history: Array[CardData] = []
var _rng_seed: int = 0

func _init(rng_seed: int = 0) -> void:
	_rng_seed = rng_seed
	player = Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	enemy = Fighter.new("Enemy", BattleConfig.ENEMY_MAX_HP)
	deck = Deck.new(CardLibrary.build_starting_deck(), rng_seed)
	brain = EnemyBrain.new()
	_combo_rules = [ComboRule.jab_straight()] as Array[ComboRule]

func start() -> void:
	is_over = false
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

	var context: Dictionary = {"bonus_damage": bonus, "results": [], "log": []}
	for effect: CardEffect in card.effects:
		effect.apply(player, enemy, context)

	_play_history.append(card)
	_emit_log(context)

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
	_check_battle_over()
	return true

func end_turn() -> void:
	if is_over:
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
