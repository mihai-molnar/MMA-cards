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

## The play sequence (anticipation + lunge) now spans Juice.ANTICIPATE_TIME +
## Juice.LUNGE_TIME = 0.57s -- longer than COLUMNS*ROWS*FRAME_STRIDE covers
## at the default stride (12 * 2/60.0 = 0.4s). Stride 6 (0.1s apart, 1.2s
## total across the 4x3 grid) comfortably spans the full 0.57s with room to
## spare, so the sheet shows the card actually arriving and fading rather
## than being cut off mid-flight.
const PLAY_FRAME_STRIDE: int = 6

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
	await _capture_refan()
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
		view.pressed.emit(), COLUMNS, ROWS, PLAY_FRAME_STRIDE)
	_free_scene(scene)

## Refan: playing a card from a multi-card hand shows both the lunge AND the
## remaining cards sliding into their closed-up slots -- _capture_play()
## above forces a single-card hand specifically so nothing is left behind to
## re-fan, which isolates the lunge but has nothing to say about
## HandView.rebuild()'s carried-position slide. Block is played here for the
## same reason as above: no damage means no hit-stop, shake or flash
## competing for attention with the re-fan this sequence exists to show.
func _capture_refan() -> void:
	var scene: Node = await _new_scene()
	scene.battle.deck.hand = [
		CardLibrary.load_card(&"jab"),
		CardLibrary.load_card(&"block"),
		CardLibrary.load_card(&"straight"),
	] as Array[CardData]
	scene.hand_view.rebuild(scene.battle)
	await _settle(60)

	await _capture("refan", func() -> void:
		var view: CardView = scene.hand_view.get_child(1) as CardView
		view.pressed.emit(), COLUMNS, ROWS, PLAY_FRAME_STRIDE)
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

## Fires `trigger`, then captures columns*rows frames spaced stride/60.0
## seconds apart (stride is calibrated in frames at a nominal 60fps) and
## tiles them into one image.
##
## Paced by real elapsed time (Time.get_ticks_msec()) rather than a raw
## await-process_frame count: this tool runs non-headless, and how much
## real time a fixed frame count spans depends on the display's actual
## refresh rate. Confirmed on this machine -- an external display running
## at 100Hz, not 60 -- a frame-count stride captured a shorter real-time
## window than the constants below were sized for, cutting the play
## sequence off mid-flight instead of showing it arrive and fade. Pacing by
## wall-clock time keeps each stride's real-world duration the same
## regardless of refresh rate.
func _capture(name: String, trigger: Callable,
		columns: int = COLUMNS, rows: int = ROWS, stride: int = FRAME_STRIDE) -> void:
	var shots: Array[Image] = []
	trigger.call()
	var interval: float = stride / 60.0
	var next_capture: float = Time.get_ticks_msec() / 1000.0
	for i: int in range(columns * rows):
		next_capture += interval
		while (Time.get_ticks_msec() / 1000.0) < next_capture:
			await process_frame
		# root.get_texture() can otherwise read a stale render: the viewport's
		# texture is only guaranteed current as of the last completed draw,
		# which does not necessarily line up with the process frame that just
		# elapsed. Confirmed empirically -- without this, several consecutive
		# captures in the play sequence silently repeated an already-stale
		# frame instead of advancing, one file:cell to the next.
		await RenderingServer.frame_post_draw
		shots.append(root.get_texture().get_image())

	var cell: Vector2i = shots[0].get_size()
	var sheet := Image.create(cell.x * columns, cell.y * rows, false, shots[0].get_format())
	for i: int in range(shots.size()):
		var col: int = i % columns
		var row: int = i / columns
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, cell),
			Vector2i(col * cell.x, row * cell.y))
	sheet.save_png("/tmp/juice-sheet-%s.png" % name)
	print("  wrote /tmp/juice-sheet-%s.png (%d frames, %dx%d grid, stride %d = %.2fs apart)" %
		[name, shots.size(), columns, rows, stride, interval])
