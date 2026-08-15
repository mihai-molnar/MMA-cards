extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_illustrations_load(t)
	_test_frames_load(t)
	_test_missing_illustration_returns_null(t)
	_test_results_are_cached(t)
	_test_illustrations_and_frames_do_not_collide(t)

func _test_illustrations_load(t: TestRunner) -> void:
	for card_id: StringName in [&"jab", &"straight", &"block"]:
		var texture: Texture2D = CardArt.illustration_for(card_id)
		t.check(texture != null, "%s resolves to an illustration texture" % card_id)

func _test_frames_load(t: TestRunner) -> void:
	# The frame is looked up by name, not per card, which is what lets a new
	# card ship with only an illustration. There is exactly one frame now --
	# the master template every card wears.
	t.check(CardArt.frame_for(CardTemplate.FRAME) != null,
		"the master template frame resolves to a texture")

func _test_missing_illustration_returns_null(t: TestRunner) -> void:
	# A card authored before its art exists is a legitimate state -- it renders
	# a complete frame around an empty window -- so this must stay quiet rather
	# than push_error.
	var texture: Texture2D = CardArt.illustration_for(&"no_such_card_id")
	t.check(texture == null, "an id with no matching illustration resolves to null")

func _test_results_are_cached(t: TestRunner) -> void:
	# Godot's `==` on Objects is reference equality, so this is a real identity
	# check: the same object twice proves the second call served the cache
	# rather than reloading the file.
	var first: Texture2D = CardArt.illustration_for(&"block")
	var second: Texture2D = CardArt.illustration_for(&"block")
	t.check(first == second, "repeated illustration lookups return the identical cached texture")

	var frame_first: Texture2D = CardArt.frame_for(CardTemplate.FRAME)
	var frame_second: Texture2D = CardArt.frame_for(CardTemplate.FRAME)
	t.check(frame_first == frame_second, "repeated frame lookups return the identical cached texture")

## The two lookups share one cache. Keying it by card id or frame name alone
## would collide the moment someone adds a card whose id matches the frame's
## name: its illustration and the frame would map to the same key and serve
## each other's texture. Keying by resolved path cannot collide, and this is
## the check that holds that.
func _test_illustrations_and_frames_do_not_collide(t: TestRunner) -> void:
	var frame: Texture2D = CardArt.frame_for(CardTemplate.FRAME)
	var same_named_illustration: Texture2D = CardArt.illustration_for(CardTemplate.FRAME)
	t.check(frame != null, "the master frame still resolves")
	t.check(same_named_illustration == null,
		"no illustration exists for the frame's name, and the frame does not stand in for one")
