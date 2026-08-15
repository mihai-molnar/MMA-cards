class_name CardView
extends Button

## One card, composed at runtime: an illustration, the shared master frame,
## and four text zones read from CardData. Knows how to draw a card and
## report clicks; knows nothing about whether playing it is legal.
##
## Nothing about the face is baked into an image, so a balance change is
## reflected on the card the moment the .tres is regenerated. Geometry and
## typography live in CardTemplate.

signal card_selected(view: CardView)
## Emitted by apply_hover on every actual state change, so HandView can part
## the neighbours without HandView having to wire up its own mouse tracking.
signal hover_changed(view: CardView, hovered: bool)

const CARD_SIZE: Vector2 = Vector2(200, 300)
## Combo-armed BRIGHTENS the frame rather than tinting it gold, and the channel
## values are deliberately above 1.0. The obvious approach --
## `Color.WHITE.lerp(Color(1.0, 0.80, 0.20), 0.25)`, which is what shipped
## first -- makes an already-gold frame very slightly warmer: measured against
## a render, mean gold luma moved 167.4 -> 170.1, a 1.6% shift that is simply
## not visible on a card swaying in a fan. Godot treats modulate above 1.0 as
## overbright, so this reads as the card lighting up, which is the state being
## communicated. Blue stays below 1.0 so it brightens toward gold, not white.
const COMBO_ARMED_TINT: Color = Color(1.30, 1.20, 0.88)
const UNAFFORDABLE_ALPHA: float = 0.45

const HOVER_Z: int = 50
const LUNGE_Z: int = 60

var card: CardData

## Where this card sits when not hovered. HandView sets these when it fans.
var rest_position: Vector2 = Vector2.ZERO
var rest_rotation: float = 0.0
var rest_z_index: int = 0

## Where the current animation is heading. Tweens need real frames, which
## headless tests do not have, so tests assert these rather than the live
## transform. Always recomputed from rest_*, so hovering cannot drift.
var target_position: Vector2 = Vector2.ZERO
var target_rotation: float = 0.0
var target_scale: Vector2 = Vector2.ONE

## The anchor most recently passed to lunge_to(). Test hook, set before the
## is_inside_tree() guard so it is observable even though tests instantiate
## cards detached and never see the tween itself run.
var debug_last_lunge_anchor: Vector2 = Vector2.ZERO

var _hovered: bool = false
var _tween: Tween

## Continuous-motion layers, added on top of the tweened target_* values every
## frame. See _process.
var _idle_phase: float = 0.0
var _idle_offset: Vector2 = Vector2.ZERO
var _idle_rotation: float = 0.0
var _tilt_offset: Vector2 = Vector2.ZERO
var _tilt_rotation: float = 0.0
## Hand parting (see HandView): where the fan wants this card shoved while a
## neighbour is hovered, and the lerped live value. A fourth additive compose
## layer, deliberately NOT a tween -- the shared _tween slot stays free for
## hover/lunge, so parting can never fight them.
var _part_target: Vector2 = Vector2.ZERO
var _part_offset: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _lunging: bool = false

## Bottom to top: illustration, frame, then the four text zones. See _build().
var _illustration: TextureRect
var _frame: TextureRect
var _title_label: ArcTitleLabel
var _type_label: Label
var _rules_label: RichTextLabel
var _cost_label: Label

static func create(p_card: CardData) -> CardView:
	var view := CardView.new()
	view.configure(p_card)
	return view

func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	# Bottom-centre, so rotation reads as a held fan rather than a pinwheel.
	pivot_offset = Vector2(CARD_SIZE.x / 2.0, CARD_SIZE.y)
	flat = true
	# Never take keyboard focus: flat = true hides the normal stylebox, but a
	# clicked Button still grabs focus and Godot paints its default white focus
	# rectangle over the card. Mouse-driven game, no keyboard nav.
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_build()
	_idle_phase = randf() * TAU
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)

## The live transform is composed from three layers every frame:
##   target_* : absolute values the tweens drive (hover, squash, lunge, deal)
##   idle     : continuous sway, additive, paused while hovered or lunging
##   tilt     : cursor lean, additive, hovered card only
##
## Tweens therefore must NEVER target position/rotation/scale directly — this
## loop would overwrite them every frame and the result would be jitter rather
## than a clean failure.
func _process(delta: float) -> void:
	_elapsed += delta
	_update_idle()
	_update_tilt(delta)
	_update_part(delta)
	position = Juice.compose_position(target_position, _idle_offset, _tilt_offset, _part_offset)
	rotation = Juice.compose_rotation(target_rotation, _idle_rotation, _tilt_rotation)
	scale = target_scale

func _update_idle() -> void:
	# Hovering stops the sway: the card being read is the one card holding
	# still. A lunging card is already fully driven by its tween.
	if _hovered or _lunging:
		_idle_offset = Vector2.ZERO
		_idle_rotation = 0.0
		return
	_idle_offset = Juice.idle_offset(_elapsed, _idle_phase)
	_idle_rotation = Juice.idle_rotation(_elapsed, _idle_phase)

## Leans the hovered card toward the cursor, Balatro-style. Only the hovered
## card tilts — cheaper, and unread cards stay still.
func _update_tilt(delta: float) -> void:
	var want_offset := Vector2.ZERO
	var want_rotation: float = 0.0
	if _hovered and not _lunging and is_inside_tree():
		var to_cursor: Vector2 = get_global_mouse_position() - (global_position + CARD_SIZE / 2.0)
		var nx: float = clampf(to_cursor.x / (CARD_SIZE.x * 1.5), -1.0, 1.0)
		var ny: float = clampf(to_cursor.y / (CARD_SIZE.y * 1.5), -1.0, 1.0)
		want_rotation = deg_to_rad(nx * Juice.TILT_MAX_DEG)
		want_offset = Vector2(nx, ny) * Juice.TILT_MAX_PX
	var weight: float = clampf(delta * Juice.TILT_LERP_SPEED, 0.0, 1.0)
	_tilt_offset = _tilt_offset.lerp(want_offset, weight)
	_tilt_rotation = lerpf(_tilt_rotation, want_rotation, weight)

## Eases the live part offset toward its target, same shape as _update_tilt.
## The hovered card itself always has a zero target (HandView never parts it),
## so this needs no hovered/lunging special case.
func _update_part(delta: float) -> void:
	var weight: float = clampf(delta * Juice.PART_LERP_SPEED, 0.0, 1.0)
	_part_offset = _part_offset.lerp(_part_target, weight)

## Where the fan wants this card shoved sideways while a neighbour is hovered.
## Called by HandView; a plain target, lerped in _process, never a tween.
func set_part_offset(x: float) -> void:
	_part_target = Vector2(x, 0.0)

func debug_part_target() -> Vector2:
	return _part_target

func debug_idle_offset() -> Vector2:
	return _idle_offset

func debug_tilt() -> Vector2:
	return _tilt_offset

func is_lunging() -> bool:
	return _lunging

## True while a tween is actively driving target_* toward a destination.
## Test hook: lets tests confirm an animation was actually started, rather
## than only inspecting where target_* ends up.
func debug_is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

func _build() -> void:
	# Bottom to top. The frame is drawn OVER the illustration, not under it:
	# the illustration fills a plain rectangle and the frame's own window is
	# what crops it to shape, so a new illustration needs no matching cut-out.
	_illustration = TextureRect.new()
	_illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration.clip_contents = true
	_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_illustration)

	# STRETCH_SCALE, not KEEP_ASPECT: the frames are 1024x1536, exactly
	# CARD_SIZE's 2:3, so scaling is uniform anyway -- and being explicit means
	# a future frame authored at the wrong aspect distorts visibly instead of
	# quietly letterboxing itself out of alignment with the zones.
	_frame = TextureRect.new()
	_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	# The title bends along the banner's arch -- an ArcTitleLabel, not a flat
	# Label. It styles itself from CardTemplate.
	_title_label = ArcTitleLabel.new()
	add_child(_title_label)

	_type_label = _make_label(CardTemplate.TYPE_SIZE, CardTemplate.TYPE_COLOR, true)
	add_child(_type_label)

	_cost_label = _make_label(CardTemplate.COST_SIZE, CardTemplate.COST_COLOR, true)
	add_child(_cost_label)

	# A RichTextLabel, not a Label: the numbers inside the rules text are
	# coloured via bbcode (CardTemplate.rules_bbcode), which Label cannot
	# render. Light ink on the dark panel, and the only wrapping label.
	_rules_label = RichTextLabel.new()
	_rules_label.bbcode_enabled = true
	_rules_label.scroll_active = false
	_rules_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Centred, not top-aligned: RULES_ZONE is fitted to the panel, and cards
	# differ in line count (Block wraps to one line, Straight to two). Pinning
	# to the top leaves a one-line card's text floating above an empty panel.
	_rules_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rules_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if CardTemplate.FONT != null:
		_rules_label.add_theme_font_override("normal_font", CardTemplate.FONT)
	_rules_label.add_theme_font_size_override("normal_font_size", CardTemplate.RULES_SIZE)
	_rules_label.add_theme_color_override("default_color", CardTemplate.RULES_COLOR)
	add_child(_rules_label)

	pressed.connect(_on_pressed)

func _make_label(font_size: int, color: Color, outlined: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	# Outlined labels are the display text (title, badges); un-outlined is the
	# rules ink. The two faces are picked in CardTemplate, not here.
	var font: Font = CardTemplate.DISPLAY_FONT if outlined else CardTemplate.FONT
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_color", color)
	if outlined:
		label.add_theme_constant_override("outline_size", CardTemplate.OUTLINE_SIZE)
		label.add_theme_color_override("font_outline_color", CardTemplate.OUTLINE_COLOR)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func configure(p_card: CardData) -> void:
	card = p_card
	if card == null:
		return
	var variant: StringName = CardTemplate.variant_for(card)
	_frame.texture = CardArt.frame_for(CardTemplate.frame_name(variant))
	_illustration.texture = CardArt.illustration_for(card.id)
	_title_label.text = card.display_name
	_cost_label.text = str(card.cost)
	_type_label.text = CardTemplate.type_text(variant)
	# The numbers live INSIDE this text, coloured (damage red, guard blue) by
	# CardTemplate.rules_bbcode -- and they are derived from the card's
	# effects or its authored rules_text, never stored twice, so the card
	# cannot print a value the rules disagree with.
	_rules_label.text = CardTemplate.rules_bbcode(card)
	_layout_zones()
	set_combo_armed(false)

## Positions every layer from the template's normalized zones. One shared
## frame, so every card lays out identically.
##
## These write position/size on CHILD controls directly. That does not violate
## the compose-never-assign rule: _process composes position/rotation/scale of
## the CardView itself, and never touches its children's rects.
func _layout_zones() -> void:
	_place(_illustration, CardTemplate.to_pixels(CardTemplate.WINDOW_ZONE, CARD_SIZE))
	_place(_title_label, CardTemplate.to_pixels(CardTemplate.TITLE_ZONE, CARD_SIZE))
	_place(_type_label, CardTemplate.to_pixels(CardTemplate.TYPE_ZONE, CARD_SIZE))
	_place(_rules_label, CardTemplate.to_pixels(CardTemplate.RULES_ZONE, CARD_SIZE))
	_place_centred(_cost_label, CardTemplate.COST_CENTRE, CardTemplate.COST_BOX)

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

## Centres a control on a normalized point. Defers the centring arithmetic to
## CardTemplate.centred_pixels() so there is exactly one copy of it -- the
## bounds tests use the same function, and a second copy here would be free to
## drift away from the one under test.
##
## Reads `size` BACK after assigning it, because Control clamps size up to its
## minimum: a two-digit number at font 22 is wider than the attack frame's 20px
## badge gap, so the label silently becomes bigger than the box it was given.
## Positioning from the requested box instead of the actual size would then
## push every two-digit value half a box off its icon -- and it would look
## almost right, which is the worst kind of wrong.
func _place_centred(control: Control, centre: Vector2, box: Vector2) -> void:
	var rect: Rect2 = CardTemplate.centred_pixels(centre, box, CARD_SIZE)
	control.size = rect.size
	control.position = rect.get_center() - control.size / 2.0

## Re-renders the rules label from live fighters, so the printed number
## reflects whatever modifiers currently apply (Leg Injury halving the
## source's outgoing damage, for instance) instead of the card's flat base
## value. The initial face composition in configure() keeps calling the
## plain single-argument rules_bbcode(card); this is what HandView calls on
## every refresh so the preview stays current as statuses come and go.
func update_rules_preview(source: Fighter, target: Fighter) -> void:
	if card == null:
		return
	_rules_label.text = CardTemplate.rules_bbcode(card, source, target)

func set_affordable(value: bool) -> void:
	disabled = not value
	modulate.a = 1.0 if value else UNAFFORDABLE_ALPHA

## Idempotent: always computed from a fixed base (Color.WHITE), never lerped
## from whatever modulate currently holds. refresh_states() calls this once per
## model event, and lerping from the live value is exactly the bug that shipped
## once already -- the tint drifted further gold on every refresh.
##
## The FRAME is tinted, not the illustration: the gold belongs on the gold
## frame, and tinting the artwork would misrepresent what it depicts. Tinting
## modulate's RGB only (alpha stays 1.0) keeps this composing with
## set_affordable(false), which dims via modulate.a on the whole Button --
## Godot multiplies a child's modulate into its parent's when drawing, so the
## two combine automatically rather than fighting over one value.
func set_combo_armed(value: bool) -> void:
	_frame.modulate = COMBO_ARMED_TINT if value else Color.WHITE

## Everything the card displays, for tests. The rules come back PARSED --
## the visible characters, colour tags stripped -- because that is what the
## player reads.
func debug_text() -> String:
	return "%s | %s AP | %s | %s" % [
		_title_label.text, _cost_label.text, _type_label.text,
		_rules_label.get_parsed_text()]

func _on_pressed() -> void:
	card_selected.emit(self)

## Called by HandView when it fans the hand. Snaps immediately unless the card
## is mid-hover, so a rebuild never yanks a lifted card out from under the cursor.
func set_rest_transform(p_position: Vector2, p_rotation: float, p_z_index: int) -> void:
	rest_position = p_position
	rest_rotation = p_rotation
	rest_z_index = p_z_index
	if _hovered:
		return
	target_position = p_position
	target_rotation = p_rotation
	target_scale = Vector2.ONE
	position = p_position
	rotation = p_rotation
	scale = Vector2.ONE
	z_index = p_z_index

## Named is_card_hovered() rather than is_hovered(): BaseButton (our ancestor)
## already defines a native is_hovered() backed by the engine's own mouse
## tracking. GDScript cannot actually override it — calls resolve to the native
## getter regardless of a script method of the same name, so a same-named
## override silently returns the wrong value (confirmed: it kept reading false
## after apply_hover(true) in headless tests, which never generate real mouse
## input). This is a script-level notion of "hover" driven entirely by
## apply_hover(), which is why it needs its own name.
func is_card_hovered() -> bool:
	return _hovered

## Exposed separately from the mouse signals so tests can drive hover without
## synthesising input events.
func apply_hover(value: bool) -> void:
	if _hovered == value:
		return
	_hovered = value
	hover_changed.emit(self, value)
	if value:
		z_index = HOVER_Z
		_animate_to(rest_position - Vector2(0.0, Juice.HOVER_LIFT), 0.0, Vector2.ONE * Juice.HOVER_SCALE)
	else:
		z_index = rest_z_index
		_animate_to(rest_position, rest_rotation, Vector2.ONE)
	_update_idle()

## The played-card animation: a short backswing away from the target, then the
## strike. The card must already have been reparented out of HandView.
func lunge_to(anchor: Vector2) -> void:
	debug_last_lunge_anchor = anchor
	_lunging = true
	z_index = LUNGE_Z
	disabled = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		queue_free()
		return

	var centre: Vector2 = target_position + CARD_SIZE / 2.0
	var toward: Vector2 = (anchor - centre).normalized()
	var wind_up: Vector2 = target_position - toward * Juice.ANTICIPATE_DIST

	var tween := create_tween()
	# Anticipation: pull back before striking, so the punch has a windup.
	tween.tween_property(self, "target_position", wind_up, Juice.ANTICIPATE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "target_scale", Juice.SQUASH_SCALE, Juice.ANTICIPATE_TIME)
	# The strike: accelerate into the target, stretched along travel.
	tween.chain().tween_property(self, "target_position", anchor - CARD_SIZE / 2.0, Juice.LUNGE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "target_scale",
		Juice.STRETCH_SCALE * Juice.LUNGE_SCALE, Juice.LUNGE_TIME)
	tween.parallel().tween_property(self, "target_rotation", 0.0, Juice.LUNGE_TIME)
	# Stay fully opaque for LUNGE_FADE_RATIO of the strike, then fade over what
	# remains, in parallel with the position tween above. A plain
	# tween_interval() followed by a plain tween_property() does NOT achieve
	# this: a non-parallel tweener starts after the *whole* previous parallel
	# group finishes (here, LUNGE_TIME -- the longest tweener in the group),
	# not after just the interval, so the fade would never visibly start
	# early (confirmed empirically before landing on this). set_delay() on
	# the parallel-joined PropertyTweener itself is the correct primitive:
	# it delays that one tweener's own start within the group.
	var fade_time: float = Juice.LUNGE_TIME * (1.0 - Juice.LUNGE_FADE_RATIO)
	var fade_delay: float = Juice.LUNGE_TIME - fade_time
	tween.parallel().tween_property(self, "modulate:a", 0.0, fade_time).set_delay(fade_delay)
	tween.chain().tween_callback(queue_free)
	_tween = tween

## Springs this card to a position, optionally after a delay. Owns the tween in
## the shared _tween slot, so a hover or lunge starting mid-flight cancels it
## instead of fighting it. HandView's deal uses this rather than creating its
## own tween -- a tween owned by another node is invisible to _animate_to's
## kill, and the two then drive target_position simultaneously.
func spring_to(p_position: Vector2, delay: float = 0.0) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		# No _process off-tree, so snap immediately, same as _animate_to's
		# out-of-tree branch.
		target_position = p_position
		position = p_position
		return
	_tween = Juice.spring(create_tween())
	_tween.tween_interval(delay)
	_tween.tween_property(self, "target_position", p_position, Juice.SPRING_TIME)

## Places the card at `start` and springs it to its resting slot. Used when the
## hand re-fans after a card leaves: the rebuild destroys and recreates every
## node, so without carrying the old position across, survivors simply appear
## at their new slots and the re-fan reads as a snap.
##
## Takes only a start -- the destination is always rest_position, which
## set_rest_transform() (via HandView.layout_cards(), always called before
## this) has already written. Owns the tween in the shared _tween slot,
## killing any existing one, exactly as spring_to() does -- a tween created
## outside CardView is invisible to _animate_to's kill, which is precisely
## the bug that once left hover silently dead.
func slide_from(start: Vector2, delay: float = 0.0) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		# No _process off-tree, so snap immediately to the rest position
		# layout_cards() already assigned -- same as spring_to's and
		# _animate_to's out-of-tree branch.
		target_position = rest_position
		position = rest_position
		return
	target_position = start
	position = start
	_tween = Juice.spring(create_tween())
	_tween.tween_interval(delay)
	_tween.tween_property(self, "target_position", rest_position, Juice.REFAN_TIME)

func _animate_to(p_position: Vector2, p_rotation: float, p_scale: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		# No _process off-tree, so snap immediately -- tests need this branch,
		# and there is no tween to animate the snap away in the next frame.
		target_position = p_position
		target_rotation = p_rotation
		target_scale = p_scale
		position = p_position
		rotation = p_rotation
		scale = p_scale
		return
	# In-tree: target_* stays at its current value here and the tween below
	# carries it to p_position/p_rotation/p_scale over Juice.HOVER_TIME. Do
	# NOT pre-assign target_* to the destination -- that would make the tween
	# interpolate from the destination to itself, i.e. animate nothing, and
	# _process would compose the final pose on the very next frame instead of
	# easing toward it.
	_tween = Juice.spring(create_tween())
	_tween.tween_property(self, "target_position", p_position, Juice.HOVER_TIME)
	_tween.parallel().tween_property(self, "target_rotation", p_rotation, Juice.HOVER_TIME)
	_tween.parallel().tween_property(self, "target_scale", p_scale, Juice.HOVER_TIME)

## Compresses the card the instant it is pressed, before anything else happens.
## Immediate physical response to a click is most of what makes it feel good.
func _on_button_down() -> void:
	if not is_inside_tree():
		return
	# Share _tween slot so squash, hover and lunge tweens are mutually exclusive.
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tween := create_tween()
	tween.tween_property(self, "target_scale", Juice.SQUASH_SCALE, Juice.SQUASH_TIME)
	tween.tween_property(self, "target_scale",
		Vector2.ONE * Juice.HOVER_SCALE if _hovered else Vector2.ONE, Juice.SQUASH_TIME)
	_tween = tween

func _on_mouse_entered() -> void:
	apply_hover(true)

func _on_mouse_exited() -> void:
	apply_hover(false)
