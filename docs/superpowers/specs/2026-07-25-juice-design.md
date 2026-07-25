# Game Feel ("Juice") Pass — Design

**Date:** 2026-07-25
**Status:** Approved for planning
**Engine:** Godot 4.5.1 (GDScript, typed)
**Predecessors:** `2026-07-25-mma-cards-poc-design.md` (combat), `2026-07-25-ui-polish-design.md` (layout, hover, hit feedback)

## Goal

Make the game feel good to play: every click, hover and hit should land with weight.
Target reference is **Balatro** — maximum juice, everything alive, heavy overshoot,
constant subtle motion.

Presentation only. **No file under `scripts/core/` changes.** All 344 existing
checks must continue to pass.

## Scope

**In:** bigger window; easing/overshoot on every animation; squash & stretch;
anticipation windup; hit-stop; screen shake; hard flashes; cursor tilt; idle sway;
staggered card deal; tumbling damage numbers; impact and trail particles.

**Out:** sound (needs audio assets — explicitly deferred), card art, sprites,
camera zoom, chromatic aberration, post-processing shaders.

## Resolution

Window `1920×1080` → **`2560×1440`**. Design space stays `1152×648`, so
`canvas_items` stretch scales everything 2.22× instead of 1.67×. No layout work —
two values in `project.godot`. Both of the user's displays exceed 2560×1440.

## The architectural problem, and the fix

Today tweens write `position` and `rotation` directly. Balatro-style juice means a
card is **always** moving — idle sway, cursor tilt — *while* also being tweened by
hover, squash and lunge. Those conflict: the tween sets `position`, `_process`
overwrites it, and the result is jitter.

**Every card transform is therefore composed, once per frame, from three layers:**

| Layer | Driven by | Nature |
|---|---|---|
| `_anim_position` / `_anim_rotation` / `_anim_scale` | Tweens (hover, squash, lunge, deal) | **Absolute** target values |
| idle offset | `_process`, per-card phase | Additive |
| tilt offset | `_process`, cursor position | Additive |

```gdscript
position = _anim_position + idle_offset + tilt_offset
rotation = _anim_rotation + idle_rotation + tilt_rotation
scale    = _anim_scale
```

The `_anim_*` values are **absolute, not offsets** — that is what lets hover tween
`_anim_rotation` to exactly `0.0` to straighten a tilted card, while `rest_rotation`
remains the value it returns to. `set_rest_transform` updates `_anim_*` to the rest
values only when the card is not hovered.

**Tweens must never target `position`, `rotation` or `scale` directly.** They target
`_anim_*`. This is the single rule that keeps the three layers from fighting.

Composition is a **pure static function** in `juice.gd`, called from `_process`, so
it is directly testable without frames or a scene tree.

## New files

```
scripts/ui/
  juice.gd            Every duration, curve and magnitude, plus tween helpers
                      (spring_to, squash, punch) and the pure compose function.
                      THE tuning surface — juice is iterated, so it must be one file.
  screen_fx.gd        Screen shake, hit-stop, full-screen flash. Owns the
                      CanvasLayer offset so shake moves the whole view at once.
  particle_burst.gd   CPUParticles2D factory — coloured squares, no art assets.
                      Impact bursts and card trails.
```

Modified: `card_view.gd` (composition, squash, anticipation, tilt, idle),
`hand_view.gd` (staggered deal, tilt routing), `fighter_panel.gd` (tumbling numbers,
flash, impact burst), `battle_view.gd` (wire `ScreenFx`, trigger hit-stop and shake),
`project.godot` (window size).

`CPUParticles2D` is chosen over `GPUParticles2D` deliberately: it needs no
`ParticleProcessMaterial` to be built in code, and at this scale the GPU version
buys nothing.

## Two failure modes that would break the game outright

These get tests because the failure is catastrophic, not cosmetic.

**1. Hit-stop leaves the game frozen.** Hit-stop works by dropping
`Engine.time_scale`. If it never restores, the game is frozen forever.

- Restore via a timer created with `ignore_time_scale = true`, so it still fires
  while the world is slowed.
- Plus a watchdog: `ScreenFx._process` force-restores if a freeze has outlived its
  intended duration, measured against `Time.get_ticks_msec()` (real time, unaffected
  by `time_scale`).
- The unfreeze decision is a **pure function** of "now" so it can be tested without
  touching the global.

**2. Screen shake leaves the whole UI crooked.** Shake offsets the `CanvasLayer` —
which `BattleView` creates, so `ScreenFx` receives it by injection
(`bind_layer(layer: CanvasLayer)`) rather than reaching up the tree for it. A stuck
offset tilts everything permanently.

- Shake always tweens back to a stored home value, never by accumulating deltas, so
  it is self-correcting.
- Tested: after a shake completes, offset is exactly the home value.

## Techniques

Starting values only — all live in `juice.gd` and are expected to change during
tuning. They are listed so the plan has concrete code, not because they are final.

| Technique | Behaviour | Starting values |
|---|---|---|
| Spring easing | Every settle overshoots and returns | `TRANS_BACK`, `EASE_OUT`, 0.34s |
| Hover | Lift, scale up, straighten to 0°, idle pauses | 0.16s, `TRANS_BACK` |
| Squash | On press, card compresses | scale `(1.14, 0.86)`, 0.09s |
| Stretch | On launch, card elongates along travel | scale `(0.88, 1.16)` |
| Anticipation | Small backswing opposite the lunge before it fires | 14px, 0.07s |
| Lunge | Travel to the fighter, spin, fade | 0.24s |
| Hit-stop | World nearly freezes on impact | `time_scale` 0.05 for 0.09s |
| Screen shake | Whole view kicks, scaled to damage | `clampf(4 + dmg * 0.9, 5, 22)` px, 0.28s |
| Flash | Struck fighter's rect flashes white | 0.11s |
| Cursor tilt | **Hovered card only** leans toward the mouse | max 7°, lerped at 12/s |
| Idle sway | Every non-hovered card breathes, per-card phase | 1.6px, 0.9°, 2.6s period |
| Staggered deal | Cards fly up from below into their slots, one at a time | 0.055s apart, from +220px |
| Tumbling numbers | Damage numbers arc sideways and spin as they rise | 26px arc, 26° spin, 0.75s |
| Impact particles | Burst of coloured squares at the struck fighter | 18 particles |
| Card trail | Particles shed along a lunging card's path | continuous while lunging |

## Readability

Balatro can afford constant motion because its cards are mostly large glyphs. Ours
carry five lines of rules text, and constant motion under small text fights
legibility.

Two mitigations, both deliberate:

1. Idle amplitude stays small — 1.6px and 0.9°, enough to feel alive, not enough to
   blur text.
2. **Hovering pauses that card's idle sway entirely and straightens it.** The card
   being read is the one card holding still. Cursor tilt still applies, so it stays
   alive without wobbling.

If it still reads as noisy, `juice.gd` has one constant per effect to turn down.

## Validation

Still frames cannot show whether motion feels right, so the plan builds a
**contact-sheet tool**: capture ~12 frames across a single animation and tile them
into one PNG. That reveals the curve — overshoot and settle, versus linear slide,
versus wobbling too long — which is the only way to tune easing without feeling it.

It is not a substitute for playing the game. This pass ends with the user playing it
and reporting what is too much or too little; `juice.gd` is structured so that
feedback maps to single constants.

## Testing

**Tested** — real bugs live here:

1. Transform composition: given absolute anim values plus idle and tilt offsets, the
   composed position and rotation are correct.
2. Composition with zero idle and zero tilt equals the anim values exactly (so a
   still card sits precisely where layout put it).
3. Hovering zeroes the idle contribution (the readability guarantee).
4. Hit-stop's unfreeze decision returns false before the duration elapses and true
   after.
5. `Engine.time_scale` is exactly `1.0` after a freeze is force-restored, and the
   test leaves the global untouched.
6. Screen shake returns the offset to exactly its home value.
7. Shake amplitude is clamped at both ends, and scales monotonically between.
8. Staggered deal leaves every card's `_anim_position` equal to its `rest_position`
   once the sequence completes — the stagger must not misplace a card.
9. A particle burst is configured `one_shot` and frees itself when finished.
10. All 344 pre-existing checks still pass.

**Iterated by eye** — asserting these would be theatre: every duration, curve and
magnitude in the table above.

## Decisions Made During Design

1. **Balatro reference over Hades or Slay the Spire** — maximum juice, chosen
   explicitly.
2. **Sound out of scope** — the largest single contributor to game feel, but it needs
   audio assets. Deferred rather than faked.
3. **Bigger window, not a bigger design space** — everything scales up; no relayout.
4. **`_anim_*` values are absolute, not offsets**, so hover can straighten a tilted
   card to exactly 0° while `rest_rotation` remains its return value.
5. **Composition is a pure static function** so the layer most likely to break is
   the layer most easily tested.
6. **Cursor tilt applies only to the hovered card**, not the whole hand — cheaper,
   and keeps unread cards still.
7. **`CPUParticles2D` over `GPUParticles2D`** — configurable purely in code, no
   process material, sufficient at this scale.
8. **Hit-stop gets a watchdog** because the failure mode is a permanently frozen
   game, not a cosmetic glitch.
