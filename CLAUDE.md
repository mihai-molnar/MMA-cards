# mma-cards

Slay the Spire-inspired MMA card battler. Godot 4.5.1, typed GDScript.
Currently a two-fight run: 14-card deck, 3 AP per turn, jab->straight combo,
guard, strength, telegraphed enemy intent, HP carried between fights. Fight
1 is the Brawler, fight 2 the harder Kickboxer (who mirrors Low Kick's Leg
Injury back at the player).

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
on a clean tree ends with `810 checks, 0 failures` / `PASS`.

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

Within `scripts/core/`, an opponent is data, not code: `OpponentData` is one
opponent (identity, hp, a fixed rotation of turns); `OpponentMove` is one
labelled action inside a turn, built from the same `CardEffect`s cards use,
so the enemy has no separate combat path. `OpponentLibrary` builds every
`OpponentData` in code from `BattleConfig` constants (the opponent analogue
of `CardLibrary`, minus the `.tres`/generator step — opponents have no art
or composed face to bake). `EnemyBrain` is now a pure rotation interpreter:
it steps through whatever `OpponentData` it is handed and contains no
per-opponent branching. `RunState` owns what persists across fights — HP
carry-over and position in the opponent sequence; `BattleState` stays
run-blind, `battle_over` means only "this fight ended," and `BattleView`
is what turns that into the next fight or a run-ending banner.

There are two seams left for a future map: `RunState.current_opponent()`
is today a linear walk of `BattleConfig.RUN_OPPONENTS`, the only place a
branching map would change how the next opponent is chosen; and
`BattleView`'s continue/restart handlers are the only place that decides
what happens between fights (the seam a real map screen would replace).

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
`DISPLAY_NAME`, `SHOW_TURNS` (which number display code prints beside it:
`true` for a countdown like Leg Injury's remaining turns, `false` for a
magnitude like strength stacks), a `description()` static (the hover
tooltip's body — derive its numbers from `BattleConfig`, never literals),
and **both** `modify_outgoing_damage(amount, stacks)` and
`modify_incoming_damage(amount, stacks)` as statics — pass-through if
unused, since `StatusRegistry` calls both unconditionally. Then add one
line to `StatusRegistry.DEFINITIONS`. The damage pipeline needs no changes.
Optionally drop an icon at `assets/icons/<status_id>.png` — FighterPanel
then shows it as an icon + number badge on the fighter's rect and drops the
status from its text line; without one, the text line carries it, which is
a complete fallback, not an error. `DISPLAY_NAME` doubles as the card-text
keyword: rules text naming it gets it coloured yellow and the hover tooltip
(`StatusTooltip`, driven by `BattleView`) explains it. A status applied by
a card with `extend_duration = true` on its `ApplyStatusEffect` ADDS
durations on re-application (each Low Kick keeps the leg hurt one turn
longer) instead of refreshing to the longer one.

**Add an opponent:** write a `_make_*()` in `OpponentLibrary` that builds an
`OpponentData` with its rotation of `OpponentMove`s, add its tunables to
`BattleConfig`, register its id in `OpponentLibrary.opponent()`, and append
the id to `BattleConfig.RUN_OPPONENTS`. **Never** add a branch to
`BattleState` for an opponent — an `OpponentMove` resolves through the same
`CardEffect`s a card does, so the enemy needs no combat path of its own.

**Add a combo:** construct another `ComboRule` in `BattleState._combo_rules`.
Rules match on card tags, so no card code changes. On the card face, write
the word "Combo" plus the trigger ("Combo right after Jab.") — it renders
as a yellow keyword and the hover tooltip explains the mechanic from
`ComboRule.keyword_description()`; never print the bonus number on the
card, that is exactly the stale-number trap the keyword exists to avoid.

**Change balance:** everything tunable is in `scripts/core/battle_config.gd`.
No magic numbers anywhere else. But the constants are not uniformly live:
- `JAB_COST`, `JAB_DAMAGE`, `STRAIGHT_COST`, `STRAIGHT_DAMAGE`, `BLOCK_COST`,
  `BLOCK_GUARD` are baked into `resources/cards/*.tres` by
  `tools/generate_cards.gd` at generation time. Editing one of these does
  **nothing** to the running game until you re-run the generator (see
  Commands above). `tests/suites/test_card_library.gd` asserts the loaded
  `.tres` values against these constants, so a forgotten regen now fails the
  suite instead of silently doing nothing.
- Every other constant (combo ratio, strength scaling, AP, hand size, HP) is
  read directly at battle time and takes effect immediately — no regen step
  needed. That includes every `BRAWLER_*`, `KICKBOXER_*` and
  `RUN_OPPONENTS` constant: `OpponentLibrary` reads them straight from
  `BattleConfig` with no `.tres`/generator step of its own. The old
  `ENEMY_*` constants are gone — enemy behavior is per-opponent now, not
  a single shared enemy.

## Card art

Card faces are composed at runtime, not painted. `CardView` stacks six layers
— illustration, frame, then title, type, rules and cost text — and every
number on the card is read from `CardData`. Nothing is baked into an image, so
a balance change shows up on the card as soon as the `.tres` is regenerated.

**There is one frame design, in two colourways.** The master is
`assets/frames/card_master_template.png` (a dark octagon-cage MMA template,
padded from its delivered 1035x1519 to 1036x1554 so it is exactly the
card's 2:3), red-accented, worn by attack cards.
`card_master_template_defense.png` is the SAME template with the red
accents recoloured steel-blue, worn by defense cards — the hue split is
what lets a player sort attack from defense at fan distance without reading
anything. It is **generated, never authored**:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . \
  --script res://tools/generate_defense_frame.gd
```

recolours red-dominant pixels (feathered on `r - max(g, b)` so anti-aliased
trim edges don't halo) and is deterministic — same master in, byte-identical
PNG out. Generated rather than separately authored on purpose: a second
authored PNG would not be pixel-aligned with the master, and every
`CardTemplate` zone is shared between the two frames, which the recolour
guarantees by construction and the PNG-measuring template tests then
enforce on both frames. If defense ever gets its own design language
(different geometry, not just hue), replace the generated file at the same
path — those tests failing loudly is the signal that per-variant zones have
become a real requirement.

There is **no value badge** — the damage/guard number lives inside the
rules text, coloured (see below). The small **type plate** under the art
window prints `ATTACK` or `DEFENSE` from `CardTemplate.variant_for()` —
tag-driven: anything tagged `defense` is DEFENSE, everything else ATTACK.
The same variant picks the frame via `CardTemplate.frame_name()`.

Three lookups, all by convention, all in `scripts/ui/card_art.gd`:

- **Illustration**, per card id: a card with id `jab` uses
  `res://assets/illustrations/jab.png`.
- **Frame**, by name: `frame_for(CardTemplate.frame_name(variant))` — one
  texture per colourway.
- **Status icon**, per status id: `status_icon_for(&"leg_injury")` →
  `res://assets/icons/leg_injury.png`; null (a legitimate fallback) when no
  icon exists.

That asymmetry is the point. Adding a card means authoring a `.tres` and
dropping in **one** illustration — the frame it wears already exists. A card
with no illustration yet renders a complete, correct frame around an empty
window: a real degradation path, not a bug.

`CardArt`'s cache is keyed by resolved path rather than by bare name. Keying
by the bare name would collide the day someone adds a card whose id matches
the frame's name — its illustration and the frame would share a key and serve
each other's texture.

**Numbers and keywords in the rules text are coloured by
`CardTemplate.rules_bbcode()`**: damage numbers red (`RULES_DAMAGE_COLOR`),
guard numbers blue (`RULES_GUARD_COLOR`), keywords yellow
(`RULES_KEYWORD_COLOR`). The rules label is a `RichTextLabel` (Label cannot
render inline colour). Each number is coloured by the sentence it sits in —
"damage" goes red, "guard"/"block" blue, a sentence naming a status keeps
its numbers plain (a duration is not damage), and a sentence naming nothing
falls back to the card's variant. Keywords are every registered status's
`DISPLAY_NAME` plus `COMBO_KEYWORD` — the one game-rule keyword with no
status behind it, whose tooltip body is `ComboRule.keyword_description()`
(the ratio derived from `COMBO_BONUS_RATIO`, so a rebalance cannot strand a
stale number; the card itself prints no bonus number at all). Matching is
word-bounded and case-insensitive so STR never fires inside STRAIGHT. Any
card whose text names a keyword gets the `StatusTooltip` above it on hover.
The colour tags add no visible characters, so the wrap tests measure
`rules_plain()` and model what the label renders — with one qualification,
below, for live previews.

**Card faces preview live damage.** `rules_bbcode(card, source, target)`
takes two optional `Fighter`s; when both are given and the card has a sole
`DamageEffect`, the printed damage number is replaced by
`Combat.preview_damage()` — the same pipeline the telegraph and
`resolve_damage` use, so the face cannot diverge from what the hit will do.
A weakened number (Leg Injury halving your kicks) turns orange
(`RULES_WEAKENED_COLOR`); a buffed one stays red — a buff still reads as a
plain hit. `HandView.refresh_states()` calls
`CardView.update_rules_preview(battle.player, battle.enemy)` on every hand
card whenever `BattleView` refreshes (ap, fighters, hand changes), and
called with `null`s the output is byte-identical to the un-previewed
render — pinned by `test_card_preview.gd`. The qualification: a preview
*replaces* the number's text, so a previewed face can render text the
`rules_plain()` wrap tests do not model. Today previews only shrink
numbers (the player has no strength source); the day a source-side buff
can widen one ("9" → "11"), the painted-panel wrap tests stop covering
the previewed face and need a preview-aware case.

**Geometry and typography live in `scripts/ui/card_template.gd`**, as zones
normalized to 0-1 fractions of the card rect rather than pixels — `CARD_SIZE`
has changed once already, and normalized zones survive that without a
re-measure.

Two zone subtleties, both learned the hard way (on the previous two-frame
templates, and both still binding):

- **`WINDOW_ZONE` covers the frame's transparent art opening with bleed, it
  does not trace it.** The opening is an octagon with anti-aliased cut
  corners, so an illustration cut to the opening's bbox shows the background
  through the semi-transparent edge pixels as dark gaps between art and
  frame — that shipped once. Overshoot is free: the frame draws over the
  illustration. `_test_window_zone_covers_the_frame_opening` measures the
  opening from the PNG and asserts containment.
- **`RULES_ZONE` is a wrapping box, not a text extent.** Lines are
  centre-aligned inside it, so the zone is wide and centred on the rules
  panel's measured centre (x `.498`) — what must sit on the painted panel
  is each rendered *line*, and `_test_rules_lines_fit_the_painted_panel`
  models exactly that: it greedily wraps each library card's plain text at
  the zone's pixel width and asserts per line against the painted pixels.
  `_test_rules_zone_is_centred_on_the_panel` pins the zone centre to the
  painted centre — an off-centre zone renders every centred line visibly
  left or right of the panel's middle.

**The title is an `ArcTitleLabel`** (`scripts/ui/arc_title_label.gd`), not a
flat Label: the banner is a shallow arch — midline highest mid-span
(y `.088`), sagging toward both ends — so `TITLE_ZONE` is centred on the
apex and each glyph is offset down a parabola (`TITLE_ARC_BOW`, the measured
sag at the zone edge as a fraction of zone width). Glyphs stay upright; at
this bow the tangent rotation would move nothing visibly. A flat title
across the arch read as pasted on — flagged from an in-game screenshot.

`COST_CENTRE` and `TYPE_ZONE` carry a deliberate `.005`-`.007` downward
nudge relative to their icons' measured pixel centres: caps and digits have
no descender, so a Label centring its full line box parks the glyph
optically high in the icon.
`RULES_SIZE` is `11`, chosen by rendering rather than arithmetic: `10` read
lost in the master template's tall panel. Nothing about it can be derived
from the zone's dimensions alone.

**Card-face layout cannot be verified by tests.** An assertion that
`_type_label.position` equals the template zone proves the code matches the
constants — and it is the constants that are the guess. Judge it from a
render:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . \
  --script res://tools/capture_cards.gd
```

writes `/tmp/card-faces.png` with a row of all four library cards plus an
armed/un-armed Straight pair on a second row beneath (to judge the combo
tint below), laid out to fit the project's 1152x648 base canvas. No extra zoom row is needed: at
that canvas size, `window/stretch/mode="canvas_items"` over the 2560x1440
window already renders the capture at 2560/1152 = 2.222x, so a 200x300 card
lands as roughly 444x667 real pixels in the PNG. Run it **non-headless** —
`get_texture()` needs a rendering context. This is the static sibling of
"Verifying animation" below, and it has the same shape: green tests, wrong
picture.

A state indicator drawn on top of an element needs measuring, not
eyeballing. `set_combo_armed()` tints the frame with
`COMBO_ARMED_TINT = Color(1.30, 1.20, 0.88)` — a 30% overbright warm push.
On the old gold frame an earlier version lerped toward gold instead; it
satisfied the `!= Color.WHITE` assertion but moved mean rendered gold luma
from 167.4 to 170.1, a 1.6% change that read as nothing at all in the
capture. The test passed either way — only the render told them apart. On
the master template the same overbright warm push turns the neutral steel
trim brass-gold — verified against the capture's armed/un-armed pair, it
reads even more clearly than it did on gold.

Frame, illustration, background, portrait and ui-icon `.import` files must
keep `mipmaps/generate=true`.
Cards draw at a 5x (frame) and 10x (illustration) downscale while swaying and
rotating, and the stage's portraits/BG/icons all draw well under native size;
without mipmaps that shimmers rather than merely softening.
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

**The fight stage.** `FightStage` (`scripts/ui/fight_stage.gd`) is the HUD's
bottom layer and owns all scenery: the octagon background, the two
half-screen fighter portraits that ARE the scene, the fight-opening slam
(both halves collide at the centre seam; `BattleView` hooks screenshake at
`on_impact` and calls `battle.start()` only at `on_settled`, so the hand
deals after the stage is at rest — the model is never gated on animation
beyond that one deferred `start()`), and per-side hit feedback
(`flash_hit`/`shake`, routed by `BattleView` from
`BattleHud.last_damage_side()`). Portraits resolve by fighter id via
`CardArt.portrait_for` (`assets/portraits/<id>.png` — the player is
`player`, an opponent's id is its `OpponentData.id`, so a new opponent's
portrait is one file). HP/AP icon frames are HUD chrome in `assets/ui/`,
NOT `assets/icons/` (that directory stays reserved for status icons keyed
by status id). `FighterPanel` no longer draws a rectangle: its face is the
HP heart (value inside; centred until too wide, then anchored at the icon's
centre growing rightward), the player-only AP bolt, a blue `+n` guard
readout, and the status rows — while its hp/guard *diffing* brain, pulse
decisions and `suppress_next_guard_pulse()` machinery survive unchanged.
Every label drawn over the portraits is styled by `HudText.style` (Kreon,
white fill, black outline — the fighting-game legibility standard).

One Godot trap the stage taught: on a `TextureRect`, set `stretch_mode`/
`expand_mode` BEFORE `position`/`size`. `Control.set_size()` clamps against
`get_minimum_size()`, and the default `EXPAND_KEEP_SIZE` reports the source
PNG's own pixel size as that minimum — assigning `.size` first silently
snaps a 72px icon back to its native 1254px. The symptom is silent
wrongness in the render; no test can see it (see "Verifying animation").

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

**Sound.** `SoundFx` (`scripts/ui/sound_fx.gd`) is the audio sibling of
`ScreenFx`, owned by `BattleView`. Streams live in `assets/audio/` (a
directory separate from `assets/icons/`, which stays reserved for status
icons) and are registered by id in `SoundFx._STREAMS`: `punch` (three
variations, picked at random per hit so a flurry doesn't machine-gun),
`kick`, `card_fan` (fresh-hand deal only — a rebuild from playing a card
stays silent), `click` (End Turn / Continue / Restart), and `slam` (the
portrait clash at fight start). Per-sound gain and the hit pitch spread
live in `Juice` (`SFX_VOLUME_DB`, `SFX_PITCH_MIN/MAX`) with every other
feel magnitude. Which hit sound an attack warrants is a pure static —
`hit_sound_for_card` (kick tag → kick, other damage → punch, no damage →
silent) and `hit_sound_for_moves` (the enemy analogue, reading the coming
turn's move labels before `end_turn()` resolves them) — and `BattleView`
arms it in `_pending_hit_sound` exactly like `_pending_reaction_delay`,
*binding* it into the deferred fighter update so the punch is heard when
the hit visually lands and a racing later event cannot overwrite it. The
sound only fires when the panels actually record damage, the same
condition as hit-stop. `play()` records its decision (id and chosen
variant) *before* the `is_inside_tree()` guard, per rule 3, so
`test_sound_fx.gd` can assert it detached; an unknown id `push_error`s
loudly, which the test wrapper turns into a failed run. Adding a sound is:
drop a wav in `assets/audio/`, register it in `_STREAMS` and
`SFX_VOLUME_DB`, call `sound_fx.play(&"id")` from `BattleView`.

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
The enemy INTENT obeys the same rule: `play_card` re-telegraphs
synchronously (Low Kick halves the coming attack), and
`BattleView._on_intent_changed` defers that update by the same impact
delay, re-reading the current intent at fire time so a racing immediate
update can never be overwritten by stale in-flight text. Verified by
sampling the intent label against wall clock: the flip lands at ~the
impact delay, alongside the HP drop. When sampling such timings, let the
scene idle ~30 frames first — the startup hitch's inflated deltas skew any
timer created near boot, which reads as an early fire but is a
measurement artifact.

**`FighterPanel` derives damage feedback by diffing hp/guard itself**, so
`BattleState` needs no damage payload and `scripts/core/` stays presentation-
free. One subtlety: guard clearing at a turn start is indistinguishable from
guard absorbing a hit in such a diff, so `BattleView` calls
`suppress_next_guard_pulse()` at the moments guard expires. Without it the
game tells the player their Block worked on the enemy turns that deal no
damage. There is now a fourth suppression moment: the fight/run transition
in `BattleView` — `_on_continue_pressed` and `_on_restart_pressed` both
call `_suppress_transition_guard_pulses()`, so a fighter who ends a battle
still holding guard doesn't read the next fight's zeroed guard as an absorb.

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

Playable two-fight run (Brawler then Kickboxer, HP carried between fights),
fully art-directed down to the fight screen itself (portrait fight stage
with a slam intro, icon readouts, outlined HUD text), sound effects on
every battle beat (see "Sound" under Game feel), 810 headless checks.
What is conspicuously still placeholder:

- **No music, and the sound palette is minimal.** One click for all UI, no
  whiff/guard sound for Block, no result-banner stinger, no crowd bed.
- **No map, no deck-building, no card rewards.** The run is a fixed two-fight
  sequence; `RunState.current_opponent()` is the seam a branching map would
  replace.
