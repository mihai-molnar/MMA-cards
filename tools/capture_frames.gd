extends SceneTree

## Renders tiled contact sheets of consecutive frames so animation curves can
## be judged from a still image. A single screenshot cannot show whether
## motion overshoots and settles, slides linearly, or wobbles too long; a
## strip of frames can.
##
## Run NON-headless (a rendering context is required -- root.get_texture()
## needs a real surface, and DisplayServer.window_get_size() reports (0,0)
## under --headless):
##   "$GODOT" --path . --script res://tools/capture_frames.gd
##
## Writes /tmp/juice-sheet-<name>.png per captured sequence.

const COLUMNS: int = 4
const ROWS: int = 3
const FRAME_STRIDE: int = 2

## The hit sequence stacks hit-stop, screen shake, a flash, particles and a
## tumbling damage number -- more is happening per second than in a hover or
## a card play, so it gets a bigger, coarser-grained window to avoid running
## out of frames before the shake and number have had time to read.
const HIT_COLUMNS: int = 4
const HIT_ROWS: int = 4
const HIT_FRAME_STRIDE: int = 3

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _capture_hover()
	await _capture_play()
	await _capture_hit()
	print("contact sheets written to /tmp/juice-sheet-*.png")
	quit(0)

## Instantiates a fresh Level and lets it settle (deal-in, first layout) before
## anything touches it. Every sequence gets its own scene so state from one
## capture (spent AP, a card leaving the hand, a fighter's hp) never leaks
## into the next.
func _new_scene() -> Node:
	var scene: Node = load("res://level.tscn").instantiate()
	root.add_child(scene)
	for _i: int in range(10):
		await process_frame
	return scene

func _free_scene(scene: Node) -> void:
	root.remove_child(scene)
	scene.queue_free()

## Hover: the fan's centre card lifts under the cursor. Should overshoot and
## settle (spring easing), not slide linearly into place.
##
## The extra settle wait matters: the hand's own staggered deal-in (Task 5)
## is still finishing for the later cards ~10 frames after the scene is
## built (up to DEAL_STAGGER * index + SPRING_TIME of game time), and that
## tween writes to the same `target_position` property hover does. Trigger
## hover before it finishes and the two tweens fight over the same property,
## which is not the hover curve this sequence is trying to isolate.
func _capture_hover() -> void:
	var scene: Node = await _new_scene()
	await _settle(60)
	await _capture("hover", func() -> void:
		var card: CardView = scene.hand_view.get_child(2) as CardView
		card.apply_hover(true))
	_free_scene(scene)

## Play: the hand is forced to a single Block card before it is clicked, for
## two reasons. First, a random draw might not be affordable or might not
## even be an attack, so the sequence would not be reproducible. Second, and
## more important, Block does not damage the enemy, so playing it never
## triggers hit-stop -- this isolates the card's own anticipation + lunge
## motion from the impact reaction, which gets its own dedicated sequence
## below.
##
## The click is simulated by emitting the real `pressed` signal (not
## HandView.card_chosen directly) so the full path runs, including
## HandView._hand_off() -- that is what reparents the card out of the hand
## and arms _pending_view before HandView.launch_play() claims it. Emitting
## card_chosen straight would skip _hand_off, leave _pending_view unset, and
## launch_play() would silently no-op: the card would just vanish on the
## next hand rebuild with no lunge at all.
func _capture_play() -> void:
	var scene: Node = await _new_scene()
	scene.battle.deck.hand = [CardLibrary.load_card(&"block")] as Array[CardData]
	scene.hand_view.rebuild(scene.battle)
	await _settle(60)

	await _capture("play", func() -> void:
		var view: CardView = scene.hand_view.get_child(0) as CardView
		view.pressed.emit())
	_free_scene(scene)

## Hit: the enemy is brought to low hp through the real signal path (Fighter.
## apply_hp_loss(), then BattleState.fighters_changed emitted by hand), which
## drives the exact same reaction a real hit would -- so the resulting jolt is
## left to fully settle before anything is captured, rather than special-cased
## away. Only then is a Straight forced into the hand and played, so the
## FighterPanel's own before/after diff reports the card's true damage
## instead of the distance from full health.
func _capture_hit() -> void:
	var scene: Node = await _new_scene()
	scene.battle.enemy.apply_hp_loss(scene.battle.enemy.hp - 12)
	scene.battle.fighters_changed.emit()
	await _settle(90)

	scene.battle.deck.hand = [CardLibrary.load_card(&"straight")] as Array[CardData]
	scene.hand_view.rebuild(scene.battle)
	await _settle(60)

	var trigger := func() -> void:
		var view: CardView = scene.hand_view.get_child(0) as CardView
		view.pressed.emit()
	await _capture("hit", trigger, HIT_COLUMNS, HIT_ROWS, HIT_FRAME_STRIDE)
	_free_scene(scene)

func _settle(frames: int) -> void:
	for _i: int in range(frames):
		await process_frame

## Fires `trigger`, then captures columns*rows frames every stride frames and
## tiles them into one image.
func _capture(name: String, trigger: Callable,
		columns: int = COLUMNS, rows: int = ROWS, stride: int = FRAME_STRIDE) -> void:
	var shots: Array[Image] = []
	trigger.call()
	for i: int in range(columns * rows):
		for _s: int in range(stride):
			await process_frame
		shots.append(root.get_texture().get_image())

	var cell: Vector2i = shots[0].get_size()
	var sheet := Image.create(cell.x * columns, cell.y * rows, false, shots[0].get_format())
	for i: int in range(shots.size()):
		var col: int = i % columns
		var row: int = i / columns
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, cell),
			Vector2i(col * cell.x, row * cell.y))
	sheet.save_png("/tmp/juice-sheet-%s.png" % name)
	print("  wrote /tmp/juice-sheet-%s.png (%d frames, %dx%d grid, stride %d)" %
		[name, shots.size(), columns, rows, stride])
