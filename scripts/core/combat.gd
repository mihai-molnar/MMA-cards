class_name Combat
extends RefCounted

## The single damage pipeline. Every point of damage in the game flows through
## resolve_damage, player and enemy alike:
##   base -> attacker outgoing -> defender incoming -> clamp -> guard -> hp

class DamageResult extends RefCounted:
	var raw: int = 0
	var absorbed: int = 0
	var hp_loss: int = 0
	## The hit took the target's guard from above zero to exactly zero. An
	## exact soak counts -- the guard broke even though nothing got through.
	var broke_guard: bool = false

	func _init(p_raw: int, p_absorbed: int, p_hp_loss: int, p_broke_guard: bool = false) -> void:
		raw = p_raw
		absorbed = p_absorbed
		hp_loss = p_hp_loss
		broke_guard = p_broke_guard

static func resolve_damage(base: int, source: Fighter, target: Fighter) -> DamageResult:
	var amount: int = base
	amount = StatusRegistry.modify_outgoing(source.statuses, amount)
	amount = StatusRegistry.modify_incoming(target.statuses, amount)
	amount = maxi(amount, 0)

	var had_guard: bool = target.guard > 0
	var absorbed: int = target.absorb_into_guard(amount)
	var hp_loss: int = target.apply_hp_loss(amount - absorbed)
	return DamageResult.new(amount, absorbed, hp_loss, had_guard and target.guard == 0)

## What `base` would hit for, applying the same modifier pipeline as
## resolve_damage (outgoing then incoming, then the clamp) without the guard
## or hp steps. Used by the enemy intent telegraph — it must not mutate
## anything, and it must never diverge from what resolve_damage would
## actually produce, or the telegraph lies.
static func preview_damage(base: int, source: Fighter, target: Fighter) -> int:
	var amount: int = base
	amount = StatusRegistry.modify_outgoing(source.statuses, amount)
	amount = StatusRegistry.modify_incoming(target.statuses, amount)
	return maxi(amount, 0)
