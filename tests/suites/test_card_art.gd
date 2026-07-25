extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_found_art_loads_a_texture(t)
	_test_missing_art_returns_null(t)
	_test_results_are_cached(t)

func _test_found_art_loads_a_texture(t: TestRunner) -> void:
	var texture: Texture2D = CardArt.texture_for(&"jab")
	t.check(texture != null, "jab has a matching card_jab.png and resolves to a texture")

func _test_missing_art_returns_null(t: TestRunner) -> void:
	# No asset exists for this id -- this is a legitimate fallback case (a
	# card added without art yet), not an error, so it must return null
	# quietly rather than push_error.
	var texture: Texture2D = CardArt.texture_for(&"no_such_card_id")
	t.check(texture == null, "an id with no matching PNG resolves to null")

func _test_results_are_cached(t: TestRunner) -> void:
	# Same object both times -- proves the second call served the cache
	# rather than reloading the file. Godot's `==` on Objects is reference
	# equality, so this is a real identity check, not a value comparison.
	var first: Texture2D = CardArt.texture_for(&"block")
	var second: Texture2D = CardArt.texture_for(&"block")
	t.check(first == second, "repeated lookups of the same id return the identical cached texture")
