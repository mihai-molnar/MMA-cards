extends SceneTree

## Renders the card library exactly as CardView draws them and writes a
## screenshot: row one is the five library/preview faces (see _add_row), row
## two is the un-armed/combo-armed Straight pair plus the whole reward pool
## (BattleConfig.REWARD_CARDS -- six cards since the KO pass added High
## Kick, Flying Knee and Elbow), laid out so both rows fit on the project's
## 1152x648 base canvas.
##
## Card-face layout is geometry no test can check. An assertion that
## _type_label.position equals CardTemplate's zone proves the code did what
## the code says -- not that the number landed inside the shield. This project
## has been burned by that exact class of green-test-over-broken-visual
## before (see CLAUDE.md, "Verifying animation -- tests cannot see motion").
##
## There used to be a second copy of the three-card row scaled 3x underneath,
## meant to zoom in on whichever edge looked off. It never fit: even before a
## second row (the combo pair) was added below it, the 3x row's own height
## alone (900px) put it well past the 648-tall canvas, so root.get_texture()
## never actually contained it -- the capture silently cropped it away every
## time the tool ran. It was deleted rather than resized, because a second
## row is redundant here: project.godot sets window/stretch/mode to
## "canvas_items" with a 2560x1440 window over a 1152x648 canvas, so this
## capture is already rendered at 2560.0 / 1152.0 = 2.222x -- a 200x300 card
## lands as roughly 444x667 real pixels in the written PNG. That is the
## zoomed-in detail the deleted row existed to provide.
##
## Run NON-headless -- get_texture() needs a real rendering context:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_cards.gd

const OUTPUT: String = "/tmp/card-faces.png"
const CARD_IDS: Array[StringName] = [&"jab", &"straight", &"block", &"low_kick"]
const GAP: float = 20.0
## Six reward cards no longer fit at full scale beside the combo pair (6*200
## + 5*20 = 1300px alone, before the pair or margins). REWARD_SCALE shrinks
## just the reward strip -- the combo pair stays full scale so the tint
## comparison that row exists for is untouched. 0.5 is the smallest of the
## already-established "grid of many cards" scales in the codebase
## (DevMenu/PileView use 0.55, RewardsView 0.7 for three cards) -- picked
## here because six cards is the most crowded grid this project renders.
const REWARD_SCALE: float = 0.5
const REWARD_GAP: float = 14.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.09, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	# Two stacked rows since the library grew to four cards, plus a fifth
	# preview card appended to the card row (see _add_row): the card row is
	# now 1080px of content (5 cards + 4 internal gaps), which no longer
	# leaves room for the 420px combo pair beside it inside the 1152-wide
	# canvas (1080 + 20 + 420 = 1520). Horizontally the card row alone still
	# fits: GAP + 1080 = 1100 against the 1152-wide canvas -- 52px to spare.
	# Vertically both rows fit with margin: GAP + 300 + GAP + 300 = 640
	# against the 648-tall canvas -- 8px to spare, so keep GAP at 20 or
	# re-check this arithmetic.
	_add_row(Vector2(GAP, GAP))
	_add_combo_row(Vector2(GAP, GAP + CardView.CARD_SIZE.y + GAP))

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

## The same Straight, un-armed then combo-armed, side by side, plus the
## whole reward pool sharing row two. The pair stays full scale (420px);
## the reward strip renders at REWARD_SCALE and is sized to fit the
## remaining width -- see _add_reward_strip.
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

	_add_reward_strip(row, 2.0 * (CardView.CARD_SIZE.x + GAP))

## Iterates BattleConfig.REWARD_CARDS directly (live-read, like every other
## reader of that constant -- RewardPool, CardLibrary, the dev menu) rather
## than a hardcoded id list, so a future pool change shows up here with no
## edit to this tool. Each card renders at REWARD_SCALE, vertically centred
## in the row's CARD_SIZE.y band so it sits level with the full-scale combo
## pair beside it. Uses set_rest_transform's pivot-compensated placement
## (see DevMenu.open() for the same math) since CardView scales about its
## bottom-centre pivot -- a naive position assignment would offset a scaled
## card up and to the right of where it visually belongs.
##
## Width check at REWARD_SCALE 0.5 (cell 100x150), REWARD_GAP 14: six cells
## plus five gaps is 6*100 + 5*14 = 670px, starting at x_start (440 local, or
## 460 once the row's own GAP-px origin is added) -- the strip's right edge
## lands at 460 + 670 = 1130, inside the 1152-wide canvas with 22px to
## spare. Widen REWARD_GAP or shrink REWARD_SCALE if the pool grows again.
func _add_reward_strip(row: Control, x_start: float) -> void:
	var cell: Vector2 = CardView.CARD_SIZE * REWARD_SCALE
	var y: float = (CardView.CARD_SIZE.y - cell.y) / 2.0
	var x: float = x_start
	for card_id: StringName in BattleConfig.REWARD_CARDS:
		var view: CardView = CardView.create(CardLibrary.load_card(card_id))
		var rest := Vector2(
			x - CardView.CARD_SIZE.x * (1.0 - REWARD_SCALE) / 2.0,
			y - CardView.CARD_SIZE.y * (1.0 - REWARD_SCALE))
		view.set_rest_transform(rest, 0.0, 0, REWARD_SCALE)
		row.add_child(view)
		x += cell.x + REWARD_GAP

func _add_row(origin: Vector2) -> void:
	var row := Control.new()
	row.position = origin
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

	_add_injured_jab_preview(row, x)

## A fifth card: the same Jab, but with update_rules_preview() called against
## a leg-injured source fighter, so its printed damage shows the LIVE 3
## (weakened orange) instead of the flat base 6 (plain damage red) the other
## row-one cards render with. A throwaway Fighter pair -- update_rules_preview
## only reads their statuses, so neither needs to join the scene tree.
func _add_injured_jab_preview(row: Control, x: float) -> void:
	var injured := Fighter.new("Injured", 50)
	injured.statuses.apply(LegInjuryStatus.ID, 1, 3)
	var target := Fighter.new("Target", 50)

	var view: CardView = CardView.create(CardLibrary.load_card(&"jab"))
	view.update_rules_preview(injured, target)
	view.target_position = Vector2(x, 0.0)
	row.add_child(view)
