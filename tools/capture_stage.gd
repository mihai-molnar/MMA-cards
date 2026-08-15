extends SceneTree

## Captures the fully composed fight stage -- background, both portraits, HUD
## readouts and the dealt hand -- so layout can be judged from a real render
## rather than from the constants that produced it. Companion to
## capture_cards.gd (static face layout) and capture_frames.gd (motion
## contact sheets); this tool needs both, because the stage has a settled
## composition to check AND a portrait-collision animation to check.
##
## Two captures, each against its own fresh scene instance (a settled first
## capture cannot be rewound to also serve as frame zero of the second):
##
##  - /tmp/fight-stage.png: one frame taken SETTLE_WAIT real seconds after the
##    scene enters the tree -- past the portrait slam
##    (Juice.SLAM_TIME + 2 * Juice.SLAM_RECOIL_TIME ~= 0.77s), past
##    battle.start(), and past the hand's staggered deal-in
##    (Juice.DEAL_STAGGER * (HandView.HAND_SIZE - 1) + Juice.SPRING_TIME
##    ~= 0.56s for the last card) -- roughly 1.33s end to end, so 1.5s leaves
##    only ~170ms of margin. Bumped to 1.6s here for headroom rather than
##    cutting it that close.
##  - /tmp/fight-stage-frames.png: a 4x3 contact sheet of the first ~0.9 real
##    seconds -- the portrait fly-in, collision and recoil all happen inside
##    that window. A single screenshot cannot show acceleration or recoil;
##    only a strip of frames can (see CLAUDE.md, "Verifying animation --
##    tests cannot see motion").
##
## Run NON-headless -- get_texture() needs a real rendering context, and
## DisplayServer.window_get_size() reports (0,0) under --headless:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_stage.gd
##
## Both captures pace by real elapsed time (Time.get_ticks_msec()), never by
## a fixed frame count -- this machine's external display runs at 100Hz, and
## a 60fps-tuned frame count would cut every window short (see
## capture_frames.gd's identical note, confirmed there empirically).

const STATIC_OUTPUT: String = "/tmp/fight-stage.png"
const FRAMES_OUTPUT: String = "/tmp/fight-stage-frames.png"

const SETTLE_WAIT: float = 1.6

const FRAME_COLUMNS: int = 4
const FRAME_ROWS: int = 3
## 12 frames * 0.075s = 0.9s of real time across the sheet.
const FRAME_INTERVAL: float = 0.075

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _capture_static()
	await _capture_slam_frames()
	print("wrote %s and %s" % [STATIC_OUTPUT, FRAMES_OUTPUT])
	quit(0)

func _new_scene() -> Node:
	var scene: Node = load("res://level.tscn").instantiate()
	root.add_child(scene)
	return scene

func _free_scene(scene: Node) -> void:
	root.remove_child(scene)
	scene.queue_free()

## The settled composition: BG, both portraits, HUD readouts and the dealt
## hand, all at rest.
func _capture_static() -> void:
	var scene: Node = _new_scene()
	await _wait_real_seconds(SETTLE_WAIT)
	# root.get_texture() can otherwise read a stale render: the viewport's
	# texture is only current as of the last COMPLETED draw, which does not
	# necessarily line up with the process frame that just elapsed (same
	# note as capture_cards.gd and capture_frames.gd).
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(STATIC_OUTPUT)
	print("wrote %s" % STATIC_OUTPUT)
	_free_scene(scene)

## The slam window: FRAME_COLUMNS * FRAME_ROWS frames spanning the first
## ~0.9 real seconds from scene creation, tiled into one sheet so the
## collision curve (accelerate in, contact, recoil, resettle) is inspectable
## rather than eyeballed off a single screenshot.
func _capture_slam_frames() -> void:
	var scene: Node = _new_scene()
	var shots: Array[Image] = []
	var next_capture: float = Time.get_ticks_msec() / 1000.0
	for _i: int in range(FRAME_COLUMNS * FRAME_ROWS):
		next_capture += FRAME_INTERVAL
		while (Time.get_ticks_msec() / 1000.0) < next_capture:
			await process_frame
		await RenderingServer.frame_post_draw
		shots.append(root.get_texture().get_image())

	var cell: Vector2i = shots[0].get_size()
	var sheet := Image.create(cell.x * FRAME_COLUMNS, cell.y * FRAME_ROWS, false, shots[0].get_format())
	for i: int in range(shots.size()):
		var col: int = i % FRAME_COLUMNS
		var row: int = i / FRAME_COLUMNS
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, cell), Vector2i(col * cell.x, row * cell.y))
	sheet.save_png(FRAMES_OUTPUT)
	print("wrote %s (%d frames, %dx%d grid, %.3fs apart)" %
		[FRAMES_OUTPUT, shots.size(), FRAME_COLUMNS, FRAME_ROWS, FRAME_INTERVAL])
	_free_scene(scene)

func _wait_real_seconds(seconds: float) -> void:
	var deadline: float = Time.get_ticks_msec() / 1000.0 + seconds
	while (Time.get_ticks_msec() / 1000.0) < deadline:
		await process_frame
