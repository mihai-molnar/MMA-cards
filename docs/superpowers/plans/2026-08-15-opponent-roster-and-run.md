# Opponent Roster and Run Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current opponent harder (attack / attack+block / block+buff rotation), then chain a second, harder opponent (the Kickboxer) into a two-fight run with HP carry-over — structured so more opponents and a future Slay-the-Spire-style map slot in without rework.

**Architecture:** Opponents become data (`OpponentData` built in code by `OpponentLibrary` from `BattleConfig` constants — no `.tres`, no generator). `EnemyBrain` shrinks to an interpreter that steps through an opponent's rotation of multi-move turns. A new `RunState` owns what persists across fights (player HP, position in the opponent sequence); `BattleState` stays a single, run-blind battle. `BattleView` owns the `RunState` and builds a fresh `BattleState` per fight, showing an interstitial banner between fights.

**Tech Stack:** Godot 4.5.1, typed GDScript, the project's custom headless test runner (`./tests/run_tests.sh`).

**Spec:** `docs/superpowers/specs/2026-08-15-opponent-roster-and-run-design.md`

## Global Constraints

- The Godot binary path contains a space — always quote it: `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`.
- Run tests ONLY via `./tests/run_tests.sh` (never `run_tests.gd` directly — false PASS risk). Exit 0 + `PASS` = green. The wrapper's `--import` step is what makes new `class_name` globals resolve — a `Identifier "X" not declared` failure right after adding a class means the import didn't run, not a code bug.
- Typed GDScript: explicit parameter and return types on every function.
- `scripts/core/` is `RefCounted`/`Resource` only — never reference `Node`, `SceneTree`, or any scene-tree API there.
- UI text is ASCII only (no emoji/symbol glyphs). Intent strings look like `ATTACK 12`, `BLOCK 8`, `BUFF +2 STR`.
- Every `Button` gets `focus_mode = Control.FOCUS_NONE`.
- Commit with `git add -A` so new `.uid` sidecars (generated on import for each new `.gd`) are staged. End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- No card constants change in this feature — `tools/generate_cards.gd` is never re-run, and `git status` must never show `resources/cards/*.tres` modified.
- All balance numbers live in `scripts/core/battle_config.gd`. Nothing hardcodes them — not even `OpponentLibrary`.
- Test suites live in `tests/suites/test_*.gd`, auto-discovered, and every suite starts with exactly:
  ```gdscript
  extends RefCounted

  const TestRunner := preload("res://tests/run_tests.gd")

  func run(t: TestRunner) -> void:
  ```
  Assertion API: `t.check(condition, message)` and `t.check_eq(actual, expected, message)`.

---

### Task 1: Rename `ENEMY_*` constants to `BRAWLER_*`

The current opponent becomes one of several, so his constants get his name. Purely mechanical; behavior identical; tests stay green throughout.

**Files:**
- Modify: `scripts/core/battle_config.gd:35-39`
- Modify: `scripts/core/enemy_brain.gd` (5 references)
- Modify: `scripts/core/battle_state.gd:37` (1 reference)

**Interfaces:**
- Consumes: nothing new.
- Produces: `BattleConfig.BRAWLER_MAX_HP: int = 48`, `BRAWLER_ATTACK_DAMAGE: int = 8`, `BRAWLER_GUARD_AMOUNT: int = 8`, `BRAWLER_BUFF_STRENGTH: int = 2`, `BRAWLER_BUFF_DURATION: int = 2`. Later tasks reference these exact names. `ENEMY_MAX_HP` is gone; `BattleConfig.PLAYER_MAX_HP` etc. are untouched.

- [ ] **Step 1: Confirm the full set of references**

Run:
```bash
grep -rn "ENEMY_MAX_HP\|ENEMY_ATTACK_DAMAGE\|ENEMY_GUARD_AMOUNT\|ENEMY_BUFF_STRENGTH\|ENEMY_BUFF_DURATION" --include="*.gd" "/Users/mihai/Godot games/mma-cards"
```
Expected hits ONLY in: `scripts/core/battle_config.gd` (definitions), `scripts/core/enemy_brain.gd` (5 uses), `scripts/core/battle_state.gd` (1 use of `ENEMY_MAX_HP`). If any other file appears (a test, a tool), rename it there too in Step 2.

- [ ] **Step 2: Rename definitions and references**

In `scripts/core/battle_config.gd`, replace lines 35-39 with:

```gdscript
const BRAWLER_MAX_HP: int = 48
const BRAWLER_ATTACK_DAMAGE: int = 8
const BRAWLER_GUARD_AMOUNT: int = 8
const BRAWLER_BUFF_STRENGTH: int = 2
## 2 turns means: live during the buff turn AND the following attack turn.
const BRAWLER_BUFF_DURATION: int = 2
```

(`BRAWLER_MAX_HP` moves down here from line 7's `ENEMY_MAX_HP` slot — delete `const ENEMY_MAX_HP: int = 48` from line 7.)

In `scripts/core/enemy_brain.gd`: `ENEMY_ATTACK_DAMAGE` → `BRAWLER_ATTACK_DAMAGE` (2 places), `ENEMY_GUARD_AMOUNT` → `BRAWLER_GUARD_AMOUNT` (2 places), `ENEMY_BUFF_STRENGTH` → `BRAWLER_BUFF_STRENGTH` (2 places), `ENEMY_BUFF_DURATION` → `BRAWLER_BUFF_DURATION` (1 place).

In `scripts/core/battle_state.gd` line 37: `BattleConfig.ENEMY_MAX_HP` → `BattleConfig.BRAWLER_MAX_HP`.

- [ ] **Step 3: Run the full suite**

Run: `./tests/run_tests.sh`
Expected: `644 checks, 0 failures` / `PASS`, exit 0.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Rename ENEMY_* balance constants to BRAWLER_*

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `OpponentMove` and `OpponentData`

The data vocabulary: a move is a labelled bundle of existing `CardEffect`s that can print its own intent telegraph; an opponent is identity + HP + a rotation of turns, each turn a list of moves.

**Files:**
- Create: `scripts/core/opponent_move.gd`
- Create: `scripts/core/opponent_data.gd`
- Test: `tests/suites/test_opponent_data.gd`

**Interfaces:**
- Consumes: `DamageEffect.amount: int`, `GuardEffect.amount: int`, `ApplyStatusEffect.{status_id, stacks, target_self}`, `Combat.preview_damage(base: int, source: Fighter, target: Fighter) -> int`, `StatusRegistry.display_name(id: StringName) -> String`.
- Produces:
  - `OpponentMove.new(label: String, effects: Array[CardEffect])`; fields `label: String`, `effects: Array[CardEffect]`; method `intent_text(enemy: Fighter, target: Fighter) -> String`.
  - `OpponentData.new(id: StringName, display_name: String, max_hp: int, rotation: Array[Array])`; fields `id`, `display_name`, `max_hp`, `rotation` (each element of `rotation` is one turn: a plain `Array` whose elements are `OpponentMove`).

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_opponent_data.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_attack_move_previews_through_the_pipeline(t)
	_test_guard_move_prints_its_amount(t)
	_test_buff_move_prints_stacks_and_keyword(t)
	_test_multi_effect_move_telegraphs_its_damage(t)
	_test_opponent_data_holds_its_rotation(t)

func _attack_move(amount: int) -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = amount
	var effects: Array[CardEffect] = [damage]
	return OpponentMove.new("ATTACK", effects)

func _test_attack_move_previews_through_the_pipeline(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var move := _attack_move(8)
	t.check_eq(move.intent_text(enemy, player), "ATTACK 8", "an unbuffed attack move telegraphs its base damage")

	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(move.intent_text(enemy, player), "ATTACK 12", "a buffed attack move previews through the live damage pipeline")

func _test_guard_move_prints_its_amount(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var guard := GuardEffect.new()
	guard.amount = 8
	var effects: Array[CardEffect] = [guard]
	var move := OpponentMove.new("BLOCK", effects)
	t.check_eq(move.intent_text(enemy, player), "BLOCK 8", "a guard move telegraphs its static amount")

func _test_buff_move_prints_stacks_and_keyword(t: TestRunner) -> void:
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = 2
	buff.turns = 2
	buff.target_self = true
	var effects: Array[CardEffect] = [buff]
	var move := OpponentMove.new("BUFF", effects)
	t.check_eq(move.intent_text(enemy, player), "BUFF +2 STR", "a buff move telegraphs stacks and the status keyword")

func _test_multi_effect_move_telegraphs_its_damage(t: TestRunner) -> void:
	# Shaped like the kickboxer's leg kick: damage plus a debuff on the target.
	var enemy := Fighter.new("Enemy", 48)
	var player := Fighter.new("Player", 50)
	var damage := DamageEffect.new()
	damage.amount = 5
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = 1
	injury.target_self = false
	var effects: Array[CardEffect] = [damage, injury]
	var move := OpponentMove.new("LEG KICK", effects)
	t.check_eq(move.intent_text(enemy, player), "LEG KICK 5", "a damage-plus-debuff move telegraphs label and damage")

func _test_opponent_data_holds_its_rotation(t: TestRunner) -> void:
	var turn_one: Array = [_attack_move(8)]
	var turn_two: Array = [_attack_move(8), _attack_move(8)]
	var rotation: Array[Array] = [turn_one, turn_two]
	var opponent := OpponentData.new(&"test_dummy", "Test Dummy", 40, rotation)
	t.check_eq(opponent.id, &"test_dummy", "OpponentData keeps its id")
	t.check_eq(opponent.display_name, "Test Dummy", "OpponentData keeps its display name")
	t.check_eq(opponent.max_hp, 40, "OpponentData keeps its max hp")
	t.check_eq(opponent.rotation.size(), 2, "OpponentData keeps its rotation")
	t.check_eq((opponent.rotation[1] as Array).size(), 2, "a rotation turn can hold multiple moves")
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/run_tests.sh`
Expected: FAIL — the suite dies loading with `Identifier "OpponentMove" not declared` (reported as a suite-load failure, exit 1). That is the correct failure mode for a missing class.

- [ ] **Step 3: Implement the two classes**

Create `scripts/core/opponent_move.gd`:

```gdscript
class_name OpponentMove
extends RefCounted

## One named enemy action inside a rotation turn: the label the intent
## telegraph prints, plus the CardEffects the action resolves with. The
## enemy has no separate combat path -- these are the same effect classes
## the player's cards use.

var label: String
var effects: Array[CardEffect] = []

func _init(p_label: String, p_effects: Array[CardEffect]) -> void:
	label = p_label
	effects = p_effects

## Telegraph for this move. Damage previews through Combat.preview_damage so
## the telegraph can never diverge from what resolve_damage would produce
## (a Low Kick must halve "ATTACK 8" to "ATTACK 4" in real time). Guard and
## buff amounts are static and print as authored. Priority order: a move
## with any damage telegraphs as damage -- the leg kick reads "LEG KICK 5",
## not as its rider debuff.
func intent_text(enemy: Fighter, target: Fighter) -> String:
	for effect: CardEffect in effects:
		if effect is DamageEffect:
			return "%s %d" % [label, Combat.preview_damage((effect as DamageEffect).amount, enemy, target)]
	for effect: CardEffect in effects:
		if effect is GuardEffect:
			return "%s %d" % [label, (effect as GuardEffect).amount]
	for effect: CardEffect in effects:
		if effect is ApplyStatusEffect:
			var status := effect as ApplyStatusEffect
			return "%s +%d %s" % [label, status.stacks, StatusRegistry.display_name(status.status_id)]
	return label
```

Create `scripts/core/opponent_data.gd`:

```gdscript
class_name OpponentData
extends RefCounted

## One opponent: identity, hit points, and the fixed rotation EnemyBrain
## steps through. `rotation` is an Array of turns; each turn is an Array
## whose elements are OpponentMove, resolved in listed order. Built in code
## by OpponentLibrary -- nothing here is loaded from disk.

var id: StringName
var display_name: String
var max_hp: int
var rotation: Array[Array] = []

func _init(p_id: StringName, p_display_name: String, p_max_hp: int, p_rotation: Array[Array]) -> void:
	id = p_id
	display_name = p_display_name
	max_hp = p_max_hp
	rotation = p_rotation
```

- [ ] **Step 4: Run to verify it passes**

Run: `./tests/run_tests.sh`
Expected: `PASS`, checks count grows by 10 (644 → 654), exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "OpponentMove and OpponentData: the enemy-rotation data vocabulary

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Kickboxer constants, run sequence, and `OpponentLibrary`

The roster: both opponents built in code from `BattleConfig`. The Brawler gets the NEW 3-turn rotation here (nothing consumes the library yet, so the running game is unchanged until Task 4 wires it in).

**Files:**
- Modify: `scripts/core/battle_config.gd` (add kickboxer + run constants after the `BRAWLER_*` block)
- Create: `scripts/core/opponent_library.gd`
- Test: `tests/suites/test_opponent_library.gd`

**Interfaces:**
- Consumes: `OpponentMove`, `OpponentData` (Task 2); `BattleConfig.BRAWLER_*` (Task 1); `LegInjuryStatus.ID`, `StrengthStatus.ID`, `BattleConfig.LEG_INJURY_TURNS`.
- Produces:
  - `BattleConfig.KICKBOXER_MAX_HP: int = 56`, `KICKBOXER_LEG_KICK_DAMAGE: int = 5`, `KICKBOXER_ATTACK_DAMAGE: int = 10`, `KICKBOXER_GUARD_AMOUNT: int = 10`, `KICKBOXER_BUFF_STRENGTH: int = 2`, `KICKBOXER_BUFF_DURATION: int = 2`, `RUN_OPPONENTS: Array[StringName] = [&"brawler", &"kickboxer"]`.
  - `OpponentLibrary.opponent(id: StringName) -> OpponentData` (static; `null` + `push_error` on unknown id).
  - Brawler: id `&"brawler"`, name `"Brawler"`, rotation `[ATTACK] / [ATTACK, BLOCK] / [BLOCK, BUFF]`.
  - Kickboxer: id `&"kickboxer"`, name `"Kickboxer"`, rotation `[LEG KICK] / [ATTACK] / [ATTACK, BLOCK] / [BLOCK, BUFF]`.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_opponent_library.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_brawler_shape(t)
	_test_kickboxer_shape(t)
	_test_leg_kick_composition(t)
	_test_run_sequence(t)

func _labels(turn: Array) -> Array:
	var result: Array = []
	for move: OpponentMove in turn:
		result.append(move.label)
	return result

func _test_brawler_shape(t: TestRunner) -> void:
	var brawler: OpponentData = OpponentLibrary.opponent(&"brawler")
	t.check_eq(brawler.id, &"brawler", "the brawler knows its id")
	t.check_eq(brawler.display_name, "Brawler", "the brawler has a display name")
	t.check_eq(brawler.max_hp, BattleConfig.BRAWLER_MAX_HP, "the brawler's hp comes from BattleConfig")
	t.check_eq(brawler.rotation.size(), 3, "the brawler runs a 3-turn rotation")
	t.check_eq(_labels(brawler.rotation[0]), ["ATTACK"], "turn 1 is a plain attack")
	t.check_eq(_labels(brawler.rotation[1]), ["ATTACK", "BLOCK"], "turn 2 attacks behind a block")
	t.check_eq(_labels(brawler.rotation[2]), ["BLOCK", "BUFF"], "turn 3 blocks and buffs")

func _test_kickboxer_shape(t: TestRunner) -> void:
	var kickboxer: OpponentData = OpponentLibrary.opponent(&"kickboxer")
	t.check_eq(kickboxer.display_name, "Kickboxer", "the kickboxer has a display name")
	t.check_eq(kickboxer.max_hp, BattleConfig.KICKBOXER_MAX_HP, "the kickboxer's hp comes from BattleConfig")
	t.check_eq(kickboxer.rotation.size(), 4, "the kickboxer runs a 4-turn rotation")
	t.check_eq(_labels(kickboxer.rotation[0]), ["LEG KICK"], "the kickboxer opens with the leg kick")
	t.check_eq(_labels(kickboxer.rotation[1]), ["ATTACK"], "turn 2 is a plain attack")
	t.check_eq(_labels(kickboxer.rotation[2]), ["ATTACK", "BLOCK"], "turn 3 attacks behind a block")
	t.check_eq(_labels(kickboxer.rotation[3]), ["BLOCK", "BUFF"], "turn 4 blocks and buffs")

func _test_leg_kick_composition(t: TestRunner) -> void:
	var kickboxer: OpponentData = OpponentLibrary.opponent(&"kickboxer")
	var leg_kick: OpponentMove = kickboxer.rotation[0][0]
	t.check_eq(leg_kick.effects.size(), 2, "the leg kick is damage plus a rider")
	var damage := leg_kick.effects[0] as DamageEffect
	t.check_eq(damage.amount, BattleConfig.KICKBOXER_LEG_KICK_DAMAGE, "the kick's damage comes from BattleConfig")
	var injury := leg_kick.effects[1] as ApplyStatusEffect
	t.check_eq(injury.status_id, LegInjuryStatus.ID, "the rider applies Leg Injury")
	t.check(not injury.target_self, "the injury lands on the TARGET -- the player")
	t.check_eq(injury.turns, BattleConfig.LEG_INJURY_TURNS, "the injury shares the player Low Kick's duration constant")
	t.check(injury.extend_duration, "repeat kicks extend the injury, mirroring the player's Low Kick")

func _test_run_sequence(t: TestRunner) -> void:
	t.check_eq(BattleConfig.RUN_OPPONENTS.size(), 2, "the run is two fights long")
	t.check_eq(BattleConfig.RUN_OPPONENTS[0], &"brawler", "fight 1 is the brawler")
	t.check_eq(BattleConfig.RUN_OPPONENTS[1], &"kickboxer", "fight 2 is the kickboxer")
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/run_tests.sh`
Expected: FAIL — suite-load failure on `Identifier "OpponentLibrary" not declared`, exit 1.

- [ ] **Step 3: Add the constants**

In `scripts/core/battle_config.gd`, directly after the `BRAWLER_*` block:

```gdscript
const KICKBOXER_MAX_HP: int = 56
## The signature move: chip damage plus Leg Injury on the player, mirroring
## the player's own Low Kick (shared LEG_INJURY_* constants keep the mirror
## exact by construction).
const KICKBOXER_LEG_KICK_DAMAGE: int = 5
const KICKBOXER_ATTACK_DAMAGE: int = 10
const KICKBOXER_GUARD_AMOUNT: int = 10
const KICKBOXER_BUFF_STRENGTH: int = 2
const KICKBOXER_BUFF_DURATION: int = 2

## The run: opponent ids fought in order. A future map replaces how the
## next id is chosen (see RunState); this array is the linear placeholder.
const RUN_OPPONENTS: Array[StringName] = [&"brawler", &"kickboxer"]
```

- [ ] **Step 4: Implement `OpponentLibrary`**

Create `scripts/core/opponent_library.gd`:

```gdscript
class_name OpponentLibrary
extends RefCounted

## Builds every opponent in code from BattleConfig constants -- the opponent
## analogue of CardLibrary, minus the .tres step: opponents have no art or
## composed face to bake, so a generator would add nothing.
##
## Adding an opponent: write a _make_*() below, register its id in
## opponent(), add its constants to BattleConfig, and append the id to
## BattleConfig.RUN_OPPONENTS.

static func opponent(id: StringName) -> OpponentData:
	match id:
		&"brawler":
			return _make_brawler()
		&"kickboxer":
			return _make_kickboxer()
	push_error("OpponentLibrary: unknown opponent id %s" % id)
	return null

static func _make_brawler() -> OpponentData:
	var rotation: Array[Array] = [
		[_attack(BattleConfig.BRAWLER_ATTACK_DAMAGE)],
		[_attack(BattleConfig.BRAWLER_ATTACK_DAMAGE), _block(BattleConfig.BRAWLER_GUARD_AMOUNT)],
		[_block(BattleConfig.BRAWLER_GUARD_AMOUNT), _buff(BattleConfig.BRAWLER_BUFF_STRENGTH, BattleConfig.BRAWLER_BUFF_DURATION)],
	]
	return OpponentData.new(&"brawler", "Brawler", BattleConfig.BRAWLER_MAX_HP, rotation)

static func _make_kickboxer() -> OpponentData:
	var rotation: Array[Array] = [
		[_leg_kick()],
		[_attack(BattleConfig.KICKBOXER_ATTACK_DAMAGE)],
		[_attack(BattleConfig.KICKBOXER_ATTACK_DAMAGE), _block(BattleConfig.KICKBOXER_GUARD_AMOUNT)],
		[_block(BattleConfig.KICKBOXER_GUARD_AMOUNT), _buff(BattleConfig.KICKBOXER_BUFF_STRENGTH, BattleConfig.KICKBOXER_BUFF_DURATION)],
	]
	return OpponentData.new(&"kickboxer", "Kickboxer", BattleConfig.KICKBOXER_MAX_HP, rotation)

static func _attack(amount: int) -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = amount
	var effects: Array[CardEffect] = [damage]
	return OpponentMove.new("ATTACK", effects)

static func _block(amount: int) -> OpponentMove:
	var guard := GuardEffect.new()
	guard.amount = amount
	var effects: Array[CardEffect] = [guard]
	return OpponentMove.new("BLOCK", effects)

static func _buff(stacks: int, turns: int) -> OpponentMove:
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = stacks
	buff.turns = turns
	buff.target_self = true
	var effects: Array[CardEffect] = [buff]
	return OpponentMove.new("BUFF", effects)

## The player's own Low Kick, mirrored back: chip damage plus Leg Injury on
## the TARGET. Shares LEG_INJURY_TURNS and extend_duration semantics with
## the player's card so the mirror stays exact by construction.
static func _leg_kick() -> OpponentMove:
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.KICKBOXER_LEG_KICK_DAMAGE
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = BattleConfig.LEG_INJURY_TURNS
	injury.target_self = false
	injury.extend_duration = true
	var effects: Array[CardEffect] = [damage, injury]
	return OpponentMove.new("LEG KICK", effects)
```

- [ ] **Step 5: Run to verify it passes**

Run: `./tests/run_tests.sh`
Expected: `PASS`, checks count grows by 23 (654 → 677), exit 0. `git status` shows no `resources/cards/*.tres` changes.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "OpponentLibrary: brawler and kickboxer rosters from BattleConfig

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `EnemyBrain` becomes a rotation interpreter; `BattleState` takes an opponent

The behavioral switch: the brawler's new rotation goes live, so the two battle suites are updated in the same task. Note the reused-effect subtlety: `OpponentData` holds ONE effect instance per move, applied every cycle — legal because `CardEffect.apply()` never mutates the effect itself, only the fighters and context.

**Files:**
- Modify: `scripts/core/enemy_brain.gd` (full rewrite)
- Modify: `scripts/core/battle_state.gd:34-40` (`_init`)
- Test: `tests/suites/test_enemy_brain.gd` (full rewrite)
- Test: `tests/suites/test_battle_turns.gd` (two functions change)
- Test: `tests/suites/test_battle_combat.gd` (one function changes)

**Interfaces:**
- Consumes: `OpponentData.rotation`, `OpponentMove.{effects, intent_text}`, `OpponentLibrary.opponent()`, `BattleConfig.RUN_OPPONENTS`.
- Produces:
  - `EnemyBrain.new(opponent: OpponentData)`; `advance() -> void`, `reset() -> void`, `build_effects() -> Array[CardEffect]`, `intent_text(enemy: Fighter, target: Fighter) -> String` (multi-move turns join with `" + "`), and NEW `rotation_index() -> int`. `EnemyBrain.Action`, `CYCLE`, and `current_action` are GONE.
  - `BattleState.new(rng_seed: int = 0, opponent: OpponentData = null, starting_hp: int = -1)` — `null` opponent defaults to the first `RUN_OPPONENTS` entry (so every existing `BattleState.new()` / `BattleState.new(seed)` call site still works and still fights the brawler); `starting_hp <= 0` means full HP. The enemy `Fighter` takes `opponent.display_name` and `opponent.max_hp`.

- [ ] **Step 1: Update the tests first (they must fail against the old code)**

Replace the entire contents of `tests/suites/test_enemy_brain.gd` with:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_brawler_cycle_intents(t)
	_test_multi_move_turn_applies_every_effect(t)
	_test_buffed_attack_previews_real_damage(t)
	_test_reset(t)

func _new_brawler_brain() -> EnemyBrain:
	return EnemyBrain.new(OpponentLibrary.opponent(&"brawler"))

func _test_brawler_cycle_intents(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var brain := _new_brawler_brain()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8", "the brawler opens by attacking")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8 + BLOCK 8", "turn two attacks behind a block")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "BLOCK 8 + BUFF +2 STR", "turn three blocks and buffs")
	brain.advance()
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 8", "the cycle wraps back to the opening attack")

func _test_multi_move_turn_applies_every_effect(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var brain := _new_brawler_brain()
	brain.advance()   # ATTACK + BLOCK
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(player.hp, BattleConfig.PLAYER_MAX_HP - 8, "the attack half of the turn lands for 8")
	t.check_eq(enemy.guard, 8, "the block half of the same turn raises 8 guard")

	brain.advance()   # BLOCK + BUFF
	for effect: CardEffect in brain.build_effects():
		effect.apply(enemy, player, context)
	t.check_eq(enemy.guard, 16, "the third turn stacks another 8 guard")
	t.check_eq(enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the third turn also grants 2 strength")

func _test_buffed_attack_previews_real_damage(t: TestRunner) -> void:
	var enemy := Fighter.new("Brawler", BattleConfig.BRAWLER_MAX_HP)
	var player := Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	var brain := _new_brawler_brain()
	enemy.statuses.apply(StrengthStatus.ID, 2, 2)
	t.check_eq(brain.intent_text(enemy, player), "ATTACK 12", "a buffed attack telegraphs its real damage")

func _test_reset(t: TestRunner) -> void:
	var brain := _new_brawler_brain()
	brain.advance()
	brain.advance()
	t.check_eq(brain.rotation_index(), 2, "advance walks the rotation")
	brain.reset()
	t.check_eq(brain.rotation_index(), 0, "reset returns to the top of the rotation")
```

In `tests/suites/test_battle_turns.gd`, replace `_test_enemy_guard_timing` (lines 74-86) with:

```gdscript
func _test_enemy_guard_timing(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	battle.end_turn()   # brawler turn 1: ATTACK
	battle.end_turn()   # brawler turn 2: ATTACK + BLOCK -> gains 8 guard
	t.check_eq(battle.enemy.guard, 8, "the enemy has guard up during the player's turn")

	battle.deck.hand = [CardLibrary.load_card(&"jab")] as Array[CardData]
	battle.play_card(0)
	t.check_eq(battle.enemy.guard, 2, "the enemy's guard absorbs the jab")
	t.check_eq(battle.enemy.hp, 48, "the enemy takes no hp damage behind guard")

	battle.end_turn()   # brawler turn 3: BLOCK + BUFF
	# 8, not 10: the leftover 2 guard expired at the enemy's own turn start
	# (guard never survives into its owner's next turn) before turn 3's
	# fresh block landed. 10 here would mean expiry silently stopped.
	t.check_eq(battle.enemy.guard, 8, "expiry cleared the leftover guard before the fresh block landed")
```

Still in `test_battle_turns.gd`, in `_test_restart_resets_full_state`: replace line 98 with

```gdscript
	t.check_eq(battle.brain.rotation_index(), 2, "the enemy brain advanced past its opening turn before restart")
```

and replace line 123 with

```gdscript
	t.check_eq(battle.brain.rotation_index(), 0, "restart returns the enemy brain to the top of its rotation")
```

Also update the two stale comments on lines 94-95 to `# brawler turn 1: ATTACK` and `# brawler turn 2: ATTACK + BLOCK`.

In `tests/suites/test_battle_combat.gd`, replace `_test_buff_timing_across_turns` (lines 123-143) with:

```gdscript
func _test_buff_timing_across_turns(t: TestRunner) -> void:
	var battle: BattleState = _new_battle()
	# Brawler cycle: 1 ATTACK, 2 ATTACK+BLOCK, 3 BLOCK+BUFF, then wraps.
	battle.end_turn()   # ATTACK 8
	t.check_eq(battle.player.hp, 42, "the brawler's opening attack deals 8")

	battle.end_turn()   # ATTACK 8 + BLOCK 8
	t.check_eq(battle.player.hp, 34, "the second turn's attack also lands for 8")
	t.check_eq(battle.enemy.guard, 8, "the second turn also raises 8 guard")

	battle.end_turn()   # BLOCK 8 + BUFF +2 STR
	t.check_eq(battle.player.hp, 34, "the block-and-buff turn deals no damage")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 2, "the brawler holds 2 strength after buffing")
	t.check_eq(battle.brain.intent_text(battle.enemy, battle.player), "ATTACK 12", "the telegraph warns of a 12 damage attack")

	battle.end_turn()   # ATTACK, buffed: 12
	t.check_eq(battle.player.hp, 22, "the buffed attack deals 12")
	t.check_eq(battle.enemy.statuses.get_stacks(StrengthStatus.ID), 0, "strength expires after the attack it paid for")

	battle.end_turn()   # ATTACK 8 + BLOCK, unbuffed again
	t.check_eq(battle.player.hp, 14, "the following attack is back to a plain 8")

	battle.end_turn()   # BLOCK + BUFF
	battle.end_turn()   # ATTACK, buffed again
	t.check_eq(battle.player.hp, 2, "the next cycle's buffed attack also deals 12")
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `./tests/run_tests.sh`
Expected: FAIL, exit 1 — `test_enemy_brain.gd` fails to load (`EnemyBrain.new()` arity / missing `rotation_index`), and that alone fails the run. Do not worry about counting individual failures here.

- [ ] **Step 3: Rewrite `EnemyBrain`**

Replace the entire contents of `scripts/core/enemy_brain.gd` with:

```gdscript
class_name EnemyBrain
extends RefCounted

## Steps through an OpponentData's fixed rotation. The current turn is
## always known, so the player can read the telegraph before committing.
##
## The rotation's OpponentMoves carry ONE CardEffect instance each, reused
## every cycle -- legal because CardEffect.apply() mutates only the fighters
## and the context, never the effect itself.

var opponent: OpponentData

var _index: int = 0

func _init(p_opponent: OpponentData) -> void:
	opponent = p_opponent

func advance() -> void:
	_index = (_index + 1) % opponent.rotation.size()

func reset() -> void:
	_index = 0

func rotation_index() -> int:
	return _index

func current_moves() -> Array:
	return opponent.rotation[_index]

func build_effects() -> Array[CardEffect]:
	var effects: Array[CardEffect] = []
	for move: OpponentMove in current_moves():
		effects.append_array(move.effects)
	return effects

## ASCII only -- the default font has no glyphs for sword/shield symbols.
## Multi-move turns join with " + ": "ATTACK 8 + BLOCK 8".
func intent_text(enemy: Fighter, target: Fighter) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for move: OpponentMove in current_moves():
		parts.append(move.intent_text(enemy, target))
	return " + ".join(parts)
```

- [ ] **Step 4: Update `BattleState._init`**

In `scripts/core/battle_state.gd`, replace lines 34-40 with:

```gdscript
## `opponent` null means the first opponent of the run -- every pre-run call
## site (and test) that wrote BattleState.new() or BattleState.new(seed)
## keeps working and keeps fighting the brawler. `starting_hp <= 0` means
## full hp; a run passes the carried hp here. Note restart() returns the
## player to FULL hp regardless of starting_hp -- only tests call it; the
## run flow builds a fresh BattleState per fight instead.
func _init(rng_seed: int = 0, opponent: OpponentData = null, starting_hp: int = -1) -> void:
	_rng_seed = rng_seed
	var chosen: OpponentData = opponent if opponent != null else OpponentLibrary.opponent(BattleConfig.RUN_OPPONENTS[0])
	player = Fighter.new("Player", BattleConfig.PLAYER_MAX_HP)
	if starting_hp > 0:
		player.hp = mini(starting_hp, BattleConfig.PLAYER_MAX_HP)
	enemy = Fighter.new(chosen.display_name, chosen.max_hp)
	deck = Deck.new(CardLibrary.build_starting_deck(), rng_seed)
	brain = EnemyBrain.new(chosen)
	_combo_rules = [ComboRule.jab_straight()] as Array[ComboRule]
```

- [ ] **Step 5: Run to verify everything passes**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0. If a `test_battle_*` expectation fails, re-derive by hand against the brawler cycle (turn 1 ATTACK 8, turn 2 ATTACK 8 + BLOCK 8, turn 3 BLOCK 8 + BUFF) before touching any number — the tests above were derived from exactly that cycle and the guard/status timing rules (guard expires at owner's turn START; statuses tick at owner's turn END).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "EnemyBrain interprets OpponentData rotations; brawler's harder cycle goes live

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Kickboxer battle integration — the mirrored Leg Injury

Proves the first *player-owned* timed debuff behaves: applied on the enemy's turn, halves exactly one player turn, expires at the player's own turn end. Also proves combo bonus is added before the injury halves the total.

**Files:**
- Test: `tests/suites/test_battle_combat.gd` (add two functions + register them in `run()`)

**Interfaces:**
- Consumes: `BattleState.new(rng_seed, opponent, starting_hp)` (Task 4), `OpponentLibrary.opponent(&"kickboxer")` (Task 3), existing `_stack_hand` helper in the same suite.
- Produces: nothing new — pure test coverage.

- [ ] **Step 1: Add the failing tests**

In `tests/suites/test_battle_combat.gd`, add to `run()` (after the `_test_low_kicks_stack_duration(t)` line):

```gdscript
	_test_kickboxer_leg_kick_halves_the_players_next_turn(t)
	_test_kickboxer_injury_halves_combo_total(t)
```

Add the functions (after `_test_low_kicks_stack_duration`):

```gdscript
func _new_kickboxer_battle() -> BattleState:
	var battle := BattleState.new(12345, OpponentLibrary.opponent(&"kickboxer"))
	battle.start()
	return battle

## The kickboxer's signature is the player's own Low Kick mirrored back:
## the injury lands on the PLAYER, halves exactly one turn of the player's
## attacks, and expires at the player's own turn end.
func _test_kickboxer_leg_kick_halves_the_players_next_turn(t: TestRunner) -> void:
	var battle: BattleState = _new_kickboxer_battle()
	t.check_eq(battle.enemy.display_name, "Kickboxer", "fight 2's enemy fighter carries the kickboxer's name")
	t.check_eq(battle.enemy.hp, 56, "the kickboxer starts at 56 hp")
	t.check_eq(battle.brain.intent_text(battle.enemy, battle.player), "LEG KICK 5", "the kickboxer telegraphs the opening leg kick")

	battle.end_turn()   # LEG KICK: 5 damage + Leg Injury on the player
	t.check_eq(battle.player.hp, 45, "the leg kick lands for 5")
	t.check(battle.player.statuses.has(&"leg_injury"), "the PLAYER is leg-injured")

	_stack_hand(battle, [&"jab"])
	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 53, "the injured jab deals floori(6 * 0.5) = 3")

	battle.end_turn()   # player turn end ticks the injury away; enemy ATTACK 10
	t.check(not battle.player.statuses.has(&"leg_injury"),
		"the injury expires at the player's own turn end -- exactly one halved turn")
	t.check_eq(battle.player.hp, 35, "the kickboxer's second turn attacks for 10")

	_stack_hand(battle, [&"jab"])
	battle.play_card(0)
	t.check_eq(battle.enemy.hp, 47, "after expiry the jab is back to its full 6")

## The combo bonus is added to base damage BEFORE modifiers, so the injury
## halves the combined total: straight 9 + bonus 7 = 16 -> floori 8.
func _test_kickboxer_injury_halves_combo_total(t: TestRunner) -> void:
	var battle: BattleState = _new_kickboxer_battle()
	battle.end_turn()   # LEG KICK -> the player is injured
	_stack_hand(battle, [&"jab", &"straight"])
	battle.play_card(0)   # injured jab: 3
	battle.play_card(0)   # injured combo straight: floori((9 + 7) * 0.5) = 8
	t.check_eq(battle.enemy.hp, 56 - 3 - 8, "the combo bonus lands before the injury halves the total")
```

- [ ] **Step 2: Run the tests**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0 — Tasks 3-4 already built everything these tests exercise; this task's value is pinning the player-owned-debuff timing so later work cannot break it silently. If any check fails, that is a REAL bug in the effect/status symmetry — debug the code, do not adjust the expected numbers (they follow mechanically from `LEG_INJURY_DAMAGE_MULT = 0.5`, jab 6, straight 9, `COMBO_BONUS_RATIO = 0.5`).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "Pin the kickboxer's mirrored Leg Injury timing in battle tests

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `RunState`

What persists across fights, behind the interface a future map will sit behind.

**Files:**
- Create: `scripts/core/run_state.gd`
- Test: `tests/suites/test_run_state.gd`

**Interfaces:**
- Consumes: `BattleConfig.{PLAYER_MAX_HP, RUN_OPPONENTS}`, `OpponentLibrary.opponent()`, and (in the integration test) `BattleState.new(rng_seed, opponent, starting_hp)`.
- Produces: `RunState.new()`; field `player_hp: int`; methods `current_opponent() -> OpponentData` (null once complete), `fight_number() -> int` (1-based), `record_result(won: bool, remaining_hp: int) -> void`, `is_complete() -> bool`, `reset() -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/suites/test_run_state.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_fresh_run(t)
	_test_victory_advances_and_carries_hp(t)
	_test_defeat_holds_position(t)
	_test_completion(t)
	_test_reset(t)
	_test_hp_carries_into_the_next_battle(t)

func _test_fresh_run(t: TestRunner) -> void:
	var run := RunState.new()
	t.check_eq(run.fight_number(), 1, "a fresh run starts at fight 1")
	t.check_eq(run.player_hp, BattleConfig.PLAYER_MAX_HP, "a fresh run starts at full hp")
	t.check_eq(run.current_opponent().id, &"brawler", "fight 1 is the brawler")
	t.check(not run.is_complete(), "a fresh run is not complete")

func _test_victory_advances_and_carries_hp(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 33)
	t.check_eq(run.fight_number(), 2, "a win advances to the next fight")
	t.check_eq(run.player_hp, 33, "the winner's remaining hp carries forward")
	t.check_eq(run.current_opponent().id, &"kickboxer", "fight 2 is the kickboxer")
	t.check(not run.is_complete(), "the run continues after fight 1")

func _test_defeat_holds_position(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(false, 0)
	t.check_eq(run.fight_number(), 1, "a loss does not advance the run")
	t.check(not run.is_complete(), "a lost run is not complete -- it restarts instead")

func _test_completion(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 20)
	run.record_result(true, 11)
	t.check(run.is_complete(), "beating every opponent completes the run")
	t.check_eq(run.current_opponent(), null, "a complete run has no next opponent")

func _test_reset(t: TestRunner) -> void:
	var run := RunState.new()
	run.record_result(true, 20)
	run.reset()
	t.check_eq(run.fight_number(), 1, "reset returns to fight 1")
	t.check_eq(run.player_hp, BattleConfig.PLAYER_MAX_HP, "reset restores full hp")

func _test_hp_carries_into_the_next_battle(t: TestRunner) -> void:
	var run := RunState.new()
	var first := BattleState.new(12345, run.current_opponent(), run.player_hp)
	first.start()
	first.player.apply_hp_loss(17)
	first.enemy.hp = 1
	first.deck.hand = [CardLibrary.load_card(&"jab")] as Array[CardData]
	first.play_card(0)
	t.check(first.is_over, "the finishing jab ends fight 1")

	run.record_result(true, first.player.hp)
	var second := BattleState.new(12345, run.current_opponent(), run.player_hp)
	second.start()
	t.check_eq(second.player.hp, 33, "fight 2 starts at the carried 33 hp")
	t.check_eq(second.player.max_hp, BattleConfig.PLAYER_MAX_HP, "max hp is unchanged")
	t.check_eq(second.enemy.display_name, "Kickboxer", "fight 2 faces the kickboxer")
	t.check_eq(second.player.guard, 0, "no guard carries between fights")
	t.check_eq(second.player.statuses.get_stacks(StrengthStatus.ID), 0, "no statuses carry between fights")
	t.check_eq(second.deck.total_cards(), 14, "the deck is rebuilt fresh")
	t.check_eq(second.deck.hand.size(), BattleConfig.HAND_SIZE, "a fresh opening hand is drawn")
```

- [ ] **Step 2: Run to verify it fails**

Run: `./tests/run_tests.sh`
Expected: FAIL — suite-load failure on `Identifier "RunState" not declared`, exit 1.

- [ ] **Step 3: Implement `RunState`**

Create `scripts/core/run_state.gd`:

```gdscript
class_name RunState
extends RefCounted

## What persists ACROSS fights: the player's hp and the position in the
## opponent sequence. A battle is BattleState's problem; the run is this
## class's. Today the sequence is a linear walk of
## BattleConfig.RUN_OPPONENTS -- a future Slay-the-Spire-style map replaces
## only HOW the next opponent is chosen; current_opponent(),
## record_result(), is_complete() and reset() are the seam and survive
## unchanged.

var player_hp: int = BattleConfig.PLAYER_MAX_HP

var _fight_index: int = 0

## The opponent the next (or current) battle is fought against; null once
## every opponent is beaten.
func current_opponent() -> OpponentData:
	if is_complete():
		return null
	return OpponentLibrary.opponent(BattleConfig.RUN_OPPONENTS[_fight_index])

## 1-based, for banner text ("FIGHT 2: ...").
func fight_number() -> int:
	return _fight_index + 1

## Called once per battle_over. Carries the survivor's hp either way; only
## a win advances the sequence -- a loss holds position and the view resets
## the whole run instead.
func record_result(won: bool, remaining_hp: int) -> void:
	player_hp = remaining_hp
	if won:
		_fight_index += 1

func is_complete() -> bool:
	return _fight_index >= BattleConfig.RUN_OPPONENTS.size()

func reset() -> void:
	player_hp = BattleConfig.PLAYER_MAX_HP
	_fight_index = 0
```

- [ ] **Step 4: Run to verify it passes**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "RunState: hp carry-over and the linear fight sequence

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: HUD banners, CONTINUE button, and the opponent's name

The presentation vocabulary the run flow needs: three banner modes on the existing result panel, a `continue_pressed` signal, the enemy panel showing the real opponent name, and a wider intent label for multi-move telegraphs.

**Files:**
- Modify: `scripts/ui/fighter_panel.gd` (add two methods after `shake_amplitude`)
- Modify: `scripts/ui/battle_hud.gd` (banner rework, name setter, intent label width, debug hooks)
- Test: `tests/suites/test_battle_hud.gd` (new)

**Interfaces:**
- Consumes: `FighterPanel._name_label` (exists; built in `_build`).
- Produces:
  - `FighterPanel.set_fighter_name(name: String) -> void`, `FighterPanel.fighter_name() -> String`.
  - `BattleHud` signal `continue_pressed()`; methods `show_defeat() -> void`, `show_run_complete() -> void`, `show_fight_intro(fight_number: int, opponent_name: String) -> void` (renders `FIGHT %d: %s` with the name uppercased), `set_enemy_name(name: String) -> void`; `hide_result()` unchanged; **`show_result(player_won)` is REMOVED** (Task 8 removes its only caller — in this task, grep first; if anything besides `BattleView._show_result` calls it, stop and re-plan).
  - Test hooks: `debug_result_text() -> String`, `debug_restart_button() -> Button`, `debug_continue_button() -> Button`, `debug_enemy_panel() -> FighterPanel`.

- [ ] **Step 1: Confirm `show_result`'s callers**

Run:
```bash
grep -rn "show_result\|_intent_label\|intent_label" --include="*.gd" "/Users/mihai/Godot games/mma-cards/scripts" "/Users/mihai/Godot games/mma-cards/tests" "/Users/mihai/Godot games/mma-cards/tools"
```
Expected: `show_result` appears only in `battle_hud.gd` (definition) and `battle_view.gd` (`_show_result` caller); the intent label only inside `battle_hud.gd`. If a test or tool also references them, account for it before proceeding.

- [ ] **Step 2: Write the failing test**

Create `tests/suites/test_battle_hud.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_fight_intro_banner(t)
	_test_defeat_banner(t)
	_test_run_complete_banner(t)
	_test_continue_signal_and_focus(t)
	_test_enemy_name(t)

func _test_fight_intro_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_fight_intro(2, "Kickboxer")
	t.check_eq(hud.debug_result_text(), "FIGHT 2: KICKBOXER", "the intro banner names the coming fight")
	t.check(hud.debug_continue_button().visible, "the intro banner offers CONTINUE")
	t.check(not hud.debug_restart_button().visible, "the intro banner hides RESTART")
	hud.free()

func _test_defeat_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_defeat()
	t.check_eq(hud.debug_result_text(), "YOU LOSE", "the defeat banner reads YOU LOSE")
	t.check(hud.debug_restart_button().visible, "the defeat banner offers RESTART")
	t.check(not hud.debug_continue_button().visible, "the defeat banner hides CONTINUE")
	hud.free()

func _test_run_complete_banner(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.show_run_complete()
	t.check_eq(hud.debug_result_text(), "RUN COMPLETE", "beating the last opponent completes the run")
	t.check(hud.debug_restart_button().visible, "the run-complete banner offers RESTART")
	t.check(not hud.debug_continue_button().visible, "the run-complete banner hides CONTINUE")
	hud.free()

func _test_continue_signal_and_focus(t: TestRunner) -> void:
	var hud := BattleHud.new()
	t.check_eq(hud.debug_continue_button().focus_mode, Control.FOCUS_NONE, "CONTINUE never grabs focus")
	t.check_eq(hud.debug_restart_button().focus_mode, Control.FOCUS_NONE, "RESTART never grabs focus")
	var fired: Array = []
	hud.continue_pressed.connect(func() -> void: fired.append(true))
	hud.debug_continue_button().pressed.emit()
	t.check_eq(fired.size(), 1, "pressing CONTINUE emits continue_pressed")
	hud.free()

func _test_enemy_name(t: TestRunner) -> void:
	var hud := BattleHud.new()
	hud.set_enemy_name("Kickboxer")
	t.check_eq(hud.debug_enemy_panel().fighter_name(), "Kickboxer", "the enemy panel shows the opponent's real name")
	hud.free()
```

- [ ] **Step 3: Run to verify it fails**

Run: `./tests/run_tests.sh`
Expected: FAIL, exit 1 — the suite dies on the missing `show_fight_intro` (an `Invalid call` engine error the wrapper catches, or a suite-load failure).

- [ ] **Step 4: Implement the `FighterPanel` additions**

In `scripts/ui/fighter_panel.gd`, after the `shake_amplitude` static (line 65), add:

```gdscript
## The panel is built once with a placeholder name; the run swaps in each
## opponent's real name at fight start.
func set_fighter_name(name: String) -> void:
	_name_label.text = name

func fighter_name() -> String:
	return _name_label.text
```

- [ ] **Step 5: Implement the `BattleHud` changes**

In `scripts/ui/battle_hud.gd`:

a) Add the signal after `restart_pressed()` (line 9):

```gdscript
signal continue_pressed()
```

b) Add two member vars after `_result_label` (line 65):

```gdscript
var _restart_button: Button
var _continue_button: Button
```

c) Widen the intent label for multi-move telegraphs — replace lines 80-81 (`_intent_label = _add_label(...)` and the size line) with:

```gdscript
	# Wide enough for the longest multi-move telegraph
	# ("INTENT: ATTACK 10 + BLOCK 10") without clipping; right-aligned so
	# growth extends leftward into empty space.
	_intent_label = _add_label("", Vector2(620, 20), 20)
	_intent_label.size = Vector2(500, 28)
```

d) Replace `_build_result_panel` (lines 116-140) with:

```gdscript
func _build_result_panel() -> void:
	_result_panel = Control.new()
	_result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_panel.visible = false
	_result_panel.z_index = RESULT_PANEL_Z
	add_child(_result_panel)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	_result_panel.add_child(dim)

	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	# Full design-space width and centred: banner text now varies in length
	# ("FIGHT 2: KICKBOXER", "RUN COMPLETE"), so a fixed x would park long
	# strings visibly off-centre.
	_result_label.position = Vector2(0, 180)
	_result_label.size = Vector2(1152, 60)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)

	_restart_button = _add_banner_button("RESTART", func() -> void: restart_pressed.emit())
	_continue_button = _add_banner_button("CONTINUE", func() -> void: continue_pressed.emit())

## Both banner buttons share one slot; _show_banner picks which is visible.
func _add_banner_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(476, 260)
	button.custom_minimum_size = Vector2(180, 48)
	# Same reason as End Turn's: no focus, no white focus rectangle.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	_result_panel.add_child(button)
	return button
```

e) Replace `show_result` (lines 193-196) with:

```gdscript
func show_defeat() -> void:
	_show_banner("YOU LOSE", Color(1.0, 0.5, 0.5), _restart_button)

func show_run_complete() -> void:
	_show_banner("RUN COMPLETE", Color(0.5, 1.0, 0.5), _restart_button)

func show_fight_intro(fight_number: int, opponent_name: String) -> void:
	_show_banner("FIGHT %d: %s" % [fight_number, opponent_name.to_upper()],
		Color(1.0, 0.75, 0.35), _continue_button)

func _show_banner(text: String, colour: Color, button: Button) -> void:
	_result_label.text = text
	_result_label.modulate = colour
	_restart_button.visible = button == _restart_button
	_continue_button.visible = button == _continue_button
	_result_panel.visible = true
```

f) Add the name setter and the test hooks after `suppress_enemy_guard_pulse` (line 191):

```gdscript
## The run swaps the real opponent name in at each fight start.
func set_enemy_name(name: String) -> void:
	_enemy_panel.set_fighter_name(name)

## Test hooks -- banner internals the suites assert without walking children.
func debug_result_text() -> String:
	return _result_label.text

func debug_restart_button() -> Button:
	return _restart_button

func debug_continue_button() -> Button:
	return _continue_button

func debug_enemy_panel() -> FighterPanel:
	return _enemy_panel
```

Note: `BattleView._show_result` still calls the now-deleted `show_result` — that call site is replaced in Task 8. The test run below will fail if we leave it, so as a temporary bridge for THIS task only, change `battle_view.gd:202` from `hud.show_result(player_won)` to:

```gdscript
	if player_won:
		hud.show_run_complete()
	else:
		hud.show_defeat()
```

(Behavior-equivalent for the current single battle; Task 8 replaces this whole function with the real run flow.)

- [ ] **Step 6: Run to verify it passes**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "HUD banner modes, CONTINUE button, and real opponent names

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Wire the run into `BattleView`, verify in-game, update docs

The final assembly: `BattleView` owns a `RunState`, builds a fresh `BattleState` per fight, and routes `battle_over` into interstitial / run-complete / defeat. Then the part tests cannot do: play it.

**Files:**
- Modify: `scripts/ui/battle_view.gd`
- Modify: `CLAUDE.md`
- Test: full suite + manual playthrough (no new automated tests — `BattleView` needs a live scene tree, which is exactly why its logic above stays thin: every decision it routes is already tested in `RunState`/`BattleState`/`BattleHud` suites)

**Interfaces:**
- Consumes: `RunState` (Task 6), `BattleState.new(rng_seed, opponent, starting_hp)` (Task 4), `BattleHud.{show_defeat, show_run_complete, show_fight_intro, set_enemy_name, continue_pressed}` (Task 7).
- Produces: the playable two-fight run.

- [ ] **Step 1: Rework `BattleView`**

In `scripts/ui/battle_view.gd`:

a) Add the run field after `var battle: BattleState` (line 7):

```gdscript
var run: RunState
```

b) Replace `_ready` (lines 28-32) with:

```gdscript
func _ready() -> void:
	run = RunState.new()
	_build_ui()
	_start_fight()

## One call per fight: a fresh BattleState against the run's current
## opponent, seeded with the carried hp. The old BattleState (and its
## signal connections) is dropped with the reassignment -- deferred
## timers that fire afterwards re-read `battle` and see the new fight.
func _start_fight() -> void:
	battle = BattleState.new(0, run.current_opponent(), run.player_hp)
	_connect_battle()
	hud.set_enemy_name(battle.enemy.display_name)
	battle.start()
```

c) In `_build_ui`, add the continue connection right after the `hud.restart_pressed.connect(...)` line (line 40):

```gdscript
	hud.continue_pressed.connect(_on_continue_pressed)
```

d) Replace `_on_battle_over`, `_show_result`, and `_on_restart_pressed` (lines 190-211) with:

```gdscript
## The banner waits for the killing blow to land (plus a beat) when the win
## came from a played card -- battle_over is emitted synchronously from
## inside play_card(), while the card has not even left the hand, and a
## banner at that instant hides the entire payoff. RESULT_BEAT stacks on the
## impact delay so this timer always fires after _land_fighter_update's.
## The run records the result immediately (model state, like the battle
## itself); only the banner is deferred.
func _on_battle_over(player_won: bool) -> void:
	run.record_result(player_won, battle.player.hp)
	var delay: float = _pending_reaction_delay
	if delay > 0.0 and is_inside_tree():
		get_tree().create_timer(delay + Juice.RESULT_BEAT).timeout.connect(
			_show_result.bind(player_won))
	else:
		_show_result(player_won)

func _show_result(player_won: bool) -> void:
	# Drop any lifted card before the banner appears, so nothing is left raised
	# behind it.
	hand_view.clear_hover()
	if not player_won:
		hud.show_defeat()
	elif run.is_complete():
		hud.show_run_complete()
	else:
		hud.show_fight_intro(run.fight_number(), run.current_opponent().display_name)
	hand_view.refresh_states(battle)

## CONTINUE: the next fight of the same run, carried hp and all.
func _on_continue_pressed() -> void:
	hud.hide_result()
	_suppress_transition_guard_pulses()
	_start_fight()

## RESTART: the whole run from fight 1 at full hp -- a loss and a completed
## run both land here.
func _on_restart_pressed() -> void:
	hud.hide_result()
	_suppress_transition_guard_pulses()
	run.reset()
	_start_fight()

## A fighter who ends a battle still holding guard would otherwise read the
## fresh fight's zeroed guard as an absorb and pulse. Same reasoning as the
## per-turn expiry suppressions -- a fight boundary is a guard expiry, not
## a block.
func _suppress_transition_guard_pulses() -> void:
	hud.suppress_player_guard_pulse()
	hud.suppress_enemy_guard_pulse()
```

- [ ] **Step 2: Run the full suite**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0. Also run `git status` — `resources/cards/*.tres` must be untouched.

- [ ] **Step 3: Manual playthrough (tests cannot see this)**

Launch the game:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Verify, in order:
1. Fight 1 shows enemy name **Brawler**, intent `ATTACK 8`; second turn's intent reads `ATTACK 8 + BLOCK 8` (not clipped by the label edge); third `BLOCK 8 + BUFF +2 STR`.
2. Playing Low Kick against a telegraphed `ATTACK 8` flips it to `ATTACK 4` as the kick lands (existing behavior survives).
3. Win fight 1 (debug freely — playing badly on purpose also checks the YOU LOSE → RESTART path): the banner reads `FIGHT 2: KICKBOXER`, centred, with a CONTINUE button.
4. CONTINUE: the player's HP bar carries the fight-1 damage; the enemy panel reads **Kickboxer** at 56 HP; opening intent `LEG KICK 5`.
5. After the leg kick lands, the player's panel shows the Leg Injury status (icon badge if `assets/icons/leg_injury.png` exists, text line otherwise) and the player's attacks visibly deal halved damage for that one turn.
6. Win fight 2: banner reads `RUN COMPLETE`; RESTART returns to fight 1, full HP, name **Brawler**.
7. Lose a fight: `YOU LOSE`; RESTART returns to fight 1 at full HP.

If any visual timing looks wrong (banner racing the killing blow, HP dropping while the card is mid-flight), consult "The presentation layer" rules in CLAUDE.md before changing anything — the deferral logic is deliberate and untouched by this plan.

- [ ] **Step 4: Update CLAUDE.md**

Apply these edits (wording may be tightened, content must land):

1. Intro paragraph: replace "Currently a single-battle proof of concept: 14-card deck, 3 AP per turn, jab->straight combo, guard, strength, telegraphed enemy intent." with "Currently a two-fight run: 14-card deck, 3 AP per turn, jab->straight combo, guard, strength, telegraphed enemy intent, HP carried between fights. Fight 1 is the Brawler, fight 2 the harder Kickboxer (who mirrors Low Kick's Leg Injury back at the player)."
2. Architecture section: note the new core classes — `OpponentData`/`OpponentMove` (an opponent as data; moves are labelled bundles of the same `CardEffect`s cards use), `OpponentLibrary` (builds them in code from `BattleConfig`; deliberately no `.tres`/generator step), `EnemyBrain` (now a rotation interpreter, no per-opponent code), `RunState` (owns HP carry-over and the fight sequence; `BattleState` stays run-blind — `battle_over` means "this fight ended"). Document the two map seams: RunState's next-opponent choice and BattleView's between-fight transition.
3. "How to extend": add an "**Add an opponent:**" entry — `_make_*()` in `OpponentLibrary`, constants in `BattleConfig`, id appended to `RUN_OPPONENTS`; never a branch in `BattleState`.
4. "Change balance": note `BRAWLER_*`/`KICKBOXER_*`/`RUN_OPPONENTS` are runtime-read (no regen needed), and that `ENEMY_*` names are gone.
5. Fix the stale guard-pulse sentence: "the two-in-three enemy turns that deal no damage" → "the enemy turns that deal no damage" — and note there is now a fourth suppression moment: the fight/run transition in `BattleView`.
6. "State of the project": single battle → two-fight run with carried HP; the map, card rewards, and deck-building remain the conspicuous absences.
7. Update the expected test count in the Commands section from `644 checks` to the actual number printed by the final `./tests/run_tests.sh` run.

- [ ] **Step 5: Final verification**

Run: `./tests/run_tests.sh`
Expected: `PASS`, exit 0, and the check count matches what Step 4 wrote into CLAUDE.md.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Two-fight run: RunState wiring, fight interstitials, and doc updates

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
