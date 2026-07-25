# MMA Cards Combat POC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a playable single-battle MMA card game — 12-card deck, 3 AP per turn, jab→straight combo, guard, strength, telegraphed enemy intent — on a data-driven foundation that extends to more cards and statuses without refactoring.

**Architecture:** Two layers with an enforced boundary. `scripts/core/` contains pure rules as `RefCounted`/`Resource` subclasses with zero node dependencies, fully testable headless. `scripts/ui/` renders state and forwards input, and never computes rules. Cards are `.tres` resources composed of a list of `CardEffect` objects; the enemy uses the same effect classes, so there is one damage pipeline for both sides.

**Tech Stack:** Godot 4.5.1, typed GDScript, custom headless `SceneTree` test runner (no external test framework).

## Global Constraints

- Godot binary: `/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot` — **path contains a space, always quote it**.
- **Test command — always this, and only this:**
  ```bash
  ./tests/run_tests.sh
  ```
  **Never invoke `run_tests.gd` directly.** GDScript has no catchable
  exceptions: when a runtime error occurs partway through a suite (a typo'd
  call, a null deref), the engine aborts that suite's body and the runner
  reports `PASS` with exit 0 — the remaining assertions silently never run.
  Verified: a suite with `t.chekc(...)` reports `4 checks, 0 failures / PASS`.
  The wrapper is what makes the result trustworthy — it fails on engine error
  markers in the output as well as on a non-zero exit code.

  The wrapper also runs the **mandatory** `--import` step first. Godot resolves
  `class_name` globals through `.godot/global_script_class_cache.cfg`, which
  only the editor or an explicit `--import` writes — and `.godot/` is
  gitignored. Without it, every suite referencing a newly added class fails to
  load with `Identifier "X" not declared in the current scope`. Verified
  empirically on a cache-less checkout.
- **Every test suite starts with exactly this preamble:**
  ```gdscript
  extends RefCounted

  const TestRunner := preload("res://tests/run_tests.gd")

  func run(t: TestRunner) -> void:
  ```
  Reference game classes (`Fighter`, `Combat`, `BattleConfig`, …) directly by
  their global names — the `--import` step is what makes those resolve. The local
  `preload` const is only for `TestRunner` itself, so the runner's type resolves
  even before an import has run.
- All GDScript is **typed**: explicit parameter and return types on every function.
- Naming: `PascalCase` for `class_name`, `snake_case` for members and functions, leading `_` for private.
- `scripts/core/` must never reference `Node`, `SceneTree`, or any scene-tree API. If a change seems to require it, the change belongs in `scripts/ui/`.
- Balance constants live only in `scripts/core/battle_config.gd`. No magic numbers elsewhere.
- Use Godot 4 integer helpers: `mini()`, `maxi()`, `floori()` — not `min()`/`max()`/`floor()` where ints are intended.
- UI text is ASCII only. Godot's default font does not render `⚔`/`🛡`/`↑`; use `ATTACK 12`, `BLOCK 8`, `BUFF +2 STR`.
- **Commit Godot's `.uid` sidecars.** Godot 4.4+ writes a `<name>.gd.uid` beside
  every script when it imports. These are project assets, not build artifacts —
  stage with `git add -A` rather than naming files individually, so none are left
  untracked. Partial `.uid` commits have twice blocked worktree merges in this
  project; a `.uid` present in one branch but untracked in another aborts the
  merge outright.
- Commit after every task.

## Spec Reference

`docs/superpowers/specs/2026-07-25-mma-cards-poc-design.md`

Key numbers: Player 50 HP, Enemy 48 HP, 3 AP/turn, 5-card hand, deck = 5 jab / 4 straight / 3 block. Jab 1 AP / 6 dmg. Straight 2 AP / 9 dmg. Block 1 AP / 5 guard. Combo `[jab, straight]` → straight deals `9 + floori((6+9) * 0.5)` = 16. Enemy cycle attack 8 → block 8 → buff +2 STR (2-turn duration). Strength = +25% outgoing per stack.

## File Structure

```
scripts/core/                    pure rules, no node dependencies
  battle_config.gd               tunable constants                        (Task 2)
  status_bag.gd                  stacks + turn countdown                  (Task 2)
  statuses/strength.gd           outgoing damage modifier                 (Task 3)
  status_registry.gd             id -> definition dispatch                (Task 3)
  fighter.gd                     hp, guard, statuses                      (Task 4)
  combat.gd                      the single damage pipeline               (Task 5)
  card_effect.gd                 effect base resource                     (Task 6)
  effects/damage_effect.gd                                                (Task 6)
  effects/guard_effect.gd                                                 (Task 6)
  effects/apply_status_effect.gd                                          (Task 6)
  card_data.gd                   cost, tags, effects[]                    (Task 6)
  combo_rule.gd                  tag-sequence matching                    (Task 7)
  card_library.gd                loads .tres, builds starting deck        (Task 8)
  deck.gd                        draw / hand / discard                    (Task 9)
  enemy_brain.gd                 intent cycle                             (Task 10)
  battle_state.gd                turn machine, AP, combos, win/lose  (Tasks 11-12)

scripts/ui/
  card_view.gd                   one card button                          (Task 13)
  hand_view.gd                   the hand row                             (Task 13)
  battle_hud.gd                  fighters, bars, buttons, log             (Task 14)
  battle_view.gd                 builds layout, wires signals             (Task 14)

resources/cards/                 jab.tres, straight.tres, block.tres      (Task 8)
tools/generate_cards.gd          writes the .tres files                   (Task 8)
level.tscn                       existing scene, gains battle_view.gd     (Task 14)
tests/run_tests.gd               headless runner + assertions             (Task 1)
tests/suites/*.gd                one suite per area                  (Tasks 2-13)
CLAUDE.md                                                                 (Task 15)
```

---

### Task 1: Headless test harness

**Files:**
- Create: `tests/run_tests.gd`
- Create: `tests/suites/test_harness.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: nothing.
- Produces: `TestRunner` (the `SceneTree` script) exposing `check(condition: bool, message: String) -> void` and `check_eq(actual: Variant, expected: Variant, message: String) -> void`. Every later suite is a `RefCounted` script with a local `const TestRunner := preload("res://tests/run_tests.gd")` and `func run(t: TestRunner) -> void`. Suites are auto-discovered: the runner scans `tests/suites/` for `test_*.gd` and runs them in sorted order. Creating the file is all the registration there is — no shared file to edit, which is what lets independent tasks run in parallel without colliding.

> **Amended during implementation.** Three changes the original code did not
> anticipate, all now reflected in Global Constraints:
> 1. The mandatory `--import` step before tests (global `class_name` resolution
>    depends on a gitignored cache).
> 2. A load guard, so a suite that fails to parse reports a failure instead of
>    hanging the run forever.
> 3. **Suite auto-discovery** replacing the hand-edited `SUITES` array. The
>    runner scans `tests/suites/` for `test_*.gd` and runs them in sorted order.
>    This removes the one file every task would otherwise have to edit — which
>    is what allows independent tasks to run in parallel without colliding — and
>    eliminates the mistyped-path failure mode entirely.
>
> See `.superpowers/sdd/2026-07-25-mma-cards-poc/task-1-report.md` for the
> reproductions. The code below is the original; the committed version carries
> all three changes.

- [ ] **Step 1: Write the harness self-test suite**

Create `tests/suites/test_harness.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

## Proves the runner counts checks and compares values correctly.
func run(t: TestRunner) -> void:
	t.check(true, "check() accepts a true condition")
	t.check_eq(2 + 2, 4, "check_eq() compares equal integers")
	t.check_eq("jab", "jab", "check_eq() compares equal strings")
```

- [ ] **Step 2: Run it to verify it fails (runner does not exist yet)**

Run:
```bash
./tests/run_tests.sh
```
Expected: FAIL — Godot reports it cannot open `res://tests/run_tests.gd`.

- [ ] **Step 3: Write the runner**

Create `tests/run_tests.gd`:

```gdscript
extends SceneTree

## Headless test runner. Add new suites to SUITES.
## Run via ./tests/run_tests.sh -- never directly (see Global Constraints).

const SUITES: Array = [
	"res://tests/suites/test_harness.gd",
]

var _checks: int = 0
var _failures: Array[String] = []
var _current_suite: String = ""

func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_record_failure(message)

func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_record_failure("%s — expected %s, got %s" % [message, expected, actual])

func _record_failure(message: String) -> void:
	var line: String = "[%s] %s" % [_current_suite, message]
	_failures.append(line)
	print("  FAIL: %s" % line)

func _initialize() -> void:
	for suite_path: String in SUITES:
		_current_suite = suite_path.get_file().get_basename()
		print("Running %s" % _current_suite)
		var script: GDScript = load(suite_path)
		var suite: RefCounted = script.new()
		suite.run(self)

	print("\n%d checks, %d failures" % [_checks, _failures.size()])
	if _failures.is_empty():
		print("PASS")
	else:
		print("FAILED:")
		for failure: String in _failures:
			print("  - %s" % failure)
	quit(0 if _failures.is_empty() else 1)
```

- [ ] **Step 4: Run to verify it passes**

Run the test command from Step 2.
Expected: `3 checks, 0 failures` then `PASS`, exit code 0. Verify with `echo $?`.

- [ ] **Step 5: Verify the harness actually detects failures**

Temporarily change `t.check_eq(2 + 2, 4, ...)` to `t.check_eq(2 + 2, 5, ...)`, run again.
Expected: `3 checks, 1 failures`, `FAILED:` block naming the check, exit code 1.
**Then change it back to `4` and re-run to confirm PASS.** A harness that cannot fail is worthless — this step proves it can.

- [ ] **Step 6: Set the main scene**

In `project.godot`, add to the `[application]` section:

```
run/main_scene="res://level.tscn"
```

- [ ] **Step 7: Commit**

```bash
git add tests/ project.godot
git commit -m "test: add headless test runner and suite registry"
```

---

### Task 2: BattleConfig and StatusBag

**Files:**
- Create: `scripts/core/battle_config.gd`
- Create: `scripts/core/status_bag.gd`
- Create: `tests/suites/test_status_bag.gd`

**Interfaces:**
- Consumes: `TestRunner` from Task 1.
- Produces:
  - `BattleConfig` — constants only, no instances.
  - `StatusBag` with `apply(id: StringName, stacks: int, turns_remaining: int) -> void`, `get_stacks(id: StringName) -> int`, `has(id: StringName) -> bool`, `ids() -> Array`, `tick_turn_end() -> void`, `clear() -> void`.
  - Duration convention: `turns_remaining == -1` means permanent. `tick_turn_end()` decrements positive counters and removes entries that reach 0.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_status_bag.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_apply_and_read(t)
	_test_stacking(t)
	_test_expiry_countdown(t)
	_test_permanent(t)
	_test_clear(t)

func _test_apply_and_read(t: TestRunner) -> void:
	var bag := StatusBag.new()
	t.check_eq(bag.get_stacks(&"strength"), 0, "unknown status reads as 0 stacks")
	t.check(not bag.has(&"strength"), "unknown status is absent")
	bag.apply(&"strength", 2, 2)
	t.check_eq(bag.get_stacks(&"strength"), 2, "applied status reports its stacks")
	t.check(bag.has(&"strength"), "applied status is present")
	t.check_eq(bag.ids(), [&"strength"], "ids() lists applied statuses")

func _test_stacking(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.apply(&"strength", 3, 1)
	t.check_eq(bag.get_stacks(&"strength"), 5, "re-applying adds stacks")

func _test_expiry_countdown(t: TestRunner) -> void:
	# A 2-turn buff must survive the turn it was applied on and expire at the
	# end of the following turn. This is the enemy buff timing.
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 2, "2-turn buff survives its own turn end")
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 0, "2-turn buff expires at the next turn end")
	t.check(not bag.has(&"strength"), "expired status is removed, not left at 0")

func _test_permanent(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 1, -1)
	bag.tick_turn_end()
	bag.tick_turn_end()
	bag.tick_turn_end()
	t.check_eq(bag.get_stacks(&"strength"), 1, "permanent status never expires")

func _test_clear(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"strength", 2, 2)
	bag.clear()
	t.check_eq(bag.get_stacks(&"strength"), 0, "clear() removes everything")
```

No registration step: the runner auto-discovers any `test_*.gd` in
`tests/suites/`. Creating the file is all it takes.

- [ ] **Step 2: Run to verify it fails**

Run the test command.
Expected: FAIL — parse error, `Identifier "StatusBag" not declared in the current scope`.

- [ ] **Step 3: Write BattleConfig**

Create `scripts/core/battle_config.gd`:

```gdscript
class_name BattleConfig
extends RefCounted

## Every tunable number in the game. Nothing else should hardcode balance values.

const PLAYER_MAX_HP: int = 50
const ENEMY_MAX_HP: int = 48
const AP_PER_TURN: int = 3
const HAND_SIZE: int = 5

## Card id -> copies in the starting deck. Totals 12.
const DECK_COMPOSITION: Dictionary = {
	&"jab": 5,
	&"straight": 4,
	&"block": 3,
}

const JAB_COST: int = 1
const JAB_DAMAGE: int = 6
const STRAIGHT_COST: int = 2
const STRAIGHT_DAMAGE: int = 9
const BLOCK_COST: int = 1
const BLOCK_GUARD: int = 5

const ENEMY_ATTACK_DAMAGE: int = 8
const ENEMY_GUARD_AMOUNT: int = 8
const ENEMY_BUFF_STRENGTH: int = 2
## 2 turns means: live during the buff turn AND the following attack turn.
const ENEMY_BUFF_DURATION: int = 2

## Combo bonus = floori(sum_of_base_damage * COMBO_BONUS_RATIO)
const COMBO_BONUS_RATIO: float = 0.5
## Each strength stack adds this fraction of base outgoing damage.
const STRENGTH_DAMAGE_PER_STACK: float = 0.25

const STATUS_PERMANENT: int = -1
```

- [ ] **Step 4: Write StatusBag**

Create `scripts/core/status_bag.gd`:

```gdscript
class_name StatusBag
extends RefCounted

## Stack-based statuses with a turn countdown.
## turns_remaining of BattleConfig.STATUS_PERMANENT (-1) never expires.

var _entries: Dictionary = {}

func apply(id: StringName, stacks: int, turns_remaining: int) -> void:
	if stacks <= 0:
		return
	if _entries.has(id):
		var entry: Dictionary = _entries[id]
		entry["stacks"] = entry["stacks"] + stacks
		# Refreshing takes the longer of the two durations; permanent always wins.
		if entry["turns"] != BattleConfig.STATUS_PERMANENT:
			if turns_remaining == BattleConfig.STATUS_PERMANENT:
				entry["turns"] = BattleConfig.STATUS_PERMANENT
			else:
				entry["turns"] = maxi(entry["turns"], turns_remaining)
	else:
		_entries[id] = {"stacks": stacks, "turns": turns_remaining}

func get_stacks(id: StringName) -> int:
	if not _entries.has(id):
		return 0
	return _entries[id]["stacks"]

func has(id: StringName) -> bool:
	return _entries.has(id)

func ids() -> Array:
	return _entries.keys()

func tick_turn_end() -> void:
	for id: StringName in _entries.keys():
		var entry: Dictionary = _entries[id]
		if entry["turns"] == BattleConfig.STATUS_PERMANENT:
			continue
		entry["turns"] = entry["turns"] - 1
		if entry["turns"] <= 0:
			_entries.erase(id)

func clear() -> void:
	_entries.clear()
```

- [ ] **Step 5: Run to verify it passes**

Run the test command.
Expected: PASS, exit 0. The `_test_expiry_countdown` checks are the important ones — they encode the enemy buff timing.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/battle_config.gd scripts/core/status_bag.gd tests/
git commit -m "feat: add battle config constants and status bag with turn expiry"
```

---

### Task 3: Strength status and StatusRegistry

**Files:**
- Create: `scripts/core/statuses/strength.gd`
- Create: `scripts/core/status_registry.gd`
- Create: `tests/suites/test_status_registry.gd`

**Interfaces:**
- Consumes: `StatusBag`, `BattleConfig`.
- Produces:
  - `StrengthStatus` with `const ID: StringName = &"strength"`, `const DISPLAY_NAME: String = "STR"`, and statics `modify_outgoing_damage(amount: int, stacks: int) -> int` and `modify_incoming_damage(amount: int, stacks: int) -> int`.
  - `StatusRegistry` with statics `modify_outgoing(bag: StatusBag, amount: int) -> int`, `modify_incoming(bag: StatusBag, amount: int) -> int`, `display_name(id: StringName) -> String`.
- **Contract for new statuses:** every status script must define `ID`, `DISPLAY_NAME`, and *both* modifier statics (pass-through if unused), then be added to `StatusRegistry.DEFINITIONS`. No reflection, so both hooks are mandatory.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_status_registry.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_strength_math(t)
	_test_registry_dispatch(t)

func _test_strength_math(t: TestRunner) -> void:
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 0), 8, "0 strength leaves damage unchanged")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 2), 12, "2 strength turns 8 into 12")
	t.check_eq(StrengthStatus.modify_outgoing_damage(8, 1), 10, "1 strength turns 8 into 10")
	# 9 * 1.25 = 11.25 -> floors to 11
	t.check_eq(StrengthStatus.modify_outgoing_damage(9, 1), 11, "strength bonus floors, never rounds up")
	t.check_eq(StrengthStatus.modify_incoming_damage(8, 2), 8, "strength does not change incoming damage")

func _test_registry_dispatch(t: TestRunner) -> void:
	var bag := StatusBag.new()
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 8, "empty bag applies no modifiers")

	bag.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "registry routes through strength")
	t.check_eq(StatusRegistry.modify_incoming(bag, 8), 8, "registry incoming is pass-through for strength")
	t.check_eq(StatusRegistry.display_name(StrengthStatus.ID), "STR", "registry exposes display names")

	bag.apply(&"unregistered_status", 5, 2)
	t.check_eq(StatusRegistry.modify_outgoing(bag, 8), 12, "unregistered status is ignored, not crashing")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "StrengthStatus" not declared in the current scope`.

- [ ] **Step 3: Write the strength status**

Create `scripts/core/statuses/strength.gd`:

```gdscript
class_name StrengthStatus
extends RefCounted

## Each stack adds BattleConfig.STRENGTH_DAMAGE_PER_STACK of base outgoing damage.
## Every status definition must provide ID, DISPLAY_NAME, and BOTH modifier
## statics — StatusRegistry calls them unconditionally.

const ID: StringName = &"strength"
const DISPLAY_NAME: String = "STR"

static func modify_outgoing_damage(amount: int, stacks: int) -> int:
	if stacks <= 0:
		return amount
	return floori(amount * (1.0 + BattleConfig.STRENGTH_DAMAGE_PER_STACK * stacks))

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount
```

- [ ] **Step 4: Write the registry**

Create `scripts/core/status_registry.gd`:

```gdscript
class_name StatusRegistry
extends RefCounted

## Maps status id -> definition script. To add a status: write the script in
## scripts/core/statuses/ following the StrengthStatus contract, then add one
## line here. The damage pipeline needs no changes.

const DEFINITIONS: Dictionary = {
	&"strength": preload("res://scripts/core/statuses/strength.gd"),
}

static func modify_outgoing(bag: StatusBag, amount: int) -> int:
	var result: int = amount
	for id: StringName in bag.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		result = definition.modify_outgoing_damage(result, bag.get_stacks(id))
	return result

static func modify_incoming(bag: StatusBag, amount: int) -> int:
	var result: int = amount
	for id: StringName in bag.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		result = definition.modify_incoming_damage(result, bag.get_stacks(id))
	return result

static func display_name(id: StringName) -> String:
	if not DEFINITIONS.has(id):
		return String(id).to_upper()
	var definition: GDScript = DEFINITIONS[id]
	return definition.DISPLAY_NAME
```

- [ ] **Step 5: Run to verify it passes**

Run the test command. Expected: PASS.

If calling statics through the `GDScript` variable errors at runtime, that is a real finding — report it rather than working around it silently, since the whole extensibility claim rests on this dispatch working.

- [ ] **Step 6: Commit**

```bash
git add scripts/core/statuses/ scripts/core/status_registry.gd tests/
git commit -m "feat: add strength status and registry dispatch"
```

---

### Task 4: Fighter

**Files:**
- Create: `scripts/core/fighter.gd`
- Create: `tests/suites/test_fighter.gd`

**Interfaces:**
- Consumes: `StatusBag`, `BattleConfig`.
- Produces: `Fighter` with `_init(p_display_name: String, p_max_hp: int)`, public vars `display_name: String`, `max_hp: int`, `hp: int`, `guard: int`, `statuses: StatusBag`, and methods `is_alive() -> bool`, `add_guard(amount: int) -> void`, `expire_guard() -> void`, `tick_statuses_turn_end() -> void`, `apply_hp_loss(amount: int) -> int` (returns HP actually lost), `absorb_into_guard(amount: int) -> int` (returns amount absorbed), `reset() -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_fighter.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_state(t)
	_test_guard(t)
	_test_hp_loss(t)
	_test_reset(t)

func _test_initial_state(t: TestRunner) -> void:
	var f := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	t.check_eq(f.display_name, "Player", "fighter keeps its display name")
	t.check_eq(f.hp, 50, "fighter starts at full hp")
	t.check_eq(f.max_hp, 50, "fighter records its max hp")
	t.check_eq(f.guard, 0, "fighter starts with no guard")
	t.check(f.is_alive(), "fighter starts alive")

func _test_guard(t: TestRunner) -> void:
	var f := Fighter.new("Player", 50)
	f.add_guard(5)
	t.check_eq(f.guard, 5, "add_guard raises guard")
	f.add_guard(5)
	t.check_eq(f.guard, 10, "guard from two blocks accumulates")
	t.check_eq(f.absorb_into_guard(4), 4, "absorb returns the amount taken by guard")
	t.check_eq(f.guard, 6, "absorbed damage reduces guard")
	t.check_eq(f.absorb_into_guard(99), 6, "absorb is capped at remaining guard")
	t.check_eq(f.guard, 0, "guard bottoms out at 0")
	f.add_guard(8)
	f.expire_guard()
	t.check_eq(f.guard, 0, "expire_guard clears guard")

func _test_hp_loss(t: TestRunner) -> void:
	var f := Fighter.new("Enemy", 48)
	t.check_eq(f.apply_hp_loss(6), 6, "apply_hp_loss returns hp actually lost")
	t.check_eq(f.hp, 42, "hp drops by the loss")
	t.check(f.is_alive(), "fighter above 0 hp is alive")
	t.check_eq(f.apply_hp_loss(999), 42, "overkill only reports the hp that existed")
	t.check_eq(f.hp, 0, "hp floors at 0, never negative")
	t.check(not f.is_alive(), "fighter at 0 hp is not alive")

func _test_reset(t: TestRunner) -> void:
	var f := Fighter.new("Player", 50)
	f.apply_hp_loss(20)
	f.add_guard(5)
	f.statuses.apply(StrengthStatus.ID, 2, 2)
	f.reset()
	t.check_eq(f.hp, 50, "reset restores full hp")
	t.check_eq(f.guard, 0, "reset clears guard")
	t.check_eq(f.statuses.get_stacks(StrengthStatus.ID), 0, "reset clears statuses")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "Fighter" not declared in the current scope`.

- [ ] **Step 3: Write Fighter**

Create `scripts/core/fighter.gd`:

```gdscript
class_name Fighter
extends RefCounted

## A combatant's mutable state. Knows nothing about turns, cards, or the scene
## tree — BattleState drives it.

var display_name: String
var max_hp: int
var hp: int
var guard: int = 0
var statuses: StatusBag

func _init(p_display_name: String, p_max_hp: int) -> void:
	display_name = p_display_name
	max_hp = p_max_hp
	hp = p_max_hp
	statuses = StatusBag.new()

func is_alive() -> bool:
	return hp > 0

func add_guard(amount: int) -> void:
	if amount <= 0:
		return
	guard += amount

## Returns how much of `amount` the guard absorbed, and consumes that guard.
func absorb_into_guard(amount: int) -> int:
	var absorbed: int = mini(guard, maxi(amount, 0))
	guard -= absorbed
	return absorbed

## Returns hp actually lost (never more than the hp that existed).
func apply_hp_loss(amount: int) -> int:
	var loss: int = mini(maxi(amount, 0), hp)
	hp -= loss
	return loss

func expire_guard() -> void:
	guard = 0

func tick_statuses_turn_end() -> void:
	statuses.tick_turn_end()

func reset() -> void:
	hp = max_hp
	guard = 0
	statuses.clear()
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/fighter.gd tests/
git commit -m "feat: add Fighter with guard absorption and hp floor"
```

---

### Task 5: The damage pipeline

**Files:**
- Create: `scripts/core/combat.gd`
- Create: `tests/suites/test_combat.gd`

**Interfaces:**
- Consumes: `Fighter`, `StatusRegistry`.
- Produces: `Combat` with an inner `class DamageResult extends RefCounted` holding `raw: int`, `absorbed: int`, `hp_loss: int`; statics `resolve_damage(base: int, source: Fighter, target: Fighter) -> DamageResult` and `preview_damage(base: int, source: Fighter) -> int`.
- `preview_damage` applies only the source's outgoing modifiers. The enemy intent display uses it so a buffed attack telegraphs 12, not 8.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_combat.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_plain_damage(t)
	_test_guard_absorption(t)
	_test_guard_spillover(t)
	_test_strength_applied(t)
	_test_clamping(t)
	_test_preview(t)

func _make_pair() -> Array:
	return [Fighter.new("Player", 50), Fighter.new("Enemy", 48)]

func _test_plain_damage(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	var result = Combat.resolve_damage(6, player, enemy)
	t.check_eq(result.raw, 6, "unmodified damage passes through at face value")
	t.check_eq(result.absorbed, 0, "no guard means nothing absorbed")
	t.check_eq(result.hp_loss, 6, "all damage reaches hp")
	t.check_eq(enemy.hp, 42, "enemy 48 takes a jab down to 42")

func _test_guard_absorption(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.add_guard(8)
	var result = Combat.resolve_damage(6, player, enemy)
	t.check_eq(result.absorbed, 6, "guard absorbs damage below its value")
	t.check_eq(result.hp_loss, 0, "hp is untouched while guard holds")
	t.check_eq(enemy.guard, 2, "guard is reduced by what it absorbed")
	t.check_eq(enemy.hp, 48, "enemy hp unchanged behind guard")

func _test_guard_spillover(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.add_guard(8)
	var result = Combat.resolve_damage(16, player, enemy)
	t.check_eq(result.absorbed, 8, "guard absorbs up to its value")
	t.check_eq(result.hp_loss, 8, "damage above guard spills to hp")
	t.check_eq(enemy.guard, 0, "guard is spent")
	t.check_eq(enemy.hp, 40, "enemy takes the spillover")

func _test_strength_applied(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	var result = Combat.resolve_damage(8, enemy, player)
	t.check_eq(result.raw, 12, "2 strength turns an 8 attack into 12")
	t.check_eq(player.hp, 38, "player takes the buffed hit")

	# Player guard 5 against that same buffed 12 leaves 7 through.
	var pair2: Array = _make_pair()
	var player2: Fighter = pair2[0]
	var enemy2: Fighter = pair2[1]
	enemy2.statuses.apply(StrengthStatus.ID, 2, 2)
	player2.add_guard(5)
	Combat.resolve_damage(8, enemy2, player2)
	t.check_eq(player2.hp, 43, "guard 5 vs buffed 12 leaves 7 through")

func _test_clamping(t: TestRunner) -> void:
	var pair: Array = _make_pair()
	var player: Fighter = pair[0]
	var enemy: Fighter = pair[1]
	var result = Combat.resolve_damage(-5, player, enemy)
	t.check_eq(result.raw, 0, "negative damage clamps to 0")
	t.check_eq(enemy.hp, 48, "negative damage cannot heal")

	Combat.resolve_damage(999, player, enemy)
	t.check_eq(enemy.hp, 0, "overkill floors hp at 0")

func _test_preview(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	t.check_eq(Combat.preview_damage(8, enemy), 8, "preview of an unbuffed attack is 8")
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(Combat.preview_damage(8, enemy), 12, "preview reflects strength for the intent display")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "Combat" not declared in the current scope`.

- [ ] **Step 3: Write Combat**

Create `scripts/core/combat.gd`:

```gdscript
class_name Combat
extends RefCounted

## The single damage pipeline. Every point of damage in the game flows through
## resolve_damage, player and enemy alike:
##   base -> attacker outgoing -> defender incoming -> clamp -> guard -> hp

class DamageResult extends RefCounted:
	var raw: int = 0
	var absorbed: int = 0
	var hp_loss: int = 0

	func _init(p_raw: int, p_absorbed: int, p_hp_loss: int) -> void:
		raw = p_raw
		absorbed = p_absorbed
		hp_loss = p_hp_loss

static func resolve_damage(base: int, source: Fighter, target: Fighter) -> DamageResult:
	var amount: int = base
	amount = StatusRegistry.modify_outgoing(source.statuses, amount)
	amount = StatusRegistry.modify_incoming(target.statuses, amount)
	amount = maxi(amount, 0)

	var absorbed: int = target.absorb_into_guard(amount)
	var hp_loss: int = target.apply_hp_loss(amount - absorbed)
	return DamageResult.new(amount, absorbed, hp_loss)

## What `base` would hit for, given only the source's modifiers. Used by the
## enemy intent telegraph — it must not mutate anything.
static func preview_damage(base: int, source: Fighter) -> int:
	return maxi(StatusRegistry.modify_outgoing(source.statuses, base), 0)
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/combat.gd tests/
git commit -m "feat: add single damage pipeline with guard and status modifiers"
```

---

### Task 6: Card effects and CardData

**Files:**
- Create: `scripts/core/card_effect.gd`
- Create: `scripts/core/effects/damage_effect.gd`
- Create: `scripts/core/effects/guard_effect.gd`
- Create: `scripts/core/effects/apply_status_effect.gd`
- Create: `scripts/core/card_data.gd`
- Create: `tests/suites/test_effects.gd`

**Interfaces:**
- Consumes: `Fighter`, `Combat`, `BattleConfig`.
- Produces:
  - `CardEffect extends Resource` with `apply(source: Fighter, target: Fighter, context: Dictionary) -> void` (base pushes an error) and `describe() -> String`.
  - `DamageEffect` with `@export var amount: int`.
  - `GuardEffect` with `@export var amount: int` — applies guard to **source**, not target.
  - `ApplyStatusEffect` with `@export var status_id: StringName`, `@export var stacks: int`, `@export var turns: int`, `@export var target_self: bool`.
  - `CardData extends Resource` with `@export` `id: StringName`, `display_name: String`, `cost: int`, `tags: Array[StringName]`, `effects: Array[CardEffect]`, `rules_text: String`; plus `total_base_damage() -> int`.
- **Context dictionary contract** — `BattleState` builds it per card play:
  - `"bonus_damage": int` — combo bonus. The first `DamageEffect` to run adds it to its own amount and resets the key to 0, so a multi-hit card cannot double-dip.
  - `"results": Array` — each `DamageEffect` appends its `Combat.DamageResult`.
  - `"log": Array` — human-readable strings for the combat log.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_effects.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_damage_effect(t)
	_test_bonus_consumed_once(t)
	_test_guard_effect(t)
	_test_apply_status_effect(t)
	_test_card_data(t)

func _new_context(bonus: int) -> Dictionary:
	return {"bonus_damage": bonus, "results": [], "log": []}

func _test_damage_effect(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := DamageEffect.new()
	effect.amount = 6
	var context: Dictionary = _new_context(0)
	effect.apply(player, enemy, context)
	t.check_eq(enemy.hp, 42, "damage effect routes through the pipeline")
	t.check_eq(context["results"].size(), 1, "damage effect records its result")

func _test_bonus_consumed_once(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := DamageEffect.new()
	effect.amount = 9
	var context: Dictionary = _new_context(7)
	effect.apply(player, enemy, context)
	t.check_eq(enemy.hp, 48 - 16, "combo bonus is added to the straight's damage")
	t.check_eq(context["bonus_damage"], 0, "bonus is consumed so a second hit cannot reuse it")

	# A second damage effect in the same play gets no bonus.
	var effect2 := DamageEffect.new()
	effect2.amount = 9
	effect2.apply(player, enemy, context)
	t.check_eq(enemy.hp, 48 - 16 - 9, "a second hit deals plain damage")

func _test_guard_effect(t: TestRunner) -> void:
	var player := Fighter.new("Player", 50)
	var enemy := Fighter.new("Enemy", 48)
	var effect := GuardEffect.new()
	effect.amount = 5
	effect.apply(player, enemy, _new_context(0))
	t.check_eq(player.guard, 5, "guard effect protects the source")
	t.check_eq(enemy.guard, 0, "guard effect does not touch the target")

func _test_apply_status_effect(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var effect := ApplyStatusEffect.new()
	effect.status_id = StrengthStatus.ID
	effect.stacks = 2
	effect.turns = 2
	effect.target_self = true
	effect.apply(enemy, player, _new_context(0))
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "self-targeted status lands on the source")
	t.check_eq(player.statuses.get_stacks(StrengthStatus.ID), 0, "self-targeted status spares the target")

func _test_card_data(t: TestRunner) -> void:
	var card := CardData.new()
	card.id = &"straight"
	card.display_name = "STRAIGHT"
	card.cost = 2
	card.tags = [&"straight"] as Array[StringName]
	var effect := DamageEffect.new()
	effect.amount = 9
	card.effects = [effect] as Array[CardEffect]
	t.check_eq(card.total_base_damage(), 9, "total_base_damage sums damage effects")

	var blocker := CardData.new()
	blocker.id = &"block"
	var guard := GuardEffect.new()
	guard.amount = 5
	blocker.effects = [guard] as Array[CardEffect]
	t.check_eq(blocker.total_base_damage(), 0, "a card with no damage effects reports 0")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "DamageEffect" not declared in the current scope`.

- [ ] **Step 3: Write the effect base class**

Create `scripts/core/card_effect.gd`:

```gdscript
class_name CardEffect
extends Resource

## One thing a card does. Cards are lists of these, so adding a card is
## composing effects rather than adding a branch to a play function.
##
## context keys (built by BattleState per play):
##   "bonus_damage": int  — combo bonus; the first DamageEffect consumes it
##   "results": Array     — Combat.DamageResult objects appended by damage
##   "log": Array         — human-readable strings for the combat log

func apply(_source: Fighter, _target: Fighter, _context: Dictionary) -> void:
	push_error("CardEffect.apply() must be overridden by %s" % get_script().resource_path)

func describe() -> String:
	return ""
```

- [ ] **Step 4: Write the three effects**

Create `scripts/core/effects/damage_effect.gd`:

```gdscript
class_name DamageEffect
extends CardEffect

@export var amount: int = 0

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	# The combo bonus applies to the first damage effect only.
	var bonus: int = context.get("bonus_damage", 0)
	context["bonus_damage"] = 0

	var result: Combat.DamageResult = Combat.resolve_damage(amount + bonus, source, target)
	context["results"].append(result)
	context["log"].append("%s deals %d damage" % [source.display_name, result.raw])

func describe() -> String:
	return "Deal %d damage." % amount
```

Create `scripts/core/effects/guard_effect.gd`:

```gdscript
class_name GuardEffect
extends CardEffect

@export var amount: int = 0

func apply(source: Fighter, _target: Fighter, context: Dictionary) -> void:
	source.add_guard(amount)
	context["log"].append("%s gains %d guard" % [source.display_name, amount])

func describe() -> String:
	return "Gain %d guard." % amount
```

Create `scripts/core/effects/apply_status_effect.gd`:

```gdscript
class_name ApplyStatusEffect
extends CardEffect

@export var status_id: StringName = &""
@export var stacks: int = 0
## Turn countdown; BattleConfig.STATUS_PERMANENT (-1) never expires.
@export var turns: int = BattleConfig.STATUS_PERMANENT
@export var target_self: bool = true

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	var recipient: Fighter = source if target_self else target
	recipient.statuses.apply(status_id, stacks, turns)
	context["log"].append("%s gains %d %s" % [
		recipient.display_name, stacks, StatusRegistry.display_name(status_id)
	])

func describe() -> String:
	return "Gain %d %s." % [stacks, StatusRegistry.display_name(status_id)]
```

- [ ] **Step 5: Write CardData**

Create `scripts/core/card_data.gd`:

```gdscript
class_name CardData
extends Resource

## A card is data: what it costs, what it is tagged as, and what it does.
## Adding a card means authoring a .tres — never editing a play function.

@export var id: StringName = &""
@export var display_name: String = ""
@export var cost: int = 0
## Combo rules match on these.
@export var tags: Array[StringName] = []
@export var effects: Array[CardEffect] = []
@export var rules_text: String = ""

## Base damage before any modifiers. Combo bonuses are computed from this, so
## it is derived from the effects rather than duplicated in a field.
func total_base_damage() -> int:
	var total: int = 0
	for effect: CardEffect in effects:
		if effect is DamageEffect:
			total += (effect as DamageEffect).amount
	return total

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
```

- [ ] **Step 6: Run to verify it passes**

Run the test command. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/core/card_effect.gd scripts/core/effects/ scripts/core/card_data.gd tests/
git commit -m "feat: add composable card effects and CardData resource"
```

---

### Task 7: ComboRule

**Files:**
- Create: `scripts/core/combo_rule.gd`
- Create: `tests/suites/test_combo_rule.gd`

**Interfaces:**
- Consumes: `CardData`, `BattleConfig`.
- Produces: `ComboRule` with `_init(p_sequence: Array[StringName], p_bonus_ratio: float)`, `evaluate(history: Array, candidate: CardData) -> int` returning bonus damage or 0, and `static jab_straight() -> ComboRule`.
- `history` is the cards already played this turn, oldest first. A match requires the candidate to carry the last tag in the sequence and the immediately preceding history entries to carry the earlier tags, in order, with nothing in between.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_combo_rule.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func _card(card_id: StringName, tag: StringName, damage: int) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id).to_upper()
	card.tags = [tag] as Array[StringName]
	var effect := DamageEffect.new()
	effect.amount = damage
	card.effects = [effect] as Array[CardEffect]
	return card

func _jab() -> CardData:
	return _card(&"jab", &"jab", 6)

func _straight() -> CardData:
	return _card(&"straight", &"straight", 9)

func _block() -> CardData:
	var card := CardData.new()
	card.id = &"block"
	card.tags = [&"defense"] as Array[StringName]
	var effect := GuardEffect.new()
	effect.amount = 5
	card.effects = [effect] as Array[CardEffect]
	return card

func run(t: TestRunner) -> void:
	var rule := ComboRule.jab_straight()

	# The headline case: jab then straight is 6 + 9 + floor(15 * 0.5) = 22 total.
	t.check_eq(rule.evaluate([_jab()], _straight()), 7, "jab into straight grants a 7 damage bonus")

	# An intervening card breaks the chain.
	t.check_eq(rule.evaluate([_jab(), _block()], _straight()), 0, "a block between jab and straight breaks the combo")

	# Order matters.
	t.check_eq(rule.evaluate([_straight()], _jab()), 0, "straight into jab is not a combo")

	# Wrong candidate, right history.
	t.check_eq(rule.evaluate([_jab()], _jab()), 0, "jab into jab is not a combo")

	# Nothing played yet.
	t.check_eq(rule.evaluate([], _straight()), 0, "a straight opening the turn gets no bonus")

	# Only the immediately preceding card is consulted.
	t.check_eq(rule.evaluate([_block(), _jab()], _straight()), 7, "only the card immediately before matters")

	# A longer history still matches on its tail.
	t.check_eq(rule.evaluate([_jab(), _straight(), _jab()], _straight()), 7, "a second combo in the same turn still triggers")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "ComboRule" not declared in the current scope`.

- [ ] **Step 3: Write ComboRule**

Create `scripts/core/combo_rule.gd`:

```gdscript
class_name ComboRule
extends RefCounted

## Matches a sequence of tags against the cards played consecutively this turn.
## Adding a combo is constructing another rule — no code changes elsewhere.

var sequence: Array[StringName] = []
var bonus_ratio: float = 0.0

func _init(p_sequence: Array[StringName], p_bonus_ratio: float) -> void:
	sequence = p_sequence
	bonus_ratio = p_bonus_ratio

static func jab_straight() -> ComboRule:
	return ComboRule.new([&"jab", &"straight"] as Array[StringName], BattleConfig.COMBO_BONUS_RATIO)

## Bonus damage if playing `candidate` now completes the sequence, else 0.
## `history` is this turn's plays, oldest first.
func evaluate(history: Array, candidate: CardData) -> int:
	var length: int = sequence.size()
	if length == 0:
		return 0
	if not candidate.has_tag(sequence[length - 1]):
		return 0

	var prefix_length: int = length - 1
	if history.size() < prefix_length:
		return 0

	var matched: Array[CardData] = []
	var start: int = history.size() - prefix_length
	for i: int in range(prefix_length):
		var card: CardData = history[start + i]
		if not card.has_tag(sequence[i]):
			return 0
		matched.append(card)
	matched.append(candidate)

	var total_damage: int = 0
	for card: CardData in matched:
		total_damage += card.total_base_damage()
	return floori(total_damage * bonus_ratio)

func describe() -> String:
	var names: Array[String] = []
	for tag: StringName in sequence:
		names.append(String(tag).to_upper())
	return " -> ".join(names)
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: PASS. The first check (bonus of 7) is the one that makes the combo total 22.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/combo_rule.gd tests/
git commit -m "feat: add tag-sequence combo rule"
```

---

### Task 8: Card resources and library

**Files:**
- Create: `tools/generate_cards.gd`
- Create: `resources/cards/jab.tres` (generated)
- Create: `resources/cards/straight.tres` (generated)
- Create: `resources/cards/block.tres` (generated)
- Create: `scripts/core/card_library.gd`
- Create: `tests/suites/test_card_library.gd`

**Interfaces:**
- Consumes: `CardData`, `DamageEffect`, `GuardEffect`, `BattleConfig`.
- Produces: `CardLibrary` with statics `load_card(card_id: StringName) -> CardData`, `build_starting_deck() -> Array[CardData]`, `all_ids() -> Array`.
- `.tres` files are **generated** by the tool script rather than hand-written, so the resource format is guaranteed valid. They are normal inspector-editable resources afterward.
- `CardLibrary` uses `load()`, not `preload()` — `preload` would make the script fail to parse before the resources exist.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_card_library.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cards_load(t)
	_test_starting_deck(t)

func _test_cards_load(t: TestRunner) -> void:
	var jab: CardData = CardLibrary.load_card(&"jab")
	t.check(jab != null, "jab.tres loads")
	t.check_eq(jab.cost, 1, "jab costs 1 AP")
	t.check_eq(jab.total_base_damage(), 6, "jab deals 6 damage")
	t.check(jab.has_tag(&"jab"), "jab carries the jab tag")

	var straight: CardData = CardLibrary.load_card(&"straight")
	t.check_eq(straight.cost, 2, "straight costs 2 AP")
	t.check_eq(straight.total_base_damage(), 9, "straight deals 9 damage")
	t.check(straight.has_tag(&"straight"), "straight carries the straight tag")

	var blocker: CardData = CardLibrary.load_card(&"block")
	t.check_eq(blocker.cost, 1, "block costs 1 AP")
	t.check_eq(blocker.total_base_damage(), 0, "block deals no damage")
	t.check_eq(blocker.effects.size(), 1, "block has one effect")
	t.check_eq((blocker.effects[0] as GuardEffect).amount, 5, "block grants 5 guard")

func _test_starting_deck(t: TestRunner) -> void:
	var deck: Array[CardData] = CardLibrary.build_starting_deck()
	t.check_eq(deck.size(), 12, "starting deck holds 12 cards")

	var counts: Dictionary = {}
	for card: CardData in deck:
		counts[card.id] = counts.get(card.id, 0) + 1
	t.check_eq(counts.get(&"jab", 0), 5, "deck holds 5 jabs")
	t.check_eq(counts.get(&"straight", 0), 4, "deck holds 4 straights")
	t.check_eq(counts.get(&"block", 0), 3, "deck holds 3 blocks")

	# Each deck entry must be an independent instance — a shared resource would
	# let per-card state leak between copies later.
	t.check(deck[0] != deck[1] or deck[0].id != deck[1].id, "deck entries are separate instances")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "CardLibrary" not declared in the current scope`.

- [ ] **Step 3: Write the generator tool**

Create `tools/generate_cards.gd`:

```gdscript
extends SceneTree

## Generates resources/cards/*.tres from BattleConfig values.
## Run: godot --headless --path . --script res://tools/generate_cards.gd
##
## Cards are generated rather than hand-written so the .tres format is always
## valid. The output is a normal resource — edit it in the inspector, or add a
## new card by extending CARDS below and re-running.

const OUTPUT_DIR: String = "res://resources/cards"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_save(_make_jab())
	_save(_make_straight())
	_save(_make_block())

	print("Generated 3 card resources in %s" % OUTPUT_DIR)
	quit(0)

func _save(card: CardData) -> void:
	var path: String = "%s/%s.tres" % [OUTPUT_DIR, card.id]
	var error: int = ResourceSaver.save(card, path)
	if error != OK:
		printerr("Failed to save %s (error %d)" % [path, error])
		quit(1)
	else:
		print("  wrote %s" % path)

func _make_jab() -> CardData:
	var card := CardData.new()
	card.id = &"jab"
	card.display_name = "JAB"
	card.cost = BattleConfig.JAB_COST
	card.tags = [&"jab", &"attack"] as Array[StringName]
	card.rules_text = "Deal %d damage." % BattleConfig.JAB_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.JAB_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

func _make_straight() -> CardData:
	var card := CardData.new()
	card.id = &"straight"
	card.display_name = "STRAIGHT"
	card.cost = BattleConfig.STRAIGHT_COST
	card.tags = [&"straight", &"attack"] as Array[StringName]
	card.rules_text = "Deal %d damage." % BattleConfig.STRAIGHT_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.STRAIGHT_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

func _make_block() -> CardData:
	var card := CardData.new()
	card.id = &"block"
	card.display_name = "BLOCK"
	card.cost = BattleConfig.BLOCK_COST
	card.tags = [&"defense"] as Array[StringName]
	card.rules_text = "Gain %d guard." % BattleConfig.BLOCK_GUARD
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.BLOCK_GUARD
	card.effects = [guard] as Array[CardEffect]
	return card
```

- [ ] **Step 4: Run the generator**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/generate_cards.gd
```
Expected: three `wrote res://resources/cards/*.tres` lines, exit 0.

Then confirm the files exist and are non-trivial:
```bash
ls -l resources/cards/ && cat resources/cards/jab.tres
```
Expected: `jab.tres` references `card_data.gd`, embeds a `SubResource` for the `DamageEffect` with `amount = 6`.

- [ ] **Step 5: Write CardLibrary**

Create `scripts/core/card_library.gd`:

```gdscript
class_name CardLibrary
extends RefCounted

## Loads card resources and builds the starting deck.
## Uses load() rather than preload() so this script parses even before the
## generator has produced the .tres files.

const CARD_DIR: String = "res://resources/cards"

static func load_card(card_id: StringName) -> CardData:
	var path: String = "%s/%s.tres" % [CARD_DIR, card_id]
	var resource: Resource = load(path)
	if resource == null:
		push_error("CardLibrary: no card resource at %s" % path)
		return null
	# Duplicate so every deck entry is an independent instance.
	return (resource as CardData).duplicate(true)

static func all_ids() -> Array:
	return BattleConfig.DECK_COMPOSITION.keys()

static func build_starting_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		var copies: int = BattleConfig.DECK_COMPOSITION[card_id]
		for _i: int in range(copies):
			var card: CardData = load_card(card_id)
			if card != null:
				deck.append(card)
	return deck
```

- [ ] **Step 6: Run to verify it passes**

Run the test command. Expected: PASS.

If `duplicate(true)` does not deep-copy the effects array, the "separate instances" check will catch it — fix by duplicating effects explicitly rather than loosening the test.

- [ ] **Step 7: Commit**

```bash
git add tools/ resources/ scripts/core/card_library.gd tests/
git commit -m "feat: generate card resources and add card library"
```

---

### Task 9: Deck

**Files:**
- Create: `scripts/core/deck.gd`
- Create: `tests/suites/test_deck.gd`

**Interfaces:**
- Consumes: `CardData`, `CardLibrary`, `BattleConfig`.
- Produces: `Deck` with `_init(cards: Array[CardData], rng_seed: int = 0)`, public arrays `draw_pile: Array[CardData]`, `hand: Array[CardData]`, `discard_pile: Array[CardData]`, and methods `draw(count: int) -> int` (returns how many were drawn), `discard_hand() -> void`, `take_from_hand(index: int) -> CardData`, `total_cards() -> int`, `reset(cards: Array[CardData]) -> void`.
- RNG is seeded so tests are deterministic. Tests that need a specific hand assign `deck.hand` directly.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_deck.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_initial_state(t)
	_test_draw(t)
	_test_conservation(t)
	_test_reshuffle(t)
	_test_take_from_hand(t)

func _new_deck() -> Deck:
	return Deck.new(CardLibrary.build_starting_deck(), 12345)

func _test_initial_state(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.total_cards(), 12, "deck starts with 12 cards")
	t.check_eq(deck.draw_pile.size(), 12, "all cards start in the draw pile")
	t.check_eq(deck.hand.size(), 0, "hand starts empty")
	t.check_eq(deck.discard_pile.size(), 0, "discard starts empty")

func _test_draw(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	t.check_eq(deck.draw(5), 5, "draw reports how many it drew")
	t.check_eq(deck.hand.size(), 5, "hand holds 5 after a draw")
	t.check_eq(deck.draw_pile.size(), 7, "draw pile drops to 7")
	t.check_eq(deck.total_cards(), 12, "drawing conserves the card count")

func _test_conservation(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	for _turn: int in range(6):
		deck.draw(BattleConfig.HAND_SIZE)
		t.check_eq(deck.total_cards(), 12, "card count stays 12 after drawing")
		deck.discard_hand()
		t.check_eq(deck.total_cards(), 12, "card count stays 12 after discarding")
		t.check_eq(deck.hand.size(), 0, "discard_hand empties the hand")

func _test_reshuffle(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	# Turn 1: 12 -> draw 5 -> draw pile 7, discard 5
	deck.draw(5)
	deck.discard_hand()
	# Turn 2: draw 5 -> draw pile 2, discard 10
	deck.draw(5)
	deck.discard_hand()
	t.check_eq(deck.draw_pile.size(), 2, "draw pile is down to 2 before the reshuffle")
	t.check_eq(deck.discard_pile.size(), 10, "discard has grown to 10")

	# Turn 3: only 2 left, so the discard must reshuffle in to complete the draw.
	t.check_eq(deck.draw(5), 5, "draw completes by reshuffling the discard")
	t.check_eq(deck.hand.size(), 5, "hand is full after the reshuffle")
	t.check_eq(deck.discard_pile.size(), 0, "discard was consumed by the reshuffle")
	t.check_eq(deck.draw_pile.size(), 7, "remaining cards return to the draw pile")
	t.check_eq(deck.total_cards(), 12, "reshuffling conserves the card count")

func _test_take_from_hand(t: TestRunner) -> void:
	var deck: Deck = _new_deck()
	deck.draw(5)
	var card: CardData = deck.take_from_hand(2)
	t.check(card != null, "take_from_hand returns the card")
	t.check_eq(deck.hand.size(), 4, "the card leaves the hand")
	t.check_eq(deck.discard_pile.size(), 1, "the played card goes to the discard")
	t.check_eq(deck.total_cards(), 12, "playing conserves the card count")
	t.check(deck.take_from_hand(99) == null, "an out-of-range index returns null safely")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "Deck" not declared in the current scope`.

- [ ] **Step 3: Write Deck**

Create `scripts/core/deck.gd`:

```gdscript
class_name Deck
extends RefCounted

## Draw pile, hand, and discard. The total card count is invariant: cards only
## ever move between the three piles.

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(cards: Array[CardData], rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	reset(cards)

func reset(cards: Array[CardData]) -> void:
	draw_pile = cards.duplicate()
	hand.clear()
	discard_pile.clear()
	_shuffle(draw_pile)

## Draws up to `count` cards, reshuffling the discard pile if the draw pile
## runs out. Returns how many were actually drawn.
func draw(count: int) -> int:
	var drawn: int = 0
	for _i: int in range(count):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			_reshuffle_discard_into_draw()
		hand.append(draw_pile.pop_back())
		drawn += 1
	return drawn

func discard_hand() -> void:
	for card: CardData in hand:
		discard_pile.append(card)
	hand.clear()

## Removes a card from the hand and sends it to the discard. Returns null if
## the index is out of range.
func take_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var card: CardData = hand[index]
	hand.remove_at(index)
	discard_pile.append(card)
	return card

func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size()

func _reshuffle_discard_into_draw() -> void:
	for card: CardData in discard_pile:
		draw_pile.append(card)
	discard_pile.clear()
	_shuffle(draw_pile)

func _shuffle(pile: Array[CardData]) -> void:
	# Fisher-Yates using the seeded RNG so tests are deterministic.
	for i: int in range(pile.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var temp: CardData = pile[i]
		pile[i] = pile[j]
		pile[j] = temp
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/deck.gd tests/
git commit -m "feat: add deck with draw, discard, and reshuffle"
```

---

### Task 10: EnemyBrain

**Files:**
- Create: `scripts/core/enemy_brain.gd`
- Create: `tests/suites/test_enemy_brain.gd`

**Interfaces:**
- Consumes: `CardEffect`, `DamageEffect`, `GuardEffect`, `ApplyStatusEffect`, `Fighter`, `Combat`, `BattleConfig`.
- Produces: `EnemyBrain` with `enum Action { ATTACK, BLOCK, BUFF }`, `var current_action: Action`, and methods `advance() -> void`, `build_effects() -> Array[CardEffect]`, `intent_text(enemy: Fighter) -> String`, `reset() -> void`.
- The enemy uses the same `CardEffect` classes the player's cards use — there is no separate enemy combat path.
- Intent text is ASCII: `"ATTACK 8"`, `"ATTACK 12"` when buffed, `"BLOCK 8"`, `"BUFF +2 STR"`.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_enemy_brain.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_cycle_order(t)
	_test_effects(t)
	_test_intent_text(t)
	_test_reset(t)

func _test_cycle_order(t: TestRunner) -> void:
	var brain := EnemyBrain.new()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "the enemy opens by attacking")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.BLOCK, "attack is followed by block")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.BUFF, "block is followed by buff")
	brain.advance()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "the cycle wraps back to attack")

func _test_effects(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}

	var brain := EnemyBrain.new()
	# ATTACK
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, 42, "the enemy attack deals 8")

	# BLOCK
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.guard, 8, "the enemy block grants 8 guard")

	# BUFF
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the enemy buff grants 2 strength")

	# The buffed attack, one cycle later.
	brain.advance()
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, 42 - 12, "the attack after a buff deals 12")

func _test_intent_text(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var brain := EnemyBrain.new()
	t.check_eq(brain.intent_text(enemy), "ATTACK 8", "unbuffed attack telegraphs 8")

	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(brain.intent_text(enemy), "ATTACK 12", "a buffed attack telegraphs its real damage")

	brain.advance()
	t.check_eq(brain.intent_text(enemy), "BLOCK 8", "block intent shows the guard amount")
	brain.advance()
	t.check_eq(brain.intent_text(enemy), "BUFF +2 STR", "buff intent shows the strength gain")

func _test_reset(t: TestRunner) -> void:
	var brain := EnemyBrain.new()
	brain.advance()
	brain.advance()
	brain.reset()
	t.check_eq(brain.current_action, EnemyBrain.Action.ATTACK, "reset returns to the start of the cycle")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "EnemyBrain" not declared in the current scope`.

- [ ] **Step 3: Write EnemyBrain**

Create `scripts/core/enemy_brain.gd`:

```gdscript
class_name EnemyBrain
extends RefCounted

## A fixed attack -> block -> buff cycle. The next action is always known, so
## the player can read it before committing to a turn.
##
## Actions are built from the same CardEffect classes the player's cards use —
## the enemy has no separate combat path.

enum Action { ATTACK, BLOCK, BUFF }

const CYCLE: Array = [Action.ATTACK, Action.BLOCK, Action.BUFF]

var current_action: Action = Action.ATTACK

var _index: int = 0

func advance() -> void:
	_index = (_index + 1) % CYCLE.size()
	current_action = CYCLE[_index]

func reset() -> void:
	_index = 0
	current_action = CYCLE[0]

func build_effects() -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	match current_action:
		Action.ATTACK:
			var damage := DamageEffect.new()
			damage.amount = BattleConfig.ENEMY_ATTACK_DAMAGE
			effects.append(damage)
		Action.BLOCK:
			var guard := GuardEffect.new()
			guard.amount = BattleConfig.ENEMY_GUARD_AMOUNT
			effects.append(guard)
		Action.BUFF:
			var buff := ApplyStatusEffect.new()
			buff.status_id = StrengthStatus.ID
			buff.stacks = BattleConfig.ENEMY_BUFF_STRENGTH
			buff.turns = BattleConfig.ENEMY_BUFF_DURATION
			buff.target_self = true
			effects.append(buff)
	return effects

## ASCII only — the default font has no glyphs for sword/shield symbols.
func intent_text(enemy: Fighter) -> String:
	match current_action:
		Action.ATTACK:
			return "ATTACK %d" % Combat.preview_damage(BattleConfig.ENEMY_ATTACK_DAMAGE, enemy)
		Action.BLOCK:
			return "BLOCK %d" % BattleConfig.ENEMY_GUARD_AMOUNT
		Action.BUFF:
			return "BUFF +%d STR" % BattleConfig.ENEMY_BUFF_STRENGTH
	return "?"
```

- [ ] **Step 4: Run to verify it passes**

Run the test command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/enemy_brain.gd tests/
git commit -m "feat: add enemy brain with telegraphed intent cycle"
```

---

### Task 11: BattleState — turn flow, AP, guard timing

**Files:**
- Create: `scripts/core/battle_state.gd`
- Create: `tests/suites/test_battle_turns.gd`

**Interfaces:**
- Consumes: everything from Tasks 2-10.
- Produces: `BattleState` with:
  - Signals: `turn_started(turn_number: int)`, `ap_changed(current: int, maximum: int)`, `hand_changed()`, `card_played(card: CardData, combo_bonus: int)`, `fighters_changed()`, `intent_changed(text: String)`, `log_line(text: String)`, `battle_over(player_won: bool)`.
  - Vars: `player: Fighter`, `enemy: Fighter`, `deck: Deck`, `brain: EnemyBrain`, `turn_number: int`, `ap: int`, `is_over: bool`.
  - Methods: `_init(rng_seed: int = 0)`, `start() -> void`, `can_play(index: int) -> bool`, `play_card(index: int) -> bool`, `end_turn() -> void`, `restart() -> void`, `combo_bonus_for(index: int) -> int`.
- Task 12 adds combo integration, enemy execution, and win/lose to this same file. This task builds the skeleton: turn counter, AP, draw/discard, guard expiry, and an enemy turn that only advances the intent.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_battle_turns.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_start(t)
	_test_turn_counter(t)
	_test_ap(t)
	_test_player_guard_timing(t)
	_test_enemy_guard_timing(t)

func _new_battle() -> BattleState:
	var battle := BattleState.new(12345)
	battle.start()
	return battle

func _test_start(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	t.check_eq(battle.turn_number, 1, "the player's first turn is turn 1")
	t.check_eq(battle.player.hp, 50, "player starts at 50 hp")
	t.check_eq(battle.enemy.hp, 48, "enemy starts at 48 hp")
	t.check_eq(battle.ap, 3, "the player starts with 3 AP")
	t.check_eq(battle.deck.hand.size(), 5, "the opening hand holds 5 cards")
	t.check(not battle.is_over, "the battle is not over at the start")

func _test_turn_counter(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()
	t.check_eq(battle.turn_number, 2, "ending a turn advances the counter once, not twice")
	battle.end_turn()
	battle.end_turn()
	t.check_eq(battle.turn_number, 4, "the counter advances once per full round")

	battle.restart()
	t.check_eq(battle.turn_number, 1, "restart returns to turn 1")

func _test_ap(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Stack a known hand: two straights (2 AP each) and a jab.
	battle.deck.hand = [
		CardLibrary.load_card(&"straight"),
		CardLibrary.load_card(&"straight"),
		CardLibrary.load_card(&"jab"),
	] as Array[CardData]

	t.check(battle.can_play(0), "a 2 AP straight is playable with 3 AP")
	t.check(battle.play_card(0), "playing the straight succeeds")
	t.check_eq(battle.ap, 1, "AP drops from 3 to 1")

	t.check(not battle.can_play(0), "the second straight is unaffordable with 1 AP")
	t.check(not battle.play_card(0), "playing an unaffordable card is refused")
	t.check_eq(battle.ap, 1, "a refused play does not spend AP")

	t.check(battle.play_card(1), "the 1 AP jab is still playable")
	t.check_eq(battle.ap, 0, "AP reaches 0 and never goes negative")

	battle.end_turn()
	t.check_eq(battle.ap, 3, "AP resets to 3 at the start of the next turn")
	t.check_eq(battle.deck.hand.size(), 5, "a fresh hand of 5 is drawn")

func _test_player_guard_timing(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.deck.hand = [CardLibrary.load_card(&"block")] as Array[CardData]
	battle.play_card(0)
	t.check_eq(battle.player.guard, 5, "block grants the player 5 guard")

	battle.end_turn()
	# Guard must have survived the enemy turn and then cleared at the start of
	# the player's new turn. The enemy's opening attack is 8, so 3 gets through.
	t.check_eq(battle.player.hp, 47, "player guard absorbed 5 of the enemy's 8 damage")
	t.check_eq(battle.player.guard, 0, "guard clears at the start of the player's next turn")

func _test_enemy_guard_timing(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()   # enemy attacks, now intends to block
	battle.end_turn()   # enemy blocks -> gains 8 guard
	t.check_eq(battle.enemy.guard, 8, "the enemy has guard up during the player's turn")

	battle.deck.hand = [CardLibrary.load_card(&"jab")] as Array[CardData]
	battle.play_card(0)
	t.check_eq(battle.enemy.guard, 2, "the enemy's guard absorbs the jab")
	t.check_eq(battle.enemy.hp, 48, "the enemy takes no hp damage behind guard")

	battle.end_turn()
	t.check_eq(battle.enemy.guard, 0, "enemy guard clears at the start of its next turn")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "BattleState" not declared in the current scope`.

- [ ] **Step 3: Write BattleState**

Create `scripts/core/battle_state.gd`:

```gdscript
class_name BattleState
extends RefCounted

## The turn state machine and the only thing that mutates the battle. Emits
## signals for the view; never touches the scene tree itself.
##
## Turn order per round:
##   player turn start -> player acts -> player turn end -> enemy turn -> repeat
##
## Guard expires at its owner's turn START (so it survives the opponent's turn).
## Status timers decrement at its owner's turn END.

signal turn_started(turn_number: int)
signal ap_changed(current: int, maximum: int)
signal hand_changed()
signal card_played(card: CardData, combo_bonus: int)
signal fighters_changed()
signal intent_changed(text: String)
signal log_line(text: String)
signal battle_over(player_won: bool)

var player: Fighter
var enemy: Fighter
var deck: Deck
var brain: EnemyBrain
var turn_number: int = 0
var ap: int = 0
var is_over: bool = false

var _combo_rules: Array[ComboRule] = []
var _play_history: Array[CardData] = []
var _rng_seed: int = 0

func _init(rng_seed: int = 0) -> void:
	_rng_seed = rng_seed
	player = Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	enemy = Fighter.new("Enemy", BattleConfig.ENEMY_MAX_HP)
	deck = Deck.new(CardLibrary.build_starting_deck(), rng_seed)
	brain = EnemyBrain.new()
	_combo_rules = [ComboRule.jab_straight()] as Array[ComboRule]

func start() -> void:
	is_over = false
	turn_number = 0
	_begin_player_turn()

func restart() -> void:
	player.reset()
	enemy.reset()
	deck.reset(CardLibrary.build_starting_deck())
	brain.reset()
	start()

## Bonus damage the card at `index` would gain from a combo right now.
func combo_bonus_for(index: int) -> int:
	if index < 0 or index >= deck.hand.size():
		return 0
	var card: CardData = deck.hand[index]
	var best: int = 0
	for rule: ComboRule in _combo_rules:
		best = maxi(best, rule.evaluate(_play_history, card))
	return best

func can_play(index: int) -> bool:
	if is_over:
		return false
	if index < 0 or index >= deck.hand.size():
		return false
	return deck.hand[index].cost <= ap

func play_card(index: int) -> bool:
	if not can_play(index):
		return false

	var bonus: int = combo_bonus_for(index)
	var card: CardData = deck.take_from_hand(index)
	ap -= card.cost

	var context: Dictionary = {"bonus_damage": bonus, "results": [], "log": []}
	for effect: CardEffect in card.effects:
		effect.apply(player, enemy, context)

	_play_history.append(card)
	_emit_log(context)

	card_played.emit(card, bonus)
	ap_changed.emit(ap, BattleConfig.AP_PER_TURN)
	hand_changed.emit()
	fighters_changed.emit()
	return true

func end_turn() -> void:
	if is_over:
		return
	deck.discard_hand()
	player.tick_statuses_turn_end()
	hand_changed.emit()

	_run_enemy_turn()
	if is_over:
		return
	_begin_player_turn()

func _begin_player_turn() -> void:
	turn_number += 1
	player.expire_guard()
	_play_history.clear()
	deck.draw(BattleConfig.HAND_SIZE)
	ap = BattleConfig.AP_PER_TURN

	turn_started.emit(turn_number)
	ap_changed.emit(ap, BattleConfig.AP_PER_TURN)
	hand_changed.emit()
	fighters_changed.emit()
	intent_changed.emit(brain.intent_text(enemy))

func _run_enemy_turn() -> void:
	enemy.expire_guard()
	# Task 12 executes the intent here.
	enemy.tick_statuses_turn_end()
	brain.advance()
	intent_changed.emit(brain.intent_text(enemy))
	fighters_changed.emit()

func _emit_log(context: Dictionary) -> void:
	for line: String in context["log"]:
		log_line.emit(line)
```

- [ ] **Step 4: Run and expect the guard-timing tests to fail**

Run the test command.
Expected: the turn-counter and AP checks PASS; `_test_player_guard_timing` FAILS ("player guard absorbed 5 of the enemy's 8 damage" — expected 47, got 50) and `_test_enemy_guard_timing` FAILS, because `_run_enemy_turn` does not execute the intent yet.

This is expected — Task 12 makes them pass. Record the exact failing checks before moving on.

- [ ] **Step 5: Commit the skeleton**

```bash
git add scripts/core/battle_state.gd tests/
git commit -m "feat: add battle state turn machine with AP and guard timing"
```

---

### Task 12: BattleState — enemy execution, combos, win/lose

**Files:**
- Modify: `scripts/core/battle_state.gd`
- Create: `tests/suites/test_battle_combat.gd`

**Interfaces:**
- Consumes: `BattleState` from Task 11.
- Produces: no new public API — `_run_enemy_turn()` now executes the telegraphed intent, and `_check_battle_over()` ends the battle. The `battle_over(player_won: bool)` signal fires exactly once per battle.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_battle_combat.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_combo_integration(t)
	_test_combo_broken(t)
	_test_buff_timing_across_turns(t)
	_test_win(t)
	_test_loss(t)

func _new_battle() -> BattleState:
	var battle := BattleState.new(12345)
	battle.start()
	return battle

func _stack_hand(battle: BattleState, ids: Array) -> void:
	var hand: Array[CardData] = []
	for card_id: StringName in ids:
		hand.append(CardLibrary.load_card(card_id))
	battle.deck.hand = hand

func _test_combo_integration(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"jab", &"straight"])

	t.check_eq(battle.combo_bonus_for(1), 0, "a straight played first gets no bonus")
	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 42, "the jab deals 6")
	t.check_eq(battle.combo_bonus_for(0), 7, "the straight is now armed for a 7 bonus")

	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 26, "the combo straight deals 16, taking 48 to 26")
	t.check_eq(battle.ap, 0, "the combo consumed all 3 AP")

func _test_combo_broken(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	_stack_hand(battle, [&"jab", &"block", &"straight"])
	battle.play_card(0)   # jab, 1 AP
	battle.play_card(0)   # block, 1 AP — breaks the chain
	t.check_eq(battle.combo_bonus_for(0), 0, "a block between jab and straight breaks the combo")
	battle.play_card(0)   # straight, 1 AP left... refused, costs 2
	t.check_eq(battle.enemy.hp, 42, "only the jab landed; the straight was unaffordable")

	# Verify the break directly with enough AP available.
	var battle2: BattleState = _new_battle()
	_stack_hand(battle2, [&"jab", &"block", &"straight"])
	battle2.ap = 10
	battle2.play_card(0)
	battle2.play_card(0)
	battle2.play_card(0)
	t.check_eq(battle2.enemy.hp, 48 - 6 - 9, "the broken-combo straight deals a plain 9")

func _test_buff_timing_across_turns(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Enemy cycle: turn 1 attack, turn 2 block, turn 3 buff, turn 4 attack.
	battle.end_turn()   # enemy attacks for 8
	t.check_eq(battle.player.hp, 42, "the enemy's opening attack deals 8")

	battle.end_turn()   # enemy blocks
	t.check_eq(battle.player.hp, 42, "a blocking enemy deals no damage")

	battle.end_turn()   # enemy buffs
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the enemy holds 2 strength after buffing")
	t.check_eq(battle.brain.intent_text(battle.enemy), "ATTACK 12", "the telegraph warns of a 12 damage attack")

	battle.end_turn()   # enemy attacks, buffed
	t.check_eq(battle.player.hp, 30, "the buffed attack deals 12")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 0, "strength expires after the attack it paid for")

	battle.end_turn()   # enemy blocks
	battle.end_turn()   # enemy buffs
	battle.end_turn()   # enemy attacks buffed again
	t.check_eq(battle.player.hp, 30 - 12, "the next cycle's buffed attack also deals 12")

func _test_win(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	var won: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: won.append(player_won))

	battle.enemy.hp = 6
	_stack_hand(battle, [&"jab"])
	battle.play_card(0)

	t.check_eq(battle.enemy.hp, 0, "the finishing blow drops the enemy to exactly 0")
	t.check(battle.is_over, "the battle is marked over")
	t.check_eq(won.size(), 1, "battle_over fires exactly once")
	t.check_eq(won[0], true, "the player is reported as the winner")

	t.check(not battle.play_card(0), "cards cannot be played after the battle ends")

func _test_loss(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	var won: Array = []
	battle.battle_over.connect(func(player_won: bool) -> void: won.append(player_won))

	battle.player.hp = 5
	battle.end_turn()   # enemy attacks for 8

	t.check_eq(battle.player.hp, 0, "the player's hp floors at 0")
	t.check(battle.is_over, "the battle is marked over on a loss")
	t.check_eq(won.size(), 1, "battle_over fires exactly once on a loss")
	t.check_eq(won[0], false, "the player is reported as the loser")
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — the enemy-turn checks (`_test_buff_timing_across_turns`, `_test_loss`) fail because the intent is never executed, plus the two guard-timing failures still outstanding from Task 11.

- [ ] **Step 3: Execute the enemy intent and check for a winner**

In `scripts/core/battle_state.gd`, replace `_run_enemy_turn()` with:

```gdscript
func _run_enemy_turn() -> void:
	enemy.expire_guard()

	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	_emit_log(context)

	enemy.tick_statuses_turn_end()
	brain.advance()
	intent_changed.emit(brain.intent_text(enemy))
	fighters_changed.emit()
	_check_battle_over()
```

Add `_check_battle_over()`:

```gdscript
## Ends the battle if either fighter is down. Returns true if it ended.
func _check_battle_over() -> bool:
	if is_over:
		return true
	if not enemy.is_alive():
		is_over = true
		log_line.emit("Enemy is down. You win!")
		battle_over.emit(true)
		return true
	if not player.is_alive():
		is_over = true
		log_line.emit("You are down. You lose.")
		battle_over.emit(false)
		return true
	return false
```

Call it at the end of `play_card()` — after the signals, before `return true`:

```gdscript
	card_played.emit(card, bonus)
	ap_changed.emit(ap, BattleConfig.AP_PER_TURN)
	hand_changed.emit()
	fighters_changed.emit()
	_check_battle_over()
	return true
```

- [ ] **Step 4: Run to verify everything passes**

Run the test command.
Expected: PASS — including the two guard-timing checks from Task 11, which now have a real enemy attack to absorb.

The load-bearing checks: `enemy.hp == 26` after a combo, `player.hp == 30` after the buffed attack, and strength reading 0 immediately after.

- [ ] **Step 5: Commit**

```bash
git add scripts/core/battle_state.gd tests/
git commit -m "feat: execute enemy intents, wire combos, and end the battle"
```

---

### Task 13: CardView and HandView

**Files:**
- Create: `scripts/ui/card_view.gd`
- Create: `scripts/ui/hand_view.gd`
- Create: `tests/suites/test_card_view.gd`

**Interfaces:**
- Consumes: `CardData`, `BattleState`.
- Produces:
  - `CardView extends Button` with `static create(card: CardData) -> CardView`, `configure(card: CardData) -> void`, `set_affordable(value: bool) -> void`, `set_combo_armed(value: bool) -> void`, signal `card_selected(view: CardView)`, and `var card: CardData`.
  - `HandView extends HBoxContainer` with `rebuild(battle: BattleState) -> void`, `refresh_states(battle: BattleState) -> void`, signal `card_chosen(index: int)`.
- Card size 120×170. Colors: attack cards dark red-grey, defense cards dark blue-grey. Unaffordable cards drop to 45% modulate alpha and set `disabled = true`. Combo-armed cards get a gold border.
- The test suite instantiates real `Control` nodes — the test runner is a `SceneTree`, so `root.add_child()` works. Free every node created.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_card_view.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_card_view_text(t)
	_test_affordability(t)
	_test_hand_view_rebuild(t)

func _test_card_view_text(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"jab")
	var view: CardView = CardView.create(card)
	t.check(view != null, "CardView.create returns a view")
	t.check_eq(view.card.id, &"jab", "the view remembers its card")
	var text: String = view.debug_text()
	t.check(text.contains("JAB"), "the card shows its name")
	t.check(text.contains("1 AP"), "the card shows its cost")
	t.check(text.contains("6"), "the card shows its damage")
	view.free()

	var blocker: CardData = CardLibrary.load_card(&"block")
	var block_view: CardView = CardView.create(blocker)
	t.check(block_view.debug_text().contains("5"), "the block card shows its guard value")
	block_view.free()

func _test_affordability(t: TestRunner) -> void:
	var card: CardData = CardLibrary.load_card(&"straight")
	var view: CardView = CardView.create(card)
	view.set_affordable(true)
	t.check(not view.disabled, "an affordable card accepts clicks")
	t.check_eq(view.modulate.a, 1.0, "an affordable card renders at full opacity")

	view.set_affordable(false)
	t.check(view.disabled, "an unaffordable card refuses clicks")
	t.check(view.modulate.a < 1.0, "an unaffordable card is dimmed")
	view.free()

func _test_hand_view_rebuild(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	battle.deck.hand = [
		CardLibrary.load_card(&"jab"),
		CardLibrary.load_card(&"straight"),
	] as Array[CardData]

	var hand := HandView.new()
	hand.rebuild(battle)
	t.check_eq(hand.get_child_count(), 2, "the hand view shows one node per card")

	# 3 AP: both are affordable.
	hand.refresh_states(battle)
	var first: CardView = hand.get_child(0) as CardView
	var second: CardView = hand.get_child(1) as CardView
	t.check(not first.disabled, "the jab is affordable with 3 AP")
	t.check(not second.disabled, "the straight is affordable with 3 AP")

	# 1 AP: the 2-cost straight is not.
	battle.ap = 1
	hand.refresh_states(battle)
	t.check(not first.disabled, "the 1 AP jab stays affordable")
	t.check(second.disabled, "the 2 AP straight is disabled at 1 AP")

	hand.free()
```

- [ ] **Step 2: Run to verify it fails**

Expected: FAIL — `Identifier "CardView" not declared in the current scope`.

- [ ] **Step 3: Write CardView**

Create `scripts/ui/card_view.gd`:

```gdscript
class_name CardView
extends Button

## One card, rendered as a labelled rectangle. Knows how to draw a card and
## report clicks; knows nothing about whether playing it is legal.

signal card_selected(view: CardView)

const CARD_SIZE: Vector2 = Vector2(120, 170)
const ATTACK_COLOR: Color = Color(0.32, 0.16, 0.16)
const DEFENSE_COLOR: Color = Color(0.16, 0.20, 0.32)
const COMBO_BORDER_COLOR: Color = Color(1.0, 0.80, 0.20)
const UNAFFORDABLE_ALPHA: float = 0.45

var card: CardData

var _background: ColorRect
var _name_label: Label
var _cost_label: Label
var _text_label: Label

static func create(p_card: CardData) -> CardView:
	var view := CardView.new()
	view.configure(p_card)
	return view

func _init() -> void:
	custom_minimum_size = CARD_SIZE
	flat = true
	clip_contents = true
	_build()

func _build() -> void:
	_background = ColorRect.new()
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 8
	column.offset_top = 8
	column.offset_right = -8
	column.offset_bottom = -8
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_name_label = _make_label(18)
	column.add_child(_name_label)

	_cost_label = _make_label(14)
	_cost_label.modulate = Color(0.85, 0.85, 0.60)
	column.add_child(_cost_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	_text_label = _make_label(13)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_text_label)

	pressed.connect(_on_pressed)

func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func configure(p_card: CardData) -> void:
	card = p_card
	if card == null:
		return
	_name_label.text = card.display_name
	_cost_label.text = "%d AP" % card.cost
	_text_label.text = _rules_text()
	_background.color = DEFENSE_COLOR if card.has_tag(&"defense") else ATTACK_COLOR
	set_combo_armed(false)

func _rules_text() -> String:
	if not card.rules_text.is_empty():
		return card.rules_text
	var parts: Array[String] = []
	for effect: CardEffect in card.effects:
		var description: String = effect.describe()
		if not description.is_empty():
			parts.append(description)
	return " ".join(parts)

func set_affordable(value: bool) -> void:
	disabled = not value
	modulate.a = 1.0 if value else UNAFFORDABLE_ALPHA

func set_combo_armed(value: bool) -> void:
	if value:
		add_theme_constant_override("outline_size", 3)
		_background.color = _background.color.lerp(COMBO_BORDER_COLOR, 0.25)
	else:
		remove_theme_constant_override("outline_size")
		if card != null:
			_background.color = DEFENSE_COLOR if card.has_tag(&"defense") else ATTACK_COLOR

## Everything the card displays, for tests.
func debug_text() -> String:
	return "%s | %s | %s" % [_name_label.text, _cost_label.text, _text_label.text]

func _on_pressed() -> void:
	card_selected.emit(self)
```

- [ ] **Step 4: Write HandView**

Create `scripts/ui/hand_view.gd`:

```gdscript
class_name HandView
extends HBoxContainer

## The row of cards in hand. Rebuilds from BattleState and reports which index
## was clicked; it does not decide whether the play is legal.

signal card_chosen(index: int)

const CARD_SPACING: int = 12

func _init() -> void:
	add_theme_constant_override("separation", CARD_SPACING)
	alignment = BoxContainer.ALIGNMENT_CENTER

func rebuild(battle: BattleState) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	for index: int in range(battle.deck.hand.size()):
		var view: CardView = CardView.create(battle.deck.hand[index])
		var captured_index: int = index
		view.card_selected.connect(func(_v: CardView) -> void: card_chosen.emit(captured_index))
		add_child(view)

	refresh_states(battle)

## Updates affordability dimming and combo highlights without rebuilding.
func refresh_states(battle: BattleState) -> void:
	for index: int in range(get_child_count()):
		var view: CardView = get_child(index) as CardView
		if view == null:
			continue
		view.set_affordable(battle.can_play(index))
		view.set_combo_armed(battle.combo_bonus_for(index) > 0)
```

- [ ] **Step 5: Run to verify it passes**

Run the test command. Expected: PASS.

Note: `rebuild()` uses `remove_child()` before `queue_free()` so `get_child_count()` is correct immediately, which the test depends on.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/card_view.gd scripts/ui/hand_view.gd tests/
git commit -m "feat: add card and hand views with affordability and combo highlight"
```

---

### Task 14: BattleHud, BattleView, and the playable scene

**Files:**
- Create: `scripts/ui/battle_hud.gd`
- Create: `scripts/ui/battle_view.gd`
- Modify: `level.tscn`

**Interfaces:**
- Consumes: `BattleState`, `HandView`, `CardView`.
- Produces:
  - `BattleHud extends Control` — builds every static element and exposes `update_fighters(battle)`, `update_ap(current, maximum)`, `update_turn(turn_number)`, `update_intent(text)`, `append_log(line)`, `show_result(player_won)`, `hide_result()`, plus signals `end_turn_pressed()` and `restart_pressed()`.
  - `BattleView extends Node2D` — attached to `level.tscn`; owns the `BattleState`, builds the `BattleHud` and `HandView`, wires signals both ways.
- No headless test — this task is verified by launching the game. The rules underneath are already covered by Tasks 2-12.

- [ ] **Step 1: Write BattleHud**

Create `scripts/ui/battle_hud.gd`:

```gdscript
class_name BattleHud
extends Control

## Every static UI element: fighter rectangles, hp/guard/status readouts, turn
## and AP counters, intent, log, buttons, and the result banner.
## Renders what it is told; computes no rules.

signal end_turn_pressed()
signal restart_pressed()

const PLAYER_COLOR: Color = Color(0.20, 0.40, 0.85)
const ENEMY_COLOR: Color = Color(0.85, 0.25, 0.25)
const FIGHTER_SIZE: Vector2 = Vector2(140, 160)
const LOG_LINES: int = 5

var _turn_label: Label
var _intent_label: Label
var _enemy_hp_label: Label
var _enemy_status_label: Label
var _player_hp_label: Label
var _player_status_label: Label
var _ap_label: Label
var _pile_label: Label
var _log_label: Label
var _result_panel: Control
var _result_label: Label

var _log_lines: Array[String] = []

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.09, 0.09, 0.12)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_turn_label = _add_label("TURN 1", Vector2(24, 20), 20)
	_intent_label = _add_label("", Vector2(640, 20), 20)
	_intent_label.modulate = Color(1.0, 0.75, 0.35)

	# Enemy block
	_add_rect(ENEMY_COLOR, Vector2(200, 60))
	_add_label("ENEMY", Vector2(228, 130), 16)
	_enemy_hp_label = _add_label("", Vector2(380, 70), 22)
	_enemy_status_label = _add_label("", Vector2(380, 104), 16)
	_enemy_status_label.modulate = Color(1.0, 0.8, 0.4)

	# Player block
	_add_rect(PLAYER_COLOR, Vector2(60, 250))
	_add_label("PLAYER", Vector2(84, 320), 16)
	_player_hp_label = _add_label("", Vector2(230, 260), 22)
	_player_status_label = _add_label("", Vector2(230, 294), 16)
	_player_status_label.modulate = Color(0.6, 0.9, 1.0)

	_ap_label = _add_label("", Vector2(820, 260), 24)
	_pile_label = _add_label("", Vector2(24, 430), 14)
	_log_label = _add_label("", Vector2(430, 330), 14)
	_log_label.modulate = Color(0.75, 0.75, 0.80)

	var end_turn := Button.new()
	end_turn.text = "END TURN"
	end_turn.position = Vector2(820, 310)
	end_turn.custom_minimum_size = Vector2(160, 44)
	end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	add_child(end_turn)

	_build_result_panel()

func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	add_child(_result_panel)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_result_panel.add_child(dim)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.position = Vector2(430, 240)
	_result_panel.add_child(_result_label)

	var restart := Button.new()
	restart.text = "RESTART"
	restart.position = Vector2(470, 320)
	restart.custom_minimum_size = Vector2(180, 48)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	_result_panel.add_child(restart)

func _add_label(text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _add_rect(color: Color, at: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.position = at
	rect.size = FIGHTER_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect

func update_turn(turn_number: int) -> void:
	_turn_label.text = "TURN %d" % turn_number

func update_intent(text: String) -> void:
	_intent_label.text = "INTENT: %s" % text

func update_ap(current: int, maximum: int) -> void:
	_ap_label.text = "AP  %d / %d" % [current, maximum]

func update_fighters(battle: BattleState) -> void:
	_enemy_hp_label.text = "ENEMY  %d / %d" % [battle.enemy.hp, battle.enemy.max_hp]
	_enemy_status_label.text = _status_line(battle.enemy)
	_player_hp_label.text = "PLAYER  %d / %d" % [battle.player.hp, battle.player.max_hp]
	_player_status_label.text = _status_line(battle.player)
	_pile_label.text = "draw %d    discard %d" % [
		battle.deck.draw_pile.size(), battle.deck.discard_pile.size()
	]

## Guard and statuses, omitted entirely when zero.
func _status_line(fighter: Fighter) -> String:
	var parts: Array[String] = []
	if fighter.guard > 0:
		parts.append("GUARD %d" % fighter.guard)
	for id: StringName in fighter.statuses.ids():
		parts.append("%s %d" % [StatusRegistry.display_name(id), fighter.statuses.get_stacks(id)])
	return "   ".join(parts)

func append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > LOG_LINES:
		_log_lines.pop_front()
	_log_label.text = "\n".join(_log_lines)

func clear_log() -> void:
	_log_lines.clear()
	_log_label.text = ""

func show_result(player_won: bool) -> void:
	_result_label.text = "YOU WIN" if player_won else "YOU LOSE"
	_result_label.modulate = Color(0.5, 1.0, 0.5) if player_won else Color(1.0, 0.5, 0.5)
	_result_panel.visible = true

func hide_result() -> void:
	_result_panel.visible = false
```

- [ ] **Step 2: Write BattleView**

Create `scripts/ui/battle_view.gd`:

```gdscript
class_name BattleView
extends Node2D

## Entry point, attached to level.tscn. Owns the BattleState, builds the UI, and
## translates signals in both directions. It never computes rules.

var battle: BattleState
var hud: BattleHud
var hand_view: HandView

func _ready() -> void:
	battle = BattleState.new()
	_build_ui()
	_connect_battle()
	battle.start()

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	hud = BattleHud.new()
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	layer.add_child(hud)

	hand_view = HandView.new()
	hand_view.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hand_view.offset_top = -200
	hand_view.offset_bottom = -20
	hand_view.card_chosen.connect(_on_card_chosen)
	hud.add_child(hand_view)

func _connect_battle() -> void:
	battle.turn_started.connect(_on_turn_started)
	battle.ap_changed.connect(_on_ap_changed)
	battle.hand_changed.connect(_on_hand_changed)
	battle.fighters_changed.connect(_on_fighters_changed)
	battle.intent_changed.connect(hud.update_intent)
	battle.log_line.connect(hud.append_log)
	battle.battle_over.connect(_on_battle_over)

func _on_turn_started(turn_number: int) -> void:
	hud.update_turn(turn_number)
	hud.append_log("-- Turn %d --" % turn_number)

func _on_ap_changed(current: int, maximum: int) -> void:
	hud.update_ap(current, maximum)
	hand_view.refresh_states(battle)

func _on_hand_changed() -> void:
	hand_view.rebuild(battle)

func _on_fighters_changed() -> void:
	hud.update_fighters(battle)
	hand_view.refresh_states(battle)

func _on_card_chosen(index: int) -> void:
	battle.play_card(index)

func _on_end_turn_pressed() -> void:
	battle.end_turn()

func _on_battle_over(player_won: bool) -> void:
	hud.show_result(player_won)

func _on_restart_pressed() -> void:
	hud.hide_result()
	hud.clear_log()
	battle.restart()
```

- [ ] **Step 3: Attach the script to level.tscn**

Replace the contents of `level.tscn` with (keeping the original `uid`):

```
[gd_scene load_steps=2 format=3 uid="uid://1cx84gr6g02v"]

[ext_resource type="Script" path="res://scripts/ui/battle_view.gd" id="1_battle"]

[node name="Level" type="Node2D"]
script = ExtResource("1_battle")
```

- [ ] **Step 4: Verify the test suite still passes**

Run the test command. Expected: PASS — the UI additions must not have broken any rules test.

- [ ] **Step 5: Launch the game and play a full battle**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Confirm by playing:
- Turn 1 reads `TURN 1`, `AP 3 / 3`, five cards, `INTENT: ATTACK 8`.
- Player is a blue rectangle at 50/50, enemy a red rectangle at 48/48.
- Clicking a jab drops the enemy to 42 and AP to 2; straights in hand gain the gold combo tint.
- Playing that straight deals 16 (enemy to 26), not 9.
- 2-AP straights dim and stop responding once AP is below 2.
- End Turn: the enemy attacks for 8, the log records it, a fresh hand of 5 appears, AP returns to 3.
- By turn 3 the intent reads `BUFF +2 STR`, and the following turn's intent reads `ATTACK 12`.
- Reducing the enemy to 0 shows `YOU WIN`; Restart returns to turn 1 at full HP.

Report anything that does not match rather than adjusting the numbers to fit.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/battle_hud.gd scripts/ui/battle_view.gd level.tscn
git commit -m "feat: add battle HUD and wire the playable scene"
```

---

### Task 15: CLAUDE.md

**Files:**
- Create: `CLAUDE.md`

**Interfaces:**
- Consumes: the finished project.
- Produces: no code. Captures the facts a fresh session cannot derive from reading the source.

- [ ] **Step 1: Write CLAUDE.md**

Create `CLAUDE.md`:

```markdown
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
Exits 0 on pass, 1 on failure. Run this before every commit.

**Never invoke `run_tests.gd` directly — it can report a false PASS.**
GDScript has no catchable exceptions, so a runtime error partway through a
suite (a typo'd call, a null deref) aborts that suite's body while the runner
still prints `PASS` and exits 0; the remaining assertions silently never ran.
The wrapper is what makes the result trustworthy: it fails on engine error
markers (`SCRIPT ERROR`, `Parse Error`, `Invalid call`) as well as on a
non-zero exit code.

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

## Architecture

Two layers, and the boundary is the point:

- `scripts/core/` — pure rules. `RefCounted`/`Resource` only. **Never** reference
  `Node`, `SceneTree`, or any scene-tree API here. If a change seems to need one,
  it belongs in `scripts/ui/`. This is what makes the rules testable headless.
- `scripts/ui/` — rendering and input. Reads state, emits input, computes no rules.

`BattleState` is the only thing that mutates a battle. It emits signals; the view
subscribes. The view never writes to the model.

## How to extend

**Add a card:** author a `.tres` in `resources/cards/` (or add a builder to
`tools/generate_cards.gd` and re-run it), then add its id to
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
No magic numbers anywhere else.

## Timing rules that are easy to get wrong

- **Guard expires at its owner's turn START**, so it survives the opponent's turn.
  Expiring it at the owner's own turn end would make Block a dead card.
- **Status timers decrement at their owner's turn END.** The enemy's 2-turn
  strength buff is therefore live during both the buff turn and the following
  attack, then expires.
- **Combo requires strictly consecutive plays.** Any card in between breaks it.
  The bonus is `floori(sum_of_base_damage * 0.5)`, added to base damage before
  modifiers, and is consumed by the first `DamageEffect` so multi-hit cards
  cannot double-dip.

## Conventions

- Typed GDScript: explicit parameter and return types on every function.
- `PascalCase` class names, `snake_case` members, leading `_` for private.
- Integer helpers: `mini()`, `maxi()`, `floori()` — not the float versions.
- UI text is ASCII. The default font renders no emoji or symbol glyphs, so use
  `ATTACK 12`, not a sword icon.
- Commit Godot's `.uid` sidecars (`<name>.gd.uid`) — project assets, not build
  artifacts. Stage with `git add -A` so none are left untracked; a `.uid`
  tracked on one branch but untracked on another aborts a merge.
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
```

- [ ] **Step 2: Verify the documented commands actually work**

Run each of the three commands from the Commands section verbatim, including the quotes.
Expected: the game launches, the tests report PASS with exit 0, and the generator rewrites three `.tres` files.

A command in CLAUDE.md that has not been run is a guess, not documentation.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md with commands, layer rules, and extension guide"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: constants and cards → Task 2/8; combo → Task 7/12; guard → Task 4/5/11; statuses and strength timing → Task 2/3/12; damage pipeline → Task 5; enemy AI and intent → Task 10; turn structure and turn counter → Task 11; deck flow → Task 9; win/lose/restart → Task 12/14; UI layout → Task 13/14; the 22 spec test cases → distributed across Tasks 2-12; CLAUDE.md → Task 15.

**Deviations from the spec's file list**, both flagged to the user before writing:
1. UI is built in code rather than hand-authored `.tscn`. `level.tscn` keeps its original root node and UID and gains only a script reference. There is no `scenes/card.tscn`; `CardView.create()` replaces it. The core/ui boundary is unchanged.
2. Card `.tres` files are generated by `tools/generate_cards.gd` rather than hand-written, so the resource format is guaranteed valid. They remain ordinary inspector-editable resources.
3. Mockup glyphs `⚔`/`🛡`/`↑` are ASCII (`ATTACK 12`, `BLOCK 8`, `BUFF +2 STR`) because Godot's default font has no glyphs for them.

**Known intentional red flag.** Task 11 Step 4 ends with failing tests, made to pass in Task 12. This is deliberate — `BattleState` is one file with two reviewable halves — and the step says so explicitly with the exact expected failures.

**Type consistency check.** `Deck.take_from_hand` (not `remove_from_hand`) is used consistently in Task 9 and `BattleState.play_card`. `Fighter.apply_hp_loss`/`absorb_into_guard` match their use in `Combat.resolve_damage`. `CardData.has_tag` is defined in Task 6 and used in Tasks 7 and 13. `StatusBag.ids()` is defined in Task 2 and used in Tasks 3 and 14. `Combat.preview_damage` is defined in Task 5 and used in Task 10. `EnemyBrain.build_effects` is named consistently in Tasks 10 and 12. `HandView.refresh_states`/`rebuild` match between Tasks 13 and 14.

**Placeholder scan.** No TBD/TODO, no "add error handling", no "similar to Task N", no "write tests for the above" — every test and implementation step carries its actual code. Every type, method, and signal referenced in a later task is defined in an earlier one.
