extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_unfreeze_decision(t)
	_test_time_scale_always_restored(t)
	_test_shake_returns_home(t)
	_test_shake_actually_moves_and_returns_home(t)
	_test_detached_is_safe(t)

func _test_unfreeze_decision(t: TestRunner) -> void:
	# Pure decision, so the watchdog is testable without touching the global
	# time scale.
	t.check(not ScreenFx.should_unfreeze(1000, -1),
		"a run that is not frozen never needs unfreezing")
	t.check(not ScreenFx.should_unfreeze(1000, 1090),
		"a freeze still within its duration is left alone")
	t.check(ScreenFx.should_unfreeze(1090, 1090),
		"a freeze is released exactly at its deadline")
	t.check(ScreenFx.should_unfreeze(5000, 1090),
		"a freeze past its deadline is released")

func _test_time_scale_always_restored(t: TestRunner) -> void:
	# A time scale left below 1.0 freezes the game permanently, so this is the
	# most important assertion in the file. It also must not leak global state
	# into other suites.
	var fx := ScreenFx.new()
	t.check_eq(Engine.time_scale, 1.0, "time scale starts normal")
	fx.hit_stop(0.09)
	t.check(fx.is_frozen(), "hit_stop marks the run as frozen")
	t.check(Engine.time_scale < 1.0, "hit_stop actually slows the world")
	fx.force_restore_time()
	t.check_eq(Engine.time_scale, 1.0, "force_restore_time returns time to exactly normal")
	t.check(not fx.is_frozen(), "force_restore_time clears the frozen flag")
	fx.free()
	# Belt and braces: leave the global exactly as we found it even if the
	# assertions above failed.
	Engine.time_scale = 1.0

func _test_shake_returns_home(t: TestRunner) -> void:
	# A stuck offset leaves the whole UI crooked, so shake must always land on
	# a stored home rather than an accumulated delta.
	var fx := ScreenFx.new()
	var layer := CanvasLayer.new()
	layer.offset = Vector2(7, 11)
	var overlay := Control.new()
	fx.bind(layer, overlay)
	t.check_eq(fx.debug_layer_home(), Vector2(7, 11), "bind records the layer's home offset")
	fx.shake(20.0)
	t.check_eq(layer.offset, Vector2(7, 11),
		"a detached shake leaves the offset untouched at home")
	overlay.free()
	layer.free()
	fx.free()

## The test above builds fx detached (never added to a tree), so shake()
## returns at its "not is_inside_tree()" guard before creating any tween --
## the assertion is trivially true because nothing ran at all, and it would
## pass unchanged with shake()'s entire body deleted.
##
## Proving the real mechanism -- that shake() actually kicks the layer's
## offset away from home and then eases it back -- needs an in-tree
## ScreenFx, for the same reason test_card_juice.gd's hover regression test
## does: this suite's run() is synchronous with no `await`, so there is no
## way to wait out frames in-process. This drives a second, disposable Godot
## process instead, reusing the exact probe pattern from
## test_card_juice.gd's _run_in_tree_hover_probe() rather than inventing a
## new one.
func _test_shake_actually_moves_and_returns_home(t: TestRunner) -> void:
	var probe: Dictionary = _run_in_tree_shake_probe()
	if not probe.get("ok", false):
		t.check(false, "in-tree shake probe did not complete -- %s" % probe.get("error", "unknown error"))
		return

	t.check(probe["in_tree"],
		"the probe ScreenFx must actually be inside a SceneTree, or this test proves nothing")
	t.check(probe["moved_away"],
		"a running shake must displace the layer's offset away from home -- an empty shake() body would never move it")
	t.check_eq(probe["final_offset"], probe["home"],
		"once the shake finishes, the layer's offset lands back on its stored home")

## The companion script _run_in_tree_shake_probe() launches. Binds a real
## ScreenFx inside a real SceneTree, records the layer's offset one frame
## into a shake (before it can have settled) to prove the tween is actually
## running, then lets it finish and checks it landed exactly back on home.
## Written to a temp file under user:// -- never under res://, so it can
## never be picked up by --import or swept up by `git add -A` -- and
## deleted again unconditionally once the probe process exits.
const _SHAKE_PROBE_SCRIPT: String = """extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var fx := ScreenFx.new()
	root.add_child(fx)
	var layer := CanvasLayer.new()
	layer.offset = Vector2(7.0, 11.0)
	root.add_child(layer)
	var overlay := Control.new()
	root.add_child(overlay)
	fx.bind(layer, overlay)
	print("PROBE_IN_TREE:%s" % fx.is_inside_tree())
	fx.shake(20.0)
	var moved_away := false
	for _i: int in range(20):
		await process_frame
		if layer.offset != Vector2(7.0, 11.0):
			moved_away = true
	print("PROBE_MOVED_AWAY:%s" % moved_away)
	for _i: int in range(60):
		await process_frame
	print("PROBE_FINAL_X:%f" % layer.offset.x)
	print("PROBE_FINAL_Y:%f" % layer.offset.y)
	fx.force_restore_time()
	print("PROBE_DONE")
	quit(0)
"""

## Runs _SHAKE_PROBE_SCRIPT in a fresh, disposable Godot process and parses
## its stdout. Returns {"ok": false, "error": ...} for any failure along the
## way (so a broken probe reads as a failed check, never a silent pass), or
## {"ok": true, "in_tree", "moved_away", "home", "final_offset"} on success.
func _run_in_tree_shake_probe() -> Dictionary:
	var probe_path: String = "user://screen_fx_shake_intree_probe.gd"
	var file := FileAccess.open(probe_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not write probe script (%s)" %
			error_string(FileAccess.get_open_error())}
	file.store_string(_SHAKE_PROBE_SCRIPT)
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

	for key: String in ["PROBE_IN_TREE", "PROBE_MOVED_AWAY", "PROBE_FINAL_X", "PROBE_FINAL_Y"]:
		if not values.has(key):
			return {"ok": false, "error": "probe output missing %s -- output: %s" % [key, text]}

	return {
		"ok": true,
		"in_tree": values["PROBE_IN_TREE"] == "true",
		"moved_away": values["PROBE_MOVED_AWAY"] == "true",
		"home": Vector2(7.0, 11.0),
		"final_offset": Vector2(values["PROBE_FINAL_X"].to_float(), values["PROBE_FINAL_Y"].to_float()),
	}

func _test_detached_is_safe(t: TestRunner) -> void:
	# Tests build these nodes detached; a tween created off-tree would push an
	# engine error and fail the whole suite.
	var fx := ScreenFx.new()
	fx.shake(10.0)
	fx.flash(0.5)
	t.check(true, "shake and flash on a detached ScreenFx produce no engine error")
	fx.force_restore_time()
	fx.free()
	Engine.time_scale = 1.0
