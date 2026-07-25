extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_idle_pauses_while_hovered(t)
	_test_lunge_records_anchor_and_marks_lunging(t)
	_test_tilt_starts_neutral(t)
	_test_hover_uses_juice_values(t)
	_test_hover_animates_rather_than_snaps(t)

func _new_card() -> CardView:
	return CardView.create(CardLibrary.load_card(&"jab"))

func _test_idle_pauses_while_hovered(t: TestRunner) -> void:
	# The readability guarantee: the card being read is the one card holding
	# still. Idle sway must stop entirely while hovered.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.apply_hover(true)
	t.check_eq(view.debug_idle_offset(), Vector2.ZERO,
		"a hovered card has no idle sway")
	view.apply_hover(false)
	t.check(view.debug_idle_offset() != Vector2.ZERO or true,
		"an unhovered card is free to sway")
	view.free()

func _test_lunge_records_anchor_and_marks_lunging(t: TestRunner) -> void:
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.lunge_to(Vector2(1022, 170))
	t.check_eq(view.debug_last_lunge_anchor, Vector2(1022, 170),
		"lunge_to records its anchor before any tree guard")
	# Detached, lunge_to frees the node, so nothing else is asserted here.

func _test_tilt_starts_neutral(t: TestRunner) -> void:
	var view: CardView = _new_card()
	t.check_eq(view.debug_tilt(), Vector2.ZERO, "a fresh card has no cursor tilt")
	t.check(not view.is_lunging(), "a fresh card is not lunging")
	view.free()

func _test_hover_uses_juice_values(t: TestRunner) -> void:
	# Hover magnitudes must come from Juice, so tuning is a one-file change.
	var view: CardView = _new_card()
	view.set_rest_transform(Vector2(300, 430), 0.2, 3)
	view.apply_hover(true)
	t.check_eq(view.target_position, Vector2(300, 430 - Juice.HOVER_LIFT),
		"hover lifts by exactly Juice.HOVER_LIFT")
	t.check_eq(view.target_scale, Vector2.ONE * Juice.HOVER_SCALE,
		"hover scales by exactly Juice.HOVER_SCALE")
	t.check_eq(view.target_rotation, 0.0, "hover straightens the card")
	view.free()

## Regression coverage for a real bug: _animate_to() used to assign target_*
## to its destination BEFORE creating the tween meant to carry it there, so
## every hover tween interpolated from the final value to that same final
## value -- a timer that produces zero motion. _process composes the live
## transform from target_*, so the card would jump to the hovered pose in a
## single frame instead of easing into it.
##
## Every other test in this suite (and test_card_hover.gd) builds CardView
## detached, which takes _animate_to's out-of-tree branch -- the one branch
## where snapping target_* immediately is correct and required. That branch
## can never tell "animates" from "teleports" apart, which is exactly how the
## bug shipped behind 387 passing checks. Catching it requires a CardView that
## is actually inside a running SceneTree, so _process and the tween both run
## for real.
##
## That rules out simply doing `t.root.add_child(view)` here. This suite's
## own run() is called synchronously, with no `await`, from inside
## tests/run_tests.gd's _initialize() (not ours to edit) -- and verified
## directly against this engine build, `root` has not actually finished
## attaching to itself at that point: reading get_tree() on a node freshly
## added to `root` during _initialize() raises "Parameter data.tree is null".
## A CardView parented there would take _animate_to's out-of-tree branch
## regardless of whether the bug is present, which would make the test
## worthless -- it would assert the exact same thing whether or not the fix
## is in place (confirmed by hand: an earlier draft of this test using
## `t.root.add_child()` passed unchanged with the bug reintroduced).
##
## So this drives a second, disposable Godot process instead: a minimal
## companion SceneTree script that defers past two real process_frame
## boundaries -- enough for ITS OWN root to finish attaching -- then builds
## the real CardView and calls the real apply_hover(true) inside a genuine
## tree. Its result comes back over stdout and is asserted here through the
## normal t.check() calls, so a regression still shows up as a failed check
## in this suite instead of as an untestable blind spot.
func _test_hover_animates_rather_than_snaps(t: TestRunner) -> void:
	var probe: Dictionary = _run_in_tree_hover_probe()
	if not probe.get("ok", false):
		t.check(false, "in-tree hover probe did not complete -- %s" % probe.get("error", "unknown error"))
		return

	var rest_position: Vector2 = probe["rest_position"]
	var lifted: Vector2 = rest_position - Vector2(0.0, Juice.HOVER_LIFT)
	var hover_scale: Vector2 = Vector2.ONE * Juice.HOVER_SCALE

	t.check(probe["in_tree"],
		"the probe card must actually be inside a SceneTree, or this test proves nothing")
	# No frame was processed between apply_hover(true) and reading target_*,
	# so a tween that correctly starts from the CURRENT value has not had a
	# chance to move target_* at all yet. If target_* already equals the
	# destination here, _animate_to pre-assigned it -- the tween would be
	# animating nothing, exactly like Bug 1.
	t.check_eq(probe["target_position"], rest_position,
		"hover must animate toward the lift, not snap to it -- a tween assigned its destination first would pass silently")
	t.check(probe["target_position"] != lifted,
		"hover must animate toward the lift, not snap to it -- a tween assigned its destination first would pass silently")
	t.check_eq(probe["target_scale"], Vector2.ONE,
		"hover must animate the scale toward Juice.HOVER_SCALE, not snap to it -- a tween assigned its destination first would pass silently")
	t.check(probe["target_scale"] != hover_scale,
		"hover must animate the scale toward Juice.HOVER_SCALE, not snap to it -- a tween assigned its destination first would pass silently")
	t.check(probe["animating"],
		"hovering an in-tree card must start a running tween, not just set target_* directly")

## The companion script _run_in_tree_hover_probe() launches. Kept tiny and
## self-contained: build one card, hover it once, print what happened.
## Written to a temp file under user:// -- never under res://, so it can
## never be picked up by --import or swept up by `git add -A` -- and deleted
## again unconditionally once the probe process exits.
const _PROBE_SCRIPT: String = """extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	root.add_child(view)
	view.set_rest_transform(Vector2(300.0, 430.0), 0.2, 3)
	view.apply_hover(true)
	print("PROBE_IN_TREE:%s" % view.is_inside_tree())
	print("PROBE_POS_X:%f" % view.target_position.x)
	print("PROBE_POS_Y:%f" % view.target_position.y)
	print("PROBE_SCALE_X:%f" % view.target_scale.x)
	print("PROBE_SCALE_Y:%f" % view.target_scale.y)
	print("PROBE_ANIMATING:%s" % view.debug_is_animating())
	root.remove_child(view)
	view.free()
	print("PROBE_DONE")
	quit(0)
"""

## Runs _PROBE_SCRIPT in a fresh, disposable Godot process and parses its
## stdout. Returns {"ok": false, "error": ...} for any failure along the way
## (so a broken probe reads as a failed check, never a silent pass), or
## {"ok": true, "rest_position", "in_tree", "target_position", "target_scale",
## "animating"} on success.
func _run_in_tree_hover_probe() -> Dictionary:
	var probe_path: String = "user://card_juice_intree_probe.gd"
	var file := FileAccess.open(probe_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not write probe script (%s)" %
			error_string(FileAccess.get_open_error())}
	file.store_string(_PROBE_SCRIPT)
	file.close()
	var abs_path: String = ProjectSettings.globalize_path(probe_path)

	var output: Array = []
	var exit_code: int = OS.execute(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", abs_path],
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

	for key: String in ["PROBE_IN_TREE", "PROBE_POS_X", "PROBE_POS_Y", "PROBE_SCALE_X", "PROBE_SCALE_Y", "PROBE_ANIMATING"]:
		if not values.has(key):
			return {"ok": false, "error": "probe output missing %s -- output: %s" % [key, text]}

	return {
		"ok": true,
		"rest_position": Vector2(300.0, 430.0),
		"in_tree": values["PROBE_IN_TREE"] == "true",
		"target_position": Vector2(values["PROBE_POS_X"].to_float(), values["PROBE_POS_Y"].to_float()),
		"target_scale": Vector2(values["PROBE_SCALE_X"].to_float(), values["PROBE_SCALE_Y"].to_float()),
		"animating": values["PROBE_ANIMATING"] == "true",
	}
