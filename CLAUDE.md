# mma-cards

Slay the Spire-inspired MMA card battler. Godot 4.5.1, typed GDScript.
Currently a single-battle proof of concept: 12-card deck, 3 AP per turn,
jab->straight combo, guard, strength, telegraphed enemy intent.

## Commands

The Godot binary path contains a space — always quote it.

Run the game:
```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Run the tests (headless, no window):
```bash
./tests/run_tests.sh
```
Exits 0 on pass, 1 on failure. Run this before every commit. Expected output
on a clean tree ends with `558 checks, 0 failures` / `PASS`.

**Never invoke `run_tests.gd` directly — it can report a false PASS.**
GDScript has no catchable exceptions, so a runtime error partway through a
suite (a typo'd call, a null deref) aborts that suite's body while the runner
still prints `PASS` and exits 0; the remaining assertions silently never ran.
Verified directly: injecting `t.this_method_does_not_exist_typo()` into a
suite and invoking `run_tests.gd` by itself printed `SCRIPT ERROR: Invalid
call...` followed by `217 checks, 0 failures` / `PASS`, exit code 0 — one
check quietly missing, reported as a clean pass. Running the *same* broken
suite through `tests/run_tests.sh` printed the identical PASS line, then
caught it anyway: `run_tests.sh: FAIL (engine error marker found in output
despite exit code 0)`, exit code 1. The wrapper is what makes the result
trustworthy: it fails on engine error markers (`SCRIPT ERROR`, `Parse Error`,
`Invalid call`) as well as on a non-zero exit code.

The wrapper also runs a **mandatory** `--import` first. Godot resolves
`class_name` globals through `.godot/global_script_class_cache.cfg`, which only
the editor or an explicit `--import` writes — and `.godot/` is gitignored.
Without it, suites referencing a newly added class die with
`Identifier "X" not declared in the current scope`. That is a missing import,
not a code bug.

Regenerate the card resources after changing card constants:
```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/generate_cards.gd
```
Deterministic: re-running it with unchanged `BattleConfig` values rewrites
`resources/cards/*.tres` byte-for-byte identical to what was already
committed (`git status` stays clean, MD5s unchanged). If a regen ever leaves
the tree dirty, something genuinely changed — check it in, don't ignore it.

## Architecture

Two layers, and the boundary is the point:

- `scripts/core/` — pure rules. `RefCounted`/`Resource` only. **Never** reference
  `Node`, `SceneTree`, or any scene-tree API here. If a change seems to need one,
  it belongs in `scripts/ui/`. This is what makes the rules testable headless.
  (Every file in `scripts/core/` currently extends `RefCounted` or `Resource` —
  confirmed by grepping every `extends`/`class_name` line in the directory.)
- `scripts/ui/` — rendering and input. Reads state, emits input, computes no rules.

`BattleState` is the only thing that mutates a battle. It emits signals; the view
subscribes. The view never writes to the model.

## How to extend

**Add a card:** author a `.tres` in `resources/cards/` directly, or add it to
`tools/generate_cards.gd` — write a `_make_*()` function that builds and
returns a `CardData`, call `_save()` on it from `_initialize()`, then re-run
the generator. If it belongs in the starting deck, add its id to
`BattleConfig.DECK_COMPOSITION`. A card is a cost, some tags, and a list of
`CardEffect`s. **Never** add a card enum or a branch to a play function — if you
find yourself editing `BattleState.play_card()` to support a card, the effect
system is being bypassed.

**Add an effect:** subclass `CardEffect` in `scripts/core/effects/`, override
`apply(source, target, context)` and `describe()`. The context dictionary carries
`bonus_damage` (the first `DamageEffect` consumes it), `results`, and `log`.

**Add a status:** create a script in `scripts/core/statuses/` defining `ID`,
`DISPLAY_NAME`, and **both** `modify_outgoing_damage(amount, stacks)` and
`modify_incoming_damage(amount, stacks)` as statics — pass-through if unused,
since `StatusRegistry` calls both unconditionally. Then add one line to
`StatusRegistry.DEFINITIONS`. The damage pipeline needs no changes.

**Add a combo:** construct another `ComboRule` in `BattleState._combo_rules`.
Rules match on card tags, so no card code changes.

**Change balance:** everything tunable is in `scripts/core/battle_config.gd`.
No magic numbers anywhere else. But the constants are not uniformly live:
- `JAB_COST`, `JAB_DAMAGE`, `STRAIGHT_COST`, `STRAIGHT_DAMAGE`, `BLOCK_COST`,
  `BLOCK_GUARD` are baked into `resources/cards/*.tres` by
  `tools/generate_cards.gd` at generation time. Editing one of these does
  **nothing** to the running game until you re-run the generator (see
  Commands above). `tests/suites/test_card_library.gd` asserts the loaded
  `.tres` values against these constants, so a forgotten regen now fails the
  suite instead of silently doing nothing.
- Every other constant (enemy behavior, combo ratio, strength scaling, AP,
  hand size, HP) is read directly at battle time and takes effect
  immediately — no regen step needed.

## Card art

Card faces are composed at runtime, not painted. `CardView` stacks six layers
— illustration, frame, then title, value, rules and cost text — and every
number on the card is read from `CardData`. Nothing is baked into an image, so
a balance change shows up on the card as soon as the `.tres` is regenerated.

Two lookups, both by convention, both in `scripts/ui/card_art.gd`:

- **Illustration**, per card id: a card with id `jab` uses
  `res://assets/illustrations/jab.png`.
- **Frame**, per variant: a card tagged `defense` gets
  `res://assets/frames/defense.png`, everything else `attack.png`.

That asymmetry is the point. Adding a card means authoring a `.tres` and
dropping in **one** illustration — the frame it wears already exists, chosen by
tag. A card with no illustration yet renders a complete, correct frame around
an empty window: a real degradation path, not a bug.

`CardArt`'s cache is keyed by resolved path rather than by id or variant name.
Keying by the bare name would collide the day someone adds a card with id
`attack` — its illustration and the attack frame would share a key and serve
each other's texture.

**Geometry and typography live in `scripts/ui/card_template.gd`**, as zones
normalized to 0-1 fractions of the card rect rather than pixels — `CARD_SIZE`
has changed once already, and normalized zones survive that without a
re-measure. Only two zones differ between the frames: the value badge (right of
the burst on attack, centred in the shield on defense) and the cost badge.

Two zone subtleties, both learned the hard way:

- **`WINDOW_ZONE` covers the frame's transparent art opening with bleed, it
  does not trace it.** The opening's edges are semi-transparent (ribbon drop
  shadow above, badge flanks below), so an illustration cut to the opening
  shows the background through those pixels as dark gaps between art and
  frame — that shipped once. Overshoot is free: the frame draws over the
  illustration. `_test_window_zone_covers_the_frame_opening` measures the
  opening from the PNGs and asserts containment.
- **`RULES_ZONE` is a wrapping box, not a text extent.** Lines are
  centre-aligned inside it, so the zone is wide and centred on the
  parchment's measured centre (x `.498`) even though the cost disc and
  corner ornament cut into the parchment's lower-right — what must clear
  the artwork is each rendered *line*, and the guards model exactly that:
  `_test_rules_lines_clear_both_cost_badges` (cheap, art-independent) and
  `_test_rules_lines_fit_the_painted_parchment` (samples the frame PNGs,
  the binding one) greedily wrap each library card's text at the zone's
  pixel width and assert per line. `_test_rules_zone_is_centred_on_the_
  parchment` pins the zone centre to the painted centre — an off-centre
  zone renders every centred line visibly left or right of the parchment's
  middle, which is exactly how it used to look.

The badge centres carry a deliberate `.007` downward nudge relative to the
icons' measured pixel centres: digits have no descender, so a Label centring
its full line box parks the glyph optically high in a circle or shield.
`RULES_SIZE` is `8`, chosen by rendering rather than arithmetic: nothing
about it can be derived from the zone's dimensions alone.

**Card-face layout cannot be verified by tests.** An assertion that
`_value_label.position` equals the template zone proves the code matches the
constants — and it is the constants that are the guess. Judge it from a
render:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . \
  --script res://tools/capture_cards.gd
```

writes `/tmp/card-faces.png` with a row of all three cards plus an
armed/un-armed Straight pair side by side (to judge the combo tint below), laid
out to fit the project's 1152x648 base canvas. No extra zoom row is needed: at
that canvas size, `window/stretch/mode="canvas_items"` over the 2560x1440
window already renders the capture at 2560/1152 = 2.222x, so a 200x300 card
lands as roughly 444x667 real pixels in the PNG. Run it **non-headless** —
`get_texture()` needs a rendering context. This is the static sibling of
"Verifying animation" below, and it has the same shape: green tests, wrong
picture.

A state indicator drawn on top of an element that already has that colour
needs measuring, not eyeballing. `set_combo_armed()` tints the frame with
`COMBO_ARMED_TINT = Color(1.30, 1.20, 0.88)` — a 30% overbright warm push — on
a frame that is already gold. An earlier version lerped toward gold instead;
it satisfied the `!= Color.WHITE` assertion but moved mean rendered gold luma
from 167.4 to 170.1, a 1.6% change that read as nothing at all in the capture.
The test passed either way — only the render told them apart.

Frame and illustration `.import` files must keep `mipmaps/generate=true`.
Cards draw at a 5x (frame) and 10x (illustration) downscale while swaying and
rotating; without mipmaps that shimmers rather than merely softening.
Generating them is only half the requirement: mipmaps are SAMPLED only
because `project.godot` sets
`rendering/textures/canvas_textures/default_texture_filter=2` (Linear
Mipmap). Godot's default canvas filter is plain Linear, which ignores
mipmaps entirely — the project shipped that way once, and every card face
rendered as pixelated shimmer despite correctly-imported mipmaps. Do not
remove that setting.

## Timing rules that are easy to get wrong

This asymmetry is deliberate and the easiest thing in the codebase to break
by "tidying":

- **Guard expires at its owner's turn START**, so it survives the opponent's
  turn. Expiring it at the owner's own turn end would make Block a dead card
  (it would never block anything).
- **Status timers decrement at their owner's turn END.** The enemy's 2-turn
  strength buff is therefore live during both the buff turn and the following
  attack, then expires — exactly one attack gets the bonus.
- **Combo requires strictly consecutive plays.** Any card in between breaks it.
  The bonus is `floori(sum_of_base_damage * 0.5)`, added to base damage before
  modifiers, and is consumed by the first `DamageEffect` so multi-hit cards
  cannot double-dip.

If these two expiry points are ever merged into "the same moment," the game
still runs and tests may still look plausible — check them explicitly.

## The presentation layer

Three rules govern `scripts/ui/`. Each of them has already been broken once,
and in every case the symptom was *silent wrongness*, not a crash — which is
why they are written down.

**1. A card's transform is composed, never assigned.** `CardView._process`
builds the live transform every frame from three layers:

```
position = target_position + idle_sway + cursor_tilt
rotation = target_rotation + idle_rotation + tilt_rotation
scale    = target_scale
```

**Tweens must target `target_position` / `target_rotation` / `target_scale`.**
A tween on `position` gets silently overwritten by `_process` on the next
frame — you get jitter, not a clean failure, and it is genuinely hard to
diagnose. `set_rest_transform` and the out-of-tree branches write the live
properties directly on purpose (there is no `_process` off-tree, and the tests
depend on it); those are the only legitimate exceptions.

**2. Every card animation goes through `CardView`'s single `_tween` slot.**
`_animate_to` (hover), `lunge_to` (play), `_on_button_down` (squash),
`spring_to` and `slide_from` all kill the existing `_tween` and claim it. That
mutual exclusion is the only thing preventing two tweens from driving the same
property at once. A tween created on a *different* node — say, `HandView`
animating a card — is invisible to that kill, and the two then fight; the
winner is decided by Godot's tween processing order. This is exactly how
hovering a card silently stopped lifting for 0.4s after every play. **If you
need the hand to move a card, add a method to `CardView`; never create a tween
for a card from outside it.**

**3. `create_tween()` on a node outside the scene tree pushes an engine error,
and `run_tests.sh` fails on engine error markers.** Tests build these nodes
detached, so every animation entry point needs an `is_inside_tree()` guard —
and any decision-recording must happen *before* the guard, or the tests can no
longer assert it.

## Game feel

**Every duration, curve and magnitude lives in `scripts/ui/juice.gd`.** Not in
`BattleConfig` (that is game balance), not scattered across UI files. Juice is
tuned by eye, so "that felt too slow" must be a one-line change in one known
place. Layout constants are separate and stay with their owner: card geometry
in `card_view.gd`, fan geometry in `hand_view.gd`, HUD positions in
`battle_hud.gd`.

`ScreenFx` owns two effects that fail *catastrophically* rather than
cosmetically, and both are written to be self-correcting. Do not simplify
either guard away:

- **Hit-stop lowers `Engine.time_scale`.** If it never restored, the game
  would be frozen forever. It is released by a timer created with
  `ignore_time_scale = true` (without that flag the timer is slowed by the very
  freeze it ends) *and* by a watchdog in `_process` measured against real time.
- **Shake offsets the `CanvasLayer`.** A stuck offset leaves the whole UI
  permanently crooked. Shake always tweens back to a **stored home value**,
  never by accumulating deltas, so overlapping shakes still land on home.

"Store a home value, never accumulate" is the house rule for anything that
animates away from a resting state and back. `FighterPanel._flash_rect` once
captured the *live* colour as its home, and the fighter rectangles bleached
permanently toward pink over a session.

**The model updates instantly; the fighters' VIEW of it lands with the
card.** `battle.play_card()` mutates state synchronously, but
`BattleView._on_fighters_changed` defers the whole `hud.update_fighters`
call (HP text, panel flash, damage number, rect shake, and the screen
impact read from the resulting diff) by `Juice.play_impact_delay()` — the
windup plus `LUNGE_IMPACT_RATIO` of the strike — so the hit registers as
the card reaches its target, not while it is still leaving the hand.
"Defer only the screen effects" was the shipped-and-wrong version: the
panels diff on update, so updating them immediately dropped the HP with
the card still in the fan. Enemy attacks have no card animation and land
immediately (`_pending_reaction_delay` stays 0). Hand affordability
dimming is deliberately NOT deferred — the AP is genuinely spent. The
result banner waits the same delay plus `RESULT_BEAT` for the same reason.

**`FighterPanel` derives damage feedback by diffing hp/guard itself**, so
`BattleState` needs no damage payload and `scripts/core/` stays presentation-
free. One subtlety: guard clearing at a turn start is indistinguishable from
guard absorbing a hit in such a diff, so `BattleView` calls
`suppress_next_guard_pulse()` at the three moments guard expires. Without it
the game tells the player their Block worked on the two-in-three enemy turns
that deal no damage.

## Verifying animation — tests cannot see motion

This is the most important lesson in the project.

`CardView._animate_to` once assigned `target_*` to its destination *before*
creating the tween meant to animate toward that destination. Every hover tween
interpolated from-final-to-final: a real timer producing zero motion. The card
teleported. **387 tests passed over it** — they built `CardView` detached
(taking the correct snap branch) and asserted the *target* value, which was
correct instantly.

It was found by capturing 12 consecutive frames and noticing they were
pixel-identical.

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . --script res://tools/capture_frames.gd
```

`tools/capture_frames.gd` tiles consecutive frames into one contact sheet so a
curve becomes inspectable — overshoot and settle versus a linear slide versus a
snap. **For anything whose value is motion, an assertion on the end state
proves nothing.** Capture frames, or sample the animated value across frames
and print the series.

Two practical notes: run it **non-headless** (`get_texture()` needs a rendering
context; `DisplayServer.window_get_size()` reports `(0,0)` headless), and pace
captures by **real elapsed time, not frame count** — this machine's display
runs at 100Hz, and a frame-count stride tuned at 60Hz cuts longer animations
off mid-flight.

## Layout geometry

The hovered card uses a big Slay-the-Spire zoom (`Juice.HOVER_SCALE = 1.35`)
and **deliberately overlaps the fighter panels while hovered** — it draws
above everything at `CardView.HOVER_Z` and the overlap lasts only as long as
the hover. Do not "fix" that overlap by shrinking the zoom; the zoom is the
readability mechanism for the rules text. Hovering also parts the neighbours
aside (`Juice.part_offset`, driven by `HandView._on_card_hover_changed`); the
part offset is a fourth additive compose layer on `CardView`, lerped per
frame like cursor tilt, and must never become a tween (see rule 2 above).

The hand is a fan: cards rotate up to ±12° about their **bottom-centre**.
Clearance against the HUD must therefore be measured against the **rotated
silhouette**, not the axis-aligned rect — the corner swings ~47px past the box
at the current card size, which is how a card came to overlap the End Turn
button while the test happily reported clearance. `HandView` exposes
row-aware helpers for this; use them rather than `rest_position.x + CARD_SIZE.x`.

`BattleConfig.HAND_SIZE` is capped by that clearance, and
`tests/suites/test_hand_arc.gd` asserts the ceiling so raising the hand size
trips a test instead of silently breaking a button. Two separate tests assert
clearance — a single-size case and a parameterised loop — and they have been
missed one at a time before; grep for both.

## Conventions

- Typed GDScript: explicit parameter and return types on every function.
- Every Button gets `focus_mode = Control.FOCUS_NONE`. The game is
  mouse-driven with no keyboard nav, and a clicked Button otherwise grabs
  focus and wears Godot's default white focus rectangle — `flat = true` hides
  the normal stylebox but NOT the focus one, which is how cards came to show
  a white border after every click. `test_card_view.gd` asserts this for the
  cards and both HUD buttons.
- `PascalCase` class names, `snake_case` members, leading `_` for private.
- Integer helpers: `mini()`, `maxi()`, `floori()` — not the float versions.
- UI text is ASCII. The default font renders no emoji or symbol glyphs, so use
  `ATTACK 12`, `BLOCK 8`, `BUFF +2 STR` (these are the actual literal strings
  `EnemyBrain.intent_text()` produces) — never a sword/shield/arrow icon.
- Commit Godot's `.uid` sidecars (`<name>.gd.uid`) — project assets, not build
  artifacts. Stage with `git add -A` so none are left untracked; a `.uid`
  tracked on one branch but untracked on another aborts a merge. This has
  happened twice during development.
- Tests are suites in `tests/suites/`, auto-discovered by the runner: any
  `test_*.gd` file there is picked up and run in sorted order. There is no
  registry to edit. Every suite starts with exactly this preamble:
  ```gdscript
  extends RefCounted

  const TestRunner := preload("res://tests/run_tests.gd")

  func run(t: TestRunner) -> void:
  ```
  The local `preload` const is only for `TestRunner`, so the runner's type
  resolves even before an import has run. Game classes are referenced by their
  global names — `--import` is what makes those resolve.
- A suite that fails to load is reported as a failure and exits 1, rather than
  silently passing with zero checks. Do not weaken that guard in
  `tests/run_tests.gd`; without it a mistyped suite path reads as green.

## Design docs

Three passes, each with a spec and a plan, in `docs/superpowers/`:

| Pass | Spec | Plan |
|---|---|---|
| Combat POC (rules) | `specs/2026-07-25-mma-cards-poc-design.md` | `plans/2026-07-25-mma-cards-poc.md` |
| UI polish (layout, hover, hit feedback) | `specs/2026-07-25-ui-polish-design.md` | `plans/2026-07-25-ui-polish.md` |
| Game feel (juice) | `specs/2026-07-25-juice-design.md` | `plans/2026-07-25-juice.md` |

The specs record *why* decisions were made, including several that look
arbitrary in the code — the guard/status expiry asymmetry, the strictly-
consecutive combo, the transform composition layer. Read the relevant one
before changing behaviour it covers.

Note the specs are historical: where a spec and the code disagree, the code
won during implementation and the spec was usually amended, but not always.
`CLAUDE.md` (this file) is the current truth.

## State of the project

Playable single battle, fully art-directed, 558 headless checks. What is
conspicuously still placeholder:

- **The fighters are flat coloured rectangles.** With painted cards on screen
  they are now the only unfinished-looking element. `FighterPanel` would take
  portrait art the same way `CardView` took card art.
- **No sound.** Deliberately deferred from the juice pass — it needs audio
  assets, and it is the single largest remaining contributor to game feel.
- **One battle, no run structure**, no deck-building, no card rewards.
