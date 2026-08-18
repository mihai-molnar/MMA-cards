# mma-cards

Slay the Spire-inspired MMA card battler. Godot 4.5.1, typed GDScript.
Currently a two-fight run: 14-card starting deck (4 unique cards), 3 AP per
turn, jab->straight combo, guard, strength, telegraphed enemy intent, HP
carried between fights. Beating fight 1 opens a rewards screen offering 3
random cards drawn from a 6-card pool (One-Two, Strength Up, Prepared, High
Kick, Flying Knee, Elbow -- 10 unique cards in the library total) before
fight 2, so the deck the player fights with can grow past 14. Three of the
reward cards -- High Kick, Flying Knee, Elbow -- carry a percentage chance
to KO the opponent outright on a hit that lands past guard, ending the fight
on the spot; Elbow can also inflict Bleed, a damage-per-turn status that
pierces guard. Fight 1 is the Brawler, fight 2 the harder Kickboxer (who
mirrors Low Kick's Leg Injury back at the player). A backquote-toggled dev
menu (`scripts/ui/dev_menu.gd`) plays any library card instantly against the
enemy for testing -- see "The presentation layer".

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
on a clean tree ends with `1432 checks, 0 failures` / `PASS`.

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
`bonus_damage` (the first `DamageEffect` consumes it), `results`, `log`, and
`rng` (`BattleState`'s seeded per-battle `RandomNumberGenerator`, present on
every real play and `dev_play`; an effect that rolls against it and finds it
missing from the context should fail closed -- no rng means no roll, never a
free success). `KOChanceEffect` (`scripts/core/effects/ko_chance_effect.gd`)
is the precedent for a chance-based effect that can end the fight outright:
it rolls only when the card's preceding `DamageEffect` dealt hp damage
(reads `results.back()`), so a fully blocked strike never KOs, and writes
`context["ko_attempted"]`/`context["ko"]` rather than mutating the fighter or
`BattleState` itself -- `BattleState._resolve_play` reads those two keys
generically to fire `ko_scored`/`ko_failed` and set `won_by_ko`, so the KO
card needs no branch anywhere outside the effect. `ApplyStatusEffect.chance`
is the same roll-against-`rng` pattern applied to a status instead of the
fight's outcome (Elbow's `ELBOW_BLEED_CHANCE`).

**Add a status:** create a script in `scripts/core/statuses/` defining `ID`,
`DISPLAY_NAME`, `SHOW_TURNS` (which number display code prints beside it:
`true` for a countdown like Leg Injury's remaining turns, `false` for a
magnitude like strength stacks), a `description()` static (the hover
tooltip's body — derive its numbers from `BattleConfig`, never literals),
and **all three** `modify_outgoing_damage(amount, stacks)`,
`modify_incoming_damage(amount, stacks)` and
`on_turn_start(fighter, stacks) -> bool` as statics — pass-through
(`return amount` / `return false`) if unused, since `StatusRegistry` calls
all three unconditionally. `on_turn_start` fires at its owner's turn start,
right after that turn's guard expiry (see "Timing rules" below); returning
`true` consumes the status (removes it from the bag) instead of leaving it
to tick down normally — Prepared's delayed-guard payout is the only status
that does this today. Then add one line to `StatusRegistry.DEFINITIONS`.
The damage pipeline needs no changes.
Optionally drop an icon at `assets/icons/<status_id>.png` — the status's
chip in FighterPanel's status area (a bordered dark badge under the health
readout, one chip per active status, hover-tooltipped via
`StatusTooltip.show_for_status`) then shows the icon beside its number;
without one, the chip carries `DISPLAY_NAME` as text instead — a complete
fallback, not an error. The number beside either is registry-driven:
remaining turns when `SHOW_TURNS`, stacks otherwise. `DISPLAY_NAME`
doubles as the card-text keyword: rules text naming it gets it coloured yellow and the hover tooltip
(`StatusTooltip`, driven by `BattleView`) explains it. A status applied by
a card with `extend_duration = true` on its `ApplyStatusEffect` ADDS
durations on re-application (each Low Kick keeps the leg hurt one turn
longer) instead of refreshing to the longer one.

`BleedStatus` (`scripts/core/statuses/bleed.gd`) is the precedent for a
damage-over-time status: its `on_turn_start` calls `Fighter.apply_hp_loss`
directly -- not `Combat.resolve_damage` -- so the tick pierces guard and
skips every outgoing/incoming damage modifier (a cut does not care about
strength). It returns `false` (never self-consumes; it just ticks down
like Leg Injury) and uses `extend_duration = true` the same way Leg Injury
does, so a second Elbow keeps the cut open longer rather than deeper
(`stacks` stays 1 -- a fighter either bleeds or doesn't).

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
  `BLOCK_GUARD`, `ONE_TWO_COST`, `ONE_TWO_DAMAGE`, `STRENGTH_UP_COST`,
  `STRENGTH_UP_STACKS`, `PREPARED_COST`, `PREPARED_GUARD`, and the three KO
  cards' `HIGH_KICK_COST`/`HIGH_KICK_DAMAGE`/`HIGH_KICK_KO_CHANCE`,
  `FLYING_KNEE_COST`/`FLYING_KNEE_DAMAGE`/`FLYING_KNEE_KO_CHANCE`, and
  `ELBOW_COST`/`ELBOW_DAMAGE`/`ELBOW_KO_CHANCE`/`ELBOW_BLEED_CHANCE` are
  baked into `resources/cards/*.tres` by `tools/generate_cards.gd` at
  generation time. Editing one of these does **nothing** to the running
  game until you re-run the generator (see Commands above).
  `tests/suites/test_card_library.gd` asserts the loaded `.tres` values
  against these constants, so a forgotten regen now fails the suite instead
  of silently doing nothing.
- Every other constant (combo ratio, strength scaling, AP, hand size, HP) is
  read directly at battle time and takes effect immediately — no regen step
  needed. That includes every `BRAWLER_*`, `KICKBOXER_*` and
  `RUN_OPPONENTS` constant: `OpponentLibrary` reads them straight from
  `BattleConfig` with no `.tres`/generator step of its own. The old
  `ENEMY_*` constants are gone — enemy behavior is per-opponent now, not
  a single shared enemy. `PREPARED_STATUS_TURNS` (the status's lifecycle
  ceiling, not a balance knob — see its comment in `battle_config.gd`),
  `BLEED_DAMAGE_PER_TURN`/`BLEED_TURNS` (read by `BleedStatus`, not baked
  into any card -- the card only carries the *chance* to apply Bleed, which
  IS baked; how hard and how long Bleed hits once applied is live), and
  `REWARD_CARDS` (the rewards screen's pool, read by `RewardPool.options()`
  and now six entries -- see "The rewards screen") are all live-read too,
  same as `RUN_OPPONENTS`.

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
`DISPLAY_NAME` plus two game-rule keywords with no status behind them:
`COMBO_KEYWORD`, whose tooltip body is `ComboRule.keyword_description()`
(the ratio derived from `COMBO_BONUS_RATIO`, so a rebalance cannot strand a
stale number; the card itself prints no bonus number at all), and
`BURN_KEYWORD`, whose tooltip body is `Deck.burn_description()` (kept
beside the mechanic it describes, in core, like every other keyword body).
Matching is
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
`rules_plain()` wrap tests do not model. Now that Strength Up gives the
player a buff source, a previewed number CAN widen ("9" → "13"), and the
plain-text wrap tests no longer cover that face —
`_test_rules_lines_fit_with_buffed_previews`
(`tests/suites/test_card_template.gd`) is the preview-aware case: it wraps
each card's `rules_bbcode()` output (tags stripped) at the player pumped to
`BattleConfig.STRENGTH_UP_STACKS` — the maximum reachable in a fight
today, one Strength Up — and asserts it against the painted panel the same
way the plain-text test does. Raising the reachable stacks (a second
Strength Up copy, a bigger reward) must widen this test's assumption too.

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

`COST_CENTRE` carries a deliberate `.005`-`.007` downward nudge relative
to its icon's measured pixel centre: caps and digits have no descender, so
a Label centring its full line box parks the glyph optically high in the
icon. `TYPE_ZONE` once carried the same nudge but was tuned against a
MIS-measured plate centre (`.595`; the plate's interior actually spans
y `.564`-`.618`, centre `.591`), which parked the type text visibly LOW —
flagged from a rewards-screen screenshot, confirmed by a 4x crop. The zone
now centres on the re-measured `(.499, .592)` with the nudge shrunk to
~`.001`; if the plate is ever repainted, re-measure the interior, don't
re-apply the old nudge.
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

writes `/tmp/card-faces.png` with row one the four library cards plus a
fifth leg-injured preview of Jab, and row two the armed/un-armed Straight
pair (to judge the combo tint below, full scale) sharing its width with
the whole reward pool -- `BattleConfig.REWARD_CARDS`, six cards since the
KO pass, read live rather than hardcoded -- rendered smaller at
`REWARD_SCALE` (0.5) so all six fit beside the pair inside the project's
1152x648 base canvas (see the width arithmetic in
`tools/capture_cards.gd::_add_reward_strip`). No extra zoom row is needed
for row one or the combo pair: at that canvas size,
`window/stretch/mode="canvas_items"` over the 2560x1440 window already
renders the capture at 2560/1152 = 2.222x, so a 200x300 card lands as
roughly 444x667 real pixels in the PNG (the reward strip's smaller cards
scale down from that same baseline). Run it **non-headless** —
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
- **Turn-start status hooks fire right after that guard expiry**, before
  anything else in `_begin_player_turn`/`_run_enemy_turn`
  (`StatusRegistry.apply_turn_start`, called on both sides). This is what
  lets Prepared's delayed guard land on a clean slate: the old guard is
  already gone by the time the hook grants the new amount, so the payout
  never stacks on leftovers. A hook returning `true` (only Prepared today)
  is consumed exactly once — the status is removed the same turn it pays
  out, so the chip disappears rather than lingering at 0. Bleed's hook
  returns `false` (it just ticks down) but still fires here, which is why
  both `_begin_player_turn` and `_run_enemy_turn` check `_check_battle_over()`
  immediately after the turn-start hook, before drawing a hand or acting —
  a bleeding fighter can be finished by the tick itself, before they get to
  do anything on the turn that kills them.
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
portrait is one file). HP/AP icon frames, the draw/discard pile icons and
the End Turn button plates are HUD chrome in `assets/ui/`,
NOT `assets/icons/` (that directory holds the status icons keyed by status
id, plus one non-status resident: `guard.png`, the guard chip's icon).
`FighterPanel` no longer draws a rectangle: its face is the
HP heart (value inside; centred until too wide, then anchored at the icon's
centre growing rightward), the guard chip beneath it (the guard icon plus
the blue `+n`, blue-bordered, persistent — built once and toggled by
visibility, so a hover is never interrupted), and the status chip
area under that (dark bordered badges, one per active status — the chip
ground is what makes the icons read against the bright portraits). Chips
observe the mouse (`MOUSE_FILTER_STOP` on the chip, IGNORE everywhere
else in the panel) and emit `status_hovered(id, anchor, hovered)` — the
guard chip its own `guard_hovered(anchor, hovered)`, because guard is a
rule, not a registry status: its tooltip body is
`Fighter.guard_description()` (kept in core beside the rule, like every
status description) shown via `StatusTooltip.show_info`.
`BattleHud` forwards both panels' signals and `BattleView` answers with
`StatusTooltip.show_for_status` / `show_info`, hanging BELOW the chip —
above it would cover the hp readout it sits under. The guard number is
tinted via its theme `font_color`, NOT modulate — `_punch` tweens
modulate back to WHITE, which would bleach a modulate tint. A no-op update skips the chip
rebuild so a hovered chip is never freed under the cursor. The AP bolt is
no longer in the panel at all: it is HUD chrome at the bottom-left corner
(`BattleHud.AP_ICON_AT`, heart-sized so it reads at a glance, above the
draw-pile icon), and `test_hand_arc.gd` asserts the fan's rotated
silhouette clears it at both of the icon's rows. The pile counts render
centred INSIDE their icons (`cards.png` bottom-left, `discarded_cards.png`
above the End Turn button, right-aligned with it) — there are no "draw n"
/ "discard n" text labels any more, and both icon rects get the same
per-row silhouette clearance checks. A third icon, `BURNED_ICON_AT`, sits
left of the discard icon and is visible only while `battle.deck.burned_pile`
is non-empty (`update_fighters` toggles it and its count label together each
refresh) — it wears its own `burned_cards.png` art (which replaced the
ember-tinted discard-icon placeholder it shipped with). Its rect gets the
same rotated-silhouette clearance check as the other two. The End Turn button is a
`TextureButton` wearing the metal-plate art: normal texture at rest, the
recessed "clicked" variant while held (the swap is the press animation).
The plate carries no words, so hovering it emits
`BattleHud.end_turn_hovered` and `BattleView` answers with
`StatusTooltip.show_label("END TURN", ...)` above the button. The panel's hp/guard *diffing* brain, pulse
decisions and `suppress_next_guard_pulse()` machinery survive unchanged
(the guard-absorb punch now lands on the guard readout itself).
Every label drawn over the portraits is styled by `HudText.style` (Kreon,
white fill, black outline — the fighting-game legibility standard).

**The pile browser.** The draw/discard/burned icons are `TextureButton`s
(pointer cursor); clicking one emits `BattleHud.pile_clicked` with the
matching id (`&"draw"`, `&"discard"` or `&"burned"`) and `BattleView` opens
`PileView` (`scripts/ui/pile_view.gd`): a modal full-rect overlay -- the
dimmed octagon as backdrop, the pile's cards as real `CardView`s in a
centred grid, and the close-button art (normal + clicked variants, the
same native press swap as End Turn) top right. The grid sorts by display
name ON PURPOSE: the draw pile's internal order is the upcoming draw
order, and the view must show WHAT is left without revealing WHEN it
comes. Grid cards rest at `CARD_REST_SCALE` via `set_rest_transform`'s
optional scale (unhover returns to the REST scale; hover still zooms to
the absolute hand-sized `Juice.HOVER_SCALE`, which is what keeps rules
text readable). Two subtleties: a top-row card's bottom-pivoted zoom
would fly off-screen, so `CardView.clamped_hover_y` shifts the hover
target down into view (pure static, tested); and its keyword tooltip
flips BELOW the zoomed card when the top leaves no room above
(`show_for_card`'s `below` flag). Z-ordering is deliberate:
`PileView.PILE_Z` is 10 so a hovered grid card lands at 10 + HOVER_Z(50)
= 60, still under the tooltip's 70 -- raising PILE_Z above 20 silently
puts hovered cards over their own tooltips. `close()` emits (BattleView
plays the click and clears the tooltip); `dismiss()` is the silent
variant for fight transitions, so no click plays over the slam.

**The rewards screen.** Winning a mid-run fight no longer goes straight to
the next one: `BattleHud`'s result banner still shows CONTINUE, but
`BattleView._on_continue_pressed` now hides that banner and opens
`RewardsView` (`scripts/ui/rewards_view.gd`) instead of starting the fight
directly. Modelled on `PileView` -- a full-rect modal overlay with real
`CardView`s -- but sized for three cards instead of a grid: the offered
ids come from `RewardPool.options()`, which Fisher-Yates shuffles
`BattleConfig.REWARD_CARDS` (six entries: One-Two, Strength Up, Prepared,
High Kick, Flying Knee, Elbow) and takes the front `RewardPool.OFFER_COUNT`
(3) -- three distinct random cards, different every time the screen opens.
`options()` takes an injectable `rng` so tests are deterministic; every
game call site passes none, which means a fresh randomized generator. A
pool smaller than `OFFER_COUNT` would simply offer everything (`mini()`
guards the slice), though the pool has outgrown that case now. The offered
cards render at `CARD_REST_SCALE`, and clicking one selects it,
re-using `set_combo_armed()`'s frame tint as the "this card is charged"
read -- proven legible on both colourways already -- plus a bigger
`SELECTED_SCALE`, so the chosen card sits visibly proud of its neighbours.
CONTINUE stays disabled until something is selected; SKIP always works.
Either choice emits `finished(card_id)` (`card_id` empty on skip), and
`BattleView._on_rewards_finished` is the only writer to `RunState`:
`run.add_card(card_id)` when non-empty, then the same
`_suppress_transition_guard_pulses()` + `_start_fight()` Continue used to
call directly -- so the flow is Continue -> rewards -> next fight, and a
skip still advances. Same z-cake reasoning as `PileView.PILE_Z`:
`RewardsView.REWARDS_Z` is 10, so a hovered reward card lands at
10 + HOVER_Z(50) = 60, under the tooltip's 70 -- this is where the player
first reads Burn, STR and Prepared, so the keyword tooltips have to win.
Continue/Skip are plain `Button`s on purpose, placeholder until real
button art exists (the End Turn plate treatment is the model to follow
then).

**The KO splash.** `KoSplash` (`scripts/ui/ko_splash.gd`) is the
fight-ending overlay: centre-screen art that stamps in (spring from
`KO_SPLASH_START_SCALE` down to rest), holds, then fades -- `show_ko()`
for a scored knockout, `show_failed()` for a missed roll, each choosing the
`ko`/`failed` texture from `CardArt.ui_icon_for` and recording the decision
in `_last_shown` *before* the `is_inside_tree()` guard (rule 3), so
detached tests can assert it. It sits at `SPLASH_Z = 80`, above even
`StatusTooltip.TOOLTIP_Z` (70) -- the fight's biggest moment is never
covered by a lingering tooltip. `BattleView` owns the wiring: `BattleState`
emits `ko_scored`/`ko_failed` synchronously from inside `_resolve_play`,
*before* `fighters_changed`, and `_on_ko_scored`/`_on_ko_failed` arm
`_pending_ko` exactly like `_pending_hit_sound` and `_pending_follow_up` --
the deferred `_land_fighter_update` binds it into the same impact-timed
update via `_fire_ko_splash`, which on a scored KO also kicks
`Juice.KO_SPLASH_SHAKE_AMPLITUDE` and plays `slam` (the hardest hit in the
game gets the hardest feedback); a failed roll is just the blink, since the
hit's own impact juice already played. `BattleState.won_by_ko` records
whether the fight ended by knockout rather than hp reaching zero, and
`_on_battle_over` adds `Juice.KO_SPLASH_POP_TIME + Juice.KO_SPLASH_HOLD` to
the result banner's delay on a KO win, so CONTINUE never appears mid-stamp
-- it waits for the splash to be read first, the same "defer the view, not
the model" rule as every other beat in this section.

**The dev menu.** Backquote (`KEY_QUOTELEFT`, `BattleView._unhandled_input`)
toggles `DevMenu` (`scripts/ui/dev_menu.gd`): the same modal-overlay,
real-`CardView`-grid shape as `PileView`, but populated with
`CardLibrary.build_deck(CardLibrary.all_card_ids())` -- every card in the
library, not just one pile. Clicking a card in the grid emits
`DevMenu.card_picked(card)`; `BattleView._on_dev_card_picked` calls
`BattleState.dev_play(card)`, which runs the card through the exact same
`_resolve_play` real plays use (no AP cost, no hand or deck involvement --
the card is a fresh instance outside the deck's piles, so the deck
invariant is untouched), so KO, Bleed and every signal fire normally; the
menu stays open afterward so an effect can be spammed for testing (a KO
card's roll, Elbow's Bleed chance) without reopening it each time. DEV
ONLY -- there is no in-fiction way to reach it, and it is how this project
verifies the KO/Bleed pass end-to-end since the fight cannot otherwise be
forced into a specific hp/guard state on demand.

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
stays silent), `click` (End Turn / Continue / Restart), `slam` (the
portrait clash at fight start), and `slap` (a hit fully absorbed by
guard). Per-sound gain and the hit pitch spread
live in `Juice` (`SFX_VOLUME_DB`, `SFX_PITCH_MIN/MAX`) with every other
feel magnitude. Which hit sound an attack warrants is a pure static —
`hit_sound_for_card` (kick tag → kick, other damage → punch, no damage →
silent) and `hit_sound_for_moves` (the enemy analogue, reading the coming
turn's move labels before `end_turn()` resolves them) — and `BattleView`
arms it in `_pending_hit_sound` exactly like `_pending_reaction_delay`,
*binding* it into the deferred fighter update so the punch is heard when
the hit visually lands and a racing later event cannot overwrite it. At
the landing moment a second pure static, `impact_sound(hit_sound,
hp_damage, absorbed)`, decides what actually plays: hp damage keeps the
attack's own sound, a hit guard soaked entirely becomes `slap` (read
from `BattleHud.last_absorb_amount()`, the absorb mirror of
`last_damage_amount()` — a suppressed guard expiry records kind "none"
and can never slap), and an empty `hit_sound` stays silent no matter
what the diff saw. A fully blocked hit gets the slap but none of the
impact juice — hit-stop, shake and flash still require hp damage.
`play()` records its decision (id and chosen
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

**A multi-hit play lands as TWO beats, not one big one.** One-Two breaking
guard produces a second `Combat.DamageResult`; `BattleState` announces it
via `follow_up_hit(hp_loss, absorbed)` — emitted BEFORE `fighters_changed`,
so `BattleView._on_fighters_changed` binds it into the same deferred
update (the arm-before-play pattern `_pending_hit_sound` uses; presentation
info, not a second mutation — the model is already final). At impact time
the view presents the state with the follow-up hit HELD BACK
(`BattleHud.update_fighters_mid_hit`, driving `FighterPanel.update`'s
hp/guard overrides so the panel diffs and pulses only the first hit), then
lands the real state `Juice.follow_up_beat()` later — a second damage
number, punch sound, flash and shake of its own. The card's lunge becomes a
double tap (`lunge_to(anchor, true)`: solid first strike, short retract,
fading restrike), and `follow_up_beat()` is DERIVED from the same Juice
constants that build that tween, so the second panel beat and the restrike
connect together by construction. The result banner adds the same beat when
the follow-up was the kill. Verified in the real scene by hp-label sampling
(drops at ~0.50s and ~0.30s later) plus a contact sheet showing two
distinct impact flashes.

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

Playable two-fight run (Brawler then Kickboxer, HP carried between fights)
WITH a rewards screen -- 3 random cards drawn from a 6-card pool (One-Two,
Strength Up, Prepared, High Kick, Flying Knee, Elbow), or skip -- offered
between them, fully art-directed down to the fight screen itself (portrait
fight stage with a slam intro, icon readouts, outlined HUD text), sound
effects on every battle beat (see "Sound" under Game feel), 1432 headless
checks. `RunState.deck_ids` persists the run's deck across fights -- a
reward pick joins it and every fresh `BattleState` is built from it, so a
card taken after fight 1 is in the pool (and can be drawn, played, or
burned) for fight 2. Burn is a fourth deck pile alongside draw/hand/discard:
a burned card (Strength Up today) leaves play for the rest of the *fight*
only -- `Deck.reset()` empties the burned pile at the next fight, so a
burned card is back in the pool next time, same as any other reward card.
Three reward cards can end a fight outright: High Kick, Flying Knee and
Elbow each carry a percentage chance to KO on a hit that lands past guard
(`KOChanceEffect`, `KoSplash` stamping the win in centre-screen -- see "The
presentation layer"), and Elbow can also inflict Bleed, a guard-piercing
damage-per-turn status. What is conspicuously still placeholder:

- **No music, and the sound palette is minimal.** One click for all UI, no
  sound on playing Block itself (a fully blocked incoming hit does slap),
  no result-banner stinger, no crowd bed.
- **No map, no deck-building beyond a single post-fight reward pick.** The
  run is a fixed two-fight sequence; `RunState.current_opponent()` is the
  seam a branching map would replace. The reward pool itself is randomized
  now (3 of 6, different every screen -- see "The rewards screen"), but it
  is still one flat, hand-authored list with no rarity tiers, no scaling
  with run depth, and no pool growth beyond `BattleConfig.REWARD_CARDS`.
