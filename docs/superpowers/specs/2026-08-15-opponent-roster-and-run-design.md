# Opponent roster and run structure — design

Date: 2026-08-15
Status: approved (design conversation), pending implementation

## Problem

The single opponent is too easy: he attacks only 1 turn in 3, so the player
can ignore defense and race him down. And the game ends after one fight —
there is no run. The user wants: a harder 3-turn rotation for the current
opponent (attack / attack+defend / defend+buff), a second, harder opponent
after victory, and a structure that extends to many opponents and, later, a
Slay-the-Spire-style map.

## Decisions made in brainstorming

- **HP carries over between fights.** Guard and statuses are cleared, the
  deck reshuffles fresh. Damage taken in fight 1 makes fight 2 tense.
- **Defeat anywhere restarts the whole run** at full HP from fight 1. The
  run is the unit of play, not the fight.
- **Opponent 2 is a new fighter, not a stat reskin**: new rotation plus a
  signature move built from existing mechanics.
- **After the last fight: "RUN COMPLETE"**, same banner flow as defeat.
- **The map is out of scope** but must slot in later at two known seams
  (see Extensibility).

## Architecture

Three new/changed core pieces, all `RefCounted`, all in `scripts/core/`:

### `OpponentData`

Plain data: `id: StringName`, `display_name: String`, `max_hp: int`,
`rotation: Array[OpponentTurn]` — where a turn is a list of moves and each
move is built from the existing `CardEffect` classes (`DamageEffect`,
`GuardEffect`, `ApplyStatusEffect`) plus what the intent label should say
for it. A new opponent never needs new combat code unless it introduces a
genuinely new mechanic — the same philosophy as cards. (Exact shape of
"turn" — small class vs parallel arrays — is an implementation-plan
decision; the constraint is that `EnemyBrain` can produce both the effects
and the intent text for the current turn from it.)

Intent text for a multi-move turn joins the per-move texts with `" + "`,
e.g. `ATTACK 8 + BLOCK 8`. ASCII only, per project convention. Damage
intent must keep using `Combat.preview_damage` so the telegraph never
diverges from resolution (Low Kick re-telegraphing still works).

### `OpponentLibrary`

Like `CardLibrary`: `_make_brawler()`, `_make_kickboxer()`, each building an
`OpponentData` in code from `BattleConfig` constants. No `.tres` files, no
generator step — opponents have no art or composed face to bake, so the
regen/stale-resource machinery cards need buys nothing here. Adding
opponent N = one `_make_*()` function + its constants + one id in the run
sequence.

### `EnemyBrain` becomes an interpreter

Holds an `OpponentData`, steps an index through its rotation. The `Action`
enum, `CYCLE`, and the `match` in `build_effects()`/`intent_text()` go
away. Public surface stays: `advance()`, `reset()`, `build_effects()`,
`intent_text(enemy, target)`, so `BattleState`'s call sites are unchanged.

### `RunState`

Owns what persists across fights: player HP and the fight sequence.

- Sequence today: `BattleConfig.RUN_OPPONENTS: Array[StringName]`
  (`[&"brawler", &"kickboxer"]`), walked linearly.
- Interface: `current_opponent() -> OpponentData`,
  `record_result(won: bool, remaining_hp: int)`, `is_complete() -> bool`,
  `reset()`, plus the player's current HP for seeding the next battle.

### `BattleState` stays a single battle

Constructed with an `OpponentData` and the player's starting HP.
`battle_over(player_won)` keeps meaning "this fight ended" — `BattleState`
has no knowledge of the run. `restart()`'s role shifts to the view building
a fresh `BattleState` per fight (implementation plan decides whether
`restart()` survives at all).

### `BattleView` owns the `RunState`

On `battle_over(true)`: if the run has a next opponent, show an
interstitial banner (`FIGHT 2: KICKBOXER`, a CONTINUE button — reusing the
result-panel pattern, including `focus_mode = FOCUS_NONE`) and build a
fresh `BattleState` seeded with carried HP. If the run is complete, show
`RUN COMPLETE`. On `battle_over(false)`: `YOU LOSE`, RESTART resets the
run to fight 1 at full HP. The enemy `FighterPanel` shows the opponent's
`display_name`, not "Enemy".

The existing banner timing rules apply unchanged: the banner defers by the
impact delay + `RESULT_BEAT` when the kill came from a played card.

## The two opponents

### Brawler (fight 1) — the current opponent, harder

3-turn rotation (current stats: attack 8, guard 8, buff +2 STR for 2 turns):

1. `ATTACK 8`
2. `ATTACK 8 + BLOCK 8`
3. `BLOCK 8 + BUFF +2 STR`

Why it works: attacks 2 turns in 3 (was 1 in 3), roughly doubling cycle
damage (~12 → ~20 per cycle against 50 player HP). The buff on turn 3 with
`ENEMY_BUFF_DURATION = 2` is live for exactly the next cycle's opening
attack — the scariest telegraph (`ATTACK 12`) lands right after the buff
turn, which is when Block and Low Kick matter most. Guard on 2 of 3 turns
means attack timing matters. Only 1 turn in 3 deals no damage, so Block
stops being a dead card.

HP stays 48.

### Kickboxer (fight 2) — new, harder

56 HP. 4-turn cycle, 3 attacking turns, and a signature move that mirrors
the player's own Low Kick back at them:

1. `LEG KICK 5` — damage + applies **Leg Injury** to the player
   (existing status: halves outgoing damage, expires at the injured
   fighter's turn end — the player's next turn of attacks is halved)
2. `ATTACK 10`
3. `ATTACK 10 + BLOCK 10`
4. `BLOCK 10 + BUFF +2 STR`

Harder in damage, in tempo, and he attacks the player's damage output — a
genuinely different read, built entirely from existing effects and the
existing `LegInjuryStatus`. All numbers are new `BattleConfig` constants
(runtime-read, no card regen involved).

Note: Leg Injury applied to the player is the first *player-owned* timed
debuff. Status ticking (`tick_statuses_turn_end`) is already symmetric on
`Fighter`, so this should work unchanged — but the tests must prove it,
including that the intent/preview of the player's own cards reflects the
halving (card damage preview flows through `Combat.preview_damage` for the
enemy intent; the combo/damage numbers on the player's cards are static
rules text and do not preview modifiers — unchanged behavior).

## Balance summary (constants, all in `BattleConfig`)

- Brawler: existing `ENEMY_*` constants renamed/scoped to the brawler
  (implementation plan decides naming; every number stays in
  `BattleConfig`, nothing hardcoded in `OpponentLibrary`).
- Kickboxer: `max_hp 56`, `attack 10`, `guard 10`, `buff +2 STR / 2
  turns`, `leg kick 5` + Leg Injury reusing `LEG_INJURY_TURNS` /
  `LEG_INJURY_DAMAGE_MULT` (shared with the player's Low Kick, so the
  mirror is exact by construction).
- `RUN_OPPONENTS: Array[StringName] = [&"brawler", &"kickboxer"]`.

These are runtime-read constants — no card `.tres` regeneration is
involved anywhere in this feature.

## Extensibility seams (for the future map)

1. **`RunState`'s next-opponent choice.** Today: a linear array walk. A map
   replaces *how the next opponent id is chosen* (a node graph the player
   picks from); `current_opponent()` / `record_result()` / `is_complete()`
   survive unchanged, and nothing downstream of `RunState` changes.
2. **`BattleView`'s transition point.** Today: an instant interstitial
   banner between fights. A map scene slots in at exactly that moment
   instead. Battle code never learns the map exists.

Adding opponent 3 today: one `_make_*()` in `OpponentLibrary`, its
constants in `BattleConfig`, one id appended to `RUN_OPPONENTS`.

## Timing rules — unchanged and load-bearing

- Guard still expires at owner's turn START; status timers still tick at
  owner's turn END. Multi-move turns change neither.
- A multi-move turn resolves its effects in listed order within the one
  existing enemy-turn flow (`expire_guard` → apply effects → tick →
  advance). `ATTACK + BLOCK` therefore attacks and guards in the same
  resolution step; the guard protects him during the *player's* next turn,
  as guard always has.
- Between fights, the new `BattleState` starts clean: no guard, no
  statuses, fresh deck/hand/AP. Only HP carries.
- `suppress_next_guard_pulse()` call sites must be revisited: guard-expiry
  moments per turn are unchanged, but the comment "two-in-three enemy
  turns deal no damage" is stale — verify the suppression logic keys on
  expiry moments, not on that ratio.

## Testing

Headless suites (all through `./tests/run_tests.sh`):

- **Rotation**: multi-move turns apply every effect; intent text joins
  moves with `" + "`; brawler cycle order and wraparound; buff timing
  still yields exactly one buffed attack (the cycle-opening one).
- **Kickboxer**: Leg Injury lands on the player, halves the player's card
  damage for exactly one player turn, then expires; enemy intent preview
  of `LEG KICK` matches resolution.
- **Run**: HP carries into fight 2; guard/statuses do not; deck is fresh;
  `record_result` walks the sequence; `is_complete` after the last fight;
  `reset()` restores full HP and fight 1; defeat in fight 2 restarts at
  fight 1.
- **Regression**: `test_card_library` and friends untouched — this feature
  regenerates nothing.

UI verification is manual, per project rules: boot the game, play through
both fights, check the interstitial, the opponent name, the intent labels
(multi-move text width on the label), and the RUN COMPLETE / YOU LOSE
banners. Card faces are untouched — no capture pass needed.

## Out of scope

The map itself, card rewards, deck-building between fights, opponent
portraits, sound.
