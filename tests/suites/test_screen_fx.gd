extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_unfreeze_decision(t)
	_test_time_scale_always_restored(t)
	_test_shake_returns_home(t)
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
