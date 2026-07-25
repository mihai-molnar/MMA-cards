# UI Polish Pass — Design

**Date:** 2026-07-25
**Status:** Approved for planning
**Engine:** Godot 4.5.1 (GDScript, typed)
**Predecessor:** `2026-07-25-mma-cards-poc-design.md` (combat POC, complete)

## Goal

Make the finished combat POC feel like a game rather than a debug view: a fanned
hand that responds to the cursor, card plays that read as offence or defence, hits
that land visibly, and fighters facing each other across the screen.

Cosmetic only. **No file under `scripts/core/` changes.** All 244 existing checks
must continue to pass.

## Scope

**In:** arched hand layout, card hover, directional play animation, damage/guard
feedback on both fighters, left/right fighter layout, End Turn moved bottom-right,
and extraction of the duplicated fighter display into one reusable component.

**Out:** sprites, sound, card art, screen shake, particle effects, turn-transition
animations, enemy attack animation, deck/discard pile visuals.

## Layout

Design space stays **1152×648**, so the existing `canvas_items` window scaling
keeps working untouched.

```
 TURN 3                                      INTENT: ATTACK 12
  ┌────────┐                                      ┌────────┐
  │ PLAYER │                                      │ ENEMY  │
  │ (blue) │                                      │ (red)  │
  └────────┘                                      └────────┘
  PLAYER 42/50                                  ENEMY 26/48
  GUARD 5                                            STR 2

        -- Turn 3 --
        Player deals 16 damage

  draw 4  discard 6                              AP 1 / 3
                    ___  ___  ___             ┌──────────┐
               ___ /   \/   \ ___             │ END TURN │
              /                  \            └──────────┘
```

Each fighter's numbers sit beneath its own rectangle, so HP is read where the eye
already is. Intent stays top-right above the enemy, so the threat reads as coming
from them.

| Element | Position (design space) |
|---|---|
| Turn label | `(24, 20)`, 20px |
| Intent label | `(820, 20)`, 20px |
| Player panel | origin `(60, 90)`, size `(260, 260)`, left-aligned |
| Enemy panel | origin `(832, 90)`, size `(260, 260)`, right-aligned |
| Log label | `(430, 300)`, 14px |
| Pile label | `(24, 560)`, 14px |
| AP label | `(900, 470)`, 24px |
| End Turn button | `(900, 520)`, size `(180, 48)` |
| Result banner | `(430, 170)`, 48px |
| Restart button | `(470, 245)`, size `(180, 48)` |

Hand cards span x≈316–836 (derived below), clearing the End Turn button at x=900.

## Components

One new file, three rewrites, one wiring change. Nothing under `scripts/core/`.

```
scripts/ui/
  fighter_panel.gd   NEW  — one fighter's rect + name + HP + statuses, and all
                            damage/guard feedback. Instantiated twice, mirrored.
  battle_hud.gd      REWRITE — new layout; delegates fighter display to two
                            FighterPanels, so the player/enemy duplication goes away
  hand_view.gd       REWRITE — Control (was HBoxContainer); arc layout, hover
                            routing, play animation hand-off
  card_view.gd       REWRITE — rest transform, hover state, lunge animation
  battle_view.gd     EDIT   — supply lunge anchors; existing signal wiring unchanged
```

### Why `FighterPanel` exists

`battle_hud.gd` currently hardcodes the player block and the enemy block as two
separate sets of labels. Both are being repositioned anyway, and the damage-pop
animation would otherwise need writing twice — two implementations that can drift.
One component used twice, mirrored by an `align_right: bool`, is strictly less code
and one place to fix.

## Arc layout

For card `i` of `n`, with `t` spanning −1 (leftmost) to +1 (rightmost):

```gdscript
t        = 0.0 if n == 1 else (2.0 * i / (n - 1)) - 1.0
rotation = deg_to_rad(t * MAX_FAN_ANGLE_DEG)
centre_x = HAND_CENTRE_X + t * spread          # spread = (n-1)/2 * CARD_STEP_X
y        = HAND_BASE_Y - (1.0 - t * t) * FAN_ARCH_HEIGHT
position = Vector2(centre_x - CARD_SIZE.x / 2.0, y)
pivot_offset = Vector2(CARD_SIZE.x / 2.0, CARD_SIZE.y)   # bottom-centre, like a real fan
z_index  = i                                    # later cards overlap earlier ones
```

Rotating about **bottom-centre** is what makes it read as a held fan rather than
cards pinwheeling about their middles.

`CARD_STEP_X` (100) is less than `CARD_SIZE.x` (120), so cards overlap by 20px.
Five cards therefore span 520px centred on 576 → x from 316 to 836.

A single card sits centred at 0° with no arch. An empty hand lays out nothing.

## Constants

All in `card_view.gd` / `hand_view.gd` / `fighter_panel.gd` as appropriate — these
are presentation values, so they do **not** belong in `BattleConfig`, which is for
game balance.

| Constant | Value |
|---|---|
| `MAX_FAN_ANGLE_DEG` | 12.0 |
| `FAN_ARCH_HEIGHT` | 20.0 |
| `CARD_STEP_X` | 100.0 |
| `HAND_CENTRE_X` | 576.0 |
| `HAND_BASE_Y` | 430.0 |
| `HOVER_LIFT` | 28.0 |
| `HOVER_SCALE` | 1.08 |
| `HOVER_TIME` | 0.12 |
| `BORDER_WIDTH` | 3.0 |
| `BORDER_COLOR` | `Color(0.05, 0.05, 0.07)` |
| `LUNGE_TIME` | 0.28 |
| `LUNGE_SCALE` | 1.15 |
| `LUNGE_Z` | 60 |
| `PUNCH_SCALE` | 1.35 |
| `PUNCH_TIME` | 0.18 |
| `FLOAT_RISE` | 30.0 |
| `FLOAT_TIME` | 0.6 |
| `SHAKE_TIME` | 0.2 |
| `SHAKE_STEPS` | 4 |
| `HOVER_Z` | 50 |
| `RESULT_PANEL_Z` | 100 |

`HAND_BASE_Y` moved from its original 470 to 430 during implementation, to
fix a bottom-clip bug (the fanned cards' lowest rotated corner overran the
648-tall design space). `BORDER_WIDTH`/`BORDER_COLOR` (card border, added so
overlapping same-coloured cards read as separate cards rather than fusing
into one shape) and `LUNGE_Z`/`SHAKE_STEPS` were added during implementation
and were missing from this table entirely.

**Hand-size ceiling:** the arc arithmetic's clearance of the End Turn button
(`right_edge = 636 + 50 × (n − 1)` against the button's left edge at x=900)
only holds for hand sizes **n ≤ 6** (14px of slack at n=6; n=7 overlaps the
button). `tests/suites/test_hand_arc.gd` asserts `BattleConfig.HAND_SIZE <= 6`
for exactly this reason -- raising it must trip that test rather than
silently letting a card eat End Turn's clicks.

## Hover

On `mouse_entered`: tween to lifted 28px, scale 1.08, **rotation 0** so the card
sits square-on and readable, and raise `z_index` to `HOVER_Z` (50) so it draws over
its neighbours. On `mouse_exited`: tween back to the stored resting transform and
restore `z_index` to the card's index.

**The result panel gets `z_index = 100`.** `z_index` lifts a node above later
siblings of its parent, so a hovered card at 50 inside `HandView` would otherwise
be able to draw over the game-over banner — reintroducing exactly the defect the
POC's final review caught (banner underneath a live-looking hand). On
`battle_over` the view also clears any active hover, so no card is left lifted
behind the banner.

Each card stores its resting position and rotation when the hand lays out
(`set_rest_transform`). Hover-out returns to exactly that, so repeated
hover in/out cannot drift — the same idempotence problem that bit
`set_combo_armed` during the POC.

**Unaffordable cards still lift.** You should be able to read a card you cannot
afford; it stays dimmed so it does not read as playable.

Hover is exposed as `apply_hover(value: bool)` separately from the mouse signals,
so tests can drive it without synthesising input events.

## Play animation

Attacks lunge toward the enemy panel; Block pulls back toward the player panel. The
card's direction encodes what it did.

The played card is **reparented out of `HandView`** into an overlay before
animating. This is load-bearing twice:

1. `hand_changed` fires immediately on play and rebuilds the hand, which would
   free an in-place child mid-tween.
2. It keeps `HandView`'s children exactly equal to the cards in hand, which the
   existing `test_card_view.gd` assertions depend on.

Direction comes from the two anchor points `BattleView` supplies once at build time
via `HandView.set_lunge_anchors(attack_anchor, defend_anchor)`, read from each
`FighterPanel.centre_point()`. A card with the `defense` tag lunges to the defend
anchor; anything else to the attack anchor.

The lunging card tweens position toward the anchor, scales to 1.15, fades to alpha
0 over `LUNGE_TIME`, then frees itself.

## Damage feedback

`fighters_changed` carries no payload, and changing `BattleState` for a cosmetic
feature would breach the layer boundary the POC established. Instead
`FighterPanel.update(fighter)` remembers the previous HP and guard and diffs them:

| Observed change | Reaction |
|---|---|
| HP decreased | HP text punches to 1.35 and flashes red; floating `-N` rises 30px and fades; rect shakes, amplitude `clampf(2.0 + amount / 3.0, 3.0, 10.0)` |
| HP unchanged, guard decreased | Guard badge punches and flashes (no shake, no floating number) |
| HP increased, or nothing changed | No animation |

The guard case matters: a fully-absorbed hit currently produces **no feedback at
all**, which is the single worst thing to leave silent — the player cannot tell
whether their Block worked.

HP increasing means `restart()`, which must not look like healing.

For testability the panel records `debug_last_pulse_kind` (`&"damage"`,
`&"guard"`, or `&"none"`) and `debug_last_pulse_amount`, set by the same diff that
triggers the animation.

## Testing

Tweens need real frames, so interpolation is not asserted. The tests cover the
**decisions and the maths**, which is where bugs live:

**Arc layout**
1. Five cards: x strictly increasing left to right.
2. Five cards: the centre card has the smallest y (sits highest).
3. Five cards: rotations symmetric — leftmost is the negation of rightmost.
4. Five cards: outermost rotation magnitude equals `MAX_FAN_ANGLE_DEG`.
5. One card: centred, rotation exactly 0, no arch.
6. Empty hand: no children, no error.
7. Every card's `pivot_offset` is bottom-centre.
8. Card x-span stays clear of the End Turn button's left edge (900).

**Hover**
9. `apply_hover(true)` raises the card (smaller y) and sets rotation to 0.
10. `apply_hover(false)` restores the exact resting position and rotation.
11. Hover in/out three times returns to the identical resting transform (no drift).
12. An unaffordable card still lifts on hover and remains `disabled`.

**Damage feedback**
13. HP 48→42 records `damage` with amount 6.
14. HP unchanged and guard 8→2 records `guard` with amount 6.
15. HP increasing (restart) records `none`.
16. Nothing changing records `none`.
17. Shake amplitude is clamped at both ends (amount 1 → 3.0; amount 60 → 10.0).

**Z-order regression guard**
18. A hovered card's `z_index` (50) is below the result panel's (100), so the
    game-over banner can never be drawn under a lifted card.

**Unchanged behaviour**
19. All 244 pre-existing checks still pass, including the existing
    `test_card_view.gd` assertions that `HandView`'s children are exactly the hand's
    cards and that unaffordable cards are disabled.

Then visual confirmation by screenshot, as with the POC: resting fan, a hovered
card, and a damage pulse.

## Decisions Made During Design

1. **Moderate fan (12°, 20px arch)** over subtle or pronounced — a visible fan
   where all five cards stay readable without hovering.
2. **Directional lunge** over a generic scale-punch — direction encodes offence vs
   defence for free.
3. **Punch + floating number + shake** together, with shake scaling by damage, so a
   16-damage combo feels different from a 6-damage jab.
4. **Info beside each fighter** over a shared centre column — HP is read where the
   fighter is.
5. **Guard-absorb feedback added** beyond the original request, because a fully
   blocked hit was otherwise silent.
6. **Presentation constants stay out of `BattleConfig`**, which is reserved for game
   balance.
