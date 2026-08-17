# Card Rewards, Burn, and Three New Cards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a won fight, a rewards screen offers one of three new cards (One-Two, Strength Up, Prepared) to add to a now-persistent run deck; Strength Up introduces the Burn mechanic with its own HUD pile.

**Architecture:** Pure-rules changes in `scripts/core/` (burn pile in `Deck`, guard-break detection in `Combat`, a turn-start status hook, a run-owned deck, a `RewardPool` seam), rendering in `scripts/ui/` (`RewardsView` modelled on `PileView`, a third HUD pile icon). No card enum branches anywhere: One-Two is a new `CardEffect` subclass, Prepared is a new status, Burn is a `CardData` flag routed inside `Deck`.

**Tech Stack:** Godot 4.5.1, typed GDScript, headless test runner (`./tests/run_tests.sh`).

**Spec:** `docs/superpowers/specs/2026-08-17-card-rewards-and-burn-design.md`

## Global Constraints

- Godot binary path contains a space — always quote: `"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot"`.
- Run tests ONLY via `./tests/run_tests.sh` (never `run_tests.gd` directly). Exit 0 + `PASS` = green. Run before every commit.
- `scripts/core/` never references `Node`/`SceneTree`. All new core files extend `RefCounted` or `Resource`.
- Typed GDScript: explicit parameter and return types on every function. `mini()`/`maxi()`/`floori()`, never float versions.
- Tabs for indentation (match existing files).
- UI text is ASCII only. Every `Button` gets `focus_mode = Control.FOCUS_NONE`.
- Card `.tres` files are BAKED: after editing `tools/generate_cards.gd` or the card constants, re-run the generator (command in Task 4).
- Test suites live in `tests/suites/test_*.gd`, auto-discovered, all starting with the exact preamble (`extends RefCounted`, `const TestRunner := preload("res://tests/run_tests.gd")`, `func run(t: TestRunner) -> void:`).
- Commit with `git add -A` (Godot writes `.uid` sidecars for new `.gd` files; they must be committed).
- Never tween a `CardView`'s live `position`/`rotation`/`scale` from outside it; animation entry points need `is_inside_tree()` guards.
- New `.png` assets: none are added by this plan (placeholder art reuses existing textures).

---

### Task 1: Burn in the deck model

`CardData` gains a `burn` flag; `Deck` gains a fourth pile that burn cards route to when played and that reshuffle never touches.

**Files:**
- Modify: `scripts/core/card_data.gd`
- Modify: `scripts/core/deck.gd`
- Test: `tests/suites/test_deck.gd`

**Interfaces:**
- Produces: `CardData.burn: bool` (export, default `false`); `Deck.burned_pile: Array[CardData]`; `Deck.burn_description() -> String` (static). `Deck.take_from_hand()` routes on `card.burn`. Later tasks rely on exactly these names.

- [ ] **Step 1: Write the failing tests**

Open `tests/suites/test_deck.gd`, add these calls at the end of `run()`:

```gdscript
	_test_burn_card_routes_to_burned_pile(t)
	_test_burned_cards_never_reshuffle(t)
	_test_unplayed_burn_card_discards_normally(t)
	_test_reset_clears_the_burned_pile(t)
```

and these functions at the end of the file:

```gdscript
## A burn card helper: id and flag are all the deck logic reads.
func _burn_card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	card.burn = true
	return card

func _plain_card(card_id: StringName) -> CardData:
	var card := CardData.new()
	card.id = card_id
	card.display_name = String(card_id)
	return card

## Playing a burn card sends it to the burned pile, not the discard, and the
## total across all FOUR piles stays invariant.
func _test_burn_card_routes_to_burned_pile(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember"), _plain_card(&"jab")] as Array[CardData], 7)
	deck.draw(2)
	var burn_index: int = 0 if deck.hand[0].burn else 1
	var taken: CardData = deck.take_from_hand(burn_index)
	t.check(taken.burn, "the taken card is the burn card")
	t.check_eq(deck.burned_pile.size(), 1, "the burn card landed in the burned pile")
	t.check_eq(deck.discard_pile.size(), 0, "the burn card did not land in the discard")
	t.check_eq(deck.total_cards(), 2, "total_cards counts the burned pile")

	var plain_taken: CardData = deck.take_from_hand(0)
	t.check(not plain_taken.burn, "the remaining card is the plain one")
	t.check_eq(deck.discard_pile.size(), 1, "a plain card still routes to the discard")

## Exhausting the draw pile reshuffles the discard only -- a burned card is
## out for the rest of the fight.
func _test_burned_cards_never_reshuffle(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember"), _plain_card(&"jab")] as Array[CardData], 7)
	deck.draw(2)
	deck.take_from_hand(0 if deck.hand[0].burn else 1)
	deck.discard_hand()
	var drawn: int = deck.draw(5)
	t.check_eq(drawn, 1, "only the discarded plain card comes back")
	t.check_eq(deck.hand[0].burn, false, "the burned card stayed out")
	t.check_eq(deck.burned_pile.size(), 1, "the burned pile survived the reshuffle")

## Burn triggers on PLAY. A burn card still in hand at end of turn discards
## normally and can be drawn again.
func _test_unplayed_burn_card_discards_normally(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember")] as Array[CardData], 7)
	deck.draw(1)
	deck.discard_hand()
	t.check_eq(deck.discard_pile.size(), 1, "an unplayed burn card goes to the discard")
	t.check_eq(deck.burned_pile.size(), 0, "nothing burned")
	t.check_eq(deck.draw(1), 1, "and it can be drawn again")

func _test_reset_clears_the_burned_pile(t: TestRunner) -> void:
	var deck := Deck.new([_burn_card(&"ember")] as Array[CardData], 7)
	deck.draw(1)
	deck.take_from_hand(0)
	deck.reset([_plain_card(&"jab")] as Array[CardData])
	t.check_eq(deck.burned_pile.size(), 0, "reset clears the burned pile")
	t.check_eq(deck.total_cards(), 1, "reset leaves only the new cards")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: FAIL — `Invalid access to property or key 'burn'` / `'burned_pile'` markers (the wrapper counts engine errors as failure).

- [ ] **Step 3: Implement**

In `scripts/core/card_data.gd`, after the `tags` export:

```gdscript
## When true, playing this card sends it to the deck's burned pile instead of
## the discard: gone for the rest of the fight (it returns next fight, since
## every fight builds a fresh deck). Burn triggers on PLAY only -- an
## unplayed copy discards normally at end of turn.
@export var burn: bool = false
```

In `scripts/core/deck.gd`: change the class doc comment's first line to
`## Draw pile, hand, discard, and burned pile. The total card count is invariant:`
and `## cards only ever move between the four piles.`; add the pile after `discard_pile`:

```gdscript
## Cards burned out of the fight: played burn cards land here and the
## reshuffle never touches them. Emptied only by reset() -- i.e. next fight.
var burned_pile: Array[CardData] = []
```

In `reset()`, add `burned_pile.clear()` after `discard_pile.clear()`.

Replace `take_from_hand`'s body (keep its doc comment, amend it to mention burn):

```gdscript
## Removes a card from the hand and sends it to the discard -- or to the
## burned pile when the card burns. Returns null if the index is out of range.
func take_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var card: CardData = hand[index]
	hand.remove_at(index)
	if card.burn:
		burned_pile.append(card)
	else:
		discard_pile.append(card)
	return card
```

Update `total_cards()`:

```gdscript
func total_cards() -> int:
	return draw_pile.size() + hand.size() + discard_pile.size() + burned_pile.size()
```

Add at the end of the file (the tooltip body for the Burn keyword, kept in
core beside the rule exactly like `Fighter.guard_description()`):

```gdscript
## The Burn keyword tooltip's body -- kept here, beside the rule it
## describes, the way guard's description lives on Fighter.
static func burn_description() -> String:
	return "Burned when played: removed for the rest of the fight instead of discarded."
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`, check count grew.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Burn mechanic in the deck model: a fourth pile play-routed by CardData.burn"
```

---

### Task 2: Guard-break detection and the One-Two bonus effect

`Combat.DamageResult` learns whether the hit broke guard; a new effect deals bonus damage only on a break.

**Files:**
- Modify: `scripts/core/combat.gd`
- Create: `scripts/core/effects/guard_break_bonus_effect.gd`
- Test: `tests/suites/test_combat.gd`, `tests/suites/test_effects.gd`

**Interfaces:**
- Produces: `Combat.DamageResult.broke_guard: bool`; `GuardBreakBonusEffect extends CardEffect` with `@export var amount: int`, `apply(source, target, context)`, `describe() -> String` returning `"Breaks guard: deal %d damage again." % amount`.

- [ ] **Step 1: Write the failing tests**

In `tests/suites/test_combat.gd`, register `_test_broke_guard(t)` in `run()` and add:

```gdscript
## broke_guard: the target HAD guard and the hit took it to exactly zero. An
## exact soak counts (the guard broke; nothing got through -- yet). No guard
## to begin with is not a break.
func _test_broke_guard(t: TestRunner) -> void:
	var source := Fighter.new("A", 50)

	var unguarded := Fighter.new("B", 50)
	t.check(not Combat.resolve_damage(5, source, unguarded).broke_guard,
		"no guard means no break")

	var high_guard := Fighter.new("B", 50)
	high_guard.add_guard(8)
	t.check(not Combat.resolve_damage(5, source, high_guard).broke_guard,
		"guard surviving the hit is not a break")
	t.check_eq(high_guard.guard, 3, "guard chipped to 3")

	var exact := Fighter.new("B", 50)
	exact.add_guard(5)
	var exact_result: Combat.DamageResult = Combat.resolve_damage(5, source, exact)
	t.check(exact_result.broke_guard, "an exact soak IS a break")
	t.check_eq(exact_result.hp_loss, 0, "the exact soak cost no hp")

	var punched := Fighter.new("B", 50)
	punched.add_guard(3)
	var punched_result: Combat.DamageResult = Combat.resolve_damage(5, source, punched)
	t.check(punched_result.broke_guard, "punching through remaining guard is a break")
	t.check_eq(punched_result.hp_loss, 2, "the overflow hit hp")
```

In `tests/suites/test_effects.gd`, register `_test_guard_break_bonus_effect(t)` in `run()` and add:

```gdscript
## The One-Two mechanic: reads the LAST DamageResult in context["results"];
## a break resolves a second full hit through the same pipeline. No result
## or no break means no bonus hit (fail closed).
func _test_guard_break_bonus_effect(t: TestRunner) -> void:
	var source := Fighter.new("A", 50)
	var effect := GuardBreakBonusEffect.new()
	effect.amount = 5

	# No preceding result at all: nothing happens.
	var empty_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var untouched := Fighter.new("B", 50)
	effect.apply(source, untouched, empty_context)
	t.check_eq(untouched.hp, 50, "no preceding result means no bonus hit")
	t.check_eq((empty_context["results"] as Array).size(), 0, "and no result appended")

	# First hit breaks guard exactly: the bonus hit lands on hp.
	var broken := Fighter.new("B", 50)
	broken.add_guard(5)
	var break_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var first := DamageEffect.new()
	first.amount = 5
	first.apply(source, broken, break_context)
	effect.apply(source, broken, break_context)
	t.check_eq(broken.hp, 45, "the bonus hit landed for its full 5")
	t.check_eq((break_context["results"] as Array).size(), 2, "both hits recorded results")

	# First hit leaves guard standing: one hit only.
	var guarded := Fighter.new("B", 50)
	guarded.add_guard(8)
	var held_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	first.apply(source, guarded, held_context)
	effect.apply(source, guarded, held_context)
	t.check_eq(guarded.hp, 50, "guard held; no bonus hit")
	t.check_eq(guarded.guard, 3, "only the first hit chipped it")

	# Strength boosts BOTH hits -- each resolves through the full pipeline.
	var strong := Fighter.new("A", 50)
	strong.statuses.apply(&"strength", 2, BattleConfig.STATUS_PERMANENT)
	var victim := Fighter.new("B", 50)
	victim.add_guard(7)  # floori(5 * 1.5) = 7 breaks it exactly
	var strong_context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	first.apply(strong, victim, strong_context)
	effect.apply(strong, victim, strong_context)
	t.check_eq(victim.hp, 43, "the boosted bonus hit landed for 7")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: FAIL — `broke_guard` not found / `GuardBreakBonusEffect` not declared. (If the error is `Identifier "GuardBreakBonusEffect" not declared`, remember the wrapper's `--import` resolves new class names only once the file exists — that is the expected failure until Step 3.)

- [ ] **Step 3: Implement**

In `scripts/core/combat.gd`, extend `DamageResult`:

```gdscript
class DamageResult extends RefCounted:
	var raw: int = 0
	var absorbed: int = 0
	var hp_loss: int = 0
	## The hit took the target's guard from above zero to exactly zero. An
	## exact soak counts -- the guard broke even though nothing got through.
	var broke_guard: bool = false

	func _init(p_raw: int, p_absorbed: int, p_hp_loss: int, p_broke_guard: bool = false) -> void:
		raw = p_raw
		absorbed = p_absorbed
		hp_loss = p_hp_loss
		broke_guard = p_broke_guard
```

In `resolve_damage`, capture guard state around the absorb:

```gdscript
	var had_guard: bool = target.guard > 0
	var absorbed: int = target.absorb_into_guard(amount)
	var hp_loss: int = target.apply_hp_loss(amount - absorbed)
	return DamageResult.new(amount, absorbed, hp_loss, had_guard and target.guard == 0)
```

Create `scripts/core/effects/guard_break_bonus_effect.gd`:

```gdscript
class_name GuardBreakBonusEffect
extends CardEffect

## One-Two's second hit: lands only if the PRECEDING DamageEffect broke the
## target's guard (see Combat.DamageResult.broke_guard). Reads the last
## result in context["results"]; no preceding result means no bonus hit
## (fail closed, like ApplyStatusEffect.require_hp_damage). Deliberately NOT
## a DamageEffect subclass: total_base_damage() must not count a conditional
## hit (combo math would see a phantom double), and the first-DamageEffect-
## consumes-the-combo-bonus rule stays untouched. The bonus hit resolves
## through the full pipeline, so strength boosts it like any other hit.

@export var amount: int = 0

func apply(source: Fighter, target: Fighter, context: Dictionary) -> void:
	var results: Array = context["results"]
	var last_result: Combat.DamageResult = results.back() if not results.is_empty() else null
	if last_result == null or not last_result.broke_guard:
		return
	var result: Combat.DamageResult = Combat.resolve_damage(amount, source, target)
	context["results"].append(result)
	context["log"].append("%s breaks through for %d more damage" % [source.display_name, result.raw])

func describe() -> String:
	return "Breaks guard: deal %d damage again." % amount
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Guard-break detection and GuardBreakBonusEffect for One-Two"
```

---

### Task 3: Turn-start status hook and the Prepared status

Statuses gain a third mandatory static, `on_turn_start`; `BattleState` fires it after guard expiry on both sides; Prepared uses it to pay out delayed guard once.

**Files:**
- Modify: `scripts/core/status_bag.gd`, `scripts/core/statuses/strength.gd`, `scripts/core/statuses/leg_injury.gd`, `scripts/core/status_registry.gd`, `scripts/core/battle_state.gd`
- Create: `scripts/core/statuses/prepared.gd`
- Test: `tests/suites/test_status_bag.gd`, `tests/suites/test_status_registry.gd`, `tests/suites/test_battle_turns.gd`

**Interfaces:**
- Produces: `StatusBag.remove(id: StringName) -> void`; every status definition's `static func on_turn_start(fighter: Fighter, stacks: int) -> bool` (return `true` = consumed); `StatusRegistry.apply_turn_start(fighter: Fighter) -> void`; `PreparedStatus` with `ID = &"prepared"`, `DISPLAY_NAME = "Prepared"`, `SHOW_TURNS = false`. Task 4's generator uses `PreparedStatus.ID`.
- Consumes: `Fighter.add_guard(amount)`, `Fighter.expire_guard()` (existing).

- [ ] **Step 1: Write the failing tests**

`tests/suites/test_status_bag.gd` — register `_test_remove(t)` in `run()`, add:

```gdscript
func _test_remove(t: TestRunner) -> void:
	var bag := StatusBag.new()
	bag.apply(&"prepared", 4, 2)
	bag.remove(&"prepared")
	t.check(not bag.has(&"prepared"), "remove erases the status")
	bag.remove(&"prepared")
	t.check(not bag.has(&"prepared"), "removing an absent status is safe")
```

`tests/suites/test_status_registry.gd` — register `_test_turn_start_hook(t)` in `run()`, add:

```gdscript
## The third mandatory status static: on_turn_start(fighter, stacks) -> bool,
## called for every active status at its owner's turn start (after guard
## expiry); returning true consumes the status. Prepared pays its stacks out
## as guard exactly once; the damage-modifier statuses pass through.
func _test_turn_start_hook(t: TestRunner) -> void:
	var fighter := Fighter.new("A", 50)
	fighter.statuses.apply(PreparedStatus.ID, 4, BattleConfig.PREPARED_STATUS_TURNS)
	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.guard, 4, "prepared paid its stacks out as guard")
	t.check(not fighter.statuses.has(PreparedStatus.ID), "prepared consumed itself")

	StatusRegistry.apply_turn_start(fighter)
	t.check_eq(fighter.guard, 4, "a second turn start pays nothing more")

	# Pass-through statuses survive the hook untouched.
	var buffed := Fighter.new("B", 50)
	buffed.statuses.apply(&"strength", 2, 2)
	buffed.statuses.apply(&"leg_injury", 1, 1)
	StatusRegistry.apply_turn_start(buffed)
	t.check(buffed.statuses.has(&"strength"), "strength is not consumed by turn start")
	t.check(buffed.statuses.has(&"leg_injury"), "leg injury is not consumed by turn start")
	t.check_eq(buffed.guard, 0, "pass-through statuses grant nothing")

	# Registry metadata for the new status.
	t.check_eq(StatusRegistry.display_name(PreparedStatus.ID), "Prepared", "display name registered")
	t.check(not StatusRegistry.shows_turns(PreparedStatus.ID),
		"prepared shows its magnitude (the pending guard), not a countdown")
	t.check(StatusRegistry.description(PreparedStatus.ID).length() > 0, "prepared describes itself")
```

`tests/suites/test_battle_turns.gd` — register `_test_prepared_pays_out_at_next_turn_start(t)` and `_test_enemy_turn_start_fires_the_hook(t)` in `run()`, add:

```gdscript
## Prepared's full lifecycle inside a real battle: +4 guard now; at the NEXT
## player turn start the old guard expires FIRST, then the payout lands --
## the second 4 never stacks on leftovers of the first. Effects are applied
## directly (exactly what play_card does) so the test needs no card in hand.
func _test_prepared_pays_out_at_next_turn_start(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	var context: Dictionary = {"bonus_damage": 0, "results": [], "log": []}
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.PREPARED_GUARD
	guard.apply(battle.player, battle.enemy, context)
	var status := ApplyStatusEffect.new()
	status.status_id = PreparedStatus.ID
	status.stacks = BattleConfig.PREPARED_GUARD
	status.turns = BattleConfig.PREPARED_STATUS_TURNS
	status.target_self = true
	status.apply(battle.player, battle.enemy, context)

	t.check_eq(battle.player.guard, BattleConfig.PREPARED_GUARD, "the immediate guard landed")
	t.check(battle.player.statuses.has(PreparedStatus.ID), "the delayed grant is pending")

	battle.end_turn()

	# New player turn: expiry zeroed the old guard, then the payout granted
	# exactly PREPARED_GUARD -- whatever the enemy chipped off in between.
	t.check_eq(battle.player.guard, BattleConfig.PREPARED_GUARD,
		"payout lands AFTER expiry: exactly the delayed amount, no leftovers")
	t.check(not battle.player.statuses.has(PreparedStatus.ID), "the status consumed itself")

## The hook is symmetric: an enemy status pays out at the ENEMY's turn start
## (inside end_turn, after enemy.expire_guard()). The final guard assertion
## leans on the brawler's FIXED rotation (seed-independent): turn 1 is an
## attack with no block move, so the payout's 4 guard survives the enemy
## turn intact.
func _test_enemy_turn_start_fires_the_hook(t: TestRunner) -> void:
	var battle := BattleState.new(12345)
	battle.start()
	battle.enemy.statuses.apply(PreparedStatus.ID, 4, BattleConfig.PREPARED_STATUS_TURNS)
	battle.end_turn()
	t.check(not battle.enemy.statuses.has(PreparedStatus.ID),
		"the enemy's prepared status was consumed at its turn start")
	t.check_eq(battle.enemy.guard, 4,
		"the enemy's payout granted its guard (brawler turn 1 adds no guard of its own)")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh`
Expected: FAIL — `PreparedStatus` not declared / `remove` not found / `PREPARED_STATUS_TURNS` not found. Note `BattleConfig.PREPARED_STATUS_TURNS` is added HERE (not Task 4) because these tests need it.

- [ ] **Step 3: Implement**

`scripts/core/battle_config.gd` — add (near the other card constants; the full reward-card block comes in Task 4, this constant just lands first):

```gdscript
## Lifecycle ceiling for the Prepared status: applied mid-turn, it must
## survive its owner's turn-end tick (2 -> 1) to still be alive at the next
## turn start, where the payout consumes it. The hook consumption is the
## real lifecycle; this is the belt-and-braces bound. Not a balance knob.
const PREPARED_STATUS_TURNS: int = 2
```

`scripts/core/status_bag.gd` — add:

```gdscript
func remove(id: StringName) -> void:
	_entries.erase(id)
```

`scripts/core/statuses/strength.gd` and `scripts/core/statuses/leg_injury.gd` — add to EACH (and amend each file's "must provide" doc comment to say "ID, DISPLAY_NAME, description() and all THREE statics"):

```gdscript
## Pass-through: nothing happens at turn start and the status is kept.
static func on_turn_start(_fighter: Fighter, _stacks: int) -> bool:
	return false
```

Create `scripts/core/statuses/prepared.gd`:

```gdscript
class_name PreparedStatus
extends RefCounted

## Delayed guard, made visible: the stacks are the guard amount granted at
## the owner's NEXT turn start -- after the old guard expires, so the payout
## never stacks on leftovers. on_turn_start returns true, consuming the
## status: it pays out exactly once and the chip disappears. Every status
## definition must provide ID, DISPLAY_NAME, description() and all THREE
## statics -- StatusRegistry calls them unconditionally.

const ID: StringName = &"prepared"
const DISPLAY_NAME: String = "Prepared"
## The interesting number is the pending guard magnitude; the payout moment
## is fixed (next turn start), not a countdown worth printing.
const SHOW_TURNS: bool = false

static func description() -> String:
	return "Gains its stacks as guard at the start of its owner's next turn, after the old guard expires."

static func modify_outgoing_damage(amount: int, _stacks: int) -> int:
	return amount

static func modify_incoming_damage(amount: int, _stacks: int) -> int:
	return amount

static func on_turn_start(fighter: Fighter, stacks: int) -> bool:
	fighter.add_guard(stacks)
	return true
```

`scripts/core/status_registry.gd` — register it and add the driver:

```gdscript
const DEFINITIONS: Dictionary = {
	&"strength": preload("res://scripts/core/statuses/strength.gd"),
	&"leg_injury": preload("res://scripts/core/statuses/leg_injury.gd"),
	&"prepared": preload("res://scripts/core/statuses/prepared.gd"),
}
```

```gdscript
## Fires every active status's on_turn_start at its owner's turn start
## (BattleState calls this immediately after expire_guard(), on both sides).
## A hook returning true is consumed -- removed from the bag. ids() returns
## a copy of the keys, so removing while iterating is safe.
static func apply_turn_start(fighter: Fighter) -> void:
	for id: StringName in fighter.statuses.ids():
		if not DEFINITIONS.has(id):
			continue
		var definition: GDScript = DEFINITIONS[id]
		if definition.on_turn_start(fighter, fighter.statuses.get_stacks(id)):
			fighter.statuses.remove(id)
```

`scripts/core/battle_state.gd` — two one-line additions. In `_begin_player_turn`, directly after `player.expire_guard()`:

```gdscript
	StatusRegistry.apply_turn_start(player)
```

In `_run_enemy_turn`, directly after `enemy.expire_guard()`:

```gdscript
	StatusRegistry.apply_turn_start(enemy)
```

Also extend the class doc comment's timing note: after the guard-expiry line, add `## Turn-start status hooks (Prepared's delayed guard) fire right after that expiry.`

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Turn-start status hook; Prepared status pays out delayed guard once"
```

---

### Task 4: The three cards — constants, generator, resources

Constants into `BattleConfig`, three `_make_*()` functions into the generator, regenerate, pin the `.tres` values in tests.

**Files:**
- Modify: `scripts/core/battle_config.gd`, `tools/generate_cards.gd`
- Create (generated): `resources/cards/one_two.tres`, `resources/cards/strength_up.tres`, `resources/cards/prepared.tres`
- Test: `tests/suites/test_card_library.gd`

**Interfaces:**
- Consumes: `GuardBreakBonusEffect` (Task 2), `PreparedStatus.ID` / `BattleConfig.PREPARED_STATUS_TURNS` (Task 3), `CardData.burn` (Task 1).
- Produces: loadable cards `&"one_two"`, `&"strength_up"`, `&"prepared"`; `BattleConfig.ONE_TWO_COST/ONE_TWO_DAMAGE/STRENGTH_UP_COST/STRENGTH_UP_STACKS/PREPARED_COST/PREPARED_GUARD/REWARD_CARDS`.

- [ ] **Step 1: Write the failing tests**

In `tests/suites/test_card_library.gd`, register in `run()`:

```gdscript
	_test_reward_cards_load(t)
	_test_reward_cards_stay_out_of_the_starting_deck(t)
```

Add:

```gdscript
## The three reward cards, pinned against BattleConfig exactly like the
## starting four -- the .tres files are baked, and this is the guard that
## catches an edited constant with a forgotten regen.
func _test_reward_cards_load(t: TestRunner) -> void:
	var one_two: CardData = CardLibrary.load_card(&"one_two")
	t.check(one_two != null, "one_two.tres loads")
	t.check_eq(one_two.cost, BattleConfig.ONE_TWO_COST, "one-two costs BattleConfig.ONE_TWO_COST AP")
	t.check_eq(one_two.total_base_damage(), BattleConfig.ONE_TWO_DAMAGE,
		"one-two's BASE damage counts the first hit only -- the conditional hit must not feed combo math")
	t.check_eq(one_two.effects.size(), 2, "one-two: a damage effect and the break bonus")
	var bonus: GuardBreakBonusEffect = one_two.effects[1] as GuardBreakBonusEffect
	t.check(bonus != null, "one-two's second effect is the guard-break bonus")
	t.check_eq(bonus.amount, BattleConfig.ONE_TWO_DAMAGE, "the bonus hit deals the same 5")
	t.check(not one_two.burn, "one-two does not burn")

	var strength_up: CardData = CardLibrary.load_card(&"strength_up")
	t.check_eq(strength_up.cost, BattleConfig.STRENGTH_UP_COST, "strength up costs 0 AP")
	t.check(strength_up.burn, "strength up burns")
	t.check_eq(strength_up.effects.size(), 1, "strength up has one effect")
	var buff: ApplyStatusEffect = strength_up.effects[0] as ApplyStatusEffect
	t.check(buff != null, "strength up applies a status")
	t.check_eq(buff.status_id, &"strength", "the status is strength")
	t.check_eq(buff.stacks, BattleConfig.STRENGTH_UP_STACKS, "it grants STRENGTH_UP_STACKS stacks")
	t.check_eq(buff.turns, BattleConfig.STATUS_PERMANENT, "the strength is permanent for the fight")
	t.check(buff.target_self, "it buffs the player, not the enemy")
	t.check(strength_up.rules_text.contains("Burn"),
		"strength up's rules text names the Burn keyword")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	t.check_eq(prepared.cost, BattleConfig.PREPARED_COST, "prepared costs 1 AP")
	t.check_eq(prepared.total_guard(), BattleConfig.PREPARED_GUARD,
		"prepared's immediate guard is PREPARED_GUARD")
	t.check(prepared.has_tag(&"defense"), "prepared is a defense card (blue frame)")
	t.check_eq(prepared.effects.size(), 2, "prepared: immediate guard plus the delayed status")
	var delayed: ApplyStatusEffect = prepared.effects[1] as ApplyStatusEffect
	t.check(delayed != null, "prepared's second effect applies a status")
	t.check_eq(delayed.status_id, PreparedStatus.ID, "the status is prepared")
	t.check_eq(delayed.stacks, BattleConfig.PREPARED_GUARD, "the delayed guard equals the immediate one")
	t.check_eq(delayed.turns, BattleConfig.PREPARED_STATUS_TURNS, "with the lifecycle-ceiling duration")
	t.check(delayed.target_self, "the delayed guard is the player's own")

func _test_reward_cards_stay_out_of_the_starting_deck(t: TestRunner) -> void:
	t.check_eq(CardLibrary.build_starting_deck().size(), 14,
		"the starting deck is unchanged -- reward cards enter only via the rewards screen")
	for card_id: StringName in BattleConfig.REWARD_CARDS:
		t.check(not BattleConfig.DECK_COMPOSITION.has(card_id),
			"%s is not in DECK_COMPOSITION" % card_id)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh` — expected: FAIL (`no card resource at res://resources/cards/one_two.tres`, missing constants).

- [ ] **Step 3: Implement — constants**

`scripts/core/battle_config.gd`, after the `LEG_INJURY_*` block:

```gdscript
## Reward cards: offered by the rewards screen after a won fight, never in
## the starting deck. Baked into resources/cards/*.tres like every per-card
## constant above -- re-run tools/generate_cards.gd after editing.
const ONE_TWO_COST: int = 1
## Per hit: the base jab-cross, and the bonus cross again if the first hit
## breaks the target's guard.
const ONE_TWO_DAMAGE: int = 5
const STRENGTH_UP_COST: int = 0
const STRENGTH_UP_STACKS: int = 2
const PREPARED_COST: int = 1
## Both the immediate grant and the delayed one.
const PREPARED_GUARD: int = 4
```

And near `RUN_OPPONENTS` (live-read, no regen):

```gdscript
## The rewards screen's pool, in display order. Live-read like RUN_OPPONENTS
## -- no regen step. Today the whole pool is offered every time; a random
## draw from a larger pool later changes RewardPool, not this list's readers.
const REWARD_CARDS: Array[StringName] = [&"one_two", &"strength_up", &"prepared"]
```

- [ ] **Step 4: Implement — generator**

`tools/generate_cards.gd`: in `_initialize()` add after `_save(_make_low_kick())`:

```gdscript
	_save(_make_one_two())
	_save(_make_strength_up())
	_save(_make_prepared())
```

Change the count line to `print("Generated 7 card resources in %s" % OUTPUT_DIR)`. Add the three makers:

```gdscript
func _make_one_two() -> CardData:
	var card := CardData.new()
	card.id = &"one_two"
	card.display_name = "ONE-TWO"
	card.cost = BattleConfig.ONE_TWO_COST
	card.tags = [&"attack"] as Array[StringName]
	# Both 5s are damage numbers (red): _number_color checks "damage" before
	# "guard", so the second sentence's number reads as the hit it is, not as
	# a guard grant. The break rule itself lives in the effect.
	card.rules_text = "Deal %d damage. Breaks guard: deal %d damage again." % [
		BattleConfig.ONE_TWO_DAMAGE, BattleConfig.ONE_TWO_DAMAGE]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.ONE_TWO_DAMAGE
	var bonus := GuardBreakBonusEffect.new()
	bonus.amount = BattleConfig.ONE_TWO_DAMAGE
	card.effects = [damage, bonus] as Array[CardEffect]
	return card

func _make_strength_up() -> CardData:
	var card := CardData.new()
	card.id = &"strength_up"
	card.display_name = "STRENGTH UP"
	card.cost = BattleConfig.STRENGTH_UP_COST
	# Not tagged defense: a damage buff wears the ATTACK (red) frame under
	# the two-colourway system.
	card.tags = [&"buff"] as Array[StringName]
	# "STR" keyword-matches the strength status (word-bounded, so STRAIGHT
	# stays safe); "Burn" is the second rule-keyword after Combo -- the
	# mechanics live in the tooltips, no number here can go stale.
	card.rules_text = "Gain %d STR. Burn." % BattleConfig.STRENGTH_UP_STACKS
	card.burn = true
	var buff := ApplyStatusEffect.new()
	buff.status_id = StrengthStatus.ID
	buff.stacks = BattleConfig.STRENGTH_UP_STACKS
	buff.turns = BattleConfig.STATUS_PERMANENT
	buff.target_self = true
	card.effects = [buff] as Array[CardEffect]
	return card

func _make_prepared() -> CardData:
	var card := CardData.new()
	card.id = &"prepared"
	card.display_name = "PREPARED"
	card.cost = BattleConfig.PREPARED_COST
	card.tags = [&"defense"] as Array[StringName]
	# "Prepared" is a status keyword: yellow, tooltip-explained. Both 4s sit
	# in sentences naming "guard", so they colour guard-blue.
	card.rules_text = "Gain %d guard. Prepared: gain %d guard next turn." % [
		BattleConfig.PREPARED_GUARD, BattleConfig.PREPARED_GUARD]
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.PREPARED_GUARD
	var delayed := ApplyStatusEffect.new()
	delayed.status_id = PreparedStatus.ID
	delayed.stacks = BattleConfig.PREPARED_GUARD
	delayed.turns = BattleConfig.PREPARED_STATUS_TURNS
	delayed.target_self = true
	card.effects = [guard, delayed] as Array[CardEffect]
	return card
```

Run the generator:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/generate_cards.gd
```

Expected: `Generated 7 card resources`, and `git status` shows exactly the three new `.tres` files (the four existing ones must be byte-identical — if they changed, STOP and investigate).

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Three reward cards: One-Two, Strength Up (burn), Prepared"
```

---

### Task 5: The Burn keyword and card-face coverage

"Burn" joins "Combo" as a rule-keyword; the new faces' colouring is pinned; the preview-aware wrap case CLAUDE.md called for lands.

**Files:**
- Modify: `scripts/ui/card_template.gd`
- Test: `tests/suites/test_card_template.gd`, `tests/suites/test_card_preview.gd`

**Interfaces:**
- Consumes: `Deck.burn_description()` (Task 1), the three cards (Task 4).
- Produces: `CardTemplate.BURN_KEYWORD: StringName = &"burn"`; `keywords_in`/`keyword_title`/`keyword_description` handle it. `StatusTooltip.show_for_card` needs no changes — it renders whatever `keywords_in` returns.

- [ ] **Step 1: Write the failing tests**

`tests/suites/test_card_template.gd` — register in `run()`:

```gdscript
	_test_burn_is_a_rule_keyword(t)
	_test_reward_card_number_colours(t)
	_test_rules_lines_fit_with_buffed_previews(t)
```

Add:

```gdscript
## Burn is the second rule-keyword after Combo: no status behind it, its
## tooltip body lives beside the rule in Deck.burn_description().
func _test_burn_is_a_rule_keyword(t: TestRunner) -> void:
	t.check_eq(CardTemplate.keyword_title(CardTemplate.BURN_KEYWORD), "Burn", "the keyword's word")
	t.check_eq(CardTemplate.keyword_description(CardTemplate.BURN_KEYWORD), Deck.burn_description(),
		"the tooltip body comes from the rule's own description")

	var strength_up: CardData = CardLibrary.load_card(&"strength_up")
	var keywords: Array[StringName] = CardTemplate.keywords_in(strength_up)
	t.check(keywords.has(CardTemplate.BURN_KEYWORD), "strength up's text names Burn")
	t.check(keywords.has(&"strength"), "strength up's text names STR")
	var bbcode: String = CardTemplate.rules_bbcode(strength_up)
	t.check(bbcode.contains("[color=#%s]Burn[/color]" % CardTemplate.RULES_KEYWORD_COLOR.to_html(false)),
		"Burn renders keyword-yellow")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	t.check(CardTemplate.keywords_in(prepared).has(&"prepared"),
		"prepared's text names its own status keyword")

## One-Two: both 5s are damage-red (the second sentence names "guard" only
## as a condition; "damage" wins, checked first). Prepared: both 4s are
## guard-blue.
func _test_reward_card_number_colours(t: TestRunner) -> void:
	var damage_html: String = CardTemplate.RULES_DAMAGE_COLOR.to_html(false)
	var guard_html: String = CardTemplate.RULES_GUARD_COLOR.to_html(false)

	var one_two: CardData = CardLibrary.load_card(&"one_two")
	var one_two_bbcode: String = CardTemplate.rules_bbcode(one_two)
	t.check_eq(one_two_bbcode.count("[color=#%s]%d[/color]" % [damage_html, BattleConfig.ONE_TWO_DAMAGE]), 2,
		"both of one-two's 5s are damage-red")

	var prepared: CardData = CardLibrary.load_card(&"prepared")
	var prepared_bbcode: String = CardTemplate.rules_bbcode(prepared)
	t.check_eq(prepared_bbcode.count("[color=#%s]%d[/color]" % [guard_html, BattleConfig.PREPARED_GUARD]), 2,
		"both of prepared's 4s are guard-blue")

## The preview-aware wrap case CLAUDE.md reserved: the player can now BUFF
## (Strength Up), so a previewed damage number can be WIDER than its base
## ("9" -> "13"). The plain-text wrap tests measure rules_plain() and no
## longer model a buffed face -- this one wraps the PREVIEWED text (bbcode
## with the colour tags stripped; the tags add no visible characters) at the
## maximum reachable player strength: STRENGTH_UP_STACKS, one Strength Up
## per fight today. Raising the reachable stacks must widen this test too.
func _test_rules_lines_fit_with_buffed_previews(t: TestRunner) -> void:
	const EDGE_TOLERANCE: float = 0.03
	var strong := Fighter.new("Strong", 50)
	strong.statuses.apply(&"strength", BattleConfig.STRENGTH_UP_STACKS, BattleConfig.STATUS_PERMANENT)
	var target := Fighter.new("Target", 50)
	var tag_pattern: RegEx = RegEx.create_from_string("\\[/?color[^\\]]*\\]")

	for card_id: StringName in [&"jab", &"straight", &"low_kick", &"one_two"]:
		var card: CardData = CardLibrary.load_card(card_id)
		var previewed_plain: String = tag_pattern.sub(
			CardTemplate.rules_bbcode(card, strong, target), "", true)
		var image: Image = _frame_image(
			CardTemplate.frame_name(CardTemplate.variant_for(card)))
		var height: int = image.get_height()
		var zone_width_px: float = CardTemplate.RULES_ZONE.size.x * CARD_SIZE.x
		var rects: Array[Rect2] = _line_rects(_wrapped_lines(previewed_plain, zone_width_px))
		for rect: Rect2 in rects:
			for frac_y: float in [rect.position.y + 0.004, rect.get_center().y, rect.end.y - 0.004]:
				var y: int = mini(int(frac_y * float(height)), height - 1)
				var run: Array = _widest_panel_run(image, y)
				t.check(run[1] > run[0],
					"%s buffed: row %.3f has a wide painted-panel run" % [card_id, frac_y])
				if run[1] <= run[0]:
					continue
				t.check(run[0] <= rect.position.x + EDGE_TOLERANCE,
					"%s buffed: panel covers the line's left edge at row %.3f" % [card_id, frac_y])
				t.check(run[1] >= rect.end.x - EDGE_TOLERANCE,
					"%s buffed: panel covers the line's right edge at row %.3f" % [card_id, frac_y])
```

Also extend the existing `_test_rules_lines_fit_the_painted_panel` card list from `[&"jab", &"straight", &"block"]` to `[&"jab", &"straight", &"block", &"low_kick", &"one_two", &"strength_up", &"prepared"]` — every library card's un-previewed face must fit.

`tests/suites/test_card_preview.gd` — register `_test_one_two_previews_both_hits(t)` in `run()`, add:

```gdscript
## One-Two has a sole DamageEffect (the bonus is a GuardBreakBonusEffect,
## not a DamageEffect), so the preview machinery applies. BOTH printed 5s
## match the effect's base amount, so BOTH get replaced -- and that is
## CORRECT, not a bug to fix: the bonus hit resolves through the same
## pipeline with the same base, so one previewed value is true for both.
func _test_one_two_previews_both_hits(t: TestRunner) -> void:
	var one_two: CardData = CardLibrary.load_card(&"one_two")
	var strong := Fighter.new("Strong", 50)
	strong.statuses.apply(&"strength", 2, BattleConfig.STATUS_PERMANENT)
	var target := Fighter.new("Target", 50)

	var bbcode: String = CardTemplate.rules_bbcode(one_two, strong, target)
	var boosted: int = Combat.preview_damage(BattleConfig.ONE_TWO_DAMAGE, strong, target)
	t.check_eq(boosted, 7, "2 strength stacks boost 5 to floori(5 * 1.5) = 7")
	t.check_eq(bbcode.count("]%d[" % boosted), 2, "both hits preview the boosted value")
	t.check(not bbcode.contains("]%d[" % BattleConfig.ONE_TWO_DAMAGE),
		"the base 5 no longer appears as a coloured span")
	t.check(not bbcode.contains(CardTemplate.RULES_WEAKENED_COLOR.to_html(false)),
		"a BUFFED number stays damage-red -- weakened orange is for reductions only")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh` — expected: FAIL (`BURN_KEYWORD` not found).

- [ ] **Step 3: Implement**

`scripts/ui/card_template.gd` — beside `COMBO_KEYWORD`:

```gdscript
## The burn mechanic's keyword id. Like Combo, a game-rule keyword with no
## status behind it: its title and description resolve through
## keyword_title()/keyword_description(), the body from Deck (core), beside
## the rule it describes.
const BURN_KEYWORD: StringName = &"burn"
```

In `_keyword_ids()`, after `ids.append(COMBO_KEYWORD)`:

```gdscript
	ids.append(BURN_KEYWORD)
```

Rewrite `keyword_title` and `keyword_description` as chains:

```gdscript
## The word printed on cards and as the tooltip's heading.
static func keyword_title(id: StringName) -> String:
	if id == COMBO_KEYWORD:
		return "Combo"
	if id == BURN_KEYWORD:
		return "Burn"
	return StatusRegistry.display_name(id)

## The tooltip's body: statuses describe themselves via the registry; the
## rule keywords via the rule they name.
static func keyword_description(id: StringName) -> String:
	if id == COMBO_KEYWORD:
		return ComboRule.keyword_description()
	if id == BURN_KEYWORD:
		return Deck.burn_description()
	return StatusRegistry.description(id)
```

(`_number_color` needs NO change: it scans only `StatusRegistry.DEFINITIONS` for the plain-number rule, and "Burn." contains no digits.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`. If `_test_rules_lines_fit_with_buffed_previews` fails on a real overflow (a widened number pushing a line past the panel), that is the test doing its job: fix by rewording that card's rules text shorter, not by loosening the tolerance.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Burn keyword; card-face colour and buffed-preview wrap coverage"
```

---

### Task 6: The persistent run deck

`RunState` owns the deck across fights; `BattleState` builds from it; `BattleView` passes it.

**Files:**
- Modify: `scripts/core/run_state.gd`, `scripts/core/card_library.gd`, `scripts/core/battle_state.gd`, `scripts/ui/battle_view.gd`
- Test: `tests/suites/test_run_state.gd`

**Interfaces:**
- Produces: `RunState.deck_ids: Array[StringName]`, `RunState.add_card(card_id: StringName) -> void`; `CardLibrary.starting_deck_ids() -> Array[StringName]`, `CardLibrary.build_deck(ids: Array[StringName]) -> Array[CardData]`; `BattleState._init(rng_seed := 0, opponent := null, starting_hp := -1, deck_ids: Array[StringName] = [])` — empty `deck_ids` means the starting deck, so every existing call site keeps working.

- [ ] **Step 1: Write the failing tests**

`tests/suites/test_run_state.gd` — register `_test_deck_persists_across_fights(t)` in `run()`, add:

```gdscript
## The deck is run state: it starts as DECK_COMPOSITION expanded, grows via
## add_card (the rewards screen's only write), feeds each fight's
## BattleState, and reset() restores the base deck.
func _test_deck_persists_across_fights(t: TestRunner) -> void:
	var run := RunState.new()
	t.check_eq(run.deck_ids.size(), 14, "the run deck starts as the 14-card composition")

	run.add_card(&"one_two")
	t.check_eq(run.deck_ids.size(), 15, "a reward pick joins the run deck")

	var battle := BattleState.new(9, null, -1, run.deck_ids)
	t.check_eq(battle.deck.total_cards(), 15, "the next fight is built from the run deck")
	var has_one_two: bool = false
	for card: CardData in battle.deck.draw_pile:
		if card.id == &"one_two":
			has_one_two = true
	t.check(has_one_two, "the picked card is actually in the fight's deck")

	# The default (empty deck_ids) still builds the starting 14 -- every
	# pre-run call site and test keeps working.
	var plain := BattleState.new(9)
	t.check_eq(plain.deck.total_cards(), 14, "empty deck_ids means the starting deck")

	run.reset()
	t.check_eq(run.deck_ids.size(), 14, "reset restores the base deck")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh` — expected: FAIL (`deck_ids` not found / too many arguments).

- [ ] **Step 3: Implement**

`scripts/core/card_library.gd` — add, and rewrite `build_starting_deck` on top of the two new statics (one expansion of `DECK_COMPOSITION`, shared with `RunState`, so the two can never drift):

```gdscript
## DECK_COMPOSITION expanded to a flat id list -- the single source RunState
## seeds its run deck from and build_starting_deck() builds from.
static func starting_deck_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for card_id: StringName in BattleConfig.DECK_COMPOSITION:
		var copies: int = BattleConfig.DECK_COMPOSITION[card_id]
		for _i: int in range(copies):
			ids.append(card_id)
	return ids

## Loads a deck from an id list (the run's persistent deck). Unloadable ids
## are skipped -- load_card already push_errors, which the test wrapper
## treats as failure.
static func build_deck(ids: Array[StringName]) -> Array[CardData]:
	var deck: Array[CardData] = []
	for card_id: StringName in ids:
		var card: CardData = load_card(card_id)
		if card != null:
			deck.append(card)
	return deck

static func build_starting_deck() -> Array[CardData]:
	return build_deck(starting_deck_ids())
```

`scripts/core/run_state.gd` — extend the class doc comment (`## ...and the
deck the player has assembled -- reward picks persist here.`), add the field
and method, and extend `reset()`:

```gdscript
## The run's deck as card ids: DECK_COMPOSITION expanded, plus every reward
## pick. Each fight builds a fresh Deck from this list -- which is also what
## returns burned cards to play next fight.
var deck_ids: Array[StringName] = CardLibrary.starting_deck_ids()
```

```gdscript
## The rewards screen's only write.
func add_card(card_id: StringName) -> void:
	deck_ids.append(card_id)
```

In `reset()`, add:

```gdscript
	deck_ids = CardLibrary.starting_deck_ids()
```

`scripts/core/battle_state.gd` — extend `_init` (amend its doc comment: `## deck_ids empty means the starting deck; a run passes its persistent deck here.`):

```gdscript
func _init(rng_seed: int = 0, opponent: OpponentData = null, starting_hp: int = -1,
		deck_ids: Array[StringName] = []) -> void:
```

and replace the deck line:

```gdscript
	var cards: Array[CardData] = CardLibrary.build_starting_deck() if deck_ids.is_empty() \
		else CardLibrary.build_deck(deck_ids)
	deck = Deck.new(cards, rng_seed)
```

(`restart()` keeps building the starting deck — tests only, per its existing doc comment; the run flow builds a fresh `BattleState` per fight.)

`scripts/ui/battle_view.gd`, in `_start_fight()`:

```gdscript
	battle = BattleState.new(0, opponent, run.player_hp, run.deck_ids)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "RunState owns a persistent deck; fights build from it"
```

---

### Task 7: RewardPool and RewardsView

The core pool seam plus the full-screen chooser (placeholder buttons).

**Files:**
- Create: `scripts/core/reward_pool.gd`, `scripts/ui/rewards_view.gd`
- Test: `tests/suites/test_rewards_view.gd` (new suite — auto-discovered)

**Interfaces:**
- Consumes: `CardArt.background_for(&"rewards_bg")`, `CardView.create/card_selected/hover_changed/set_combo_armed/set_rest_transform`, `HudText.style`, `CardLibrary.load_card`.
- Produces: `RewardPool.options() -> Array[StringName]`; `RewardsView` with `open(card_ids: Array[StringName]) -> void`, `dismiss() -> void`, `signal finished(card_id: StringName)` (`&""` = skipped), `signal card_hovered(view: CardView, hovered: bool)`, and debug hooks `debug_card_views() -> Array`, `debug_continue_button() -> Button`, `debug_skip_button() -> Button`, `debug_selected_id() -> StringName`.

- [ ] **Step 1: Write the failing tests**

Create `tests/suites/test_rewards_view.gd`:

```gdscript
extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_reward_pool(t)
	_test_open_builds_the_offer(t)
	_test_selection_state_machine(t)
	_test_finished_payloads(t)
	_test_buttons_take_no_focus(t)

func _test_reward_pool(t: TestRunner) -> void:
	var options: Array[StringName] = RewardPool.options()
	t.check_eq(options, BattleConfig.REWARD_CARDS, "the pool is the configured reward list")
	options.append(&"tampered")
	t.check_eq(RewardPool.options().size(), BattleConfig.REWARD_CARDS.size(),
		"options() returns a copy -- callers cannot mutate the config")

func _test_open_builds_the_offer(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	t.check(view.visible, "opening shows the view")
	t.check_eq(view.debug_card_views().size(), 3, "one CardView per offered card")
	t.check(view.debug_continue_button().disabled, "continue starts disabled -- nothing selected")
	t.check(not view.debug_skip_button().disabled, "skip is always available")
	t.check_eq(view.debug_selected_id(), &"", "nothing selected on open")
	# Reopening rebuilds cleanly (fight 2 of a longer run someday).
	view.open(RewardPool.options())
	t.check_eq(view.debug_card_views().size(), 3, "reopening rebuilds, not accumulates")
	view.free()

func _test_selection_state_machine(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	var first: CardView = view.debug_card_views()[0]
	var second: CardView = view.debug_card_views()[1]

	first.card_selected.emit(first)
	t.check_eq(view.debug_selected_id(), first.card.id, "clicking a card selects it")
	t.check(not view.debug_continue_button().disabled, "continue enables on selection")

	second.card_selected.emit(second)
	t.check_eq(view.debug_selected_id(), second.card.id, "clicking another moves the selection")

	second.card_selected.emit(second)
	t.check_eq(view.debug_selected_id(), &"", "clicking the selected card deselects")
	t.check(view.debug_continue_button().disabled, "continue disables again")
	view.free()

func _test_finished_payloads(t: TestRunner) -> void:
	var view := RewardsView.new()
	view.open(RewardPool.options())
	var captured: Array = []
	view.finished.connect(func(card_id: StringName) -> void: captured.append(card_id))

	var chosen: CardView = view.debug_card_views()[2]
	chosen.card_selected.emit(chosen)
	view.debug_continue_button().pressed.emit()
	t.check_eq(captured.size(), 1, "continue emits finished once")
	t.check_eq(captured[0], chosen.card.id, "continue carries the selected id")
	t.check(not view.visible, "the view hides on finish")

	view.open(RewardPool.options())
	view.debug_skip_button().pressed.emit()
	t.check_eq(captured[1], &"", "skip carries the empty id")
	t.check(not view.visible, "the view hides on skip")
	view.free()

func _test_buttons_take_no_focus(t: TestRunner) -> void:
	var view := RewardsView.new()
	t.check_eq(view.debug_continue_button().focus_mode, Control.FOCUS_NONE,
		"continue takes no focus -- no white focus rectangle")
	t.check_eq(view.debug_skip_button().focus_mode, Control.FOCUS_NONE,
		"skip takes no focus")
	view.free()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh` — expected: FAIL (`RewardPool`/`RewardsView` not declared; the suite itself must be reported as a load failure or the identifiers as undeclared — either way exit 1).

- [ ] **Step 3: Implement RewardPool**

Create `scripts/core/reward_pool.gd`:

```gdscript
class_name RewardPool
extends RefCounted

## The rewards screen's card pool. Today the whole configured list is
## offered every time; this static is the SEAM where "3 random cards from a
## larger pool" lands later -- callers already receive an arbitrary id list
## and RewardsView renders whatever it is handed.

static func options() -> Array[StringName]:
	return BattleConfig.REWARD_CARDS.duplicate()
```

- [ ] **Step 4: Implement RewardsView**

Create `scripts/ui/rewards_view.gd`:

```gdscript
class_name RewardsView
extends Control

## Full-screen reward chooser after a won fight (run not complete): pick one
## card to add to the run deck, or skip. Modelled on PileView: a full-rect
## modal overlay (STOP mouse filter), real CardViews with the same absolute
## hover zoom so rules text reads at hand size, and hover relayed outward so
## BattleView can drive the keyword tooltip -- this screen is where the
## player first reads Burn, STR and Prepared, so the tooltips matter here.
## Continue/Skip are plain Buttons ON PURPOSE: placeholder until real art
## exists (the End Turn plate treatment is the model to follow then).

signal finished(card_id: StringName)
signal card_hovered(view: CardView, hovered: bool)

## Same reasoning as PileView.PILE_Z: covers every resting battle element
## while a hovered card (REWARDS_Z + HOVER_Z = 60) stays under the tooltip's
## 70. Raising this above 20 silently puts hovered cards over their tooltips.
const REWARDS_Z: int = 10

const CANVAS: Vector2 = Vector2(1152, 648)
## Bigger than PileView's 0.55: three cards are the whole show here.
const CARD_REST_SCALE: float = 0.7
## The selected card sits visibly proud of its neighbours; the armed-frame
## tint (set_combo_armed) carries the state at a glance. Judged from the
## rewards capture, not from these numbers.
const SELECTED_SCALE: float = 0.78
const CARD_GAP: float = 48.0
const CARD_TOP: float = 170.0
const TITLE_Y: float = 60.0
const BUTTON_Y: float = 560.0
const BUTTON_SIZE: Vector2 = Vector2(180, 48)

var _background: TextureRect
var _title: Label
var _row: Control
var _continue_button: Button
var _skip_button: Button
var _card_views: Array = []
var _selected: CardView = null

func _init() -> void:
	visible = false
	z_index = REWARDS_Z
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_background = TextureRect.new()
	_background.texture = CardArt.background_for(&"rewards_bg")
	# stretch/expand BEFORE position/size -- see FighterPanel._make_icon.
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_title = Label.new()
	HudText.style(_title, 28)
	_title.text = "CHOOSE A CARD"
	_title.position = Vector2(0.0, TITLE_Y)
	_title.size = Vector2(CANVAS.x, 36.0)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# IGNORE on the row, so each CardView is hit-tested on its own.
	_row = Control.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_continue_button = _make_button("CONTINUE", Vector2(CANVAS.x / 2.0 + 20.0, BUTTON_Y))
	_continue_button.disabled = true
	_continue_button.pressed.connect(_on_continue_pressed)
	_skip_button = _make_button("SKIP", Vector2(CANVAS.x / 2.0 - BUTTON_SIZE.x - 20.0, BUTTON_Y))
	_skip_button.pressed.connect(_on_skip_pressed)

func _make_button(text: String, at: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.custom_minimum_size = BUTTON_SIZE
	# No keyboard nav anywhere in the game: a focused button wears Godot's
	# default white focus rectangle, which reads as a rendering glitch.
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

## Rebuilds the offer row and shows the view. Safe to call while open.
func open(card_ids: Array[StringName]) -> void:
	for child: Node in _row.get_children():
		_row.remove_child(child)
		child.free()
	_card_views = []
	_selected = null
	_continue_button.disabled = true

	for i: int in range(card_ids.size()):
		var view: CardView = CardView.create(CardLibrary.load_card(card_ids[i]))
		view.card_selected.connect(_on_card_clicked)
		view.hover_changed.connect(func(v: CardView, hovered: bool) -> void:
			card_hovered.emit(v, hovered))
		_row.add_child(view)
		view.set_rest_transform(_rest_for(i, card_ids.size()), 0.0, i, CARD_REST_SCALE)
		_card_views.append(view)
	visible = true

## Where card `index` of `count` rests -- the row is centred on the canvas,
## and the card scales about its bottom-centre pivot, so the rest point is
## the SAME for every scale: x centres the unscaled rect on the cell, y puts
## the unscaled bottom on the cell's bottom (same arithmetic as PileView's
## grid, minus its scale-dependent offset -- anchoring the pivot at the cell
## bottom is what lets a selected card grow in place).
func _rest_for(index: int, count: int) -> Vector2:
	var cell: Vector2 = CardView.CARD_SIZE * CARD_REST_SCALE
	var row_width: float = count * cell.x + (count - 1) * CARD_GAP
	var cell_left: float = (CANVAS.x - row_width) / 2.0 + index * (cell.x + CARD_GAP)
	return Vector2(
		cell_left + cell.x / 2.0 - CardView.CARD_SIZE.x / 2.0,
		CARD_TOP + cell.y - CardView.CARD_SIZE.y)

func _on_card_clicked(view: CardView) -> void:
	_selected = null if _selected == view else view
	for i: int in range(_card_views.size()):
		var card_view: CardView = _card_views[i]
		var chosen: bool = card_view == _selected
		# The armed-frame tint doubles as the selection tint: same "this card
		# is charged" read, already verified legible on both colourways.
		card_view.set_combo_armed(chosen)
		card_view.set_rest_transform(_rest_for(i, _card_views.size()), 0.0, i,
			SELECTED_SCALE if chosen else CARD_REST_SCALE)
	_continue_button.disabled = _selected == null

func _on_continue_pressed() -> void:
	if _selected == null:
		return
	var chosen_id: StringName = _selected.card.id
	visible = false
	finished.emit(chosen_id)

func _on_skip_pressed() -> void:
	visible = false
	finished.emit(&"")

## Silent hide for transitions, mirroring PileView.dismiss().
func dismiss() -> void:
	visible = false

func debug_card_views() -> Array:
	return _card_views

func debug_continue_button() -> Button:
	return _continue_button

func debug_skip_button() -> Button:
	return _skip_button

func debug_selected_id() -> StringName:
	return _selected.card.id if _selected != null else &""
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`. (The suite runs detached — `set_rest_transform` writes live properties off-tree by design, and no animation entry point is reached.)

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "RewardPool and RewardsView: pick one of three cards, or skip"
```

---

### Task 8: The burned pile in the HUD

A third pile icon, visible only while the burned pile is non-empty, left of the discard icon, opening the same PileView grid.

**Files:**
- Modify: `scripts/ui/battle_hud.gd`, `scripts/ui/battle_view.gd`
- Test: `tests/suites/test_battle_hud.gd`, `tests/suites/test_hand_arc.gd`

**Interfaces:**
- Consumes: `Deck.burned_pile` (Task 1), `_make_pile_button`/`_make_icon_value` (existing).
- Produces: `BattleHud.BURNED_ICON_AT: Vector2`; `pile_clicked` now also emits `&"burned"`; `BattleHud.debug_burned_button() -> TextureButton`, `debug_burned_text() -> String`.

- [ ] **Step 1: Write the failing tests**

`tests/suites/test_battle_hud.gd` — register `_test_burned_icon_appears_with_burned_cards(t)` in `run()`, add:

```gdscript
## The burned icon exists only while something is burned: hidden on a fresh
## fight, shown with the count once a burn card is played, hidden again next
## fight (a fresh battle has an empty burned pile).
func _test_burned_icon_appears_with_burned_cards(t: TestRunner) -> void:
	var hud := BattleHud.new()
	var battle := BattleState.new(5)
	battle.start()

	hud.update_fighters(battle)
	t.check(not hud.debug_burned_button().visible, "no burned cards, no icon")

	var burned := CardData.new()
	burned.id = &"strength_up"
	burned.burn = true
	battle.deck.burned_pile.append(burned)
	hud.update_fighters(battle)
	t.check(hud.debug_burned_button().visible, "a burned card shows the icon")
	t.check_eq(hud.debug_burned_text(), "1", "the count renders inside the icon")

	hud.free()
```

`tests/suites/test_hand_arc.gd` — register `_test_clear_of_burned_icon(t)` in `run()`, add (mirroring `_test_clear_of_discard_icon` exactly, against the new rect):

```gdscript
## The burned icon sits LEFT of the discard icon -- closer to the fan than
## any other right-side control, so it gets the same per-row rotated-
## silhouette clearance check.
func _test_clear_of_burned_icon(t: TestRunner) -> void:
	var view: HandView = _hand_with([&"jab", &"straight", &"jab", &"block", &"straight"])
	var rightmost: CardView = view.get_child(view.get_child_count() - 1) as CardView
	for row_y: float in [BattleHud.BURNED_ICON_AT.y, BattleHud.BURNED_ICON_AT.y + BattleHud.PILE_ICON_SIZE]:
		var right_edge: float = HandView.rotated_right_edge_at_y(
			rightmost.rest_position.x, rightmost.rest_position.y, rightmost.rest_rotation,
			row_y)
		t.check(right_edge < BattleHud.BURNED_ICON_AT.x,
			"the fan stays clear of the burned icon at y %.0f (right edge %f)" % [
				row_y, right_edge])
	view.free()
```

Also extend `_test_layout_invariants_across_hand_sizes`: inside the per-`n` loop, after the End Turn check, add the same right-edge check against `BattleHud.BURNED_ICON_AT` at `BattleHud.BURNED_ICON_AT.y` (the icon's top row — the binding one, since the rotated edge only retreats further down):

```gdscript
			var burned_edge: float = HandView.rotated_right_edge_at_y(
				rightmost.rest_position.x, rightmost.rest_position.y, rightmost.rest_rotation,
				BattleHud.BURNED_ICON_AT.y)
			t.check(burned_edge < BattleHud.BURNED_ICON_AT.x,
				"hand of %d clears the burned icon (right edge %f)" % [n, burned_edge])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/run_tests.sh` — expected: FAIL (`BURNED_ICON_AT` not found).

- [ ] **Step 3: Implement**

`scripts/ui/battle_hud.gd`:

Update the `pile_clicked` doc comment to `## A pile icon was clicked: &"draw", &"discard" or &"burned".`

Add beside `DISCARD_ICON_AT`:

```gdscript
## Left of the discard icon with a small gap (1079 - 56 - 14 = 1009).
## Appears only while the burned pile is non-empty. Closer to the fan than
## the discard icon, so test_hand_arc.gd checks the rotated silhouette
## against THIS rect too -- at its rows the n=5 edge passes ~987, ~22px
## clear. If a layout change ever pushes the edge past it, move this icon,
## don't shave the check.
const BURNED_ICON_AT: Vector2 = Vector2(1009, 461)
```

Add fields beside the other pile vars:

```gdscript
var _burned_button: TextureButton
var _burned_value: Label
```

In `_build()`, after the discard lines:

```gdscript
	# Placeholder art: the discard icon in an ember tint, until real burned-
	# pile art exists. Hidden until something actually burns.
	_burned_button = _make_pile_button(&"discarded_cards", BURNED_ICON_AT, &"burned")
	_burned_button.modulate = Color(1.0, 0.55, 0.35)
	_burned_button.visible = false
	_burned_value = _make_icon_value(BURNED_ICON_AT, PILE_ICON_SIZE)
	_burned_value.visible = false
```

In `update_fighters()`, after the discard count line:

```gdscript
	var burned_count: int = battle.deck.burned_pile.size()
	_burned_button.visible = burned_count > 0
	_burned_value.visible = burned_count > 0
	_burned_value.text = str(burned_count)
```

Add debug hooks beside the others:

```gdscript
func debug_burned_button() -> TextureButton:
	return _burned_button

func debug_burned_text() -> String:
	return _burned_value.text
```

`scripts/ui/battle_view.gd`, `_on_pile_clicked` — replace the if/else with a match on all three:

```gdscript
	if pile == &"draw":
		pile_view.open(battle.deck.draw_pile,
			"DRAW PILE (%d)" % battle.deck.draw_pile.size())
	elif pile == &"burned":
		pile_view.open(battle.deck.burned_pile,
			"BURNED (%d)" % battle.deck.burned_pile.size())
	else:
		pile_view.open(battle.deck.discard_pile,
			"DISCARDED (%d)" % battle.deck.discard_pile.size())
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/run_tests.sh` — expected: `PASS`. If the burned-icon clearance checks FAIL (the estimate said ~22px slack, but the estimate is not the test): do NOT weaken the check. Move the icon up instead — try `BURNED_ICON_AT = Vector2(1009, 391)` (stacked above the discard icon, still visually grouped with it) and re-run; update the constant's comment to describe the actual position.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Burned-pile HUD icon: appears when non-empty, opens the pile browser"
```

---

### Task 9: The rewards flow in BattleView

Continue after a mid-run win opens the rewards screen; its choice feeds the run deck; then the next fight starts.

**Files:**
- Modify: `scripts/ui/battle_view.gd`

**Interfaces:**
- Consumes: `RewardsView` (Task 7), `RunState.add_card` (Task 6), `RewardPool.options()` (Task 7).
- Produces: nothing later tasks use — this is the final wiring.

No new headless tests: BattleView's signal wiring has no test suite (it is the one class verified by running the game — Task 10). The steps below are implementation plus a manual smoke check.

- [ ] **Step 1: Implement**

`scripts/ui/battle_view.gd`:

Add the field beside `pile_view`:

```gdscript
var rewards_view: RewardsView
```

In `_build_ui()`, after the `pile_view` block:

```gdscript
	# The reward chooser. Same layer cake as the pile browser: covers the
	# battle, stays under the tooltip so the new cards' keywords (Burn, STR,
	# Prepared) explain themselves right where the player first reads them.
	rewards_view = RewardsView.new()
	rewards_view.finished.connect(_on_rewards_finished)
	rewards_view.card_hovered.connect(_on_pile_card_hovered)
	hud.add_child(rewards_view)
```

(`_on_pile_card_hovered` is reused as-is: it reads `view.rest_position` generically, so the anchor math holds for reward cards too.)

In `_start_fight()`, after `pile_view.dismiss()`:

```gdscript
	rewards_view.dismiss()
```

Replace `_on_continue_pressed` (this handler is ONLY reachable from the
fight-intro banner — a mid-run win — so it is exactly the rewards moment):

```gdscript
## CONTINUE on a mid-run win: the rewards screen first; the next fight
## starts from _on_rewards_finished. Losses and the completed run show
## RESTART instead and never pass through here.
func _on_continue_pressed() -> void:
	sound_fx.play(&"click")
	hud.hide_result()
	status_tooltip.hide_tooltip()
	rewards_view.open(RewardPool.options())

## The reward decision: a non-empty id joins the run deck; either way the
## next fight starts, with the same transition suppressions Continue used
## to run directly.
func _on_rewards_finished(card_id: StringName) -> void:
	sound_fx.play(&"click")
	status_tooltip.hide_tooltip()
	if card_id != &"":
		run.add_card(card_id)
	_suppress_transition_guard_pulses()
	_start_fight()
```

- [ ] **Step 2: Run the full test suite**

Run: `./tests/run_tests.sh` — expected: `PASS` (no regressions; this task adds view wiring only).

- [ ] **Step 3: Smoke-test the flow in the running game**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path .
```

Beat the Brawler (play aggressively; Low Kick softens its attacks). Verify, in order: victory banner → CONTINUE → rewards screen on the rewards background with three faces → hovering a card zooms it and tooltips its keywords → clicking selects (gold tint + bigger), clicking again deselects, CONTINUE disabled with nothing selected → pick Strength Up, CONTINUE → fight 2 starts → play Strength Up: it goes to the burned pile, the ember icon appears left of the discard icon with count 1, clicking it opens the BURNED grid → STR chip shows 2 on the player panel and attack cards preview boosted numbers. Also verify SKIP starts fight 2 without a deck change (restart the run to test both paths).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "Rewards flow: mid-run Continue offers a card before the next fight"
```

---

### Task 10: Visual verification, capture tooling, docs

Extend the card capture with the three new faces, capture the rewards screen, judge the renders, update CLAUDE.md.

**Files:**
- Modify: `tools/capture_cards.gd`, `CLAUDE.md`
- Create: `tools/capture_rewards.gd`

**Interfaces:**
- Consumes: everything prior.

- [ ] **Step 1: Extend the card capture**

`tools/capture_cards.gd`: the card row is full (5 faces, 1080px). Put the three new faces on row two, after the combo pair: 420 (pair) + 20 + 640 (3 cards) = 1080, same width as row one — fits the 1152 canvas at GAP margins. In `_add_combo_row`, after the existing loop:

```gdscript
	# The three reward cards, sharing row two with the combo pair: the row is
	# 420 + 20 + 640 = 1080px of content, the same width as row one.
	var x: float = 2.0 * (CardView.CARD_SIZE.x + GAP)
	for card_id: StringName in [&"one_two", &"strength_up", &"prepared"]:
		var view: CardView = CardView.create(CardLibrary.load_card(card_id))
		# target_position, never position -- see the note in _add_row().
		view.target_position = Vector2(x, 0.0)
		row.add_child(view)
		x += CardView.CARD_SIZE.x + GAP
```

Update the tool's header comment ("a row of all three" → the current two-row layout including the reward cards) and run it:

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --path . --script res://tools/capture_cards.gd
```

Read `/tmp/card-faces.png` and JUDGE (green tests prove nothing here): One-Two wears the red attack frame with both 5s red; Strength Up wears the red frame, "Burn" and "STR" yellow; Prepared wears the BLUE defense frame, both 4s blue, "Prepared" yellow; every line sits on its rules panel; each illustration fills its window. Fix what reads wrong (usually `rules_text` wording or a generator tweak + regen), re-capture until right.

- [ ] **Step 2: Capture the rewards screen**

Create `tools/capture_rewards.gd`:

```gdscript
extends SceneTree

## Renders RewardsView exactly as the game shows it -- background, title,
## the three faces with the middle one selected, both buttons -- and writes
## a screenshot. Card-face and screen layout are geometry no test can check
## (see CLAUDE.md, "Verifying animation"). Run NON-headless:
##   "/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
##     --path . --script res://tools/capture_rewards.gd

const OUTPUT: String = "/tmp/rewards-screen.png"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := RewardsView.new()
	root.add_child(view)
	view.open(RewardPool.options())
	var middle: CardView = view.debug_card_views()[1]
	middle.card_selected.emit(middle)

	for _i: int in range(10):
		await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	image.save_png(OUTPUT)
	print("wrote %s" % OUTPUT)
	quit(0)
```

Run it, read `/tmp/rewards-screen.png`, judge: the background fills the screen, three cards centred and readable, the selected middle card visibly proud (bigger + gold-tinted) of its neighbours, CONTINUE/SKIP placed clear of the cards. Tune `RewardsView`'s layout constants (`CARD_TOP`, `CARD_GAP`, `SELECTED_SCALE`, `BUTTON_Y`) from the render, re-capture until it reads.

- [ ] **Step 3: Verify determinism and run everything**

```bash
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" --headless --path . --script res://tools/generate_cards.gd
git status --short   # must show no .tres changes -- regen is deterministic
./tests/run_tests.sh
```

Expected: clean tree, `PASS`.

- [ ] **Step 4: Update CLAUDE.md**

Update these sections to the new truth (follow the file's existing voice — record the WHY, not just the what):

- Header paragraph: the run now offers a card reward between fights; deck grows.
- "How to extend → Add a status": the contract now includes the third static `on_turn_start(fighter, stacks) -> bool` (pass-through returns `false`; returning `true` consumes) and when it fires (owner's turn start, after guard expiry).
- "Change balance": add `ONE_TWO_*`, `STRENGTH_UP_*`, `PREPARED_COST/GUARD` to the BAKED list; note `PREPARED_STATUS_TURNS` and `REWARD_CARDS` are live-read.
- "Card art": keywords are now every status's DISPLAY_NAME plus TWO rule keywords, Combo and Burn (`Deck.burn_description()`); the preview-aware wrap test now exists (the "day a source-side buff can widen one" paragraph is resolved — rewrite it to describe `_test_rules_lines_fit_with_buffed_previews` and its max-stacks assumption).
- "Timing rules": add the turn-start hook's position (after guard expiry, before anything else) and Prepared's exactly-once payout.
- "The presentation layer": the burned icon (left of discard, visible only when non-empty, placeholder ember-tinted discard art), `pile_clicked` third id, the rewards screen and its flow (Continue → rewards → next fight), RewardsView's z-cake note.
- "State of the project": two-fight run WITH a card reward after fight 1; deck persistence; burn; update the check count to the current number from the test output; move "no card rewards" out of the placeholder list (leave "no map / no random pools" in).

- [ ] **Step 5: Final full check and commit**

```bash
./tests/run_tests.sh
git add -A && git commit -m "Reward-card captures, rewards-screen capture tool, CLAUDE.md brought current"
```

---

## Self-Review (completed)

- **Spec coverage:** burn model (T1), One-Two (T2+T4), Prepared + hook (T3+T4), cards/constants/generator (T4), Burn keyword + preview/wrap coverage (T5), persistent deck (T6), RewardPool/RewardsView (T7), burned HUD icon + clearance (T8), flow wiring + suppressions (T9), render judgment + docs (T10). The spec's "both opponents' guard makes the break condition live" needs no task — it is existing data.
- **Type consistency:** `finished(card_id: StringName)`, `RewardPool.options() -> Array[StringName]`, `BattleState._init(..., deck_ids: Array[StringName] = [])`, `on_turn_start(fighter: Fighter, stacks: int) -> bool` used identically across tasks.
- **Known judgment points:** burned-icon clearance has a computed fallback position (Task 8 Step 4); the buffed-preview wrap test may legitimately fail on wording, with the fix direction stated (Task 5 Step 4).
