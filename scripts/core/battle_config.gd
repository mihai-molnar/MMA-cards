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

## Combo bonus = floori(sum_of_base_damage * COMBO_BONUS_RATIO)
const COMBO_BONUS_RATIO: float = 0.5
## Each strength stack adds this fraction of base outgoing damage.
const STRENGTH_DAMAGE_PER_STACK: float = 0.25

const STATUS_PERMANENT: int = -1
