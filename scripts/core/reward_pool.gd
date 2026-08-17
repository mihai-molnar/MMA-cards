class_name RewardPool
extends RefCounted

## The rewards screen's card pool. Today the whole configured list is
## offered every time; this static is the SEAM where "3 random cards from a
## larger pool" lands later -- callers already receive an arbitrary id list
## and RewardsView renders whatever it is handed.

static func options() -> Array[StringName]:
	return BattleConfig.REWARD_CARDS.duplicate()
