extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

## Coverage for HandView's carry-position-across-rebuild fix. Before this,
## rebuild() froze every CardView and built fresh ones from layout_cards()
## alone -- a surviving card had no previous position to animate from, so it
## could only appear at its new slot. That read as a snap when a played card
## left and the rest of the fan closed up, and no amount of tuning could fix
## it because the information was destroyed. rebuild() now records each
## survivor's pre-rebuild target_position, keyed by CardData identity (see
## CardLibrary.load_card()'s per-entry duplicate(), which is what makes
## identity a safe key even for two copies of the same card id), and slides
## it from there to its freshly laid-out rest slot via CardView.slide_from().

func run(t: TestRunner) -> void:
	_test_survivor_settles_at_new_rest_off_tree(t)
	_test_new_card_has_no_carried_position(t)
	_test_refan_actually_animates_in_tree(t)

## Simulates a play the way BattleView really produces one: the played card
## is removed as a HandView child (mirroring _hand_off's reparent-out, which
## always happens before battle.play_card() can trigger a rebuild -- see
## rebuild()'s own doc comment) and dropped from battle.deck.hand, then
## rebuild() runs again with the shorter hand.
func _test_survivor_settles_at_new_rest_off_tree(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	var jab: CardData = CardLibrary.load_card(&"jab")
	var straight: CardData = CardLibrary.load_card(&"straight")
	var block: CardData = CardLibrary.load_card(&"block")
	battle.deck.hand = [jab, straight, block] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)
	t.check_eq(hand.get_child_count(), 3, "initial build has one view per card")

	var straight_view: CardView = null
	for child: Node in hand.get_children():
		if (child as CardView).card == straight:
			straight_view = child as CardView
	t.check(straight_view != null, "the straight card is present in the initial build")
	hand.remove_child(straight_view)
	straight_view.queue_free()
	battle.deck.hand = [jab, block] as Array[CardData]

	hand.rebuild(battle)
	t.check_eq(hand.get_child_count(), 2, "rebuild after a play leaves exactly the remaining hand")

	var jab_view: CardView = null
	var block_view: CardView = null
	for child: Node in hand.get_children():
		var view: CardView = child as CardView
		if view.card == jab:
			jab_view = view
		elif view.card == block:
			block_view = view
	t.check(jab_view != null and block_view != null,
		"both surviving cards are still the same CardData instances")

	# Off-tree, slide_from() takes its snap branch and always lands on
	# rest_position regardless of `start` -- proving only that the *children*
	# and *destinations* survive the rebuild correctly (structure, not the
	# carry mechanism itself: an implementation that never called
	# slide_from() at all would pass this identically, since layout_cards()
	# already leaves target_position at rest_position on its own). Proving
	# the carry is keyed by CardData identity, not sibling index, needs the
	# in-tree probe below, where the mid-animation position actually depends
	# on which start value slide_from() was given.
	t.check_eq(jab_view.target_position, jab_view.rest_position,
		"off-tree, a survivor still settles exactly at its new rest position")
	t.check_eq(block_view.target_position, block_view.rest_position,
		"off-tree, a survivor still settles exactly at its new rest position")
	hand.free()

## A card drawn this turn was never a HandView child before this rebuild, so
## it is absent from the carried-position map entirely -- it must keep
## exactly today's behaviour: appear at rest immediately, never sliding from
## anywhere.
func _test_new_card_has_no_carried_position(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	var jab: CardData = CardLibrary.load_card(&"jab")
	battle.deck.hand = [jab] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)

	var straight: CardData = CardLibrary.load_card(&"straight")
	battle.deck.hand = [jab, straight] as Array[CardData]
	hand.rebuild(battle)

	var straight_view: CardView = null
	for child: Node in hand.get_children():
		if (child as CardView).card == straight:
			straight_view = child as CardView
	t.check(straight_view != null, "the newly drawn card is present")
	t.check_eq(straight_view.target_position, straight_view.rest_position,
		"a genuinely new card appears at rest, having had no previous position to slide from")
	hand.free()

## The two tests above build HandView.new() and never add it to a tree, so
## slide_from() returns at its is_inside_tree() guard before its tween ever
## runs -- proving only the destination, not the motion. Proving the re-fan
## actually animates over several frames, rather than snapping, needs a
## HandView really inside a running SceneTree, for the same reason
## test_hand_deal.gd's and test_card_juice.gd's in-tree probes do: this
## suite's run() is called synchronously with no `await` from inside
## tests/run_tests.gd's _initialize() (not ours to edit), and root has not
## even finished attaching to itself at that point. So this drives a second,
## disposable Godot process instead, reusing the exact probe pattern those
## two suites established, and asserts on its stdout through the normal
## t.check() calls.
func _test_refan_actually_animates_in_tree(t: TestRunner) -> void:
	var probe: Dictionary = _run_in_tree_refan_probe()
	if not probe.get("ok", false):
		t.check(false, "in-tree refan probe did not complete -- %s" % probe.get("error", "unknown error"))
		return

	var old_position: Vector2 = probe["old_position"]
	var new_rest: Vector2 = probe["new_rest"]
	t.check(old_position != new_rest,
		"sanity check on the test's own fixture: playing the middle card of a 3-card hand must actually move the survivor's slot in a 2-card fan")

	t.check(probe["in_tree"],
		"the probe hand must actually be inside a SceneTree, or this test proves nothing")
	# No frame was processed between the second rebuild() and reading
	# target_position, so a slide that correctly starts from the OLD position
	# has not had a chance to move yet. If it already equals new_rest here,
	# the position was never carried across the rebuild at all -- exactly the
	# original snap bug.
	t.check_eq(probe["immediate_target"], old_position,
		"immediately after the rebuild, the survivor must start from its pre-rebuild position, not its new slot")
	t.check(probe["animating"],
		"the survivor must be driven by a running tween, not just assigned its new slot directly")

	# Progressive motion, not a one-frame jump: across the sampled frames the
	# card must pass through positions distinct from both endpoints. A snap
	# (or a tween wired to the wrong duration/property) would show at most
	# two distinct values across the whole sample.
	var distinct_intermediate: int = 0
	for sample: Vector2 in probe["samples"]:
		if sample != old_position and sample != new_rest:
			distinct_intermediate += 1
	t.check(distinct_intermediate >= 5,
		"the survivor's position must move through several distinct in-between values (saw %d of %d samples), not jump in one frame -- samples: %s" % [
			distinct_intermediate, probe["samples"].size(), probe["samples"]])

	# And it must actually arrive: proving the tween drives all the way to
	# the correct destination, not just away from the old one.
	t.check_eq(probe["settled_target"], new_rest,
		"once the re-fan settles, the survivor lands exactly on its new rest position")

## The companion script _run_in_tree_refan_probe() launches. Builds a real
## three-card hand inside a real SceneTree, rebuild()s it once, then plays
## the middle card (straight) the same way _test_survivor_settles_at_new_
## rest_off_tree does above, and rebuild()s again -- this time in a tree, so
## slide_from()'s tween actually runs. Reports the survivor's pre-rebuild
## position, its immediate post-rebuild target_position (before any frame),
## ~10 frame-by-frame samples, and its settled position after the tween has
## had time to finish. Written to a temp file under user:// -- never under
## res://, so it can never be picked up by --import or swept up by `git add
## -A` -- and deleted again unconditionally once the probe process exits.
const _PROBE_SCRIPT: String = """extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var battle := BattleState.new(12345)
	battle.start()
	var jab: CardData = CardLibrary.load_card(&"jab")
	var straight: CardData = CardLibrary.load_card(&"straight")
	var block: CardData = CardLibrary.load_card(&"block")
	battle.deck.hand = [jab, straight, block] as Array[CardData]

	var hand := HandView.new()
	root.add_child(hand)
	hand.rebuild(battle)

	# The card being sampled across the rebuild is block, not the card that
	# leaves (straight). block sits at sibling index 2 in the 3-card fan and
	# index 1 in the 2-card fan once straight leaves -- a real reorder, not
	# just a reshaped fan. That makes this a real test of CardData identity
	# driving the carry rather than sibling index: an implementation that
	# carried position by matching old-index to new-index instead of by
	# CardData would hand block the wrong old position (straight's, since
	# straight sat at the old index1 nothing now occupies) instead of its own.
	var old_block: CardView = null
	var old_straight: CardView = null
	for child: Node in hand.get_children():
		var view: CardView = child as CardView
		if view.card == block:
			old_block = view
		elif view.card == straight:
			old_straight = view
	var old_position: Vector2 = old_block.target_position

	hand.remove_child(old_straight)
	old_straight.queue_free()
	battle.deck.hand = [jab, block] as Array[CardData]
	hand.rebuild(battle)

	var new_block: CardView = null
	for child: Node in hand.get_children():
		if (child as CardView).card == block:
			new_block = child as CardView

	print("PROBE_IN_TREE:%s" % new_block.is_inside_tree())
	print("PROBE_OLD_X:%f" % old_position.x)
	print("PROBE_OLD_Y:%f" % old_position.y)
	print("PROBE_NEW_REST_X:%f" % new_block.rest_position.x)
	print("PROBE_NEW_REST_Y:%f" % new_block.rest_position.y)
	print("PROBE_IMMEDIATE_X:%f" % new_block.target_position.x)
	print("PROBE_IMMEDIATE_Y:%f" % new_block.target_position.y)
	print("PROBE_ANIMATING:%s" % new_block.debug_is_animating())

	for i: int in range(10):
		await process_frame
		print("PROBE_SAMPLE_%d_X:%f" % [i, new_block.target_position.x])
		print("PROBE_SAMPLE_%d_Y:%f" % [i, new_block.target_position.y])

	for _i: int in range(50):
		await process_frame
	print("PROBE_SETTLED_X:%f" % new_block.target_position.x)
	print("PROBE_SETTLED_Y:%f" % new_block.target_position.y)
	root.remove_child(hand)
	hand.free()
	print("PROBE_DONE")
	quit(0)
"""

## Runs _PROBE_SCRIPT in a fresh, disposable Godot process and parses its
## stdout. Returns {"ok": false, "error": ...} for any failure along the way
## (so a broken probe reads as a failed check, never a silent pass), or
## {"ok": true, "in_tree", "old_position", "new_rest", "immediate_target",
## "animating", "samples", "settled_target"} on success. block -- which
## moves from sibling index 2 to index 1 once straight leaves -- is the one
## sampled, precisely so this exercises real reordering (see the probe
## script's own comment). The played card (straight) sat in the middle and
## is never a HandView child by the time rebuild() runs (see the suite's
## own doc comment).
func _run_in_tree_refan_probe() -> Dictionary:
	var probe_path: String = "user://hand_refan_intree_probe.gd"
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

	var required: Array[String] = ["PROBE_IN_TREE", "PROBE_OLD_X", "PROBE_OLD_Y",
		"PROBE_NEW_REST_X", "PROBE_NEW_REST_Y", "PROBE_IMMEDIATE_X", "PROBE_IMMEDIATE_Y",
		"PROBE_ANIMATING", "PROBE_SETTLED_X", "PROBE_SETTLED_Y"]
	for i: int in range(10):
		required.append("PROBE_SAMPLE_%d_X" % i)
		required.append("PROBE_SAMPLE_%d_Y" % i)
	for key: String in required:
		if not values.has(key):
			return {"ok": false, "error": "probe output missing %s -- output: %s" % [key, text]}

	var samples: Array[Vector2] = []
	for i: int in range(10):
		samples.append(Vector2(
			values["PROBE_SAMPLE_%d_X" % i].to_float(),
			values["PROBE_SAMPLE_%d_Y" % i].to_float()))

	return {
		"ok": true,
		"in_tree": values["PROBE_IN_TREE"] == "true",
		"old_position": Vector2(values["PROBE_OLD_X"].to_float(), values["PROBE_OLD_Y"].to_float()),
		"new_rest": Vector2(values["PROBE_NEW_REST_X"].to_float(), values["PROBE_NEW_REST_Y"].to_float()),
		"immediate_target": Vector2(values["PROBE_IMMEDIATE_X"].to_float(), values["PROBE_IMMEDIATE_Y"].to_float()),
		"animating": values["PROBE_ANIMATING"] == "true",
		"samples": samples,
		"settled_target": Vector2(values["PROBE_SETTLED_X"].to_float(), values["PROBE_SETTLED_Y"].to_float()),
	}
