extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_set_portraits_records_ids(t)
	_test_detached_slam_snaps_and_fires_callbacks(t)
	_test_hit_side_recorded_before_tree_guard(t)
	_test_centres(t)
	_test_none_side_is_silent(t)

func _test_set_portraits_records_ids(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"kickboxer")
	t.check_eq(stage.debug_portrait_ids, [&"player", &"kickboxer"], "the stage records which portraits it was given")
	stage.set_portraits(&"player", &"brawler")
	t.check_eq(stage.debug_portrait_ids, [&"player", &"brawler"], "swapping the enemy portrait re-records")
	stage.free()

func _test_detached_slam_snaps_and_fires_callbacks(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	var fired: Array = []
	stage.slam_in(func() -> void: fired.append(&"impact"), func() -> void: fired.append(&"settled"))
	t.check_eq(stage.debug_slam_count, 1, "the slam decision is recorded before the tree guard")
	t.check_eq(fired, [&"impact", &"settled"], "detached, the slam snaps and fires impact then settled synchronously")
	var homes: Array = stage.debug_portrait_positions()
	t.check_eq(homes[0], Vector2.ZERO, "detached, the left half rests at its home")
	t.check_eq(homes[1], Vector2(576, 0), "detached, the right half rests at its home")
	stage.free()

func _test_hit_side_recorded_before_tree_guard(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	stage.flash_hit(&"enemy")
	t.check_eq(stage.debug_last_hit_side, &"enemy", "the hit side is recorded even detached")
	stage.shake(&"player", 8.0)
	t.check_eq(stage.debug_last_hit_side, &"player", "shake records its side too")
	stage.free()

func _test_centres(t: TestRunner) -> void:
	var stage := FightStage.new()
	t.check_eq(stage.player_centre(), Vector2(288, 324), "the player half centres at (288, 324)")
	t.check_eq(stage.enemy_centre(), Vector2(864, 324), "the enemy half centres at (864, 324)")
	stage.free()

func _test_none_side_is_silent(t: TestRunner) -> void:
	var stage := FightStage.new()
	stage.set_portraits(&"player", &"brawler")
	stage.flash_hit(&"none")
	stage.shake(&"none", 8.0)
	t.check_eq(stage.debug_last_hit_side, &"", "a none side is ignored, not recorded")
	stage.free()
