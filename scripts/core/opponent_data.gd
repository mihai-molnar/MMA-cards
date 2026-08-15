class_name OpponentData
extends RefCounted

## One opponent: identity, hit points, and the fixed rotation EnemyBrain
## steps through. `rotation` is an Array of turns; each turn is an Array
## whose elements are OpponentMove, resolved in listed order. Built in code
## by OpponentLibrary -- nothing here is loaded from disk.

var id: StringName
var display_name: String
var max_hp: int
var rotation: Array[Array] = []

func _init(p_id: StringName, p_display_name: String, p_max_hp: int, p_rotation: Array[Array]) -> void:
	id = p_id
	display_name = p_display_name
	max_hp = p_max_hp
	rotation = p_rotation
