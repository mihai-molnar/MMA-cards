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
	_test_status_hover_forwarded(t)
	_test_guard_hover_forwarded(t)
	_test_pile_readouts_are_icon_counts(t)
	_test_pile_icons_are_clickable(t)
	_test_burned_icon_appears_with_burned_cards(t)
	_test_update_fighters_mid_hit(t)
	_test_end_turn_button_texture_states(t)
	_test_last_damage_side(t)
	_test_last_absorb_amount(t)

## The first beat of a multi-hit play: the enemy panel presents the model's
## state MINUS the follow-up hit, so its diff pulses only the first hit; the
## normal update that follows lands the rest. The player panel and pile
## counts behave exactly as in update_fighters.
func _test_update_fighters_mid_hit(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(5)
	battle.start()
	hud.update_fighters(battle)

	battle.enemy.apply_hp_loss(7)
	hud.update_fighters_mid_hit(battle, 5, 0)
	var enemy_panel: FighterPanel = hud.debug_enemy_panel()
	t.check_eq(enemy_panel.debug_last_pulse_kind, &"damage", "the first beat pulses damage")
	t.check_eq(enemy_panel.debug_last_pulse_amount, 2,
		"the first beat pulses the total minus the held-back follow-up")

	hud.update_fighters(battle)
	t.check_eq(enemy_panel.debug_last_pulse_amount, 5, "the second beat pulses the follow-up")
	hud.free()

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
	t.check_eq(hud.debug_ap_text(), "2 / 3",
		"AP renders in the HUD's own bottom-left bolt readout")
	t.check_eq(BattleHud.AP_ICON_SIZE, FighterPanel.ICON_SIZE,
		"the AP bolt is as large as the HP hearts -- it must read at a glance")
	t.check(BattleHud.AP_ICON_AT.y + BattleHud.AP_ICON_SIZE <= BattleHud.DRAW_ICON_AT.y,
		"the AP bolt sits above the draw-pile icon, not on it")
	hud.free()

func _test_guard_hover_forwarded(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(12345)
	battle.start()
	battle.player.add_guard(6)
	hud.update_fighters(battle)
	var events: Array = []
	hud.guard_hovered.connect(
		func(_anchor: Vector2, hovered: bool) -> void:
			events.append(hovered))
	hud.debug_player_panel().debug_guard_chip().mouse_entered.emit()
	t.check_eq(events, [true], "the HUD forwards its panels' guard-chip hovers")
	hud.free()

## The pile counts are numbers centred in their icons now -- the "draw n"
## and "discard n" text placeholders are gone. Draw stacks under the AP
## bolt bottom-left; discard sits above the End Turn button, right-aligned
## with it.
func _test_pile_readouts_are_icon_counts(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(12345)
	battle.start()
	hud.update_fighters(battle)
	t.check_eq(hud.debug_draw_text(), str(battle.deck.draw_pile.size()),
		"the draw icon carries the bare count, no 'draw' prefix")
	t.check_eq(hud.debug_discard_text(), str(battle.deck.discard_pile.size()),
		"the discard icon carries the bare count, no 'discard' prefix")
	t.check(BattleHud.DISCARD_ICON_AT.y + BattleHud.PILE_ICON_SIZE <= BattleHud.END_TURN_AT.y,
		"the discard icon sits above the End Turn button, not on it")
	t.check_eq(BattleHud.DISCARD_ICON_AT.x + BattleHud.PILE_ICON_SIZE,
		BattleHud.END_TURN_AT.x + BattleHud.END_TURN_SIZE.x,
		"the discard icon is right-aligned with the End Turn button")
	hud.free()

## The pile icons are buttons now: pointer cursor on hover, and a click
## reports which pile so BattleView can open the browser view.
func _test_pile_icons_are_clickable(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var draw_button: TextureButton = hud.debug_draw_button()
	var discard_button: TextureButton = hud.debug_discard_button()
	t.check(draw_button != null and discard_button != null,
		"both pile icons are TextureButtons")
	if draw_button == null or discard_button == null:
		hud.free()
		return
	for button: TextureButton in [draw_button, discard_button]:
		t.check_eq(button.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND,
			"a pile icon shows the pointer cursor on hover")
		t.check_eq(button.focus_mode, Control.FOCUS_NONE, "no focus rectangle after a click")
	var clicks: Array = []
	hud.pile_clicked.connect(func(pile: StringName) -> void: clicks.append(pile))
	draw_button.pressed.emit()
	discard_button.pressed.emit()
	t.check_eq(clicks, [&"draw", &"discard"],
		"clicking each icon reports its own pile")
	hud.free()

## The End Turn button wears the metal-plate art: normal texture at rest,
## the clicked (recessed) texture while held -- a real press animation with
## no tween needed. The art carries no words, so the hover tooltip does.
func _test_end_turn_button_texture_states(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var button: TextureButton = hud.debug_end_turn_button()
	t.check(button != null, "the End Turn button is a TextureButton now")
	if button == null:
		hud.free()
		return
	t.check(button.texture_normal != null, "the rest art is loaded")
	t.check(button.texture_pressed != null, "the pressed art is loaded")
	t.check(button.texture_normal != button.texture_pressed,
		"pressing visibly swaps the art -- the two textures differ")
	t.check(button.ignore_texture_size,
		"the button scales the art to its rect, not the art's 1536px native size")
	t.check_eq(button.focus_mode, Control.FOCUS_NONE,
		"no focus rectangle after a click, same as every other button")
	var events: Array = []
	hud.end_turn_hovered.connect(
		func(anchor: Vector2, hovered: bool) -> void:
			events.append([anchor, hovered]))
	button.mouse_entered.emit()
	button.mouse_exited.emit()
	t.check_eq(events.size(), 2, "hover in and out both report")
	if events.size() == 2:
		t.check_eq(events[0][1], true, "entering reports hovered")
		t.check_eq(events[1][1], false, "exiting reports unhovered")
		var anchor: Vector2 = events[0][0]
		t.check_eq(anchor, Vector2(BattleHud.END_TURN_AT.x + BattleHud.END_TURN_SIZE.x / 2.0,
			BattleHud.END_TURN_AT.y),
			"the anchor is the button's top-centre, for a tooltip hanging above")
	hud.free()

## The HUD owns the panels, so it is the one place both sides' chip hovers
## can be forwarded from -- BattleView connects once, not per panel.
func _test_status_hover_forwarded(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(12345)
	battle.start()
	battle.player.statuses.apply(&"leg_injury", 1, 2)
	hud.update_fighters(battle)

	var chips: Array = hud.debug_player_panel().debug_status_chip_nodes()
	t.check_eq(chips.size(), 1, "the player panel grew a chip for the applied status")
	if chips.is_empty():
		hud.free()
		return
	var events: Array = []
	hud.status_hovered.connect(
		func(id: StringName, _anchor: Vector2, hovered: bool) -> void:
			events.append([id, hovered]))
	(chips[0] as Control).mouse_entered.emit()
	t.check_eq(events, [[&"leg_injury", true]],
		"the HUD forwards its panels' chip hovers")
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

## The burned icon exists only while something is burned: hidden on a fresh
## fight, shown with the count once a burn card is played, hidden again next
## fight (a fresh battle has an empty burned pile).
func _test_burned_icon_appears_with_burned_cards(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(5)
	battle.start()

	hud.update_fighters(battle)
	t.check(not hud.debug_burned_button().visible, "no burned cards, no icon")

	var burned := CardData.new()
	burned.id = &"strength_up"
	burned.burn = true
	battle.deck.burned_pile.append(burned)
	hud.update_fighters(battle)
	t.check(hud.debug_burned_button().visible, "a burned card shows the icon")
	t.check_eq(hud.debug_burned_text(), "1", "the count renders inside the icon")

	hud.free()
