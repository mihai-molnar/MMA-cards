class_name StatusBag
extends RefCounted

## Stack-based statuses with a turn countdown.
## turns_remaining of BattleConfig.STATUS_PERMANENT (-1) never expires.

var _entries: Dictionary = {}

func apply(id: StringName, stacks: int, turns_remaining: int, extend_duration: bool = false) -> void:
	if stacks <= 0:
		return
	if _entries.has(id):
		var entry: Dictionary = _entries[id]
		if extend_duration:
			# A duration-stacking status (Low Kick's Leg Injury): each
			# application keeps the effect alive LONGER rather than deeper --
			# turns add, stacks take the larger of the two. Permanence still
			# dominates instead of arithmetic-ing on the -1 sentinel.
			entry["stacks"] = maxi(entry["stacks"], stacks)
			if entry["turns"] != BattleConfig.STATUS_PERMANENT:
				if turns_remaining == BattleConfig.STATUS_PERMANENT:
					entry["turns"] = BattleConfig.STATUS_PERMANENT
				else:
					entry["turns"] = entry["turns"] + turns_remaining
		else:
			entry["stacks"] = entry["stacks"] + stacks
			# Refreshing takes the longer of the two durations; permanent always wins.
			if entry["turns"] != BattleConfig.STATUS_PERMANENT:
				if turns_remaining == BattleConfig.STATUS_PERMANENT:
					entry["turns"] = BattleConfig.STATUS_PERMANENT
				else:
					entry["turns"] = maxi(entry["turns"], turns_remaining)
	else:
		_entries[id] = {"stacks": stacks, "turns": turns_remaining}

func get_stacks(id: StringName) -> int:
	if not _entries.has(id):
		return 0
	return _entries[id]["stacks"]

## Remaining turns, 0 when absent. BattleConfig.STATUS_PERMANENT (-1) comes
## back verbatim -- display code should not print it as a countdown.
func get_turns(id: StringName) -> int:
	if not _entries.has(id):
		return 0
	return _entries[id]["turns"]

func has(id: StringName) -> bool:
	return _entries.has(id)

func ids() -> Array:
	return _entries.keys()

func tick_turn_end() -> void:
	for id: StringName in _entries.keys():
		var entry: Dictionary = _entries[id]
		if entry["turns"] == BattleConfig.STATUS_PERMANENT:
			continue
		entry["turns"] = entry["turns"] - 1
		if entry["turns"] <= 0:
			_entries.erase(id)

func clear() -> void:
	_entries.clear()
