# Card Rewards, Burn, and Three New Cards — Design

Date: 2026-08-17
Status: approved direction, spec for review

## Goal

After winning a fight (when the run is not over), a rewards screen offers a
choice of one card from a pool of three new cards; the picked card joins the
player's deck for the rest of the run. This requires three new mechanics the
game does not have yet:

1. **A persistent deck.** Today every fight builds the same 14-card starting
   deck. The deck must become run state so a reward pick survives to the next
   fight.
2. **Burn.** A card mechanic: when played, the card goes to a new **burned
   pile** instead of the discard, and never reshuffles back this fight. The
   burned pile gets a HUD icon (left of the discard icon, visible only when
   non-empty) that opens the same `PileView` grid the other piles use.
3. **The rewards screen itself.** Full-screen view on `rewards_bg.png`, three
   selectable card faces, Continue (confirm pick) and Skip buttons —
   placeholder button art for now.

## The three cards

All three have illustrations already in `assets/illustrations/`
(`one_two.png`, `strength_up.png`, `prepared.png`). None joins
`DECK_COMPOSITION` — they enter play only via rewards.

New `BattleConfig` constants (all baked into `.tres` at generation time, like
the existing per-card constants — regen required after edits):

```gdscript
const ONE_TWO_COST: int = 1
const ONE_TWO_DAMAGE: int = 5        # per hit
const STRENGTH_UP_COST: int = 0
const STRENGTH_UP_STACKS: int = 2
const PREPARED_COST: int = 1
const PREPARED_GUARD: int = 4        # both the immediate and the delayed grant
```

One more constant is live-read (no regen needed), like `RUN_OPPONENTS`:

```gdscript
const REWARD_CARDS: Array[StringName] = [&"one_two", &"strength_up", &"prepared"]
```

### One-Two (attack, 1 AP)

Deal 5 damage. If that hit **breaks guard**, deal 5 damage again.

- "Breaks guard" means: the target's guard was above zero before the hit and
  is exactly zero after it. An exact soak (5 damage into 5 guard) IS a break.
  Against an unguarded target it hits once. Both opponents have guard moves
  (8 and 10), so the condition is live.
- `Combat.DamageResult` gains `broke_guard: bool`, computed inside
  `resolve_damage` (guard before > 0 and guard after == 0).
- New effect `GuardBreakBonusEffect extends CardEffect`
  (`scripts/core/effects/guard_break_bonus_effect.gd`): reads the LAST
  `Combat.DamageResult` in `context["results"]`; if it broke guard, resolves
  its own `amount` through `Combat.resolve_damage` (appending its result and
  log line). No preceding result means no bonus hit (fail closed, like
  `require_hp_damage`).
- It extends `CardEffect`, NOT `DamageEffect`, on purpose:
  `total_base_damage()` stays 5, so combo math never sees a phantom 10, and
  the first-`DamageEffect`-consumes-the-combo-bonus rule is untouched (the
  bonus hit never eats a combo bonus). Strength boosts both hits — each goes
  through the full pipeline.
- Card face: tags `[&"attack"]`, rules text
  `"Deal 5 damage. Breaks guard: deal 5 damage again."` (numbers from
  `ONE_TWO_DAMAGE`). The card still has a **sole `DamageEffect`**, so the
  live preview keeps working and previews the first hit's number.
  Implementation risk to check in the plan: both sentences print the same
  number, and the preview replaces the printed damage number by value — the
  replacement must target only the first hit's number (anchor it to the
  sentence, or replace the first match only), and the sentence-colouring
  rules must be checked for a sentence containing both "guard" and "damage"
  (intent: both 5s are damage numbers, red; "guard" here is a condition, not
  a guard grant, so no blue number on this card).

### Strength Up (attack colourway, 0 AP, Burn)

Gain 2 STR (permanent for the fight). **Burn.**

- One `ApplyStatusEffect`: `status_id = strength`, `stacks =
  STRENGTH_UP_STACKS`, `turns = BattleConfig.STATUS_PERMANENT`,
  `target_self = true`. The strength status and the permanent sentinel
  already exist; nothing in the damage pipeline changes.
- `burn = true` on the card (see Burn below).
- Tags `[&"buff"]` — not `defense`, so it wears the ATTACK (red) frame,
  which suits a damage buff under the two-colourway system.
- Rules text: `"Gain 2 STR. Burn."` — "STR" already keyword-matches the
  strength status (word-bounded, so STRAIGHT stays safe); "Burn" becomes the
  second rule-keyword (below).
- This is the **first player-side strength source**, which is exactly the
  case CLAUDE.md flags for the card-face preview: a previewed damage number
  can now WIDEN ("9" → "13" on Straight at 2 stacks). The painted-panel wrap
  tests gain a preview-aware case: wrap each attack card's rules text with
  its previewed numbers at the maximum reachable player strength (2 stacks —
  one Strength Up per run today) and assert the lines still fit the painted
  panel.

### Prepared (defense, 1 AP)

Gain 4 guard. Next turn, gain 4 guard again.

- Effects: a `GuardEffect` (amount `PREPARED_GUARD`) plus an
  `ApplyStatusEffect` applying a new **`prepared` status** (`stacks =
  PREPARED_GUARD`, `turns = 2`, `target_self = true`).
- The status is the delayed grant, made visible: the player sees a chip
  (icon optional later; `DISPLAY_NAME` text fallback is fine) with the
  pending amount, and "Prepared" in rules text goes yellow with a tooltip.
  `SHOW_TURNS = false` — the interesting number is the pending guard
  magnitude, and the payout timing is fixed (next turn start), not a
  countdown worth printing.
- **New, generic status hook: `on_turn_start(fighter, stacks) -> bool`.**
  Every status definition must now provide it (pass-through returning
  `false` if unused), same convention as the two damage-modifier statics —
  `StatusRegistry.apply_turn_start(bag, fighter)` calls it unconditionally
  for every active status and REMOVES the status when the hook returns
  `true` (consumed). `StatusBag` gains `remove(id)`.
- `BattleState` calls it at both owners' turn starts, immediately AFTER
  guard expiry: in `_begin_player_turn` after `player.expire_guard()`, and
  in `_run_enemy_turn` after `enemy.expire_guard()` (no enemy status uses it
  yet; the symmetry is deliberate and tested).
- `PreparedStatus.on_turn_start` adds `stacks` guard to its owner and
  returns `true` — it pays out exactly once, then the chip disappears.
  Timing walkthrough: played on turn N (+4 guard now, chip shows 4); the
  first guard survives the enemy turn and expires at turn N+1 start; the
  hook then immediately grants the second 4, which survives the next enemy
  turn. `turns = 2` is a belt-and-braces ceiling so the status also dies
  via the normal tick if the hook somehow never fires; consumption is the
  real lifecycle. Two Prepareds in one turn stack to a single 8-guard
  payout (StatusBag adds stacks) — acceptable and tested.
- Tags `[&"defense"]` — DEFENSE plate, blue frame.
- Rules text: `"Gain 4 guard. Prepared: gain 4 guard next turn."` (both
  numbers from `PREPARED_GUARD`, blue as guard numbers; "Prepared" yellow).

## Burn

- `CardData` gains `@export var burn: bool = false`.
- `Deck` gains a fourth pile, `burned_pile: Array[CardData]`, and its
  invariant becomes "cards only move between the four piles":
  - `take_from_hand` routes a `burn` card to `burned_pile` instead of
    `discard_pile`.
  - `_reshuffle_discard_into_draw` never touches it — burned cards are out
    for the rest of the fight.
  - `discard_hand` is unchanged (an unplayed burn card in hand discards
    normally and can be drawn again).
  - `total_cards()` includes it; `reset()` clears it.
- Burn cards return automatically next fight: every fight builds a fresh
  `Deck` from the run's card list.
- **"Burn" is the second rule-keyword** (after "Combo"): registered in
  `CardTemplate`'s keyword list beside `COMBO_KEYWORD`, coloured yellow,
  hover tooltip explaining the mechanic. The tooltip body lives in core
  beside the rule it describes, like guard's: `Deck.burn_description()`
  static ("Burned when played: goes to the burned pile and cannot be used
  again this fight." — final wording at implementation).

### Burned pile in the HUD

- A third pile icon in `BattleHud`, positioned left of `DISCARD_ICON_AT`
  with the same `PILE_ICON_SIZE` and a small gap, count centred inside like
  the others. **Visible only while `burned_pile` is non-empty** — it appears
  the first time a card burns and vanishes on the next fight.
- Placeholder art: reuse `discarded_cards.png` with a distinct modulate
  tint (ember red/orange) until real art exists. Same `TextureButton`
  press/pointer behaviour via `_make_pile_button`.
- Clicking emits the existing `pile_clicked` signal with `&"burned"`;
  `BattleView._on_pile_clicked` opens `PileView` with the burned cards —
  no `PileView` changes needed (it already takes an arbitrary card list).
- `test_hand_arc.gd` gains the same rotated-silhouette clearance assertions
  for the burned icon's rect (both rows) that the other icons carry — in
  BOTH the single-size test and the parameterised loop.

## The persistent deck

- `RunState` gains the deck:
  - `deck_ids: Array[StringName]`, initialised (and re-initialised by
    `reset()`) by expanding `BattleConfig.DECK_COMPOSITION`.
  - `add_card(id: StringName)` appends — the rewards screen's only write.
- `CardLibrary.build_deck(ids: Array[StringName]) -> Array[CardData]` loads
  a deck from an id list; `build_starting_deck()` becomes
  `build_deck(<expanded DECK_COMPOSITION>)` so the two can't drift.
- `BattleState._init` gains an optional `deck_ids` parameter (empty means
  the starting deck), keeping every existing call site and test working.
  `BattleView._start_fight` passes `run.deck_ids`.
- `restart()` semantics: like hp, a run restart rebuilds `RunState`, which
  restores the base deck. `BattleState.restart()` (tests only) keeps using
  the deck it was built with.

## The reward pool and rewards screen

- **`RewardPool`** (`scripts/core/reward_pool.gd`, RefCounted, static):
  `options() -> Array[StringName]` returns
  `BattleConfig.REWARD_CARDS` (`[&"one_two", &"strength_up", &"prepared"]`).
  This is the seam where "3 random cards from a bigger pool" lands later —
  callers already receive an arbitrary id list.
- **`RewardsView`** (`scripts/ui/rewards_view.gd`), modelled on `PileView`:
  a full-rect modal overlay with `rewards_bg.png` stretched as backdrop, a
  `HudText`-styled title ("CHOOSE A CARD"), and one real `CardView` per
  option, centred in a row at `PileView`'s rest scale with the same hover
  zoom (rules text readable) and keyword tooltips (Burn, STR, Prepared all
  need them here — this screen is where the player first reads these cards).
  - Clicking a card selects it (click again to deselect); the selection
    indicator is a visible rest-transform emphasis (scale bump plus tint) —
    exact values tuned from a capture, per the project's render-judged rule.
  - **Continue** (placeholder `Button`, `focus_mode = FOCUS_NONE`):
    disabled until a card is selected; confirms.
  - **Skip** (same placeholder styling): proceeds with no card.
  - Emits `finished(card_id: StringName)` — `&""` means skipped.
- **Flow change in `BattleView`:** `_on_continue_pressed` after a WIN with
  the run incomplete shows `RewardsView` instead of starting the next fight
  directly; on `finished`, a non-empty id goes to `run.add_card()`, then the
  existing next-fight path runs (including
  `_suppress_transition_guard_pulses`). Winning the final fight (run
  complete) and every loss keep their current paths — no rewards screen.
  Button clicks play the existing `click` sound.

## Testing

Headless suites (all through `./tests/run_tests.sh`):

- **Deck/burn:** burn card routes to `burned_pile`; non-burn unchanged;
  reshuffle excludes burned; unplayed burn card in hand discards normally;
  `total_cards` invariant holds across all four piles.
- **One-Two:** `broke_guard` truth table (no guard / partial guard left /
  exact soak / overkill through guard); one hit vs unguarded, two vs broken;
  strength applies to both hits; a `GuardBreakBonusEffect` with no preceding
  result does nothing.
- **Strength Up:** 2 permanent stacks on the player; card burns when played;
  outgoing damage actually rises.
- **Prepared:** +4 now; second +4 lands at next player turn start AFTER
  guard expiry (not stacked on leftovers); status consumed after payout
  (chip data gone); double-play pays 8 once; enemy-side hook symmetry
  (a synthetic status via the registry, or direct `apply_turn_start` call).
- **Run/rewards:** `RunState.deck_ids` starts as DECK_COMPOSITION expanded;
  `add_card` persists into the next fight's `BattleState` deck; `reset`
  restores the base deck; `RewardPool.options()` matches `REWARD_CARDS`.
- **Card library:** extend `test_card_library.gd` to pin the three new
  `.tres` against their `BattleConfig` constants (the forgotten-regen trap).
- **Card face:** keyword colouring for "Burn"/"Prepared"; the preview-aware
  wrap case for attack cards at 2 player strength stacks; One-Two preview
  replaces only the first hit's number.
- **HUD:** burned icon visibility rule; hand-arc clearance for its rect in
  both clearance tests.
- **RewardsView:** selection state machine and `finished` payload
  (detached-node tests; animation entry points guarded per rule 3).

Render verification (tests cannot see these — per project law):

- `capture_cards.gd` extended to include the three new faces; judge layout,
  keyword colour, the ATTACK/DEFENSE plates, and the Strength Up burn line
  from `/tmp/card-faces.png`.
- A screenshot of the rewards screen (backdrop, card row, selection
  emphasis, buttons) and of the HUD with a non-empty burned pile.

## Out of scope (YAGNI)

- Random reward pools, more than three reward cards, reward rarity.
- Real art for Continue/Skip/burned-pile icon (placeholders by design).
- Burned-pile persistence rules beyond "empties next fight".
- Map/deck-viewing screens outside battle.
