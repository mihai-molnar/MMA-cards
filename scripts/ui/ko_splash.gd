class_name KoSplash
extends Control

## The fight-ending overlay: the KO art stamps in centre-screen on a
## knockout; the failed art blinks and fades on a missed KO roll. Owned by
## BattleView, which drives it from BattleState's ko_scored/ko_failed
## signals at the deferred impact moment. Pure presentation -- the model is
## already final when this shows. Timings live in Juice; the art size (a
## layout constant) lives here, with its owner.

## Above StatusTooltip.TOOLTIP_Z (70): nothing covers the KO moment.
const SPLASH_Z: int = 80
const CANVAS: Vector2 = Vector2(1152, 648)
## Displayed art size in canvas pixels -- the PNGs are larger and scale
## down (mipmapped, so cleanly).
const ART_SIZE: Vector2 = Vector2(420, 420)

var _art: TextureRect
var _tween: Tween
## What was last shown -- recorded BEFORE the tree guard (project rule), so
## detached tests can assert the decision.
var _last_shown: StringName = &""

func _init() -> void:
	visible = false
	z_index = SPLASH_Z
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_art = TextureRect.new()
	# stretch/expand BEFORE position/size -- EXPAND_KEEP_SIZE would snap the
	# rect back to the source PNG's own pixel size (see CLAUDE.md).
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.position = (CANVAS - ART_SIZE) / 2.0
	_art.size = ART_SIZE
	# Scale about the art's centre, not its corner.
	_art.pivot_offset = ART_SIZE / 2.0
	add_child(_art)

func show_ko() -> void:
	_last_shown = &"ko"
	_art.texture = CardArt.ui_icon_for(&"ko")
	_pop(Juice.KO_SPLASH_HOLD)

func show_failed() -> void:
	_last_shown = &"failed"
	_art.texture = CardArt.ui_icon_for(&"failed")
	_pop(Juice.KO_FAILED_HOLD)

## Silent hide for fight transitions, like PileView.dismiss().
func dismiss() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false

func last_shown() -> StringName:
	return _last_shown

func debug_art_texture() -> Texture2D:
	return _art.texture

## Stamp in (spring from oversized to rest), hold, fade, hide. Detached
## (tests) there is no tree to tween in: snap to the resting look and stay
## visible.
func _pop(hold: float) -> void:
	visible = true
	_art.modulate = Color.WHITE
	_art.scale = Vector2.ONE * Juice.KO_SPLASH_START_SCALE
	if not is_inside_tree():
		_art.scale = Vector2.ONE
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# Juice.spring() types on a whole Tween (see card_view.gd's usages) --
	# tween_property() returns a PropertyTweener, so the spring trans/ease is
	# set directly on this tweener instead, keeping the fade below at its
	# plain default rather than inheriting the pop's overshoot curve.
	_tween.tween_property(_art, "scale", Vector2.ONE, Juice.KO_SPLASH_POP_TIME) \
		.set_trans(Juice.SPRING_TRANS).set_ease(Juice.SPRING_EASE)
	_tween.tween_interval(hold)
	_tween.tween_property(_art, "modulate", Color(1.0, 1.0, 1.0, 0.0), Juice.KO_SPLASH_FADE)
	_tween.tween_callback(func() -> void: visible = false)
