extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_style_applies_font_fill_and_outline(t)

func _test_style_applies_font_fill_and_outline(t: TestRunner) -> void:
	var label := Label.new()
	HudText.style(label, 20)
	t.check_eq(label.get_theme_font_size("font_size"), 20, "the requested size is applied")
	t.check_eq(label.get_theme_color("font_color"), Color.WHITE, "fill is white")
	t.check_eq(label.get_theme_color("font_outline_color"), Color.BLACK, "outline is black")
	t.check(label.get_theme_constant("outline_size") >= 3, "the outline is thick enough to read over art")
	t.check(label.get_theme_font("font") != null, "a font override is applied")
	label.free()
