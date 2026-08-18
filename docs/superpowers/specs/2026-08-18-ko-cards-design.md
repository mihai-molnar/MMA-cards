# KO Cards, Bleed, Randomized Rewards, Dev Menu — Design

Date: 2026-08-18
Status: Approved design, pre-implementation

## Overview

Three new attack cards introduce a chance-based KO mechanic that can end a
fight immediately with the player winning "by KO", plus a Bleed
damage-over-time status. The reward screen stops offering its whole pool and
instead offers 3 distinct random cards. A hotkey dev menu lets any library
card be played instantly for testing.

## The cards

All constants live in `BattleConfig` and are baked into `.tres` by
`tools/generate_cards.gd` (so `test_card_library.gd` must assert them):

| Card | Cost | Damage | KO chance | Other | Tags |
|---|---|---|---|---|---|
| High Kick | 3 | 11 | 30% | — | attack, kick |
| Flying Knee | 2 | 8 | 20% | — | attack, kick |
| Elbow | 1 | 4 | 10% | 50% chance to apply Bleed | attack |

- `kick` tag gives High Kick and Flying Knee the kick hit sound; Elbow
  defaults to punch.
- Rules text pattern: "Deal 11 damage. 30% chance to KO." Elbow adds
  "50% chance to apply Bleed."
- Illustrations already delivered: `elbow.png`, `flying_knee.png` match
  their card ids; `highkick.png` is renamed `high_kick.png` to match the
  id `high_kick`. All get mipmapped imports per the house rule.
- None of the three joins `DECK_COMPOSITION` — they are reward-pool cards.

## KO mechanic (core)

Decision: **context + signals** (approach A of three considered). No card
enum, no branch in `play_card` for a specific card — the effect system
carries everything.

- `BattleState` gains its own `RandomNumberGenerator`, seeded from the
  existing `_rng_seed` (randomized when the seed is 0, exactly like
  `Deck`), and passes it into every play context as `context["rng"]`.
  Tests pass a seed and get deterministic rolls.
- New `KOChanceEffect` (`scripts/core/effects/ko_chance_effect.gd`),
  `chance: float` export. `apply()`:
  - Rolls ONLY if the context's accumulated `results` show hp_loss > 0 —
    a hit fully soaked by guard never rolls. This is why the effect sits
    AFTER the card's `DamageEffect` in the effect list.
  - Writes `context["ko_attempted"] = true` and `context["ko"] = bool`.
  - Logs the outcome.
  - `describe()` prints "30% chance to KO." with the number derived from
    `chance`, never hard-coded.
- `ApplyStatusEffect` gains `chance: float = 1.0`, rolled from the same
  context RNG — this is Elbow's 50% Bleed; no new effect class.
- `BattleState.play_card` reads the context generically after effects run:
  - KO success: `is_over = true`, new `won_by_ko: bool` property set, log
    line, emit new signal `ko_scored()` then `battle_over(true)`.
  - KO failure: emit new signal `ko_failed()`; play continues.
- KO is player-side only today. No opponent move uses these effects, and
  nothing in the design prevents one later (the effects are symmetric).

## Bleed status (core)

`scripts/core/statuses/bleed.gd`, registered in `StatusRegistry.DEFINITIONS`:

- `ID = &"bleed"`, `DISPLAY_NAME = "Bleed"`, `SHOW_TURNS = true`.
- `on_turn_start`: deals `BattleConfig.BLEED_DAMAGE_PER_TURN` (2) straight
  to the owner's HP, **ignoring guard** (bleed pierces armor thematically
  and mechanically). Returns false — ticks down normally at turn end over
  `BattleConfig.BLEED_TURNS` (3) turns.
- Applied with `extend_duration = true` — re-application ADDS turns, like
  Leg Injury.
- `description()` derives its numbers from `BattleConfig`.
- Icon delivered at `assets/icons/bleed.png` — the status chip shows it
  with the remaining-turn count, hover tooltip included, all free from the
  registry.
- **Death-at-turn-start consequence handled explicitly**: bleed can kill
  the enemy when `_run_enemy_turn` calls `apply_turn_start(enemy)`. The
  turn checks `_check_battle_over()` immediately after that call — a dead
  enemy does not get its attack. (The player-side equivalent cannot occur
  today since only the enemy bleeds, but the check is symmetric and cheap:
  `_begin_player_turn` gets the same guard.)

## Keywords & tooltips

- **KO** becomes the third game-rule keyword beside `COMBO_KEYWORD` and
  `BURN_KEYWORD` (`KO_KEYWORD`). Its tooltip body lives in core beside the
  mechanic (a static on `KOChanceEffect`, mirroring how
  `Deck.burn_description()` sits beside burn) and MUST state the guard
  rule plainly: a KO can only land if the hit deals HP damage — a fully
  blocked hit never KOs.
- **Bleed** is a status keyword via `DISPLAY_NAME`, colored yellow and
  tooltipped like Leg Injury. Its sentence's numbers stay plain per the
  existing "a duration is not damage" coloring rule; the KO sentence's
  percentage likewise stays plain (it is a chance, not damage).
- Word-bounded matching note: "KO" is short and case-insensitive matching
  makes it shorter still; the existing word-bounded matcher must keep it
  from firing inside other words ("knockout", a hypothetical "KICKOFF") —
  a test pins this.

## Presentation: KO splash

- `KO.png` and `failed.png` move from `assets/` to `assets/ui/ko.png` and
  `assets/ui/failed.png`, mipmapped imports.
- New splash element owned by `BattleView`, drawn above every other layer
  (z above the tooltip's 70). Two modes:
  - **KO scored**: KO art pops in centre-screen with a scale overshoot,
    `ScreenFx` shake, and the `slam` sound; holds ~1 second; then the
    normal result-banner → rewards/run-end flow proceeds. The banner waits
    for the splash.
  - **KO failed**: failed art appears for a split second and fades; play
    continues uninterrupted.
- Both are deferred by the same impact delay as HP drops
  (`Juice.play_impact_delay()`), so the splash lands when the card
  visually strikes, not when the model resolves.
- Every duration/scale/curve lives in `Juice`, per the house rule.
- Animation entry points get `is_inside_tree()` guards with any
  decision-recording before the guard (house rule 3), and verification is
  by frame capture (`tools/capture_frames.gd`) — end-state assertions
  cannot see motion.

## Reward randomization

- `BattleConfig.REWARD_CARDS` grows to all six non-starting cards:
  one_two, strength_up, prepared, high_kick, flying_knee, elbow.
- `RewardPool.options()` — the documented seam — returns **3 distinct**
  cards drawn at random from that pool, seedable for tests (default
  randomized). `RewardsView` renders whatever list it is handed and needs
  no changes.

## Dev menu

- Backquote (`) toggles a modal overlay modeled on `PileView`: every
  `CardLibrary` card as a real `CardView` in a grid (name-sorted), close
  affordance included.
- Clicking a card calls new `BattleState.dev_play(card: CardData)`:
  applies the card's effects with no AP cost and no hand involvement,
  through the exact same context/signal flow as `play_card` (so KO, Bleed
  and all presentation fire normally). Guarded by `is_over` only.
- Ships in the game with no build flag — reachable only by hotkey.

## Testing

- New/extended suites: Bleed tick + extend + guard-piercing + death at
  turn start; KO roll determinism (seeded success and failure), no-roll
  when fully absorbed, `won_by_ko` and signal emission; ApplyStatusEffect
  chance; reward-pool distinctness/membership/seeded determinism;
  `dev_play`; card-library assertions for the three new cards' baked
  values; KO keyword word-bounding.
- Existing template wrap/preview tests pick up the new cards automatically
  (library-driven).
- Regenerate `.tres` after config changes; `./tests/run_tests.sh` before
  every commit; `capture_cards.gd` for the new faces, `capture_frames.gd`
  for the KO splash motion.

## Explicitly out of scope

- Enemy-side KO or Bleed use.
- Music/stingers for the KO moment (slam sound reused).
- Any map/shop beyond the existing rewards screen.
