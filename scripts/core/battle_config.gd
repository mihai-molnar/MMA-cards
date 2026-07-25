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
