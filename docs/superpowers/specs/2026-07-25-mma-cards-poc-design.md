# MMA Cards — Combat POC Design

**Date:** 2026-07-25
**Status:** Approved for planning
**Engine:** Godot 4.5.1 (GDScript, typed)

## Goal

A playable proof-of-concept for a Slay the Spire-inspired MMA card battler: one player
versus one CPU opponent, 12-card deck, turn-based, placeholder rectangle art. The POC
exists to answer one question — *does the card/AP/combo loop feel good?* — while laying a
foundation that survives contact with more cards, more statuses, and more enemies.

## Scope

**In:** single battle, 3 card types, 12-card deck, AP economy, jab→straight combo, guard,
strength, enemy intent telegraph, win/lose, restart, headless rule tests, CLAUDE.md.

**Out (deliberately deferred):** relics/passives, multiple simultaneous enemies and
targeting UI, run/map structure, save-load, deck-building between fights, animation and
sprites, sound, card upgrades, energy/AP-modifying cards.

The architecture must not *prevent* the deferred items, but none of them are built.

## Game Rules

### Constants

| Constant | Value |
|---|---|
| Player max HP | 50 |
| Enemy max HP | 48 |
| AP per turn | 3 |
| Hand size | 5 |
| Deck | 5 jab, 4 straight, 3 block (12 cards) |

All live in one block at the top of `scripts/core/battle_config.gd` for easy tuning.

### Cards

| Card | Cost | Effect | Tags |
|---|---|---|---|
| Jab | 1 AP | 6 damage | `jab` |
| Straight | 2 AP | 9 damage | `straight` |
| Block | 1 AP | 5 guard | `defense` |

### Combo

A combo triggers when a card is played whose tags complete a registered tag sequence
against the cards played **earlier in the same turn, consecutively and immediately
preceding it**.

The POC registers one rule: `[jab, straight]`.

Bonus damage = `floor(0.5 × (sum of base damage of the cards in the matched sequence))`,
added to the final card's **base** damage before any modifiers.

- Jab → Straight: jab deals 6 on play. Straight deals `9 + floor(0.5 × (6 + 9))` =
  `9 + 7` = **16**. Combo total **22**.
- Jab → Block → Straight: sequence broken. Straight deals **9**.
- Jab → Jab: no rule matches. Each deals 6.
- Combo history clears at the start of each player turn.

### Guard

Guard absorbs incoming damage before HP. Damage exceeding guard spills over to HP. There is
no per-hit absorption cap and no maximum guard value; guard from multiple Block cards adds
up within a turn.

Guard expires at the **start of its owner's next turn** — so guard gained on your turn
protects you during the opponent's turn, then clears. (Expiring at end of the owner's own
turn would make Block a dead card.)

### Statuses

Statuses are stack-based with a turn countdown. `turns_remaining` decrements at the end of
the owner's turn; the status is removed at 0. A value of `-1` means permanent.

**Strength** — each stack adds 25% outgoing damage:
`final = floor(base × (1 + 0.25 × stacks))`. Enemy with 2 strength attacks for
`floor(8 × 1.5)` = **12**.

Strength granted by the enemy's buff action is applied with `turns_remaining = 2`, which
gives the intended timing:

```
Enemy turn N   : buff       → +2 STR (turns_remaining 2 → 1 at turn end)
Enemy turn N+1 : attack     → 12 damage, then (1 → 0) removed at turn end
Enemy turn N+2 : attack     → 8 damage
```

### Damage Pipeline

All damage flows through one function so the math lives in exactly one place:

```
base
  → attacker outgoing modifiers   (strength; later: weak)
  → defender incoming modifiers   (later: vulnerable)
  → clamp to >= 0
  → absorb into defender guard
  → remainder subtracted from HP, HP floors at 0
```

### Enemy AI

A fixed 3-step cycle, repeating: **attack 8** → **block 8 guard** → **buff +2 strength**.

The enemy's next action is chosen at battle start and re-chosen at the end of each enemy
turn, so it is always known and displayed during the player's turn. The intent display
shows post-modifier values — a buffed attack telegraphs `12`, not `8`.

Enemy actions are built from the **same `CardEffect` classes the player's cards use**
(`DamageEffect(8)`, `GuardEffect(8)`, `ApplyStatusEffect(strength, 2, turns=2)`). The enemy
has no separate combat code path, so any fix to the damage pipeline applies to both sides,
and giving enemies real cards later is a swap rather than a rewrite.

### Turn Structure

```
PLAYER TURN START   expire player guard → draw 5 → AP = 3 → clear combo history
PLAYER ACTS         play cards while AP allows; End Turn button always available
PLAYER TURN END     discard hand → decrement player status timers
ENEMY TURN START    expire enemy guard
ENEMY ACTS          execute telegraphed intent
ENEMY TURN END      decrement enemy status timers → choose next intent
```

Guard expires at its owner's turn *start*; status timers decrement at its owner's turn
*end*. The two use different moments deliberately — that is what lets guard survive the
opponent's turn while a 2-turn strength buff still covers exactly one attack.

Player moves first. Battle ends the moment either fighter reaches 0 HP, checked after
every damage application.

### Deck Flow

Draw 5 at turn start. Unplayed cards are discarded at turn end. When the draw pile cannot
satisfy a draw, it takes what remains, shuffles the discard pile into the draw pile, and
continues. Card count is conserved at 12 across draw + hand + discard at all times.

### Win / Lose

Enemy HP 0 → "YOU WIN". Player HP 0 → "YOU LOSE". A banner appears, card input is
disabled, and a Restart button resets the battle to its opening state.

## Architecture

Two layers with an enforced boundary: `scripts/core/` has **zero node dependencies** and is
fully testable headless; `scripts/ui/` knows about nodes and knows nothing about rules.

```
scripts/core/            pure rules — RefCounted / Resource only
  battle_config.gd       tunable constants
  card_data.gd           CardData resource: cost, tags, effects[]
  card_effect.gd         CardEffect base resource
  effects/
    damage_effect.gd
    guard_effect.gd
    apply_status_effect.gd
  fighter.gd             hp, max_hp, guard, StatusBag
  status_bag.gd          stacks + turn countdown
  statuses/
    strength.gd          outgoing-damage modifier definition
  status_registry.gd     id → definition lookup
  combat.gd              the single damage pipeline
  combo_rule.gd          tag-sequence matching + bonus calculation
  deck.gd                draw / hand / discard, shuffle, reshuffle
  enemy_brain.gd         intent cycle, intent reporting
  battle_state.gd        turn state machine; owns fighters, deck, AP; emits signals

scripts/ui/
  battle_view.gd         subscribes to BattleState signals, drives the scene
  card_view.gd           one card's visuals; emits pressed

resources/cards/         jab.tres, straight.tres, block.tres
scenes/card.tscn
level.tscn               existing scene, root Node2D preserved
tests/run_tests.gd       headless assertions
```

That is roughly a dozen files, each small and single-purpose — more files than a hardcoded
POC would need, but each one is short enough to hold in mind, and the count is what buys
the data-driven card authoring below.

### Why this shape extends

**Adding a card** is authoring a `.tres` file — a cost, some tags, a list of effects. No
code changes, no new branch in a play function:

```
resources/cards/uppercut.tres
  cost: 2
  tags: [uppercut]
  effects: [ DamageEffect(12), ApplyStatusEffect(weak, 1) ]
```

**Adding a status** is one small file in `statuses/` plus a registry line. The damage
pipeline is untouched because it asks the registry for modifiers rather than checking
named fields.

**Adding a combo** is registering another tag sequence. `[hook, uppercut]` needs no code.

**Multiple enemies later:** every effect already takes an explicit `target` argument even
though the POC always passes the single enemy, so multi-enemy fights don't require
rewriting the effect layer.

### Data Flow

```
CardView.pressed
  → BattleView asks BattleState.play_card(index)
      → BattleState checks AP, spends it
      → ComboRule inspects this turn's play history, computes bonus
      → each CardEffect.apply(context, source, target)
          → DamageEffect calls Combat.resolve_damage(...)
      → BattleState emits signals (hp_changed, guard_changed, ap_changed,
                                   card_played, combo_triggered, battle_over)
  → BattleView updates labels, bars, card states
```

The view never mutates state and never computes rules; it renders what the signals report.

## UI Layout

Root `Level` (Node2D, existing scene and UID preserved) with a full-rect `Control` child.

```
┌──────────────────────────────────────────────────────┐
│                              INTENT: ⚔ 8             │
│              ┌──────────┐                            │
│              │   RED    │   ENEMY  48/48             │
│              │  ENEMY   │   [ 🛡 8 ]  [ ↑2 STR ]      │
│              └──────────┘                            │
│                                                      │
│  ┌──────────┐                                        │
│  │   BLUE   │   PLAYER 50/50            AP  ●●●      │
│  │  PLAYER  │   [ 🛡 5 ]                              │
│  └──────────┘                           ┌──────────┐ │
│                                         │ END TURN │ │
│  draw 4   discard 3                     └──────────┘ │
│   ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐                 │
│   │JAB │ │STR8│ │BLCK│ │JAB │ │STR8│                 │
│   │1 AP│ │2 AP│ │1 AP│ │1 AP│ │2 AP│                 │
│   │6dmg│ │9dmg│ │5grd│ │6dmg│ │9dmg│                 │
│   └────┘ └────┘ └────┘ └────┘ └────┘                 │
└──────────────────────────────────────────────────────┘
```

Fighters are `ColorRect`s — player blue, enemy red. Cards are `Button`-rooted scenes with a
`ColorRect` background and text labels, laid out in an `HBoxContainer`.

Card visual states:
- **Affordable** — full color, hover highlight.
- **Unaffordable** — dimmed, click ignored.
- **Combo armed** — after a jab is played, straights in hand get a gold border, so the
  available combo is visible rather than remembered.

Guard and strength badges hide at zero rather than showing `0`. The enemy intent is
displayed persistently throughout the player's turn.

## Testing

`tests/run_tests.gd` extends `SceneTree` and runs headless — no window, no clicking:

```
"/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot" \
  --headless --path . --script res://tests/run_tests.gd
```

It exits non-zero on any failed assertion. Cases:

**Damage and combo**
1. Jab alone: enemy 48 → 42.
2. Jab → Straight: 6 then 16; enemy 48 → 26; combo signal fired.
3. Jab → Block → Straight: straight deals 9, no combo signal.
4. Straight alone: 9.
5. Jab → Jab → Jab: 18 total, no combo.

**Guard**
6. Damage below guard: guard reduced, HP untouched.
7. Damage above guard: guard to 0, remainder to HP.
8. Player guard 5 vs enemy attack 8: player loses 3 HP.
9. Player guard expires at start of the player's next turn, not before.
10. Enemy guard survives the player's turn, expires at the start of the enemy's next.

**Strength timing**
11. Buff turn grants 2 strength.
12. The following enemy attack deals 12.
13. Strength is gone by the attack after that; damage returns to 8.

**AP**
14. Straight is unplayable with 1 AP remaining; AP never goes negative.
15. AP resets to 3 each player turn.

**Deck**
16. Card count is conserved at 12 across draw + hand + discard.
17. Drawing with an insufficient draw pile reshuffles the discard and completes the draw.

**Outcomes**
18. Enemy at 0 HP emits battle_over with a win; HP floors at 0, never negative.
19. Player at 0 HP emits battle_over with a loss.

After the headless suite passes, the game is launched normally to confirm it renders,
responds to clicks, and plays through a full battle.

## CLAUDE.md

Written as part of the build, capturing what is not derivable from reading the code:

- Godot binary path (`/Users/mihai/Godot games/Godot.app/Contents/MacOS/Godot` — contains a
  space, must be quoted), plus the run and headless-test commands.
- The layer rule: `scripts/core/` must never reference nodes or the scene tree; if a change
  requires it, the change belongs in `scripts/ui/`.
- The extension rule: adding a card means authoring a `.tres`, never editing a play
  function or adding a card enum branch.
- Where the tunable balance constants live.
- Style: typed GDScript, `snake_case` members, `PascalCase` class names, explicit return
  types.

## Decisions Made During Design

Recorded because each resolves a genuine ambiguity in the original brief:

1. **Enemy strength persists into the next attack** rather than expiring on the buff turn.
   As literally specced the buff turn accomplished nothing.
2. **Guard persists through the opponent's turn** for the same reason — otherwise Block
   never blocks anything.
3. **Combo bonus floors** (`7`, giving a 22-damage combo) rather than rounding up.
4. **Combo requires strictly consecutive plays**; an intervening card breaks it.
5. **Player HP 50, enemy HP 48** — roughly a three-turn fight.
6. **Enemy intent is telegraphed**, which is what makes Block a read rather than a guess.
