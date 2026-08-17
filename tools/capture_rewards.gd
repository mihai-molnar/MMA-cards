extends SceneTree

## Renders RewardsView exactly as the game shows it -- background, title,
## the three faces with the middle one selected, both buttons -- and writes
## a screenshot. Card-face and screen layout are geometry no test can check
## (see CLAUDE.md, "Verifying animation"). Run NON-headless:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_rewards.gd

const OUTPUT: String = "/tmp/rewards-screen.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := RewardsView.new()
	root.add_child(view)
	view.open(RewardPool.options())
	var middle: CardView = view.debug_card_views()[1]
	middle.card_selected.emit(middle)

	for _i: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	image.save_png(OUTPUT)
	print("wrote %s" % OUTPUT)
	quit(0)
