extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_plain_damage(t)
	_test_guard_absorption(t)
	_test_guard_spillover(t)
	_test_strength_applied(t)
	_test_clamping(t)
	_test_preview(t)
	_test_broke_guard(t)

func _make_pair() -> Array:
	return [Fighter.new("Player", 50), Fighter.new("Enemy", 48)]

func _test_plain_damage(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	var result = Combat.resolve_damage(6, player, enemy)
	t.check_eq(result.raw, 6, "unmodified damage passes through at face value")
	t.check_eq(result.absorbed, 0, "no guard means nothing absorbed")
	t.check_eq(result.hp_loss, 6, "all damage reaches hp")
	t.check_eq(enemy.hp, 42, "enemy 48 takes a jab down to 42")

func _test_guard_absorption(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.add_guard(8)
	var result = Combat.resolve_damage(6, player, enemy)
	t.check_eq(result.absorbed, 6, "guard absorbs damage below its value")
	t.check_eq(result.hp_loss, 0, "hp is untouched while guard holds")
	t.check_eq(enemy.guard, 2, "guard is reduced by what it absorbed")
	t.check_eq(enemy.hp, 48, "enemy hp unchanged behind guard")

func _test_guard_spillover(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.add_guard(8)
	var result = Combat.resolve_damage(16, player, enemy)
	t.check_eq(result.absorbed, 8, "guard absorbs up to its value")
	t.check_eq(result.hp_loss, 8, "damage above guard spills to hp")
	t.check_eq(enemy.guard, 0, "guard is spent")
	t.check_eq(enemy.hp, 40, "enemy takes the spillover")

func _test_strength_applied(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	var result = Combat.resolve_damage(8, enemy, player)
	t.check_eq(result.raw, 12, "2 strength turns an 8 attack into 12")
	t.check_eq(player.hp, 38, "player takes the buffed hit")

	# Player guard 5 against that same buffed 12 leaves 7 through.
	var pair2: Array = _make_pair()
	var player2: Fighter = pair2[0]
	var enemy2: Fighter = pair2[1]
	enemy2.statuses.apply(StrengthStatus.ID, 2, 2)
	player2.add_guard(5)
	Combat.resolve_damage(8, enemy2, player2)
	t.check_eq(player2.hp, 43, "guard 5 vs buffed 12 leaves 7 through")

func _test_clamping(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	var result = Combat.resolve_damage(-5, player, enemy)
	t.check_eq(result.raw, 0, "negative damage clamps to 0")
	t.check_eq(enemy.hp, 48, "negative damage cannot heal")

	Combat.resolve_damage(999, player, enemy)
	t.check_eq(enemy.hp, 0, "overkill floors hp at 0")

func _test_preview(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	t.check_eq(Combat.preview_damage(8, enemy, player), 8, "preview of an unbuffed attack is 8")
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(Combat.preview_damage(8, enemy, player), 12, "preview reflects strength for the intent display")
	t.check_eq(player.hp, 50, "preview_damage never mutates the target")
	t.check_eq(enemy.hp, 48, "preview_damage never mutates the source")

## broke_guard: the target HAD guard and the hit took it to exactly zero. An
## exact soak counts (the guard broke; nothing got through -- yet). No guard
## to begin with is not a break.
func _test_broke_guard(t: TestRunner) -> void:
	var source := Fighter.new("A", 50)

	var unguarded := Fighter.new("B", 50)
	t.check(not Combat.resolve_damage(5, source, unguarded).broke_guard,
		"no guard means no break")

	var high_guard := Fighter.new("B", 50)
	high_guard.add_guard(8)
	t.check(not Combat.resolve_damage(5, source, high_guard).broke_guard,
		"guard surviving the hit is not a break")
	t.check_eq(high_guard.guard, 3, "guard chipped to 3")

	var exact := Fighter.new("B", 50)
	exact.add_guard(5)
	var exact_result: Combat.DamageResult = Combat.resolve_damage(5, source, exact)
	t.check(exact_result.broke_guard, "an exact soak IS a break")
	t.check_eq(exact_result.hp_loss, 0, "the exact soak cost no hp")

	var punched := Fighter.new("B", 50)
	punched.add_guard(3)
	var punched_result: Combat.DamageResult = Combat.resolve_damage(5, source, punched)
	t.check(punched_result.broke_guard, "punching through remaining guard is a break")
	t.check_eq(punched_result.hp_loss, 2, "the overflow hit hp")
