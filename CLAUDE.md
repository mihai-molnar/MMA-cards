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
on a clean tree ends with `218 checks, 0 failures` / `PASS`.

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

**These same five constants are also baked into the card art as printed
numbers, and regenerating the `.tres` does not touch the art.**
`assets/cards/card_jab.png`, `card_block.png` and `card_straight.png` are
fully composed card faces — title, artwork, value badge, rules text and cost
badge already drawn in — showing jab 6 damage / 1 cost, block 5 guard /
1 cost, straight 9 damage / 2 cost. Changing `JAB_DAMAGE`, `BLOCK_GUARD`,
`STRAIGHT_DAMAGE`, or either cost constant makes the card **lie** — the
number on the art and the number the game actually uses will disagree —
until someone regenerates new art to match. There is no automated guard for
this (deliberately — see "Card art" below); check it by eye after any
balance change that touches those five constants.

## Card art

Card faces are looked up by convention, in `scripts/ui/card_art.gd`: a card
with id `jab` uses `res://assets/cards/card_jab.png`. Adding a card's art is
dropping in a matching PNG — no lookup table to edit, no code change. A card
with no matching file falls back to `CardView`'s original coloured
rectangle + labels rendering, which is a real, intentional degradation path
for a card whose art has not been painted yet, not a bug.

The three current images (`card_jab.png`, `card_block.png`,
`card_straight.png`) are fully composed card faces, not raw illustrations —
title banner, artwork, value badge, rules text and cost badge are already
drawn in, which is why `CardView` hides its own name/cost/rules-text labels
and coloured background/border whenever art is present (see `_apply_art()`).
Each image has a wide transparent glow margin around the solid card body,
and the vertical margin differs per card, so the images are used **whole**,
never cropped — cropping each to its own opaque bounds would make the three
cards different rendered sizes and break fan alignment.

**Known discrepancy — the Straight card's art describes the combo rule
incorrectly, and this is expected, not a bug to "fix" by editing code:**
`card_straight.png` prints *"Combo: If Jab was played earlier this turn,
deal 50% more damage."* That is not what the game does. The actual rule
(`ComboRule.evaluate()`, wired up as `BattleState._combo_rules`'s
`ComboRule.jab_straight()`):
- Jab must **immediately precede** the Straight — any card played in
  between breaks the combo, not just "earlier this turn."
- The bonus is 50% of the **combined** base damage of both cards
  (6 + 9 = 15, `floori(15 * 0.5)` = +7), added to the Straight's base
  damage — so a comboed Straight hits **16**, not the 13 you'd get from
  boosting 9 alone by 50%.

The user has decided the code is authoritative here and the art will be
regenerated later; until then, treat the printed rules text as wrong and the
`ComboRule` / `BattleConfig.COMBO_BONUS_RATIO` code path as the truth. This
is a deliberate documentation-over-automated-guard choice, matching the
"card values are baked into the art" note in **Change balance** above — do
not add a runtime check that cross-references card art text against
`ComboRule`.

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

## Conventions

- Typed GDScript: explicit parameter and return types on every function.
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

- Spec: `docs/superpowers/specs/2026-07-25-mma-cards-poc-design.md`
- Plan: `docs/superpowers/plans/2026-07-25-mma-cards-poc.md`
