class_name ScreenFx
extends Node

## Whole-view effects: screen shake, hit stop, and a full-screen flash.
##
## Two of these break the game outright rather than merely looking wrong, so
## both are written to be self-correcting:
##
##   * hit stop lowers Engine.time_scale. If it never restored, the game would
##     be frozen forever. It is released by a timer created with
##     ignore_time_scale (or the timer itself would crawl), AND by a watchdog in
##     _process measured against real time.
##   * shake offsets the CanvasLayer. A stuck offset leaves the entire UI
##     crooked. Shake always tweens back to a stored home value, never by
##     accumulating deltas, so it cannot drift.

var _layer: CanvasLayer
var _layer_home: Vector2 = Vector2.ZERO
var _flash_rect: ColorRect
var _freeze_until_msec: int = -1

## The CanvasLayer has no rect to anchor against, so the flash overlay is
## parented to a Control instead.
func bind(layer: CanvasLayer, overlay_parent: Control) -> void:
	_layer = layer
	_layer_home = layer.offset

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Above every card and above the result banner.
	_flash_rect.z_index = 200
	overlay_parent.add_child(_flash_rect)

## True when a freeze deadline has arrived. Pure, so the watchdog's decision is
## testable without touching the global time scale.
static func should_unfreeze(now_msec: int, freeze_until_msec: int) -> bool:
	return freeze_until_msec >= 0 and now_msec >= freeze_until_msec

func is_frozen() -> bool:
	return _freeze_until_msec >= 0

func debug_layer_home() -> Vector2:
	return _layer_home

## Nearly stops the world for a moment, so an impact reads as landing.
func hit_stop(duration: float = Juice.HITSTOP_TIME) -> void:
	_freeze_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
	Engine.time_scale = Juice.HITSTOP_SCALE
	if not is_inside_tree():
		return
	# ignore_time_scale = true, or this timer would itself be slowed to a crawl
	# and the freeze would last ~20x longer than asked.
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(force_restore_time)

## Always safe to call, including when not frozen.
func force_restore_time() -> void:
	_freeze_until_msec = -1
	Engine.time_scale = 1.0

func _process(_delta: float) -> void:
	# Watchdog. Time.get_ticks_msec() is real time and unaffected by
	# time_scale, so this still fires while the world is slowed.
	if should_unfreeze(Time.get_ticks_msec(), _freeze_until_msec):
		force_restore_time()

## Kicks the whole view. Amplitude falls off across the shake so it settles
## rather than stopping dead.
func shake(amplitude: float) -> void:
	if _layer == null or not is_inside_tree():
		return
	var step_time: float = Juice.SHAKE_TIME / float(Juice.SHAKE_STEPS + 1)
	var tween := create_tween()
	for i: int in range(Juice.SHAKE_STEPS):
		var falloff: float = 1.0 - float(i) / float(Juice.SHAKE_STEPS)
		var kick := Vector2(
			randf_range(-amplitude, amplitude) * falloff,
			randf_range(-amplitude, amplitude) * falloff)
		tween.tween_property(_layer, "offset", _layer_home + kick, step_time)
	# Always land exactly on home, never on an accumulated delta.
	tween.tween_property(_layer, "offset", _layer_home, step_time)

func flash(strength: float = Juice.FLASH_STRENGTH) -> void:
	if _flash_rect == null or not is_inside_tree():
		return
	_flash_rect.color.a = strength
	var tween := create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, Juice.FLASH_TIME)
