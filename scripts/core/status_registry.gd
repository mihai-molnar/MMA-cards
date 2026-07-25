class_name StatusRegistry
extends RefCounted

## Maps status id -> definition script. To add a status: write the script in
## scripts/core/statuses/ following the StrengthStatus contract, then add one
## line here. The damage pipeline needs no changes.

const DEFINITIONS: Dictionary = {
	&"strength": preload("res://scripts/core/statuses/strength.gd"),
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
