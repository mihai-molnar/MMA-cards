class_name BattleConfig
extends RefCounted

## Every tunable number in the game. Nothing else should hardcode balance values.

const PLAYER_MAX_HP: int = 50
const AP_PER_TURN: int = 3
const HAND_SIZE: int = 5

## Card id -> copies in the starting deck. Totals 14.
const DECK_COMPOSITION: Dictionary = {
	&"jab": 5,
	&"straight": 4,
	&"block": 3,
	&"low_kick": 2,
}

const JAB_COST: int = 1
const JAB_DAMAGE: int = 6
const STRAIGHT_COST: int = 2
const STRAIGHT_DAMAGE: int = 9
const BLOCK_COST: int = 1
const BLOCK_GUARD: int = 5
const LOW_KICK_COST: int = 0
const LOW_KICK_DAMAGE: int = 2
## Turn countdown for the injury Low Kick applies: 1 means it is live for
## the opponent's next attack and expires at their turn end -- exactly one
## weakened attack (status timers decrement at their owner's turn END).
const LEG_INJURY_TURNS: int = 1
## Outgoing damage multiplier while leg-injured -- the fighter cannot put
## weight on the leg.
const LEG_INJURY_DAMAGE_MULT: float = 0.5

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
## Lifecycle ceiling for the Prepared status: applied mid-turn, it must
## survive its owner's turn-end tick (2 -> 1) to still be alive at the next
## turn start, where the payout consumes it. The hook consumption is the
## real lifecycle; this is the belt-and-braces bound. Not a balance knob.
const PREPARED_STATUS_TURNS: int = 2

## KO cards: reward-pool attacks that can end the fight on the spot. The
## chance only rolls when the hit deals hp damage past guard -- the rule
## lives in KOChanceEffect. Cost/damage/chance are BAKED into the .tres
## files -- re-run tools/generate_cards.gd after editing.
const HIGH_KICK_COST: int = 3
const HIGH_KICK_DAMAGE: int = 11
const HIGH_KICK_KO_CHANCE: float = 0.30
const FLYING_KNEE_COST: int = 2
const FLYING_KNEE_DAMAGE: int = 8
const FLYING_KNEE_KO_CHANCE: float = 0.20
const ELBOW_COST: int = 1
const ELBOW_DAMAGE: int = 4
const ELBOW_KO_CHANCE: float = 0.10
const ELBOW_BLEED_CHANCE: float = 0.50
## Bleed: damage at the bleeding fighter's turn start, straight to hp
## (guard does not absorb it), for BLEED_TURNS turns. Live-read like every
## status constant -- no regen step.
const BLEED_DAMAGE_PER_TURN: int = 2
const BLEED_TURNS: int = 3

const BRAWLER_MAX_HP: int = 48
const BRAWLER_ATTACK_DAMAGE: int = 8
const BRAWLER_GUARD_AMOUNT: int = 8
const BRAWLER_BUFF_STRENGTH: int = 2
## 2 turns means: live during the buff turn AND the following attack turn.
const BRAWLER_BUFF_DURATION: int = 2

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

## The rewards screen's pool, in display order. Live-read like RUN_OPPONENTS
## -- no regen step. Today the whole pool is offered every time; a random
## draw from a larger pool later changes RewardPool, not this list's readers.
const REWARD_CARDS: Array[StringName] = [&"one_two", &"strength_up", &"prepared"]

## Combo bonus = floori(sum_of_base_damage * COMBO_BONUS_RATIO)
const COMBO_BONUS_RATIO: float = 0.5
## Each strength stack adds this fraction of base outgoing damage.
const STRENGTH_DAMAGE_PER_STACK: float = 0.25

const STATUS_PERMANENT: int = -1
