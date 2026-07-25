extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_deal_leaves_every_card_at_rest(t)
	_test_deal_is_safe_for_an_empty_hand(t)
	_test_deal_actually_springs_from_below(t)

func _hand_with(ids: Array) -> HandView:
	var battle := BattleState.new(12345)
	battle.start()
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand
	var view := HandView.new()
	view.rebuild(battle)
	return view

func _test_deal_leaves_every_card_at_rest(t: TestRunner) -> void:
	# The stagger animates cards in from below. If it left any card short of
	# its slot, the fan would be silently wrong.
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	view.deal_in()
	var all_at_rest: bool = true
	for child: Node in view.get_children():
		var card: CardView = child as CardView
		if card == null:
			continue
		if card.target_position != card.rest_position:
			all_at_rest = false
	t.check(all_at_rest, "every card ends the deal at exactly its rest position")
	t.check_eq(view.get_child_count(), 5, "dealing does not add or drop cards")
	view.free()

func _test_deal_is_safe_for_an_empty_hand(t: TestRunner) -> void:
	var view: HandView = _hand_with([])
	view.deal_in()
	t.check_eq(view.get_child_count(), 0, "dealing an empty hand is safe")
	view.free()

## The two tests above build HandView.new() and never add it to a tree, so
## deal_in() returns at its is_inside_tree() guard before its body runs at
## all -- the assertion above is just re-reading what layout_cards() already
## wrote, and would pass unchanged with deal_in()'s entire body deleted.
##
## Proving the real mechanism -- that deal_in() actually starts each card
## below its slot and springs it up over time -- needs a HandView that is
## really inside a running SceneTree, for the same reason
## test_card_juice.gd's hover regression test does: this suite's run() is
## called synchronously with no `await` from inside tests/run_tests.gd's
## _initialize() (not ours to edit), so there is no way to wait out frames
## in-process, and root has not even finished attaching to itself at that
## point. So this drives a second, disposable Godot process instead --
## reusing the exact probe pattern from test_card_juice.gd's
## _run_in_tree_hover_probe() rather than inventing a new one -- and asserts
## on its stdout through the normal t.check() calls.
func _test_deal_actually_springs_from_below(t: TestRunner) -> void:
	var probe: Dictionary = _run_in_tree_deal_probe()
	if not probe.get("ok", false):
		t.check(false, "in-tree deal probe did not complete -- %s" % probe.get("error", "unknown error"))
		return

	var rest_position: Vector2 = probe["rest_position"]
	var started_from: Vector2 = rest_position + Vector2(0.0, Juice.DEAL_FROM_BELOW)

	t.check(probe["in_tree"],
		"the probe hand must actually be inside a SceneTree, or this test proves nothing")
	# No frame was processed between rebuild(battle, true) and reading
	# target_position, so the tween (which starts from the CURRENT value) has
	# not had a chance to move target_position yet. If it already equals
	# rest_position here, deal_in() never displaced the card below its slot in
	# the first place -- exactly what happens if its body is deleted, since
	# layout_cards() already left target_position at rest.
	t.check_eq(probe["immediate_target"], started_from,
		"immediately after dealing, the card must start DEAL_FROM_BELOW under its rest position")
	t.check(probe["immediate_target"] != rest_position,
		"immediately after dealing, the card must not already be at rest -- deal_in() must have moved it")
	t.check(probe["immediate_animating"],
		"dealing an in-tree card must start a running tween, not just set target_position directly")
	# After enough real frames for the spring to finish, the card must have
	# actually arrived -- proving the tween drives all the way to the correct
	# destination, not just away from it.
	t.check_eq(probe["settled_target"], rest_position,
		"once the deal finishes, the card lands exactly on its rest position")

## The companion script _run_in_tree_deal_probe() launches. Builds a real
## three-card hand inside a real SceneTree, deals it in via
## HandView.rebuild(battle, true), and reports the first card's rest
## position, its target_position before any frame has run, whether a tween
## is running, and its target_position after the spring has had time to
## finish. Written to a temp file under user:// -- never under res://, so it
## can never be picked up by --import or swept up by `git add -A` -- and
## deleted again unconditionally once the probe process exits.
const _PROBE_SCRIPT: String = """extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var battle := BattleState.new(12345)
	battle.start()
	var hand: Array[CardData] = [
		CardLibrary.load_card(&"jab"),
		CardLibrary.load_card(&"straight"),
		CardLibrary.load_card(&"jab"),
	] as Array[CardData]
	battle.deck.hand = hand
	var view := HandView.new()
	root.add_child(view)
	view.rebuild(battle, true)
	var card: CardView = view.get_child(0) as CardView
	print("PROBE_IN_TREE:%s" % card.is_inside_tree())
	print("PROBE_REST_X:%f" % card.rest_position.x)
	print("PROBE_REST_Y:%f" % card.rest_position.y)
	print("PROBE_IMMEDIATE_TARGET_X:%f" % card.target_position.x)
	print("PROBE_IMMEDIATE_TARGET_Y:%f" % card.target_position.y)
	print("PROBE_IMMEDIATE_ANIMATING:%s" % card.debug_is_animating())
	for _i: int in range(90):
		await process_frame
	print("PROBE_SETTLED_TARGET_X:%f" % card.target_position.x)
	print("PROBE_SETTLED_TARGET_Y:%f" % card.target_position.y)
	root.remove_child(view)
	view.free()
	print("PROBE_DONE")
	quit(0)
"""

## Runs _PROBE_SCRIPT in a fresh, disposable Godot process and parses its
## stdout. Returns {"ok": false, "error": ...} for any failure along the way
## (so a broken probe reads as a failed check, never a silent pass), or
## {"ok": true, "in_tree", "rest_position", "immediate_target",
## "immediate_animating", "settled_target"} on success.
func _run_in_tree_deal_probe() -> Dictionary:
	var probe_path: String = "user://hand_deal_intree_probe.gd"
	var file := FileAccess.open(probe_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not write probe script (%s)" %
			error_string(FileAccess.get_open_error())}
	file.store_string(_PROBE_SCRIPT)
	file.close()
	var abs_path: String = ProjectSettings.globalize_path(probe_path)

	var output: Array = []
	# --quit-after prevents an infinite hang if the probe errors before quit(0) --
	# any error before that point would leave the nested SceneTree idling forever,
	# causing OS.execute to block forever and tests/run_tests.sh to hang. A hard
	# backstop converts a hang into the "probe never reached completion" error
	# that the parser already handles.
	var exit_code: int = OS.execute(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", abs_path, "--quit-after", "600"],
		output, true, false)
	DirAccess.remove_absolute(abs_path)

	var lines: PackedStringArray = []
	for chunk: Variant in output:
		lines.append_array(str(chunk).split("\n"))
	var text: String = "\n".join(lines)

	if exit_code != 0:
		return {"ok": false, "error": "probe process exited %d -- output: %s" % [exit_code, text]}
	if text.find("PROBE_DONE") == -1:
		return {"ok": false, "error": "probe never reached completion -- output: %s" % text}

	var values: Dictionary = {}
	for line: String in lines:
		var colon: int = line.find(":")
		if colon == -1:
			continue
		values[line.substr(0, colon)] = line.substr(colon + 1)

	for key: String in ["PROBE_IN_TREE", "PROBE_REST_X", "PROBE_REST_Y",
			"PROBE_IMMEDIATE_TARGET_X", "PROBE_IMMEDIATE_TARGET_Y", "PROBE_IMMEDIATE_ANIMATING",
			"PROBE_SETTLED_TARGET_X", "PROBE_SETTLED_TARGET_Y"]:
		if not values.has(key):
			return {"ok": false, "error": "probe output missing %s -- output: %s" % [key, text]}

	return {
		"ok": true,
		"in_tree": values["PROBE_IN_TREE"] == "true",
		"rest_position": Vector2(values["PROBE_REST_X"].to_float(), values["PROBE_REST_Y"].to_float()),
		"immediate_target": Vector2(values["PROBE_IMMEDIATE_TARGET_X"].to_float(), values["PROBE_IMMEDIATE_TARGET_Y"].to_float()),
		"immediate_animating": values["PROBE_IMMEDIATE_ANIMATING"] == "true",
		"settled_target": Vector2(values["PROBE_SETTLED_TARGET_X"].to_float(), values["PROBE_SETTLED_TARGET_Y"].to_float()),
	}
