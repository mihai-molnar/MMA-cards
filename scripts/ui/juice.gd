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
## Big Slay-the-Spire zoom: the hovered card is the one being READ, so it
## scales up until its rules text is comfortable. At 1.35 about the
## bottom-centre pivot its top reaches past the fighter panels -- accepted,
## it draws above them (CardView.HOVER_Z) and only while hovered. The old
## "hovered card never overlaps the panels" invariant (scale 1.12) is
## deliberately retired; see hand_view.gd's HAND_BASE_Y comment.
const HOVER_TIME: float = 0.16
const HOVER_LIFT: float = 40.0
const HOVER_SCALE: float = 1.35

# --- Squash and stretch --------------------------------------------------
const SQUASH_SCALE: Vector2 = Vector2(1.14, 0.86)
const SQUASH_TIME: float = 0.09
const STRETCH_SCALE: Vector2 = Vector2(0.88, 1.16)

# --- Anticipation and lunge ---------------------------------------------
## A short backswing away from the target before striking, so a punch has a
## windup instead of starting from rest.
const ANTICIPATE_DIST: float = 20.0
const ANTICIPATE_TIME: float = 0.12
const LUNGE_TIME: float = 0.45
const LUNGE_SCALE: float = 1.25
## Fraction of LUNGE_TIME the card stays fully opaque before it starts
## fading. Fading in parallel across the *whole* travel (the old behaviour)
## made the card half-transparent by the halfway point of its throw, which
## read as a flicker rather than a punch landing -- holding it solid for
## most of the trip keeps it legible right up until it strikes.
const LUNGE_FADE_RATIO: float = 0.6
## Fraction of the strike at which the blow LANDS: HP, panel feedback, hit
## stop, shake and flash all fire here, while the card is dissolving into
## the target -- not at 1.0, where the wait after the visual arrival reads
## as lag, and never at 0.0, which made every hit register while the card
## was still in the hand.
const LUNGE_IMPACT_RATIO: float = 0.85
## A beat between the killing blow landing and the result banner, so the
## impact reads before the screen changes subject.
const RESULT_BEAT: float = 0.30

# --- Hit stop ------------------------------------------------------------
## Near-freezing the world for a moment is the cheapest way to make an impact
## read as landing rather than passing through.
const HITSTOP_TIME: float = 0.09
const HITSTOP_SCALE: float = 0.05
## Damage-scaled freeze: a jab barely catches, a combo Straight visibly hangs.
## MIN doubles as the base of the ramp -- hit_stop_duration(0) == MIN.
const HITSTOP_MIN_TIME: float = 0.06
const HITSTOP_MAX_TIME: float = 0.16
const HITSTOP_PER_DAMAGE: float = 0.006

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

# --- Punch (scale-punch on HP text after damage) -------------------------
const PUNCH_SCALE: float = 1.35
const PUNCH_TIME: float = 0.18

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

# --- Hand parting on hover ------------------------------------------------
## Neighbours of the hovered card slide aside to make room, Slay the Spire
## style. PART_PX is what the immediate neighbour moves; further cards fall
## off by distance. Lerped per-frame like cursor tilt, never tweened, so it
## composes with the hover lift instead of fighting it in the _tween slot.
const PART_PX: float = 34.0
const PART_LERP_SPEED: float = 10.0

# --- Staggered deal ------------------------------------------------------
const DEAL_STAGGER: float = 0.055
const DEAL_FROM_BELOW: float = 220.0

# --- Re-fan on hand rebuild -----------------------------------------------
## When a played card leaves, the surviving cards slide from their old slots
## to their new, closed-up ones rather than snapping there (see
## CardView.slide_from and HandView.rebuild). REFAN_STAGGER stays small --
## unlike DEAL_STAGGER's full new-hand entrance, this is a small in-place
## resettle and a heavy stagger would read as sluggish rather than organic.
const REFAN_TIME: float = 0.36
const REFAN_STAGGER: float = 0.02

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


## Composes a card's on-screen position from its four layers. Tweens drive
## `anim` as an ABSOLUTE value; idle sway, cursor tilt and hand parting are
## additive on top. Pure and static so the layer most likely to break is the
## easiest to test.
static func compose_position(anim: Vector2, idle: Vector2, tilt: Vector2,
		part: Vector2 = Vector2.ZERO) -> Vector2:
	return anim + idle + tilt + part

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

## How long after a card is played its effects should visibly land: the
## windup plus the impact fraction of the strike.
static func play_impact_delay() -> float:
	return ANTICIPATE_TIME + LUNGE_TIME * LUNGE_IMPACT_RATIO

## How long the world freezes for a hit of `amount` damage.
static func hit_stop_duration(amount: int) -> float:
	return clampf(HITSTOP_MIN_TIME + amount * HITSTOP_PER_DAMAGE,
		HITSTOP_MIN_TIME, HITSTOP_MAX_TIME)

## Horizontal offset for the card at `index` while the card at `hovered` is
## hovered. Signed: right neighbours move right, left neighbours left, with a
## 1/distance falloff. `hovered` < 0 means no card is hovered.
static func part_offset(index: int, hovered: int) -> float:
	if hovered < 0 or index == hovered:
		return 0.0
	var distance: float = float(index - hovered)
	return signf(distance) * PART_PX / absf(distance)

## How far a single fighter's rectangle shakes. Smaller than the screen kick,
## and deliberately the same formula FighterPanel already shipped.
static func rect_shake_amplitude(amount: int) -> float:
	return clampf(RECT_SHAKE_BASE + amount / RECT_SHAKE_PER_DAMAGE,
		RECT_SHAKE_MIN, RECT_SHAKE_MAX)

# --- Portrait slam (fight start) ------------------------------------------
## Two metal plates colliding: a fast ease-IN travel (accelerating into the
## impact, not cushioning it), a hard screen kick at contact, then a small
## outward recoil that resettles. The recoil is what sells the mass.
const SLAM_TIME: float = 0.45
const SLAM_TRANS: Tween.TransitionType = Tween.TRANS_QUART
const SLAM_RECOIL_PX: float = 12.0
const SLAM_RECOIL_TIME: float = 0.16
const SLAM_SHAKE_AMPLITUDE: float = 18.0
const SLAM_HIT_STOP: float = 0.10

# --- Sound ----------------------------------------------------------------
## Impact sounds get a small random pitch spread so repeats read as fresh
## hits; UI sounds play at 1.0 (SoundFx._PITCH_VARIED picks which is which).
const SFX_PITCH_MIN: float = 0.94
const SFX_PITCH_MAX: float = 1.06
## Per-sound gain, tuned by ear like everything else here: hits carry the
## mix, the fan and clicks sit under them.
const SFX_VOLUME_DB: Dictionary = {
	&"punch": 0.0,
	&"kick": 0.0,
	&"card_fan": -6.0,
	&"click": -8.0,
	&"slam": 0.0,
}

# --- Portrait hit feedback ------------------------------------------------
const PORTRAIT_FLASH_TIME: float = 0.14
const PORTRAIT_FLASH_COLOR: Color = Color(1.0, 0.45, 0.45, 0.35)
const PORTRAIT_SHAKE_TIME: float = 0.22
const PORTRAIT_SHAKE_STEPS: int = 5
const PORTRAIT_SHAKE_BASE: float = 4.0
const PORTRAIT_SHAKE_PER_DAMAGE: float = 0.8
const PORTRAIT_SHAKE_MIN: float = 5.0
const PORTRAIT_SHAKE_MAX: float = 16.0

## Applies the project's standard overshoot curve to a tween.
static func spring(tween: Tween) -> Tween:
	return tween.set_trans(SPRING_TRANS).set_ease(SPRING_EASE)

## How far a struck portrait half kicks sideways. Between the rect shake
## (small) and the screen kick (large) -- the portrait is the fighter now.
static func portrait_shake_amplitude(amount: int) -> float:
	return clampf(PORTRAIT_SHAKE_BASE + amount * PORTRAIT_SHAKE_PER_DAMAGE,
		PORTRAIT_SHAKE_MIN, PORTRAIT_SHAKE_MAX)
