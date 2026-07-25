class_name GuardEffect
extends CardEffect

@export var amount: int = 0

func apply(source: Fighter, _target: Fighter, context: Dictionary) -> void:
	source.add_guard(amount)
	context["log"].append("%s gains %d guard" % [source.display_name, amount])

func describe() -> String:
	return "Gain %d guard." % amount
