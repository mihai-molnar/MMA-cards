extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_fight_intro_banner(t)
	_test_defeat_banner(t)
	_test_run_complete_banner(t)
	_test_continue_signal_and_focus(t)
	_test_enemy_name(t)

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
