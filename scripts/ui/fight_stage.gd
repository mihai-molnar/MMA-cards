class_name FightStage
extends Control

## The scenery layer: arena background plus the two half-screen fighter
## portraits that ARE the scene once a fight starts. Sits at the bottom of
## the HUD's z-order; every readout draws over it.
##
## House animation rules apply throughout: one owned tween slot per animated
## concern (killed before reuse), decisions recorded BEFORE is_inside_tree()
## guards, and every departure from rest returns to a STORED home value.

const DESIGN_SIZE: Vector2 = Vector2(1152, 648)
const HALF_SIZE: Vector2 = Vector2(576, 648)

## Test hooks -- written before any tree guard, so headless suites can
## assert the decisions the animations would act on.
var debug_slam_count: int = 0
var debug_portrait_ids: Array = []
var debug_last_hit_side: StringName = &""

var _background: TextureRect
var _left: TextureRect
var _right: TextureRect
var _left_flash: ColorRect
var _right_flash: ColorRect
## Stored homes -- the only positions shakes and slams ever return to.
var _left_home: Vector2 = Vector2.ZERO
var _right_home: Vector2 = Vector2(HALF_SIZE.x, 0.0)

var _slam_tween: Tween
var _flash_tweens: Dictionary = {}
var _shake_tweens: Dictionary = {}

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background = TextureRect.new()
	_background.texture = CardArt.background_for(&"octagon")
	# expand_mode must be set BEFORE size: Control.set_size() clamps against
	# get_minimum_size(), and the default expand_mode (EXPAND_KEEP_SIZE)
	# reports the source PNG's own pixel size (1086x1448) as that minimum.
	# Assigning `.size` first silently clamped the background's height back
	# up to 1448 instead of the intended 648 (confirmed by probing the exact
	# sequence headless -- same bug, same fix as FighterPanel._make_icon).
	# Harmless here only by accident: the extra height falls below the
	# visible canvas rather than corrupting a number inside a window.
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.size = DESIGN_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_left = _make_half(_left_home)
	_right = _make_half(_right_home)
	_left_flash = _make_flash(_left)
	_right_flash = _make_flash(_right)

## KEEP_ASPECT_COVERED crops the 3:4 portrait to the 576x648 half -- faces
## stay centred, headroom is what gets cropped.
func _make_half(home: Vector2) -> TextureRect:
	var half := TextureRect.new()
	half.position = home
	half.size = HALF_SIZE
	half.clip_contents = true
	half.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	half.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(half)
	return half

## The hit flash is a child of its portrait so slams and shakes carry it.
func _make_flash(parent: TextureRect) -> ColorRect:
	var flash := ColorRect.new()
	flash.size = HALF_SIZE
	flash.color = Color(Juice.PORTRAIT_FLASH_COLOR, 0.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(flash)
	return flash

func set_portraits(player_id: StringName, enemy_id: StringName) -> void:
	debug_portrait_ids = [player_id, enemy_id]
	_left.texture = CardArt.portrait_for(player_id)
	_right.texture = CardArt.portrait_for(enemy_id)

## Both halves fly in from offscreen and collide at the centre seam.
## on_impact fires at contact (the view hooks screenshake/hit-stop there);
## on_settled fires once the recoil resettles (the view starts the battle
## there, so the hand deals only after the stage is at rest). Detached
## (tests), snaps to home and fires both synchronously -- the decision is
## recorded either way.
func slam_in(on_impact: Callable, on_settled: Callable) -> void:
	debug_slam_count += 1
	_left.position = _left_home + Vector2(-HALF_SIZE.x, 0.0)
	_right.position = _right_home + Vector2(HALF_SIZE.x, 0.0)
	if not is_inside_tree():
		_left.position = _left_home
		_right.position = _right_home
		on_impact.call()
		on_settled.call()
		return
	if _slam_tween != null and _slam_tween.is_valid():
		_slam_tween.kill()
	_slam_tween = create_tween()
	_slam_tween.set_parallel(true)
	_slam_tween.tween_property(_left, "position", _left_home, Juice.SLAM_TIME) \
		.set_trans(Juice.SLAM_TRANS).set_ease(Tween.EASE_IN)
	_slam_tween.tween_property(_right, "position", _right_home, Juice.SLAM_TIME) \
		.set_trans(Juice.SLAM_TRANS).set_ease(Tween.EASE_IN)
	_slam_tween.set_parallel(false)
	_slam_tween.tween_callback(on_impact)
	_slam_tween.tween_property(_left, "position",
		_left_home + Vector2(-Juice.SLAM_RECOIL_PX, 0.0), Juice.SLAM_RECOIL_TIME)
	_slam_tween.parallel().tween_property(_right, "position",
		_right_home + Vector2(Juice.SLAM_RECOIL_PX, 0.0), Juice.SLAM_RECOIL_TIME)
	_slam_tween.tween_property(_left, "position", _left_home, Juice.SLAM_RECOIL_TIME)
	_slam_tween.parallel().tween_property(_right, "position", _right_home, Juice.SLAM_RECOIL_TIME)
	_slam_tween.tween_callback(on_settled)

func flash_hit(side: StringName) -> void:
	var half: TextureRect = _half_for(side)
	if half == null:
		return
	debug_last_hit_side = side
	if not is_inside_tree():
		return
	var flash: ColorRect = _left_flash if half == _left else _right_flash
	var old: Tween = _flash_tweens.get(side)
	if old != null and old.is_valid():
		old.kill()
	var tween := create_tween()
	tween.tween_property(flash, "color", Juice.PORTRAIT_FLASH_COLOR,
		Juice.PORTRAIT_FLASH_TIME * 0.35)
	tween.tween_property(flash, "color", Color(Juice.PORTRAIT_FLASH_COLOR, 0.0),
		Juice.PORTRAIT_FLASH_TIME)
	_flash_tweens[side] = tween

func shake(side: StringName, amplitude: float) -> void:
	var half: TextureRect = _half_for(side)
	if half == null:
		return
	debug_last_hit_side = side
	if not is_inside_tree():
		return
	var home: Vector2 = _left_home if half == _left else _right_home
	var old: Tween = _shake_tweens.get(side)
	if old != null and old.is_valid():
		old.kill()
		half.position = home
	var step: float = Juice.PORTRAIT_SHAKE_TIME / float(Juice.PORTRAIT_SHAKE_STEPS + 1)
	var tween := create_tween()
	for i: int in range(Juice.PORTRAIT_SHAKE_STEPS):
		var direction: float = -1.0 if i % 2 == 0 else 1.0
		tween.tween_property(half, "position", home + Vector2(direction * amplitude, 0.0), step)
	tween.tween_property(half, "position", home, step)
	_shake_tweens[side] = tween

func player_centre() -> Vector2:
	return _left_home + HALF_SIZE / 2.0

func enemy_centre() -> Vector2:
	return _right_home + HALF_SIZE / 2.0

func debug_portrait_positions() -> Array:
	return [_left.position, _right.position]

func _half_for(side: StringName) -> TextureRect:
	if side == &"player":
		return _left
	if side == &"enemy":
		return _right
	return null
