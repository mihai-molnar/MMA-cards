class_name Juice
extends RefCounted

## Every duration, curve and magnitude for game feel, in one place, plus the
## pure helpers that shape animation.
##
## Juice is tuned by eye, not derived — so the knobs live together. One file to
## edit and one place to look is what makes "that felt too slow" a one-line
## change instead of a hunt. These are presentation values and deliberately do
## NOT belong in BattleConfig, which is reserved for game balance.
##
## Statics only; never instantiated.

# --- Spring easing --------------------------------------------------------
## Overshoot-and-settle is the single biggest contributor to things feeling
## alive rather than slid into place.
const SPRING_TIME: float = 0.34
const SPRING_TRANS: Tween.TransitionType = Tween.TRANS_BACK
const SPRING_EASE: Tween.EaseType = Tween.EASE_OUT

# --- Hover ---------------------------------------------------------------
const HOVER_TIME: float = 0.16
const HOVER_LIFT: float = 34.0
const HOVER_SCALE: float = 1.12

# --- Squash and stretch --------------------------------------------------
const SQUASH_SCALE: Vector2 = Vector2(1.14, 0.86)
const SQUASH_TIME: float = 0.09
const STRETCH_SCALE: Vector2 = Vector2(0.88, 1.16)

# --- Anticipation and lunge ---------------------------------------------
## A short backswing away from the target before striking, so a punch has a
## windup instead of starting from rest.
const ANTICIPATE_DIST: float = 14.0
const ANTICIPATE_TIME: float = 0.07
const LUNGE_TIME: float = 0.24
const LUNGE_SCALE: float = 1.18

# --- Hit stop ------------------------------------------------------------
## Near-freezing the world for a moment is the cheapest way to make an impact
## read as landing rather than passing through.
const HITSTOP_TIME: float = 0.09
const HITSTOP_SCALE: float = 0.05

# --- Screen shake --------------------------------------------------------
const SHAKE_TIME: float = 0.28
const SHAKE_STEPS: int = 6
const SHAKE_BASE: float = 4.0
const SHAKE_PER_DAMAGE: float = 0.9
const SHAKE_MIN: float = 5.0
const SHAKE_MAX: float = 22.0

# --- Flash ---------------------------------------------------------------
const FLASH_TIME: float = 0.11
const FLASH_STRENGTH: float = 0.30

# --- Idle sway -----------------------------------------------------------
## Small on purpose: cards carry five lines of rules text, and a large wobble
## would blur it. Enough to feel alive, not enough to fight legibility.
const IDLE_SWAY_PX: float = 1.6
const IDLE_SWAY_DEG: float = 0.9
const IDLE_PERIOD: float = 2.6

# --- Cursor tilt ---------------------------------------------------------
const TILT_MAX_DEG: float = 7.0
const TILT_MAX_PX: float = 4.0
const TILT_LERP_SPEED: float = 12.0

# --- Staggered deal ------------------------------------------------------
const DEAL_STAGGER: float = 0.055
const DEAL_FROM_BELOW: float = 220.0

# --- Damage numbers ------------------------------------------------------
const NUMBER_TIME: float = 0.75
const NUMBER_RISE: float = 46.0
const NUMBER_ARC_X: float = 26.0
const NUMBER_SPIN_DEG: float = 26.0

# --- Particles -----------------------------------------------------------
const PARTICLES_HIT: int = 18
const PARTICLE_LIFETIME: float = 0.5
const PARTICLE_SPEED: float = 220.0
const PARTICLE_SIZE: float = 5.0

# --- Rect shake (per-fighter, smaller than the screen kick) -------------
const RECT_SHAKE_BASE: float = 2.0
const RECT_SHAKE_PER_DAMAGE: float = 3.0
const RECT_SHAKE_MIN: float = 3.0
const RECT_SHAKE_MAX: float = 10.0


## Composes a card's on-screen position from its three layers. Tweens drive
## `anim` as an ABSOLUTE value; idle sway and cursor tilt are additive on top.
## Pure and static so the layer most likely to break is the easiest to test.
static func compose_position(anim: Vector2, idle: Vector2, tilt: Vector2) -> Vector2:
	return anim + idle + tilt

static func compose_rotation(anim: float, idle: float, tilt: float) -> float:
	return anim + idle + tilt

## Sway offset for a card at `time`, with a per-card `phase` so the hand does
## not breathe in unison. The two axes use different periods so the motion
## traces a slow figure rather than a straight line.
static func idle_offset(time: float, phase: float) -> Vector2:
	var w: float = TAU / IDLE_PERIOD
	return Vector2(
		sin(time * w + phase) * IDLE_SWAY_PX,
		cos(time * w * 0.8 + phase) * IDLE_SWAY_PX)

static func idle_rotation(time: float, phase: float) -> float:
	var w: float = TAU / IDLE_PERIOD
	return deg_to_rad(sin(time * w * 0.6 + phase) * IDLE_SWAY_DEG)

## How far the whole view kicks for a hit of `amount` damage.
static func screen_shake_amplitude(amount: int) -> float:
	return clampf(SHAKE_BASE + amount * SHAKE_PER_DAMAGE, SHAKE_MIN, SHAKE_MAX)

## How far a single fighter's rectangle shakes. Smaller than the screen kick,
## and deliberately the same formula FighterPanel already shipped.
static func rect_shake_amplitude(amount: int) -> float:
	return clampf(RECT_SHAKE_BASE + amount / RECT_SHAKE_PER_DAMAGE,
		RECT_SHAKE_MIN, RECT_SHAKE_MAX)

## Applies the project's standard overshoot curve to a tween.
static func spring(tween: Tween) -> Tween:
	return tween.set_trans(SPRING_TRANS).set_ease(SPRING_EASE)
