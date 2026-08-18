class_name RewardPool
extends RefCounted

## The rewards screen's pool: OFFER_COUNT distinct cards drawn at random
## from BattleConfig.REWARD_CARDS each time the screen opens. `rng` is
## injectable so tests are deterministic; null -- every game call site --
## means a fresh randomized generator. RewardsView renders whatever list it
## is handed, so a pool smaller than OFFER_COUNT simply offers everything.

const OFFER_COUNT: int = 3

static func options(rng: RandomNumberGenerator = null) -> Array[StringName]:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var pool: Array[StringName] = BattleConfig.REWARD_CARDS.duplicate()
	# Fisher-Yates, then take the front: distinct by construction.
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var temp: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = temp
	return pool.slice(0, mini(OFFER_COUNT, pool.size()))
