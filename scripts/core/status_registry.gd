class_name StatusRegistry
extends RefCounted

## Maps status id -> definition script. To add a status: write the script in
## scripts/core/statuses/ following the StrengthStatus contract, then add one
## line here. The damage pipeline needs no changes.

const DEFINITIONS: Dictionary = {
	&"strength": preload("res://scripts/core/statuses/strength.gd"),
	&"leg_injury": preload("res://scripts/core/statuses/leg_injury.gd"),
	&"prepared": preload("res://scripts/core/statuses/prepared.gd"),
}

static func modify_outgoing(bag: StatusBag, amount: int) -> int:
	var result: int = amount
	for id: StringName in bag.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		result = definition.modify_outgoing_damage(result, bag.get_stacks(id))
	return result

static func modify_incoming(bag: StatusBag, amount: int) -> int:
	var result: int = amount
	for id: StringName in bag.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		result = definition.modify_incoming_damage(result, bag.get_stacks(id))
	return result

static func display_name(id: StringName) -> String:
	if not DEFINITIONS.has(id):
		return String(id).to_upper()
	var definition: GDScript = DEFINITIONS[id]
	return definition.DISPLAY_NAME

## What the status does, in player-facing words -- the hover tooltip's body.
## Empty for an unregistered id: the tooltip simply has nothing to explain.
static func description(id: StringName) -> String:
	if not DEFINITIONS.has(id):
		return ""
	var definition: GDScript = DEFINITIONS[id]
	return definition.description()

## Which number display code prints beside this status: true for a countdown
## (Leg Injury's remaining turns), false for a magnitude (strength stacks).
static func shows_turns(id: StringName) -> bool:
	if not DEFINITIONS.has(id):
		return false
	var definition: GDScript = DEFINITIONS[id]
	return definition.SHOW_TURNS

## Fires every active status's on_turn_start at its owner's turn start
## (BattleState calls this immediately after expire_guard(), on both sides).
## A hook returning true is consumed -- removed from the bag. ids() returns
## a copy of the keys, so removing while iterating is safe.
static func apply_turn_start(fighter: Fighter) -> void:
	for id: StringName in fighter.statuses.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		if definition.on_turn_start(fighter, fighter.statuses.get_stacks(id)):
			fighter.statuses.remove(id)
