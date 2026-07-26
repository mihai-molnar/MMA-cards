extends SceneTree

## Renders the three cards exactly as CardView draws them and writes a
## screenshot, at 1x and at 3x.
##
## Card-face layout is geometry no test can check. An assertion that
## _value_label.position equals CardTemplate's zone proves the code did what
## the code says -- not that the number landed inside the shield. This project
## has been burned by that exact class of green-test-over-broken-visual
## before (see CLAUDE.md, "Verifying animation -- tests cannot see motion").
##
## The 1x row is what the player actually sees and is the row that decides
## whether the layout is right. The 3x row is only for finding WHICH edge is
## off once the 1x row looks wrong.
##
## Run NON-headless -- get_texture() needs a real rendering context:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_cards.gd

const OUTPUT: String = "/tmp/card-faces.png"
const CARD_IDS: Array[StringName] = [&"jab", &"straight", &"block"]
const GAP: float = 20.0
const ZOOM: float = 3.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	_add_row(Vector2(GAP, GAP), 1.0)
	_add_combo_row(Vector2(GAP, GAP * 2.0 + CardView.CARD_SIZE.y))
	_add_row(Vector2(GAP, GAP * 3.0 + CardView.CARD_SIZE.y * 2.0), ZOOM)

	# Let the tree lay out and draw before reading the viewport back.
	for _i: int in range(10):
		await process_frame
	# root.get_texture() can otherwise read a stale render: the viewport's
	# texture is only current as of the last COMPLETED draw, which does not
	# necessarily line up with the process frame that just elapsed.
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	image.save_png(OUTPUT)
	print("wrote %s" % OUTPUT)
	quit(0)

## The same Straight, un-armed then combo-armed, side by side.
##
## set_combo_armed() tints the FRAME, which is already gold -- so "does the gold
## get golder" is a question a single card cannot answer and a description
## cannot either. Two cards adjacent is the only way to see whether the tint
## carries as a state change or just looks like a lighting variation. This is
## the same reason the hand's motion gets a contact sheet rather than a
## screenshot: the value being judged is a difference, so the capture has to
## contain both sides of it.
func _add_combo_row(origin: Vector2) -> void:
	var row := Control.new()
	row.position = origin
	root.add_child(row)

	for i: int in range(2):
		var view: CardView = CardView.create(CardLibrary.load_card(&"straight"))
		view.set_combo_armed(i == 1)
		# target_position, never position -- see the note in _add_row().
		view.target_position = Vector2(i * (CardView.CARD_SIZE.x + GAP), 0.0)
		row.add_child(view)

func _add_row(origin: Vector2, zoom: float) -> void:
	var row := Control.new()
	row.position = origin
	row.scale = Vector2(zoom, zoom)
	root.add_child(row)

	var x: float = 0.0
	for card_id: StringName in CARD_IDS:
		var view: CardView = CardView.create(CardLibrary.load_card(card_id))
		# NOTE: CardView is in the tree here, so _process recomposes
		# `position` from `target_position` every frame (see CLAUDE.md,
		# "A card's transform is composed, never assigned"). Assigning
		# `.position` directly (as the task brief's Step 1 code literally
		# does) gets silently overwritten back to target_position's default
		# of Vector2.ZERO on the next frame -- all three cards in a row then
		# stack at (0,0) and only the last-added one is visible on top.
		# Confirmed by running the brief's code verbatim first: the capture
		# showed only one "BLOCK" card per row instead of three. Targeting
		# `target_position` is the fix.
		view.target_position = Vector2(x, 0.0)
		row.add_child(view)
		x += CardView.CARD_SIZE.x + GAP
