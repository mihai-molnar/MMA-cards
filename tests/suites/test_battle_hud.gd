extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_fight_intro_banner(t)
	_test_defeat_banner(t)
	_test_run_complete_banner(t)
	_test_continue_signal_and_focus(t)
	_test_enemy_name(t)
	_test_stage_is_bottom_layer(t)
	_test_lunge_anchors_are_portrait_centres(t)
	_test_ap_routes_to_player_panel(t)
	_test_last_damage_side(t)
	_test_last_absorb_amount(t)

func _test_fight_intro_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_fight_intro(2, "Kickboxer")
	t.check_eq(hud.debug_result_text(), "FIGHT 2: KICKBOXER", "the intro banner names the coming fight")
	t.check(hud.debug_continue_button().visible, "the intro banner offers CONTINUE")
	t.check(not hud.debug_restart_button().visible, "the intro banner hides RESTART")
	hud.free()

func _test_defeat_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_defeat()
	t.check_eq(hud.debug_result_text(), "YOU LOSE", "the defeat banner reads YOU LOSE")
	t.check(hud.debug_restart_button().visible, "the defeat banner offers RESTART")
	t.check(not hud.debug_continue_button().visible, "the defeat banner hides CONTINUE")
	hud.free()

func _test_run_complete_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_run_complete()
	t.check_eq(hud.debug_result_text(), "RUN COMPLETE", "beating the last opponent completes the run")
	t.check(hud.debug_restart_button().visible, "the run-complete banner offers RESTART")
	t.check(not hud.debug_continue_button().visible, "the run-complete banner hides CONTINUE")
	hud.free()

func _test_continue_signal_and_focus(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.debug_continue_button().focus_mode, Control.FOCUS_NONE, "CONTINUE never grabs focus")
	t.check_eq(hud.debug_restart_button().focus_mode, Control.FOCUS_NONE, "RESTART never grabs focus")
	var fired: Array = []
	hud.continue_pressed.connect(func() -> void: fired.append(true))
	hud.debug_continue_button().pressed.emit()
	t.check_eq(fired.size(), 1, "pressing CONTINUE emits continue_pressed")
	hud.free()

func _test_enemy_name(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.set_enemy_name("Kickboxer")
	t.check_eq(hud.debug_enemy_panel().fighter_name(), "KICKBOXER", "the enemy panel shows the opponent's real name")
	hud.free()

func _test_stage_is_bottom_layer(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check(hud.stage() != null, "the hud owns a FightStage")
	t.check_eq(hud.get_child(0), hud.stage(), "the stage is the first child -- everything draws over it")
	hud.free()

func _test_lunge_anchors_are_portrait_centres(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.enemy_centre(), Vector2(864, 324), "attacks fly at the enemy portrait's centre")
	t.check_eq(hud.player_centre(), Vector2(288, 324), "block pulls back to the player portrait's centre")
	hud.free()

func _test_ap_routes_to_player_panel(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.update_ap(2, 3)
	t.check_eq(hud.debug_player_panel().debug_ap_text(), "2 / 3", "AP renders inside the player's bolt icon")
	hud.free()

func _test_last_damage_side(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.last_damage_side(), &"none", "no update yet, no side")

	var battle := BattleState.new(12345)
	battle.start()
	hud.update_fighters(battle)
	t.check_eq(hud.last_damage_side(), &"none", "the baseline update reports no side")

	battle.enemy.hp -= 4
	hud.update_fighters(battle)
	t.check_eq(hud.last_damage_side(), &"enemy", "an enemy hp drop reads as the enemy side")

	battle.player.hp -= 6
	hud.update_fighters(battle)
	t.check_eq(hud.last_damage_side(), &"player", "a player hp drop reads as the player side")

	battle.player.hp -= 3
	battle.enemy.hp -= 3
	hud.update_fighters(battle)
	t.check_eq(hud.last_damage_side(), &"player", "an equal double hit ties to the player side")
	hud.free()

## The absorb mirror of last_damage_amount(): how much guard the most recent
## update saw soaked with hp untouched -- what tells the view a hit was
## fully blocked (the slap) rather than landed (the punch).
func _test_last_absorb_amount(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.last_absorb_amount(), 0, "no update yet, no absorb")

	var battle := BattleState.new(12345)
	battle.start()
	battle.player.guard = 5
	hud.update_fighters(battle)
	t.check_eq(hud.last_absorb_amount(), 0, "gaining guard is not an absorb")

	battle.player.guard = 2
	hud.update_fighters(battle)
	t.check_eq(hud.last_absorb_amount(), 3,
		"a guard drop with hp untouched reads as that much absorbed")

	battle.player.guard = 0
	battle.player.hp -= 4
	hud.update_fighters(battle)
	t.check_eq(hud.last_absorb_amount(), 0,
		"a broken-through hit reads as damage, not absorb")

	battle.enemy.guard = 6
	hud.update_fighters(battle)
	hud.suppress_enemy_guard_pulse()
	battle.enemy.guard = 0
	hud.update_fighters(battle)
	t.check_eq(hud.last_absorb_amount(), 0,
		"a suppressed guard expiry does not read as an absorb")
	hud.free()
