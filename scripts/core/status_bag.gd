class_name StatusBag
extends RefCounted

## Stack-based statuses with a turn countdown.
## turns_remaining of BattleConfig.STATUS_PERMANENT (-1) never expires.

var _entries: Dictionary = {}

func apply(id: StringName, stacks: int, turns_remaining: int) -> void:
	if stacks <= 0:
		return
	if _entries.has(id):
		var entry: Dictionary = _entries[id]
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
