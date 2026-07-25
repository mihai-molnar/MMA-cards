class_name Fighter
extends RefCounted

## A combatant's mutable state. Knows nothing about turns, cards, or the scene
## tree — BattleState drives it.

var display_name: String
var max_hp: int
var hp: int
var guard: int = 0
var statuses: StatusBag

func _init(p_display_name: String, p_max_hp: int) -> void:
	display_name = p_display_name
	max_hp = p_max_hp
	hp = p_max_hp
	statuses = StatusBag.new()

func is_alive() -> bool:
	return hp > 0

func add_guard(amount: int) -> void:
	if amount <= 0:
		return
	guard += amount

## Returns how much of `amount` the guard absorbed, and consumes that guard.
func absorb_into_guard(amount: int) -> int:
	var absorbed: int = mini(guard, maxi(amount, 0))
	guard -= absorbed
	return absorbed

## Returns hp actually lost (never more than the hp that existed).
func apply_hp_loss(amount: int) -> int:
	var loss: int = mini(maxi(amount, 0), hp)
	hp -= loss
	return loss

func expire_guard() -> void:
	guard = 0

func tick_statuses_turn_end() -> void:
	statuses.tick_turn_end()

func reset() -> void:
	hp = max_hp
	guard = 0
	statuses.clear()
