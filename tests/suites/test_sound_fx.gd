extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_hit_sound_for_card(t)
	_test_hit_sound_for_moves(t)
	_test_streams_are_registered(t)
	_test_play_records_decision_before_tree_guard(t)
	_test_detached_is_safe(t)

## The sound a landed card hit warrants is a pure function of the card's
## data: kick-tagged cards kick, other damaging cards punch, and a card
## that deals no damage (Block) is silent -- there is no whiff asset.
func _test_hit_sound_for_card(t: TestRunner) -> void:
	t.check_eq(SoundFx.hit_sound_for_card(CardLibrary.load_card(&"jab")), &"punch",
		"a jab lands as a punch")
	t.check_eq(SoundFx.hit_sound_for_card(CardLibrary.load_card(&"straight")), &"punch",
		"a straight lands as a punch")
	t.check_eq(SoundFx.hit_sound_for_card(CardLibrary.load_card(&"low_kick")), &"kick",
		"a low kick lands as a kick")
	t.check_eq(SoundFx.hit_sound_for_card(CardLibrary.load_card(&"block")), &"",
		"block deals no damage, so it warrants no hit sound")
	t.check_eq(SoundFx.hit_sound_for_card(null), &"",
		"a null card warrants no hit sound rather than an error")

## The enemy's analogue reads the coming turn's moves: any damaging move
## picks the sound, KICK in its label makes it a kick, and a turn of pure
## guard/buff is silent.
func _test_hit_sound_for_moves(t: TestRunner) -> void:
	var kickboxer := EnemyBrain.new(OpponentLibrary.opponent(&"kickboxer"))
	# Kickboxer turn 1 is LEG KICK, turn 2 a plain ATTACK.
	t.check_eq(SoundFx.hit_sound_for_moves(kickboxer.current_moves()), &"kick",
		"the kickboxer's LEG KICK turn sounds as a kick")
	kickboxer.advance()
	t.check_eq(SoundFx.hit_sound_for_moves(kickboxer.current_moves()), &"punch",
		"the kickboxer's plain ATTACK turn sounds as a punch")

	var brawler := EnemyBrain.new(OpponentLibrary.opponent(&"brawler"))
	brawler.advance()
	brawler.advance()
	# Brawler turn 3 is BLOCK + BUFF: no damage anywhere, so no hit sound.
	t.check_eq(SoundFx.hit_sound_for_moves(brawler.current_moves()), &"",
		"a guard-and-buff enemy turn warrants no hit sound")
	t.check_eq(SoundFx.hit_sound_for_moves([]), &"",
		"an empty move list warrants no hit sound")

## Every sound id the view fires must resolve to at least one loaded
## stream, and the punch carries its three variations. This is what catches
## a moved or misnamed wav headless -- playback itself cannot be heard by
## a test.
func _test_streams_are_registered(t: TestRunner) -> void:
	for id: StringName in [&"punch", &"kick", &"card_fan", &"click", &"slam"]:
		var variants: Array = SoundFx.variants_for(id)
		t.check(variants.size() >= 1, "sound id %s has at least one stream" % id)
		for stream: Variant in variants:
			t.check(stream is AudioStream, "every %s variant is a loaded AudioStream" % id)
	t.check_eq(SoundFx.variants_for(&"punch").size(), 3,
		"the punch rotates through its three recorded variations")
	t.check_eq(SoundFx.variants_for(&"nonsense").size(), 0,
		"an unknown id has no streams rather than an error")

## Tests run detached from any tree, so play() must record WHAT it decided
## to play -- id and chosen variant -- before the is_inside_tree() guard,
## exactly like every other animation entry point in the project.
func _test_play_records_decision_before_tree_guard(t: TestRunner) -> void:
	var fx := SoundFx.new()
	fx.play(&"punch")
	t.check_eq(fx.last_played(), &"punch", "play() records the sound id it chose")
	t.check(SoundFx.variants_for(&"punch").has(fx.last_stream()),
		"play() records which punch variant it picked, chosen from the punch pool")
	fx.play(&"slam")
	t.check_eq(fx.last_played(), &"slam", "a later play overwrites the recorded id")
	fx.free()

func _test_detached_is_safe(t: TestRunner) -> void:
	# A detached SoundFx must neither crash nor push an engine error for any
	# registered id -- the wrapper fails the run on engine error markers.
	var fx := SoundFx.new()
	for id: StringName in [&"punch", &"kick", &"card_fan", &"click", &"slam"]:
		fx.play(id)
	t.check(true, "playing every sound on a detached SoundFx produces no engine error")
	fx.free()
