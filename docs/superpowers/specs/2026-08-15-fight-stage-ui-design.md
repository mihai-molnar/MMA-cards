# Fight stage UI — design

Date: 2026-08-15
Status: approved (design conversation), pending implementation
Depends on: the opponent-roster/run feature (spec
`2026-08-15-opponent-roster-and-run-design.md`, in flight on branch
`worktree-opponent-roster-run`). Implementation starts only after that
branch lands — both features touch `battle_hud.gd` / `battle_view.gd`.

## Problem

The fight screen still reads as a debug build: flat colour background,
fighters as coloured rectangles, plain text readouts. New pixel-art assets
exist (arena background, three fighter portraits, HP/AP icon frames) and
the screen should look like a fighting game: the two portraits ARE the
scene, with readouts drawn over them.

## Decisions made in brainstorming

- **Layout: top corners** (user-selected). HP hearts in the top outer
  corners, AP bolt under the player's heart (player only — the enemy has
  no AP), intent line top-right under the enemy's heart, turn counter
  top-centre. The bottom band (card fan, END TURN, draw/discard counts)
  keeps its current geometry.
- **The slam plays at EVERY fight start** (user-selected): fight 1 on
  launch, fight 2 after CONTINUE on the interstitial banner, and again
  after RESTART. Sequence: BG visible -> portraits slam in from offscreen
  and collide at the centre seam (screenshake on impact, like two metal
  plates) -> readouts appear -> the hand deals. The portraits then STAY as
  the permanent 50/50 background for the whole fight.
- **Architecture: new `FightStage` layer + slimmed `FighterPanel`**
  (user approved the recommendation; see below).
- **Typography:** Kreon (already bundled, used by the cards) everywhere on
  the HUD; white fill with black outline (Godot `outline_size` +
  `font_outline_color`) for everything drawn over portraits: HP/AP
  numbers, turn counter, intent, draw/discard counts. User explicitly
  endorsed white-with-black-border for the intent line.
- **No permanent fighter-name labels.** Portraits identify the fighters;
  the FIGHT N banner does the announcing.

## Assets

Delivered loose in `assets/`; move them to convention-keyed homes:

| Delivered | New home | Convention |
|---|---|---|
| `BG.png` (1086x1448, empty octagon) | `assets/backgrounds/octagon.png` | scene backgrounds |
| `portrait_player.png` | `assets/portraits/player.png` | portraits keyed by fighter id |
| `portrait_enemy_1.png` (mohawk) | `assets/portraits/brawler.png` | opponent id = filename |
| `portrait_enemy_2.png` (moustache) | `assets/portraits/kickboxer.png` | opponent id = filename |
| `icon_HP.png` (1254x1254 heart frame) | `assets/ui/hp.png` | HUD chrome |
| `icon_AP.png` (1254x1254 bolt frame) | `assets/ui/ap.png` | HUD chrome |

- `assets/icons/` stays reserved for STATUS icons keyed by status id — the
  HP/AP icons are HUD chrome, not statuses, hence `assets/ui/`.
- Portrait lookup mirrors the card-illustration convention: a
  `portrait_for(id: StringName)` lookup (CardArt-style, cache keyed by
  resolved path) so opponent 3 is one more file, zero code. Missing
  portrait = legitimate degradation (dark half + readouts still works),
  not an error.
- **Imports need mipmaps** (`mipmaps/generate=true`), same as card frames:
  BG and portraits draw at roughly 0.5x, the icons far smaller; without
  mipmaps they shimmer. The project's Linear-Mipmap canvas filter setting
  already samples them.
- Portraits are 3:4 (1086x1448); each half-screen is 576x648 (~0.89:1).
  Portraits scale-to-cover and crop top/bottom, horizontally centred.
  Player portrait faces right, both enemies face left, so the pair
  naturally face off across the seam.

## Architecture

Three units, one new, two reworked:

### `FightStage` (new, `scripts/ui/fight_stage.gd`)

The scenery layer, first child of the HUD (behind everything). Owns:

- The BG texture (fills the design space).
- Two half-screen portrait `TextureRect`s (left = player, right = enemy),
  scale-to-cover cropped.
- `set_portraits(player_id: StringName, enemy_id: StringName)` — resolves
  via the portrait lookup; called per fight (fight 2 swaps the enemy).
- `slam_in(on_impact: Callable, on_settled: Callable)` — animates both
  portraits from offscreen (player from left, enemy from right) to the
  centre seam. `on_impact` fires at the collision frame (BattleView hooks
  screenshake + hit-stop there); `on_settled` fires when the stage is at
  rest (BattleView deals the hand then). Follows the house animation
  rules: single tween slot per animated node, `is_inside_tree()` guard
  with decisions recorded before the guard, home values stored not
  accumulated.
- Portrait hit feedback: `flash_hit(side)` / `shake(side, amplitude)` —
  a brief damage-red flash overlay and a positional shake on one half.
  Returns to STORED home values, never accumulates.

### `FighterPanel` (reworked)

Keeps its brain, changes its face. Unchanged: the hp/guard diffing, pulse
decisions, `suppress_next_guard_pulse()`, and the `debug_last_pulse_*`
test hooks — all the timing subtleties survive verbatim. The visual output
becomes:

- The HP heart icon with `<hp> / <max>` centred in its dark window, Kreon
  white/black-outline. **Overflow rule (user-specified): if the string is
  wider than the window, anchor it at the icon's horizontal centre and let
  it grow rightward** instead of centring.
- The AP bolt icon with `<ap> / <max>` inside, same rules — built by the
  panel but only instantiated for the player side.
- Guard readout: a blue-tinted outlined `+<guard>` under the heart, only
  visible while guard > 0 (no guard icon asset exists; text stays legible).
- Status badges: the existing icon+number row, repositioned under the
  heart (below guard). Text-line fallback for iconless statuses survives.
- Damage/heal number pulses float from the heart icon.
- The flat `ColorRect` rectangle, fighter name label, and panel background
  are DELETED. The panel's rect-shake becomes an icon-cluster shake, and
  the panel reports its pulse (existing hooks) so BattleView can drive
  `FightStage.flash_hit/shake` for the portrait side plus `ScreenFx` as
  today.

### `BattleHud` / `BattleView` wiring

- `BattleHud` builds `FightStage` first (bottom of z-order), then panels
  at the top-corner anchors, turn label top-centre, intent top-right under
  the enemy heart — all Kreon white/black-outline. The flat background
  `ColorRect` is replaced by the stage. Draw/discard labels restyle
  (outline) but keep their corners. END TURN button unchanged.
- `BattleView._start_fight()` (from the roster feature) gains the stage
  sequence: `stage.set_portraits(...)` -> `slam_in` -> on impact:
  screenshake/hit-stop via `ScreenFx` -> on settled: `battle.start()`.
  The hand therefore deals only after the collision settles. RESTART and
  CONTINUE both route through `_start_fight()`, so the slam replays
  automatically. Model state is never gated on animation — only
  `battle.start()` is deferred, and input is inert until the hand exists.
- Per-side hit routing: the hud exposes which panel pulsed (extending the
  existing `last_damage_amount()` with a side) so the view can flash the
  correct portrait.

## Game feel

Every new duration/curve/magnitude lives in `Juice`: slam duration, slam
overshoot/settle, collision screenshake amplitude and hit-stop, portrait
flash colour/time, readout fade-in delay. Tuned by eye against captures,
per house rules.

## Testing and verification

- Headless suites cover the logic: panel diff decisions unchanged
  (existing suites keep passing), overflow-rule branch (centre vs
  centre-anchored-right) as a pure decision, portrait lookup path
  resolution and cache keying, stage API decision-recording before
  `is_inside_tree()` guards.
- **Layout and motion cannot be trusted to tests** (house lesson): verify
  from renders — a capture tool for the composed fight screen (static) and
  `capture_frames` contact sheets for the slam (non-headless, real-time
  paced). The slam's frames must show motion, overshoot, and settle — not
  identical frames.
- Mipmap `.import` flags checked in like the card frames'.

## Out of scope

Sound (the slam begs for it — still deferred with the rest of audio),
round-intro text ("FIGHT!"), portrait damage states, map screen.
