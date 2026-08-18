extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_show_ko_records_and_shows(t)
	_test_show_failed_records_and_shows(t)
	_test_dismiss_hides(t)
	_test_z_order_beats_the_tooltip(t)

func _test_show_ko_records_and_shows(t: TestRunner) -> void:
	var splash := KoSplash.new()
	t.check(not splash.visible, "the splash starts hidden")
	splash.show_ko()
	t.check_eq(splash.last_shown(), &"ko", "the decision is recorded before the tree guard")
	t.check(splash.visible, "showing makes it visible")
	t.check(splash.debug_art_texture() != null, "the KO art resolved from assets/ui")
	splash.free()

func _test_show_failed_records_and_shows(t: TestRunner) -> void:
	var splash := KoSplash.new()
	splash.show_failed()
	t.check_eq(splash.last_shown(), &"failed", "failed records its own kind")
	t.check(splash.visible, "the failed blink is visible too")
	t.check(splash.debug_art_texture() != null, "the failed art resolved from assets/ui")
	splash.free()

func _test_dismiss_hides(t: TestRunner) -> void:
	var splash := KoSplash.new()
	splash.show_ko()
	splash.dismiss()
	t.check(not splash.visible, "dismiss hides silently (fight transitions)")
	splash.free()

func _test_z_order_beats_the_tooltip(t: TestRunner) -> void:
	t.check(KoSplash.SPLASH_Z > StatusTooltip.TOOLTIP_Z,
		"nothing covers the fight's biggest moment -- the splash outranks the tooltip")
