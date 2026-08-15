extends SceneTree

## Generates resources/cards/*.tres from BattleConfig values.
## Run: godot --headless --path . --script res://tools/generate_cards.gd
##
## Cards are generated rather than hand-written so the .tres format is always
## valid. The output is a normal resource — edit it in the inspector, or
## regenerate it here.
##
## To add a new card: write a _make_*() function below that builds and
## returns a CardData, call _save() on it from _initialize(), and — if it
## should appear in the starting deck — add its id to
## BattleConfig.DECK_COMPOSITION.

const OUTPUT_DIR: String = "res://resources/cards"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	_save(_make_jab())
	_save(_make_straight())
	_save(_make_block())
	_save(_make_low_kick())

	print("Generated 4 card resources in %s" % OUTPUT_DIR)
	quit(0)

func _save(card: CardData) -> void:
	var path: String = "%s/%s.tres" % [OUTPUT_DIR, card.id]
	var error: int = ResourceSaver.save(card, path)
	if error != OK:
		printerr("Failed to save %s (error %d)" % [path, error])
		quit(1)
	else:
		print("  wrote %s" % path)

func _make_jab() -> CardData:
	var card := CardData.new()
	card.id = &"jab"
	card.display_name = "JAB"
	card.cost = BattleConfig.JAB_COST
	card.tags = [&"jab", &"attack"] as Array[StringName]
	card.rules_text = "Deal %d damage." % BattleConfig.JAB_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.JAB_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

func _make_straight() -> CardData:
	var card := CardData.new()
	card.id = &"straight"
	card.display_name = "STRAIGHT"
	card.cost = BattleConfig.STRAIGHT_COST
	card.tags = [&"straight", &"attack"] as Array[StringName]
	# The card names the KEYWORD and its trigger; the mechanic (the bonus
	# ratio, the strictly-consecutive requirement) lives in the Combo
	# tooltip via ComboRule.keyword_description(), derived from the live
	# config -- so no number is printed here that a rebalance could leave
	# stale, which is precisely what the old painted face did. "right after"
	# is load-bearing wording: any card in between breaks the combo, and an
	# earlier phrasing ("earlier this turn") lied about that.
	card.rules_text = "Deal %d damage. Combo right after Jab." % BattleConfig.STRAIGHT_DAMAGE
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.STRAIGHT_DAMAGE
	card.effects = [damage] as Array[CardEffect]
	return card

func _make_low_kick() -> CardData:
	var card := CardData.new()
	card.id = &"low_kick"
	card.display_name = "LOW KICK"
	card.cost = BattleConfig.LOW_KICK_COST
	card.tags = [&"kick", &"attack"] as Array[StringName]
	# "Leg Injury" is a KEYWORD: CardTemplate colours it yellow and the hover
	# tooltip explains what it does, so the card itself stays short -- the
	# mechanics (50% weaker attacks) live in the status description, not here.
	card.rules_text = "Deal %d damage. If unblocked, causes Leg Injury for %d turn." % [
		BattleConfig.LOW_KICK_DAMAGE, BattleConfig.LEG_INJURY_TURNS]
	var damage := DamageEffect.new()
	damage.amount = BattleConfig.LOW_KICK_DAMAGE
	var injury := ApplyStatusEffect.new()
	injury.status_id = LegInjuryStatus.ID
	injury.stacks = 1
	injury.turns = BattleConfig.LEG_INJURY_TURNS
	injury.target_self = false
	# A second kick keeps the leg hurt a turn longer, not hurt twice as much.
	injury.extend_duration = true
	# A fully blocked kick lands no hp damage, so it injures nothing.
	injury.require_hp_damage = true
	card.effects = [damage, injury] as Array[CardEffect]
	return card

func _make_block() -> CardData:
	var card := CardData.new()
	card.id = &"block"
	card.display_name = "BLOCK"
	card.cost = BattleConfig.BLOCK_COST
	card.tags = [&"defense"] as Array[StringName]
	card.rules_text = "Gain %d guard." % BattleConfig.BLOCK_GUARD
	var guard := GuardEffect.new()
	guard.amount = BattleConfig.BLOCK_GUARD
	card.effects = [guard] as Array[CardEffect]
	return card
