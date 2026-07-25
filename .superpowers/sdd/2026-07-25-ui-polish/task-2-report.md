# Task 2 Report: CardView hover and lunge animation

## Brief path discrepancy

The instructed brief path, `.superpowers/sdd/2026-07-25-ui-polish/task-2-brief.md`,
does not exist in this worktree — there is no `.superpowers/sdd/` directory at all.
What does exist is `docs/superpowers/plans/2026-07-25-ui-polish.md`, whose
"Task 2: CardView hover and lunge" section contains a complete, verbatim test file
and implementation (constants, interfaces, code) that match the task description
given to me exactly (`HOVER_LIFT = 28.0`, `HOVER_SCALE = 1.08`, `HOVER_TIME = 0.12`,
`HOVER_Z = 50`, `LUNGE_Z = 60`, `LUNGE_TIME = 0.28`, `LUNGE_SCALE = 1.15`, bottom-centre
pivot, `set_rest_transform`/`apply_hover`/`lunge_to`, `BattleHud.RESULT_PANEL_Z`, etc.).
I used that section as the brief. Confirmed `RESULT_PANEL_Z = 100` already exists in
`scripts/ui/battle_hud.gd` (added by commit `d01b1c9`, ahead of this task, as expected)
and did not touch that file.

## What I implemented

Added to `scripts/ui/card_view.gd`, verbatim per the plan, with one deliberate,
documented deviation (see "Bug found in the brief" below):

- Constants `HOVER_LIFT`, `HOVER_SCALE`, `HOVER_TIME`, `HOVER_Z`, `LUNGE_Z`,
  `LUNGE_TIME`, `LUNGE_SCALE`.
- `rest_position` / `rest_rotation` / `rest_z_index` — the resting transform set by
  `HandView` when it fans the hand (consumed by Task 3, not yet run in this worktree).
- `target_position` / `target_rotation` / `target_scale` — the animation's decision,
  always recomputed from `rest_*`, asserted by tests instead of the live (tween-driven)
  transform.
- `pivot_offset` set to bottom-centre (`Vector2(CARD_SIZE.x / 2.0, CARD_SIZE.y)`) in
  `_init()`, so rotation reads as a held fan rather than a pinwheel.
- `set_rest_transform(position, rotation, z_index)` — records the new rest values
  unconditionally; only snaps the live transform if the card is *not* currently
  hovered, so a hand rebuild cannot yank a lifted card out from under the cursor.
- `apply_hover(value: bool)` — lifts 28px, scales to 1.08, rotates to 0, raises
  `z_index` to `HOVER_Z` on hover-in; restores exactly `rest_position` /
  `rest_rotation` / `Vector2.ONE` / `rest_z_index` on hover-out. Targets are always
  recomputed from `rest_*`, never from the live transform, so repeated hover round
  trips cannot drift (mirrors the `set_combo_armed` lesson referenced in the brief).
- `lunge_to(anchor: Vector2)` — the played-card animation: disables input, raises
  `z_index` to `LUNGE_Z`, and either tweens toward the anchor while scaling to 1.15
  and fading out (attached to a tree) or just `queue_free()`s (detached).
- `_animate_to(...)` — the shared tween helper. Records `target_*` first (unconditionally),
  then branches on `is_inside_tree()`: snaps the live transform to the target with no
  tween when detached, otherwise creates/kills a `Tween` and animates toward it. This
  follows the required shape exactly (decision recorded before the tree-membership check).
- Wired `mouse_entered` / `mouse_exited` in `_init()` to `apply_hover(true/false)`.

Created `tests/suites/test_card_hover.gd` with all seven test functions from the brief,
verbatim except for the one renamed call site (see below).

## Bug found in the brief: `is_hovered()` collides with a native Godot method

The brief specifies a method named `is_hovered() -> bool` on `CardView`. `CardView
extends Button extends BaseButton`, and `BaseButton` already defines a native
`is_hovered()` backed by the engine's own mouse-enter/exit tracking.

First attempt: defining `func is_hovered() -> bool: return _hovered` produced a
**compile error**, not just a warning:

```
SCRIPT ERROR: Parse Error: The method "is_hovered()" overrides a method from native
class "BaseButton". This won't be called by the engine and may not work as expected.
(Warning treated as error.)
```

This project has no custom warning-severity settings in `project.godot`; Godot 4.5.1
elevates `NATIVE_METHOD_OVERRIDE` to an error by default. Because `CardView` failed to
compile, this cascaded into unrelated failures in `test_card_view.gd` too (it also uses
`CardView`), confirming the collision is real and not scoped to my new test file.

I first tried suppressing just that warning with `@warning_ignore("native_method_override")`
on the method, to keep the exact public name from the brief. That silenced the compile
error, but the resulting behavior was **wrong**, not just risky: calling
`view.is_hovered()` after `view.apply_hover(true)` still returned `false`. The engine
message is accurate — GDScript does not actually dispatch calls to a script-level
override of this particular native method; calls resolve to the native, engine-tracked
getter (which reflects real mouse events, never generated in headless tests) regardless
of the script definition. Suppressing the warning would have shipped a method that
silently lies.

**Resolution:** renamed the getter to `is_card_hovered() -> bool`, and updated the two
call sites in my own `test_card_hover.gd` to match (`view.is_card_hovered()`). This is
a genuine, minimal deviation from the brief's literal interface list, made because the
literal name is unusable — not a preference. I checked the brief's Task 3 (`HandView`)
code for any call to `is_hovered()`: there is none (`clear_hover()` only calls
`apply_hover(false)`), so this rename creates no known integration risk with the
downstream task. I did not touch `project.godot` or any warning-severity settings, since
that would be a project-wide change reaching outside this task's scope for a
single-file naming problem.

## TDD Evidence

### RED

Command: `./tests/run_tests.sh`

Before any implementation, with only `tests/suites/test_card_hover.gd` added:

```
Running test_card_hover
SCRIPT ERROR: Parse Error: Cannot find member "HOVER_Z" in base "CardView".
          at: GDScript::reload (res://tests/suites/test_card_hover.gd:34)
...
SCRIPT ERROR: Parse Error: Cannot find member "LUNGE_Z" in base "CardView".
          at: GDScript::reload (res://tests/suites/test_card_hover.gd:85)
...
ERROR: Failed to load script "res://tests/suites/test_card_hover.gd" with error "Parse error".
  FAIL: [test_card_hover] Failed to load suite script: res://tests/suites/test_card_hover.gd
...
244 checks, 1 failures
FAILED:
  - [test_card_hover] Failed to load suite script: res://tests/suites/test_card_hover.gd
run_tests.sh: FAIL (run_tests.gd exited with code 1)
```

Expected reason: `CardView.HOVER_Z` / `LUNGE_Z` do not exist yet — matches. (The suite
also references `set_rest_transform`, `apply_hover`, etc., all similarly undeclared;
the parser reports the constants first because they appear earliest in the file.)

### GREEN

Command: `./tests/run_tests.sh`

After implementing `card_view.gd` (including the `is_card_hovered()` rename):

```
Running test_battle_combat
Running test_battle_turns
Running test_card_hover
Running test_card_library
Running test_card_view
Running test_combat
Running test_combo_rule
Running test_deck
Running test_effects
Running test_enemy_brain
Running test_fighter
Running test_harness
Running test_status_bag
Running test_status_registry

265 checks, 0 failures
PASS
```

265 = 244 baseline + 21 new checks (counted via `grep -c "t\.check" tests/suites/test_card_hover.gd` = 21). Exit code 0.

## Output pristine — no engine error markers

Ran the full suite to a log file and grepped for the markers `run_tests.sh` itself
watches for:

```
grep -nE "SCRIPT ERROR|Parse Error|Invalid call|ERROR:" full_run.log
```

Result: no matches (`CLEAN: no engine error markers`). Also grepped for `WARN` — none
present either. The tween/`is_inside_tree()` guard in `_animate_to` and `lunge_to` is
exercised safely: `test_card_hover.gd` instantiates every `CardView` detached, so every
`apply_hover()` and (implicitly) `lunge_to()` call in the suite takes the
snap-instead-of-tween / `queue_free()`-instead-of-tween path, never calling
`create_tween()` on a detached node.

## `test_card_view.gd` regression guard

Confirmed via `git diff --stat -- tests/suites/test_card_view.gd`: empty — the file is
byte-for-byte untouched. It passed as part of the full suite run above (`Running
test_card_view` with no failure reported, part of the 265/0 pass).

Also confirmed untouched: `scripts/ui/battle_hud.gd` (`git diff --stat` empty) and
everything under `scripts/core/` (`git diff --stat -- scripts/core/` empty).

## Files changed

- `scripts/ui/card_view.gd` — modified (hover/lunge/rest-transform additions; see diff
  in "What I implemented"). Full diff is in the commit.
- `tests/suites/test_card_hover.gd` — created (new suite, 7 test functions, 21 checks).
- `tests/suites/test_card_hover.gd.uid` — created (Godot sidecar, staged with `git add -A`).

## Self-review findings

- Every animation entry point (`_animate_to`, `lunge_to`) records its decision
  (`target_*`, or for `lunge_to` the z_index/disabled/mouse_filter side effects) before
  branching on `is_inside_tree()`, per the required shape.
- `apply_hover` targets are recomputed from `rest_*` on every call, never from the live
  transform — verified by `_test_hover_is_idempotent`, which does three hover round
  trips and asserts a bit-identical return to `Vector2(300, 470)` / rotation `0.2`.
- `set_rest_transform` leaves the live transform alone when `_hovered` is true (only
  updates `rest_*`), matching the "must not yank a hovered card" requirement. Not
  directly exercised by a test in this task (HandView, which triggers rebuilds, is
  Task 3), but the code path is present and matches the brief precisely.
- `lunge_to` on a detached node calls `queue_free()` and returns before touching
  `create_tween()` — matches "Detached (no tree), it should just queue_free()."
- The one deviation from brief text (`is_hovered` → `is_card_hovered`) is isolated to
  `card_view.gd` and my own new test file; it does not touch `test_card_view.gd`,
  `battle_hud.gd`, or `scripts/core/`, and has no known collision with Task 3's given
  `HandView` code.
- `git add -A` was used for staging so the `.uid` sidecar is tracked alongside its
  script, per project convention.

## Concerns

- The brief (as read from the plan doc) explicitly lists `is_hovered() -> bool` as part
  of `CardView`'s produced public surface. I renamed it to `is_card_hovered()` for the
  reason above. If a later task or reviewer expects the literal name `is_hovered()`,
  this will need reconciling — but the literal name cannot work correctly in Godot 4.5
  on a `Button` subclass, so some name change was unavoidable. Flagging this explicitly
  rather than silently picking a name.
- The brief file path given in my task instructions does not exist in this worktree at
  all; I substituted the plan document's Task 2 section, which is content-identical to
  the constants/interfaces given to me directly. Flagging in case the intended brief
  file was supposed to have been generated by an earlier step that did not run here.
